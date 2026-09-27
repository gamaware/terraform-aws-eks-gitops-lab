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
- `storefront` Helm chart with a strict `values.schema.json`, HPA, PDB, NetworkPolicy, HTTPS-only ALB Ingress and a
  connection test hook.
- Argo CD app-of-apps with one folder per environment, AppProjects, sync waves, and Karpenter NodePool and
  EC2NodeClass per environment.
- Offline verification through `make verify`: mocked `terraform test`, `tflint`, `helm lint`, `kubeconform`, pytest
  render assertions, Checkov and Trivy.
- Manual `make test-live` for the dev environment, with guaranteed teardown.
- CI calling the shared `gamaware/.github` reusable workflows pinned to commit
  `1255caafb08b06cc4658318c4dd48f9dea946c9e`, plus OSSF Scorecard.
- Five architecture decision records, context and deployment diagrams, and the social preview.
