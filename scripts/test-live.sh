#!/usr/bin/env bash
# Manual live test of the dev environment. It creates real, billable AWS resources in the
# account behind the `dev` profile, checks them, and destroys them on exit, including on
# failure or Ctrl-C. Offline checks never call this. See docs/live-test.md.
#
# Requirements: aws CLI v2 with the `dev` profile, terraform, kubectl, curl, and the branch in
# GITOPS_REVISION pushed to the GitHub repository (Argo CD reads from there, not from disk).
set -euo pipefail

profile="dev"
region="us-east-1"
env_dir="infra/terraform/envs/dev"
cluster="harbor-goods-dev"
revision="${GITOPS_REVISION:-main}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/eks-gitops-live.XXXXXX")"
export KUBECONFIG="$work_dir/kubeconfig"
applied=false
keep_state=false

log() { printf '\n==> %s\n' "$*"; }

set_tf_vars() {
  tf_vars=(
    "-var=admin_role_arns=[\"$admin_role_arn\"]"
    "-var=public_access_cidrs=[\"$operator_cidr\"]"
    "-var=gitops_target_revision=$revision"
    '-var=extra_tags={purpose="portfolio-test"}'
  )
}

teardown() {
  local status=$?
  set +e
  if [ "$applied" = true ]; then
    # Apply may have failed after Argo CD started creating ALBs and nodes; reach the cluster anyway.
    aws eks update-kubeconfig --name "$cluster" --region "$region" --profile "$profile" > /dev/null 2>&1
    log "Teardown: removing workloads so their load balancers and nodes are deleted first"
    # Stop the root app from recreating what is deleted below.
    kubectl -n argocd patch application root --type merge -p '{"spec":{"syncPolicy":null}}'
    # The Ingress must go while the load balancer controller still runs, or its ALB is orphaned.
    kubectl -n argocd delete application storefront --wait --timeout=10m
    # Karpenter must still run to terminate the instances it launched.
    kubectl -n argocd delete application karpenter-nodepools --wait --timeout=10m
    kubectl wait --for=delete node -l karpenter.sh/nodepool --timeout=10m

    log "Teardown: terraform destroy"
    if ! terraform -chdir="$env_dir" destroy -auto-approve -input=false "${tf_vars[@]}"; then
      status=1
      keep_state=true
    fi

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

log "Confirming the target account"
account="$(aws sts get-caller-identity --profile "$profile" --query Account --output text)"
aws sts get-caller-identity --profile "$profile"
read -r -p "Type the account ID ($account) to create billable resources in it: " answer
[ "$answer" = "$account" ] || { echo "Aborted."; exit 1; }

caller_arn="$(aws sts get-caller-identity --profile "$profile" --query Arn --output text)"
role_name="$(echo "$caller_arn" | cut -d/ -f2)"
admin_role_arn="$(aws iam get-role --profile "$profile" --role-name "$role_name" --query Role.Arn --output text)"
operator_cidr="$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')/32"

log "Applying dev with local state in $work_dir (cluster admin: $admin_role_arn, API allowed from $operator_cidr)"
cat > "$env_dir/backend_override.tf" <<EOF
terraform {
  backend "local" {
    path = "$work_dir/terraform.tfstate"
  }
}
EOF
# Scoped to this process: Terraform and the Helm provider's `aws eks get-token` both read it.
export AWS_PROFILE="$profile"
terraform -chdir="$env_dir" init -input=false -reconfigure > /dev/null
set_tf_vars
applied=true
terraform -chdir="$env_dir" apply -auto-approve -input=false "${tf_vars[@]}"

log "Checking the cluster"
aws eks update-kubeconfig --name "$cluster" --region "$region" --profile "$profile" > /dev/null
kubectl wait --for=condition=Ready node -l harbor-goods.example.com/pool=system --timeout=10m

log "Checking that Argo CD synced the platform add-ons"
for app in aws-load-balancer-controller metrics-server karpenter karpenter-nodepools; do
  kubectl -n argocd wait "application/$app" --for=jsonpath='{.status.health.status}'=Healthy --timeout=20m
done

log "Checking that Karpenter launched a workloads node for the storefront"
kubectl -n storefront rollout status deployment/storefront --timeout=15m
kubectl get nodes -l karpenter.sh/nodepool=workloads -o name | grep -q . || { echo "no Karpenter node"; exit 1; }

log "Running the chart's connection test pod"
helm template storefront charts/storefront --namespace storefront \
  --show-only templates/tests/test-connection.yaml | kubectl apply -f -
kubectl -n storefront wait pod/storefront-test-connection \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=5m

# The dev values carry a placeholder ACM certificate, so the ALB is not expected to come up;
# docs/live-test.md explains how to test the HTTPS path with a real certificate.
log "All live checks passed; tearing down"
