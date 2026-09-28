# CLAUDE.md

Project instructions for `terraform-aws-eks-gitops-lab`. Global rules in `~/.claude/CLAUDE.md` also apply.

## Overview

Portfolio lab: Amazon EKS in Terraform, a Helm chart for a fictional workload (the "Harbor Goods" catalog API), and an
Argo CD app-of-apps with one folder per environment. Everything is verified offline with `make verify`; the only
AWS-touching target is the manual `make test-live`.

## Layout

| Path | Purpose |
| --- | --- |
| `infra/terraform/modules/<name>/` | network, eks, karpenter, observability, private-access, argocd-bootstrap, platform |
| `infra/terraform/modules/<name>/tests/` | `terraform test` with mocked providers (`infra/terraform/tests/mocks/`) |
| `infra/terraform/envs/{dev,prod}/` | thin roots; their tests cross-check names against `gitops/` |
| `charts/catalog-api/` | Helm chart with strict `values.schema.json` and `ci/` values |
| `gitops/{projects,applications}/` | AppProjects and environment-neutral Applications |
| `gitops/environments/<env>/` | Kustomize root of each app-of-apps, env patches, Karpenter pools, app values |
| `tests/` | pytest render assertions on the chart and the app-of-apps |
| `scripts/` | `install-tools.sh`, `render.sh`, `test-live.sh`, `live_install.py`, `check_private_plan.py` |
| `docs/adr/`, `docs/diagrams/` | decisions and architecture views |

## Commands

- `make verify`: everything offline (Terraform, Helm, kubeconform, pytest, Checkov, Trivy).
- `make terraform`, `make helm`, `make kubeconform`, `make render-test`, `make checkov`, `make trivy`: parts of it.
- `make test-live`: manual only, creates billable resources in the `dev` profile account. Never run it unasked.

## Coupled names

Terraform creates and `gitops/` references these; change both sides together. The env tests fail otherwise.

- Cluster and VPC `Name` tag: `harbor-goods-<env>`.
- Karpenter interruption queue `harbor-goods-<env>-karpenter`, node role `harbor-goods-<env>-karpenter-node`.
- Discovery tag `karpenter.sh/discovery=harbor-goods-<env>` on private subnets and the cluster security group.
- Load balancer controller chart version and `modules/eks/policies/aws-load-balancer-controller-v<version>.json`.
- Dev VPC CIDR `10.10.0.0/16`: `envs/dev/main.tf` and `DEV_VPC` in `tests/test_private_live.py`.

## Rules

- No scanner skips or lint suppressions. Fix the finding.
- Pin everything: provider constraints, chart versions, image digests, AMI aliases, action SHAs.
- Only documentation placeholders: account `111122223333`, `example.com`, `203.0.113.0/24`.
- Every Terraform behaviour change gets a `tftest.hcl` assertion; every chart or gitops change gets a pytest check.
- Live tests run private-only (ADR 0006): dev with `private_only = true` has no internet path, public endpoint or
  Route 53. Only the live path is private; the dev and prod examples keep their public ALB, NAT and endpoint
  options. `scripts/check_private_plan.py` is a byte-identical copy shared across repos; never edit it here.
- Conventional commits, feature branches, no AI attribution anywhere.
