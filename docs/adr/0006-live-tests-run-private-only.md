# 0006. Live tests run private-only

## Status

Accepted

## Context

The live test creates real resources in a sandbox AWS account. A run must never expose anything to the internet:
no public IP address, no public load balancer or API endpoint, no security group open to `0.0.0.0/0` or `::/0`, and
no Route 53 zone or record. The dev environment as designed has NAT egress and public subnets for load balancers, and
Argo CD pulls from GitHub. None of that is acceptable in a live run.

## Decision

`scripts/test-live.sh` applies dev with `private_only = true`:

- The VPC has no internet gateway, public subnet, NAT gateway, Elastic IP or default route. Interface endpoints and an
  S3 gateway endpoint carry every AWS API call.
- The API endpoint is private, as in every environment ([ADR 0007](0007-private-api-endpoint-in-every-environment.md)).
  The run reaches it through the Session Manager relay instead of a CodeBuild project in the VPC: the tunnel keeps
  kubectl and Helm on the operator's machine, and the relay needs only the Session Manager endpoints.
- Nodes pull images through ECR pull-through cache repositories for `public.ecr.aws` and `registry.k8s.io`.
- Argo CD is not installed. `scripts/live_install.py` installs the charts, versions and values the dev Applications
  declare with Helm through the tunnel.
- Karpenter runs in isolated-VPC mode with an instance profile that Terraform creates, because the VPC has no IAM
  endpoint. The live install forces the catalog API Ingress to an internal ALB that accepts the VPC range only.
- The rule covers live runs only. The dev and prod configurations in the repository keep their internet-facing ALB,
  and NAT egress, because showing that design is the point of the lab.

Before anything is created, the pre-flight tests must pass and `scripts/check_private_plan.py` must find nothing
internet-facing or Route 53 in the saved plan; only that plan is applied.

## Consequences

- A live run cannot expose anything, and a change that would makes the pre-flight fail before any resource exists.
- Argo CD convergence, sync waves and AppProject rules are verified offline only.
- Thirteen interface endpoints add hourly cost to a run; the relay is a `t4g.nano`.
- Two install paths exist for the same charts: Argo CD in normal environments, Helm in live runs. Both read the same
  Application manifests, and a test checks that the live install keeps their pinned versions.
- The private-only path has not run against AWS yet; the first run may surface missing endpoints or permissions.

## Compliance

- `infra/terraform/envs/dev/tests/dev.tftest.hcl`: `live_test_configuration_is_private_only` (private endpoint, no NAT
  gateway or public subnet, pull-through caches present, no Argo CD).
- `infra/terraform/modules/network/tests/network.tftest.hcl`: `private_only_has_no_internet_path`.
- `infra/terraform/modules/private-access/tests/private_access.tftest.hcl`: relay with no public IP or inbound rule;
  pull-through rules for every upstream registry.
- `tests/test_private_live.py` and `tests/test_check_private_plan.py`: internal ALB, VPC-only inbound range, no
  LoadBalancer Services, no Route 53 or ExternalDNS, no node public IPs, images through ECR, and the plan check rules.
- `scripts/test-live.sh` runs the tests and the plan check before `terraform apply`.

## Notes

Alternatives considered:

- A public API endpoint limited to the operator's `/32`: rejected, because nothing in the account may be public; ADR 0007
  later made the endpoint private in every environment.
- A CodeBuild project in VPC mode running kubectl and Helm: no public exposure either, but it needs a build
  definition, source upload and log retrieval for every step; the Session Manager tunnel keeps the run interactive.
- An in-cluster Git server or OCI charts in ECR for Argo CD: possible, but it tests a different delivery path than
  the one the environments use, for more moving parts than the Helm install.
