#!/usr/bin/env bash
# Manual live test of the dev environment. It creates real, billable AWS resources in the
# account behind the `dev` profile, checks them, and destroys them on exit, including on
# failure or Ctrl-C. Offline checks never call this. See docs/live-test.md.
#
# Live tests run private-only. Terraform applies dev with private_only=true: no internet gateway,
# NAT gateway, Elastic IP or public subnet, a private API endpoint, and no Route 53. Before
# anything is created, the offline pre-flight tests must pass and scripts/check_private_plan.py
# must find nothing internet-facing in the saved plan. The operator reaches the private API
# endpoint through Session Manager port forwarding via a relay instance with no public IP; the
# platform add-ons and the catalog API are installed with Helm through that tunnel, with images
# pulled through ECR pull-through caches. Argo CD is not installed: it syncs from GitHub, which a
# VPC without internet cannot reach.
#
# Requirements: aws CLI v2 with the `dev` profile and the Session Manager plugin, terraform,
# kubectl, helm, jq and uv.
set -euo pipefail

profile="dev"
region="us-east-1"
env_dir="infra/terraform/envs/dev"
cluster="harbor-goods-dev"
local_port="${LIVE_API_PORT:-8443}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/eks-gitops-live.XXXXXX")"
export KUBECONFIG="$work_dir/kubeconfig"
applied=false
keep_state=false
tunnel_pid=""
pytest=(uv run --no-project --with-requirements tests/requirements.txt python -m pytest -q)

log() { printf '\n==> %s\n' "$*"; }

set_tf_vars() {
  tf_vars=(
    "-var=admin_role_arns=[\"$admin_role_arn\"]"
    "-var=private_only=true"
    "-var=public_access_cidrs=[]"
    '-var=extra_tags={purpose="portfolio-test"}'
  )
}

open_tunnel() {
  local relay endpoint_host i
  relay="$(terraform -chdir="$env_dir" output -json private_access | jq -r '.instance_id // empty')"
  [ "$relay" != "" ] || { echo "No relay instance in the state; cannot reach the cluster."; return 1; }
  endpoint_host="$(terraform -chdir="$env_dir" output -raw cluster_endpoint | sed 's#^https://##')"

  log "Waiting for the relay $relay to register with Session Manager"
  for ((i = 0; i < 60; i++)); do
    [ "$(aws ssm describe-instance-information --profile "$profile" --region "$region" \
      --filters "Key=InstanceIds,Values=$relay" --query 'length(InstanceInformationList)' --output text)" = 1 ] && break
    sleep 10
  done

  log "Port forwarding 127.0.0.1:$local_port to the private API endpoint"
  aws ssm start-session --profile "$profile" --region "$region" --target "$relay" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$endpoint_host\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$local_port\"]}" \
    > "$work_dir/tunnel.log" 2>&1 &
  tunnel_pid=$!
  for ((i = 0; i < 30; i++)); do
    grep -q 'Waiting for connections' "$work_dir/tunnel.log" && break
    sleep 2
  done

  aws eks update-kubeconfig --name "$cluster" --region "$region" --profile "$profile" > /dev/null
  cluster_arn="$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')"
  # Same certificate, reached through the tunnel: kubectl verifies it against the real host name.
  kubectl config set-cluster "$cluster_arn" --server="https://127.0.0.1:$local_port" \
    --tls-server-name="$endpoint_host" > /dev/null
}

close_tunnel() {
  if [ "$tunnel_pid" != "" ]; then
    kill "$tunnel_pid" 2> /dev/null
    wait "$tunnel_pid" 2> /dev/null
    tunnel_pid=""
  fi
}

teardown() {
  local status=$?
  set +e
  if [ "$applied" = true ]; then
    if [ "$tunnel_pid" = "" ]; then
      open_tunnel || echo "Cluster unreachable; terraform destroy removes what Terraform created."
    fi
    log "Teardown: removing workloads so their load balancer and nodes are deleted first"
    # The Ingress must go while the load balancer controller still runs, or its ALB is orphaned.
    helm uninstall catalog-api --namespace catalog-api --wait --timeout 10m
    # Karpenter must still run to terminate the instances it launched.
    kubectl delete nodepools --all --wait --timeout=10m
    kubectl wait --for=delete node -l karpenter.sh/nodepool --timeout=10m
    close_tunnel

    log "Teardown: terraform destroy"
    if ! terraform -chdir="$env_dir" destroy -auto-approve -input=false "${tf_vars[@]}"; then
      status=1
      keep_state=true
    fi

    log "Teardown: deleting the pull-through cache repositories the first pulls created"
    for prefix in "$cluster-ecr-public" "$cluster-k8s"; do
      aws ecr describe-repositories --profile "$profile" --region "$region" \
        --query "repositories[?starts_with(repositoryName, '$prefix/')].repositoryName" --output text |
        tr '\t' '\n' | while read -r repo; do
        [ "$repo" = "" ] || aws ecr delete-repository --profile "$profile" --region "$region" \
          --repository-name "$repo" --force > /dev/null
      done
    done

    log "Teardown: checking for leftovers"
    # Two queries, because tag filters in one call are combined with AND.
    leftovers="$(for filter in Key=purpose,Values=portfolio-test "Key=kubernetes.io/cluster/$cluster"; do
      aws resourcegroupstaggingapi get-resources --profile "$profile" --region "$region" \
        --tag-filters "$filter" --query 'ResourceTagMappingList[].ResourceARN' --output text
    done | tr '\t' '\n' | grep -v -e ':kms:' -e '^$' | sort -u || true)"
    if [ "$leftovers" != "" ]; then
      echo "Tagged resources still present (the tagging API can lag a few minutes):"
      echo "$leftovers"
      status=1
    else
      echo "No tagged resources left. KMS keys are scheduled for deletion after 7 days."
    fi
    aws logs describe-log-groups --profile "$profile" --region "$region" \
      --log-group-name-prefix "/aws/eks/$cluster" --query 'logGroups[].logGroupName' --output text
  fi
  close_tunnel
  if [ "$keep_state" = true ]; then
    # Never delete the only record of billable resources.
    echo "terraform destroy failed. State kept in $work_dir; backend_override.tf left in place." >&2
    echo "Fix the cause, then rerun terraform destroy in $env_dir with: ${tf_vars[*]}" >&2
  else
    rm -f "$env_dir/backend_override.tf"
    rm -rf "$work_dir"
  fi
  exit "$status"
}
trap teardown EXIT

log "Pre-flight: live tests run private-only (offline checks)"
"${pytest[@]}" tests/test_private_live.py tests/test_check_private_plan.py

log "Confirming the target account"
account="$(aws sts get-caller-identity --profile "$profile" --query Account --output text)"
aws sts get-caller-identity --profile "$profile"
read -r -p "Type the account ID ($account) to create billable resources in it: " answer
[ "$answer" = "$account" ] || { echo "Aborted."; exit 1; }

caller_arn="$(aws sts get-caller-identity --profile "$profile" --query Arn --output text)"
role_name="$(echo "$caller_arn" | cut -d/ -f2)"
admin_role_arn="$(aws iam get-role --profile "$profile" --role-name "$role_name" --query Role.Arn --output text)"

log "Planning dev (private-only) with local state in $work_dir (cluster admin: $admin_role_arn)"
cat > "$env_dir/backend_override.tf" <<EOF
terraform {
  backend "local" {
    path = "$work_dir/terraform.tfstate"
  }
}
EOF
# Scoped to this process: Terraform, kubectl and Helm read it.
export AWS_PROFILE="$profile"
terraform -chdir="$env_dir" init -input=false -reconfigure > /dev/null
set_tf_vars
terraform -chdir="$env_dir" plan -input=false -out="$work_dir/live.tfplan" "${tf_vars[@]}" > /dev/null
terraform -chdir="$env_dir" show -json "$work_dir/live.tfplan" > "$work_dir/live-plan.json"

log "Pre-flight: refusing the plan if anything in it is internet-facing"
python3 scripts/check_private_plan.py "$work_dir/live-plan.json"

log "Applying the checked plan"
applied=true
terraform -chdir="$env_dir" apply -input=false "$work_dir/live.tfplan"

open_tunnel

log "Checking the cluster"
kubectl wait --for=condition=Ready node -l harbor-goods.example.com/pool=system --timeout=10m

log "Installing the add-ons and the catalog API through the tunnel, images from ECR pull-through caches"
access_json="$(terraform -chdir="$env_dir" output -json private_access)"
registry="$(jq -r .registry <<< "$access_json")"
prefix_args=()
while read -r upstream prefix; do
  prefix_args+=(--prefix "$upstream=$prefix")
done < <(jq -r '.pull_through_prefixes | to_entries[] | "\(.key) \(.value)"' <<< "$access_json")
kubectl kustomize gitops/environments/dev > "$work_dir/apps.yaml"
uv run --no-project --with-requirements tests/requirements.txt python scripts/live_install.py \
  "$work_dir/apps.yaml" "$work_dir/install" --registry "$registry" "${prefix_args[@]}" \
  --instance-profile "$(jq -r .karpenter_instance_profile <<< "$access_json")"

kubectl apply -f gitops/namespaces/
while IFS=$'\t' read -r name chart repo version namespace; do
  repo_args=()
  [ "$repo" = "-" ] || repo_args=(--repo "$repo")
  helm upgrade --install "$name" "$chart" "${repo_args[@]}" --version "$version" --namespace "$namespace" \
    --values "$work_dir/install/$name.values.yaml" --wait --timeout 15m
done < "$work_dir/install/releases.tsv"
kubectl apply -f "$work_dir/install/karpenter.yaml"
helm upgrade --install catalog-api charts/catalog-api --namespace catalog-api \
  --values "$work_dir/install/catalog-api.values.yaml" --wait --timeout 15m

log "Checking that Karpenter launched a workloads node for the catalog API"
kubectl get nodes -l karpenter.sh/nodepool=workloads -o name | grep -q . || { echo "no Karpenter node"; exit 1; }

# Health is checked from inside the VPC: a pod in the cluster calls the Service.
log "Running the chart's connection test pod"
ecr_public_prefix="$(jq -r '.pull_through_prefixes["public.ecr.aws"]' <<< "$access_json")"
helm template catalog-api charts/catalog-api --namespace catalog-api \
  --show-only templates/tests/test-connection.yaml |
  sed "s#image: public.ecr.aws/#image: $registry/$ecr_public_prefix/#" | kubectl apply -f -
kubectl -n catalog-api wait pod/catalog-api-test-connection \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=5m

# The dev values carry a placeholder ACM certificate, so the internal ALB is not expected to
# come up; docs/live-test.md lists what a private-only run does not prove.
log "All live checks passed; tearing down"
