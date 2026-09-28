# Live test (manual)

Run `make test-live` to invoke [`scripts/test-live.sh`](../scripts/test-live.sh), which provisions, checks and tears
down the dev environment in a real AWS account. CI excludes this test, and `make verify` has no dependency on it.

## Live tests run private-only

A live run must never create a resource that accepts traffic from the internet. The dev configuration and a
pre-flight enforce it:

- The `catalog-api` Ingress in `gitops/environments/dev/values/catalog-api.yaml` uses an internal ALB
  (`scheme: internal`) whose security group accepts only the dev VPC range `10.10.0.0/16` (`inboundCidrs`), so no
  `0.0.0.0/0` or `::/0` ingress rule is created.
- Nodes never get public IP addresses: private subnets set `map_public_ip_on_launch = false`, the system launch
  template has no network interface override, and both EC2NodeClasses set `associatePublicIPAddress: false`.
- The EKS API endpoint stays public, limited to the operator's single `/32` address. A private-only endpoint would
  break the run: Terraform's Helm provider installs Argo CD and kubectl runs the checks from the operator's machine,
  which has no route into the VPC. An empty allow list is not an option either, because EKS treats an enabled public
  endpoint with no CIDRs as open to `0.0.0.0/0`.
- The internet gateway, the NAT gateway and its Elastic IP stay: they are egress-only, and nodes need them to pull
  images and let Argo CD read GitHub.

The same rules run offline in `make verify`: `tests/test_private_live.py` checks the dev manifests and the plan
checker, and the `network` and `eks` Terraform tests check subnets and launch templates. Before it applies anything,
`scripts/test-live.sh` refuses to continue unless:

1. The local `gitops/` and `charts/` match the pushed `GITOPS_REVISION`, so the checks cover what Argo CD deploys.
2. `tests/test_private_live.py` passes.
3. [`scripts/check_private_plan.py`](../scripts/check_private_plan.py) finds no internet-facing resource in the saved
   plan: no internet-facing load balancer, no `0.0.0.0/0` or `::/0` security group ingress, no public IP on instances,
   launch templates or subnets, no Elastic IP beyond one per NAT gateway, and an API endpoint limited to one `/32`.

Only the plan that passed the check is applied.

## What it costs

Start a run only deliberately: it provisions billable resources for roughly 40 to 60 minutes, including an EKS control
plane, two `m7i.large` system nodes, at least one Karpenter node, a NAT gateway, KMS keys, CloudWatch log groups
and alarms.

## Prerequisites

- AWS CLI v2 must have a `dev` profile targeting a sandbox account, with permissions to create IAM roles, EKS, EC2,
  KMS, SQS, EventBridge, SNS and CloudWatch resources.
- The path must include Terraform 1.14, kubectl, Helm 4, uv and curl.
- The test branch must already exist on GitHub because Argo CD reads that repository and does not read local files.
  Set `GITOPS_REVISION=<branch>` when testing a branch other than `main`.

## What it does

1. Displays `aws sts get-caller-identity --profile dev`, then pauses until the operator types back the account ID.
2. Replaces the `terraform.tfvars` placeholders with the operator's current role as sole cluster admin and public IP
   (`/32`) as the sole address permitted to access the API endpoint.
3. Runs the private-only pre-flight above, then applies the checked plan of `infra/terraform/envs/dev`, storing local
   state in a temporary directory and assigning every resource the default `purpose=portfolio-test` tag.
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

- HTTPS through the ALB remains untested because the placeholder ACM certificate in the dev values prevents creation
  of the ALB listener. With a real certificate on a branch, the ALB is still internal and reachable only from inside
  the VPC; an internet-facing ALB is never part of a live run.
- Prod's internet-facing ALB is checked offline only.
- Applying dev alone leaves prod sizing, multi-AZ NAT and upgrades unverified.

## Output

The only repository file the script writes is a temporary `backend_override.tf`; `.gitignore` excludes it, and the
script deletes it. Keep live-run logs and state out of commits.
