# 0007. Private API endpoint in every environment

## Status

Accepted

## Context

The EKS API endpoint could be public, limited to a list of CIDR blocks (`public_access_cidrs`). Even restricted, a
public endpoint is an internet-facing control plane: it depends on the allow list staying narrow and on AWS
authentication alone, and scanners flag it (Semgrep `eks-public-endpoint-enabled`). The live test already needed a way
to reach a private endpoint (ADR 0006).

## Decision

The `eks` module sets `endpoint_public_access = false` as a literal, in every environment; the `public_access_cidrs`
input is removed. Operators and Terraform reach the private endpoint through the `private-access` module, which every
environment now creates:

- A relay instance in a private subnet, with no public IP address and no inbound security group rules. The cluster
  security group accepts HTTPS from the relay's security group.
- Session Manager interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) in every VPC, so the relay needs no
  internet egress; its only outbound rule is HTTPS to the VPC range.
- `scripts/api-tunnel.sh` (printed by each root as `api_tunnel_command`) forwards `127.0.0.1:8443` to the endpoint and
  points the kubeconfig at it, with the endpoint's host name kept for TLS verification.

Terraform's Helm provider, which installs Argo CD, takes the tunnel as `kubernetes_api_url`. From outside the VPC, the
first apply runs with `install_argocd = false`; the operator opens the tunnel and applies again with
`kubernetes_api_url = "https://127.0.0.1:8443"`. A runner inside the VPC needs neither.

## Consequences

- Nothing about the control plane is reachable from the internet, in any environment.
- Every cluster access needs IAM permission for `ssm:StartSession` on the relay and the Session Manager plugin; access
  is logged in CloudTrail as Session Manager sessions.
- A first apply from a laptop is two steps. CI that applies Terraform needs a runner inside the VPC or the same tunnel.
- The relay and three interface endpoints per VPC add a small hourly cost.
- The ALB for the catalog API stays internet-facing in dev and prod: it is the application's front door, not the
  control plane.

## Compliance

- `infra/terraform/modules/eks/tests/eks.tftest.hcl`: `api_endpoint_is_private_only`.
- `infra/terraform/envs/dev/tests/dev.tftest.hcl`: `api_is_reached_through_the_relay`.
- `infra/terraform/modules/network/tests/network.tftest.hcl`: `every_vpc_gets_session_manager_endpoints`.
- `infra/terraform/modules/private-access/tests/private_access.tftest.hcl`: relay with no public IP or inbound rule.
- Semgrep `p/default` and Trivy run in CI; `scripts/check_private_plan.py` refuses a public endpoint in a live plan.

## Notes

Alternatives considered:

- A public endpoint limited to operator CIDRs: rejected, because the control plane stays internet-facing.
- A client VPN or a bastion with SSH: more to operate, and SSH needs an inbound rule; Session Manager needs none.
- A CodeBuild project in the VPC running Terraform and kubectl: suits CI, but adds a build definition for every manual
  step. It remains an option for the pipeline.
