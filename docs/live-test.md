# Live test (manual)

`make test-live` runs [`scripts/test-live.sh`](../scripts/test-live.sh). It creates the dev environment in a real AWS
account, checks it and destroys it. CI never runs it, and `make verify` does not depend on it.

## What it costs

The run creates billable resources for about 40 to 60 minutes: an EKS control plane, two `m7i.large` system nodes, at
least one Karpenter node, a NAT gateway, KMS keys, CloudWatch log groups and alarms. Run it only when you mean to.

## Prerequisites

- AWS CLI v2 with a `dev` profile for a sandbox account, and permission to create IAM roles, EKS, EC2, KMS, SQS,
  EventBridge, SNS and CloudWatch resources.
- Terraform 1.14, kubectl, Helm 4 and curl on the path.
- The branch to test pushed to GitHub. Argo CD reads the repository from GitHub, not from your disk; set
  `GITOPS_REVISION=<branch>` to test anything other than `main`.

## What it does

1. Prints `aws sts get-caller-identity --profile dev` and waits until you type the account ID back.
2. Uses your current role as the only cluster admin and your public IP (`/32`) as the only address allowed to reach
   the API endpoint, instead of the placeholders in `terraform.tfvars`.
3. Applies `infra/terraform/envs/dev` with local state in a temporary directory and the default tag
   `purpose=portfolio-test` on every resource.
4. Waits for the system nodes, then for the `aws-load-balancer-controller`, `metrics-server`, `karpenter` and
   `karpenter-nodepools` Applications to report `Healthy`.
5. Waits for the storefront Deployment, checks that Karpenter launched a `workloads` node, and runs the chart's
   connection test pod against the Service.
6. On exit, success or failure: stops the root Application from re-syncing, deletes the storefront Application (so the
   load balancer controller removes its ALB), deletes the NodePools (so Karpenter terminates its nodes), runs
   `terraform destroy`, and lists any resource still tagged `purpose=portfolio-test` or
   `kubernetes.io/cluster/harbor-goods-dev`.

If `terraform destroy` fails, the script keeps the state directory and says where it is. Never delete it until the
destroy succeeds.

## What it does not prove

- The public HTTPS path. The dev values carry a placeholder ACM certificate, so the ALB listener cannot be created. To
  test it, request a certificate for a domain you control, set `ingress.host` and `ingress.certificateArn` in
  `gitops/environments/dev/values/storefront.yaml` on a branch, and run with `GITOPS_REVISION` set to that branch.
- Prod sizing, multi-AZ NAT or upgrades. Only dev is applied.

## Output

The script writes nothing into the repository except a temporary `backend_override.tf`, which `.gitignore` excludes
and the script removes. Do not commit logs or state from a live run.
