# Changelog

All notable changes to this project are documented in this file. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Terraform modules `network`, `eks`, `karpenter`, `observability`, `argocd-bootstrap` and the `platform`
  composition, with `dev` and `prod` environment roots on Kubernetes 1.35.
- EKS Pod Identity roles for the AWS Load Balancer Controller, Karpenter, the EBS CSI driver and the CloudWatch agent.
- Container Insights through the `amazon-cloudwatch-observability` add-on, encrypted log groups with retention, an
  encrypted SNS alarm topic and alarms for failed nodes, node CPU and memory, and running pods.
- `catalog-api` Helm chart with a strict `values.schema.json`, HPA, PDB, NetworkPolicy, HTTPS-only ALB Ingress and a
  connection test hook.
- Argo CD app-of-apps with one folder per environment, AppProjects, sync waves, and Karpenter NodePool and
  EC2NodeClass per environment.
- Offline verification through `make verify`: mocked `terraform test`, `tflint`, `helm lint`, `kubeconform`, pytest
  render assertions, Checkov and Trivy.
- Manual `make test-live` for the dev environment, with guaranteed teardown.
- CI calling the shared `gamaware/.github` reusable workflows pinned by commit SHA (see
  `.github/workflows/ci.yml`), plus OSSF Scorecard.
- Seven architecture decision records, context and deployment diagrams, and the social preview.
- Private API endpoint in every environment (ADR 0007): `endpoint_public_access = false` in the `eks` module, a
  Session Manager relay and Session Manager VPC endpoints in every environment, and `scripts/api-tunnel.sh` for
  kubectl and the Helm provider (`kubernetes_api_url`, `install_argocd`).
- Private-only live tests (ADR 0006): `private_only` mode with no internet path, VPC endpoints, a private API
  endpoint reached through a Session Manager relay, ECR pull-through caches, a Helm install in place of Argo CD, and a
  pre-flight (`scripts/check_private_plan.py`, `tests/test_private_live.py`) that refuses internet-facing or
  Route 53 resources before anything is applied.
