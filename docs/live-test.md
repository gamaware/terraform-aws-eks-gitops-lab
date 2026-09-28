# Live test (manual)

Run `make test-live` to invoke [`scripts/test-live.sh`](../scripts/test-live.sh), which provisions, checks and tears
down the dev environment in a real AWS account. CI excludes this test, and `make verify` has no dependency on it.

## Private-only

Live tests run private-only: a live run creates nothing that is reachable from the internet, nothing with a public IP
address, and nothing in Route 53. `scripts/test-live.sh` applies `infra/terraform/envs/dev` with
`private_only = true`, which changes the dev environment as follows. The rule covers live runs only: the dev and prod
configurations in the repository keep their internet-facing ALB and NAT egress; the API endpoint is private everywhere
([ADR 0007](adr/0007-private-api-endpoint-in-every-environment.md)).

- **No internet path.** The VPC has no internet gateway, public subnet, NAT gateway or Elastic IP, and no default
  route. Interface VPC endpoints (EC2, ECR API and Docker, EKS, EKS Auth, Elastic Load Balancing, CloudWatch Logs and
  Monitoring, SQS, STS, and the three Session Manager services) and an S3 gateway endpoint carry every AWS API call.
  They accept HTTPS from the VPC range only.
- **Private API endpoint.** `endpoint_public_access` is `false` in every environment. The operator reaches the
  endpoint through Session Manager port forwarding via the relay instance every environment has
  in a private subnet: no public IP address, no inbound security group rules, HTTPS out to the VPC only. The cluster
  security group accepts the relay by security group. kubectl and Helm use `https://127.0.0.1:8443` with the
  endpoint's own host name for TLS verification.
- **Images through ECR.** ECR pull-through cache rules mirror `public.ecr.aws` and `registry.k8s.io`; nodes may create
  and fill those cache repositories on first pull. Every image the run uses is rewritten to the cache.
- **No Argo CD.** Argo CD syncs from GitHub, which a VPC without internet cannot reach, so the live run does not
  install it. [`scripts/live_install.py`](../scripts/live_install.py) reads the dev app-of-apps and installs the same
  charts, pinned versions and values with Helm through the tunnel: Karpenter (in isolated-VPC mode, with an instance
  profile Terraform creates because the VPC has no IAM endpoint), the AWS Load Balancer Controller (Shield and WAF
  integration off), metrics-server, the Karpenter NodePools and EC2NodeClass, and the catalog API.
- **Internal ALB only.** `scripts/live_install.py` forces the live catalog API Ingress to `scheme: internal` with
  `inboundCidrs` set to the VPC range, so no security group opens `0.0.0.0/0` or `::/0`. The live EC2NodeClass sets
  `associatePublicIPAddress: false`, and subnets set `map_public_ip_on_launch = false`.
- **No Route 53.** No hosted zone, record or ExternalDNS; the ALB host name is an `example.com` placeholder.

### Pre-flight

Before it creates anything, `scripts/test-live.sh` refuses to continue unless:

1. `tests/test_private_live.py` and `tests/test_check_private_plan.py` pass.
2. [`scripts/check_private_plan.py`](../scripts/check_private_plan.py) finds nothing internet-facing in the saved plan
   (`terraform show -json`): no internet gateway, public NAT gateway, Elastic IP or default route to the internet, no
   public load balancer, no `0.0.0.0/0` or `::/0` ingress, no public IP address, no public API endpoint and no Route 53
   resource.

Only the plan that passed the check is applied.

### Offline tests

`make verify` runs the same rules without AWS: the `live_test_configuration_is_private_only` run in
`infra/terraform/envs/dev/tests/dev.tftest.hcl`, the `api_endpoint_is_private_only` run of the `eks` tests, the
private-only runs of the `network` and `private-access` module tests, and the pytest files above, which also check the
images, chart versions, instance profile and Karpenter settings `scripts/live_install.py` produces.

### How health is checked

From inside the VPC only: kubectl waits for the system nodes, each Helm release waits for its workloads, the run
checks that Karpenter launched a `workloads` node, and the chart's connection test pod calls the catalog API Service
from within the cluster. Nothing is called over the internet.

## What it costs

Start a run only deliberately: it provisions billable resources for roughly 40 to 60 minutes, including an EKS control
plane, two `m7i.large` system nodes, at least one Karpenter node, a `t4g.nano` relay, 13 interface endpoints in three
Availability Zones, KMS keys, CloudWatch log groups and alarms.

## Prerequisites

- AWS CLI v2 must have a `dev` profile targeting a sandbox account, with permissions to create IAM roles, EKS, EC2,
  VPC endpoint, ECR, KMS, SQS, EventBridge, SNS, CloudWatch and Session Manager resources.
- The path must include Terraform 1.14, kubectl, Helm 4, jq, uv and the Session Manager plugin for the AWS CLI.
- Accounts whose policies require tags on create: set `LIVE_EXTRA_TAGS` to a JSON object of string tags, for example
  `LIVE_EXTRA_TAGS='{"CostCenter":"YOUR_COST_CENTER"}' make test-live`. The run adds them to the Terraform default
  tags, the Karpenter EC2NodeClass, the load balancer controller's default tags and the pull-through cache repository
  creation templates. Pass them at run time; do not commit account-specific values.

## What it does

1. Runs the offline pre-flight tests.
2. Displays `aws sts get-caller-identity --profile dev`, then pauses until the operator types back the account ID.
3. Saves a plan of `infra/terraform/envs/dev` with `private_only = true`, the operator's current role as sole cluster
   admin and the default `purpose=portfolio-test` tag, refuses it if the plan check fails, and applies it with local
   state in a temporary directory.
4. Opens Session Manager port forwarding to the private API endpoint and waits for the system nodes.
5. Installs the add-ons, NodePools and catalog API through the tunnel, confirms that Karpenter launched a `workloads`
   node, and runs the chart's connection test pod.
6. Performs cleanup on every exit, regardless of success or failure: uninstalls the catalog API so the load balancer
   controller deletes its ALB, removes the NodePools so Karpenter terminates its nodes, closes the tunnel, runs
   `terraform destroy`, deletes the pull-through cache repositories the first pulls created, and lists remaining
   resources tagged `purpose=portfolio-test` or `kubernetes.io/cluster/harbor-goods-dev`.

After a failed `terraform destroy`, the script retains the state directory and reports its location; keep that directory
until destruction succeeds.

## What it does not prove

- Argo CD: the live run cannot sync from GitHub without internet access, so the app-of-apps, sync waves and
  AppProject restrictions are verified offline only (render tests and kubeconform).
- HTTPS through the ALB: the placeholder ACM certificate in the dev values prevents the listener; the ALB is internal in
  every live run.
- The dev environment with `private_only = false` (NAT egress, Argo CD through the tunnel) and prod's internet-facing
  ALB are verified offline only.
- Prod sizing, multi-AZ NAT and upgrades.
- This private-only path has not run against AWS yet; the first run may need endpoint or IAM adjustments.

## Output

The only repository file the script writes is a temporary `backend_override.tf`; `.gitignore` excludes it, and the
script deletes it. Plans, rendered values and the kubeconfig stay in the temporary directory. Keep live-run logs and
state out of commits.
