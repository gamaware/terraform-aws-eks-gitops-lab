# Live test (manual)

Run `make test-live` to invoke [`scripts/test-live.sh`](../scripts/test-live.sh), which provisions, checks and tears
down the dev environment in a real AWS account. CI excludes this test, and `make verify` has no dependency on it.

## What it costs

Start a run only deliberately: it provisions billable resources for roughly 40 to 60 minutes, including an EKS control
plane, two `m7i.large` system nodes, at least one Karpenter node, a NAT gateway, KMS keys, CloudWatch log groups
and alarms.

## Prerequisites

- AWS CLI v2 must have a `dev` profile targeting a sandbox account, with permissions to create IAM roles, EKS, EC2,
  KMS, SQS, EventBridge, SNS and CloudWatch resources.
- The path must include Terraform 1.14, kubectl, Helm 4 and curl.
- The test branch must already exist on GitHub because Argo CD reads that repository and does not read local files.
  Set `GITOPS_REVISION=<branch>` when testing a branch other than `main`.

## What it does

1. Displays `aws sts get-caller-identity --profile dev`, then pauses until the operator types back the account ID.
2. Replaces the `terraform.tfvars` placeholders with the operator's current role as sole cluster admin and public IP
   (`/32`) as the sole address permitted to access the API endpoint.
3. Applies `infra/terraform/envs/dev`, storing local state in a temporary directory and assigning every resource the
   default `purpose=portfolio-test` tag.
4. Waits first for system nodes and then for the `aws-load-balancer-controller`, `metrics-server`, `karpenter` and
   `karpenter-nodepools` Applications to reach `Healthy`.
5. Waits for the `catalog-api` Deployment before confirming that Karpenter launched a `workloads` node and executing the
   chart's connection test pod against the Service.
6. Performs cleanup on every exit, regardless of success or failure: disables root Application re-syncing, removes the
   `catalog-api` Application so the load balancer controller deletes its ALB, and removes the NodePools so Karpenter
   terminates its nodes. It then executes `terraform destroy` and lists remaining resources tagged
   `purpose=portfolio-test` or `kubernetes.io/cluster/harbor-goods-dev`.

After a failed `terraform destroy`, the script retains the state directory and reports its location; keep that directory
until destruction succeeds.

## What it does not prove

- Public HTTPS remains untested because the placeholder ACM certificate in the dev values prevents creation of the
  ALB listener. To test this path, request a certificate for a domain under your control, configure `ingress.host` and
  `ingress.certificateArn` in `gitops/environments/dev/values/catalog-api.yaml` on a branch, then run the test with
  `GITOPS_REVISION` pointing to that branch.
- Applying dev alone leaves prod sizing, multi-AZ NAT and upgrades unverified.

## Output

The only repository file the script writes is a temporary `backend_override.tf`; `.gitignore` excludes it, and the
script deletes it. Keep live-run logs and state out of commits.
