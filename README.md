# Amazon EKS with Terraform, Helm and Argo CD

An application on Amazon EKS, built in Terraform, packaged as a Helm chart and delivered by Argo CD from one folder
per environment. Everything is checked offline with a single `make verify`.

[![ci](https://github.com/gamaware/terraform-aws-eks-gitops-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/gamaware/terraform-aws-eks-gitops-lab/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Lab](https://img.shields.io/badge/type-lab-2356C2)

![Kubernetes on AWS (EKS): cluster in Terraform, Helm releases, fixes and upgrades](docs/assets/cover.png)

## What this proves

- **Cluster in Terraform, tested without AWS.** VPC, EKS, managed nodes, add-ons, Karpenter prerequisites and alarms
  are split into small modules. The 37 `terraform test` runs use mocked providers, so they need no credentials.
- **Pods get AWS access without keys or node roles.** EKS Pod Identity gives each controller one role bound to one
  service account. Nodes enforce IMDSv2 with a hop limit of 1, so pods cannot borrow the node's credentials.
- **The app ships as a Helm chart that rejects unsafe values.** The schema refuses `latest` tags, privileged ports,
  missing CPU or memory limits, an Ingress without TLS and a PDB that would block node drains.
- **GitOps with folders per environment, never branches.** An Argo CD app-of-apps syncs `gitops/environments/dev` and
  `prod`, and sync waves install controllers before the resources that need them. Tests fail if a name in Terraform
  and a name in the GitOps values drift apart.
- **Autoscaling and observability built in.** The HPA scales pods and Karpenter scales nodes within set limits.
  Container Insights, control plane logs and alarms go to CloudWatch and SNS.

## Inspect the deliverable

| Artifact | Where |
| --- | --- |
| EKS cluster, access entries, add-ons, Pod Identity | [`infra/terraform/modules/eks/`](infra/terraform/modules/eks/) |
| Karpenter IAM and interruption queue | [`infra/terraform/modules/karpenter/`](infra/terraform/modules/karpenter/) |
| Argo CD bootstrap (the only Kubernetes state in Terraform) | [`infra/terraform/modules/argocd-bootstrap/`](infra/terraform/modules/argocd-bootstrap/) |
| Environment roots | [`infra/terraform/envs/dev/`](infra/terraform/envs/dev/), [`prod/`](infra/terraform/envs/prod/) |
| Helm chart and its schema | [`charts/storefront/`](charts/storefront/), [`values.schema.json`](charts/storefront/values.schema.json) |
| App-of-apps per environment | [`gitops/environments/`](gitops/environments/) |
| Render assertions | [`tests/test_gitops.py`](tests/test_gitops.py), [`tests/test_chart.py`](tests/test_chart.py) |
| Live test with teardown | [`scripts/test-live.sh`](scripts/test-live.sh), [`docs/live-test.md`](docs/live-test.md) |

## Scenario and acceptance criteria

Harbor Goods, a fictional mid-size retailer, wants its storefront web tier on Kubernetes in AWS, with a dev cluster
for trying changes and a prod cluster that only changes through reviewed pull requests. The platform team must be able
to rebuild either cluster from code, and the storefront team must not be able to weaken cluster security from its own
folder.

The lab is done when:

- `make verify` passes with no scanner skips and no lint suppressions.
- Dev and prod are built from the same modules and differ only in their environment root and environment folder.
- No Helm value or GitOps file contains an account ID, role ARN or VPC ID, other than the placeholder ACM certificate
  ARN on the Ingress.
- The storefront runs non-root with a read-only root filesystem, scales between 3 and 12 replicas in prod, keeps at
  least 2 during node drains, and is reachable only over HTTPS.
- The Kubernetes API is reachable only from listed CIDR ranges, and cluster admins are listed explicitly.

## Architecture

![Context: a platform engineer changes the repository; Terraform builds the AWS platform, Argo CD syncs the cluster](docs/diagrams/01-context.png)

A platform engineer changes one repository. `terraform apply` builds the AWS side of each environment: VPC, EKS,
node roles, Pod Identity roles, the Karpenter interruption queue, logs and alarms. It then installs Argo CD with one
root Application. From there, Argo CD syncs everything inside the cluster from `gitops/environments/<env>`: the load
balancer controller, metrics-server, Karpenter and its NodePool, the storefront namespace and the storefront chart.
Shoppers reach the storefront through an ALB that terminates TLS.

The deployment view of one environment, with the numbered request, sync, scaling and telemetry paths, is in
[`docs/diagrams/02-deployment.png`](docs/diagrams/02-deployment.png). Sources are the `.drawio` files next to it.

## Verify locally

Prerequisites (versions used to build this repository):

| Tool | Version |
| --- | --- |
| Terraform | 1.14.5 |
| TFLint | 0.61.0 |
| Helm | 4.3.0 |
| kubectl (for `kubectl kustomize`) | 1.37 |
| uv (runs pytest and Checkov 3.3.19 in isolated environments) | 0.12 |
| Trivy | 0.74.0 |
| curl, tar, shasum | any |

```bash
make verify
```

Expected result, in under a minute once providers are cached (the first run downloads the AWS and Helm providers,
tflint plugins, kubeconform 0.8.0 with checksum verification and CRD schemas):

```text
Success! 2 passed, 0 failed.      # terraform test, once per tested module and root: 37 runs in total
Summary: 47 resources found in 10 files - Valid: 47, Invalid: 0, Errors: 0, Skipped: 0
50 passed in 0.34s
Passed checks: 235, Failed checks: 0, Skipped checks: 0      # Checkov, Terraform
Passed checks: 380, Failed checks: 0, Skipped checks: 0      # Checkov, rendered manifests
make verify: all offline checks passed
```

`make help` lists the individual targets. `make test-live` is separate and manual: it creates billable resources in
the account behind the `dev` AWS profile and destroys them on exit. Read [`docs/live-test.md`](docs/live-test.md)
before running it.

## Repository map

```text
infra/terraform/
  modules/          network, eks, karpenter, observability, argocd-bootstrap, platform (composition)
    <name>/tests/   terraform test with mocked providers (platform is covered by the root tests)
  envs/dev, prod/   thin roots: sizes, CIDRs, Kubernetes version; tests cross-check names with gitops/
  tests/mocks/      shared mock values (AWS documentation account 111122223333)
charts/storefront/  Helm chart, values.schema.json, ci/ values, connection test hook
gitops/
  projects/         AppProjects: platform, storefront
  applications/     environment-neutral Applications (add-ons, NodePools, namespaces, storefront)
  namespaces/       workload namespaces with Pod Security labels
  environments/     dev and prod: Kustomize root, patches, Karpenter pools, storefront values
tests/              pytest render assertions
scripts/            render.sh, install-tools.sh, test-live.sh
docs/               ADRs, diagrams, live test guide, cover and social preview
```

## Decisions and trade-offs

| Number | Title | Status |
| --- | --- | --- |
| [0001](docs/adr/0001-eks-pod-identity-for-controllers.md) | EKS Pod Identity for in-cluster controllers | Accepted |
| [0002](docs/adr/0002-app-of-apps-with-folders-per-environment.md) | Argo CD app-of-apps with one folder per environment | Accepted |
| [0003](docs/adr/0003-karpenter-for-workload-nodes.md) | Karpenter for workload nodes, a managed node group for the system | Accepted |
| [0004](docs/adr/0004-plain-resources-over-community-modules.md) | Plain resources in small local modules instead of the community EKS module | Accepted |
| [0005](docs/adr/0005-offline-verification-boundary.md) | What offline verification proves, and what only the live test proves | Accepted |

## Security and quality gates

| Gate | What it catches | Where |
| --- | --- | --- |
| `terraform fmt`, `validate`, `tflint` | Syntax, deprecated arguments, unused declarations, invalid AWS values | `make terraform`, shared `terraform` workflow |
| `terraform test` (mocked) | Open API endpoint, missing admins, IMDS reachable from pods, wrong Pod Identity bindings, unscoped Karpenter permissions, names that drift from `gitops/` | `make terraform` |
| `helm lint --strict` and the values schema | Unsafe or unknown chart values | `make helm`, shared `helm` workflow |
| `kubeconform` | Invalid manifests, including Argo CD and Karpenter custom resources | `make kubeconform` |
| pytest render assertions | Project escapes, wrong environment paths, wave order, unpinned charts and AMIs, pod security | `make render-test` |
| Checkov, Trivy | IaC and Kubernetes misconfiguration (no skips) | `make checkov trivy`, shared `security` workflow |
| gitleaks, detect-secrets | Committed secrets | pre-commit, shared `secrets` workflow |
| actionlint, zizmor | Workflow bugs and unpinned or over-privileged actions | pre-commit, shared `lint-actions` workflow |

CI runs with `permissions: {}` at the top, `contents: read` per job, actions pinned by SHA and no cloud credentials.

## Limits and production adaptations

- **Simulated:** Harbor Goods, its domain and its ACM certificate are fictional. The storefront image is an
  unprivileged NGINX that stands in for the real application.
- **Not run in CI:** nothing here has been applied by the pipeline. `make test-live` is the only path that touches
  AWS, and only when run by hand.
- **Out of scope:** cert-manager, ExternalDNS, Kyverno or Gatekeeper policies, a service mesh and a separate GitOps
  configuration repository.
- **A real engagement adds:** remote state in S3 with a bootstrap stack, a CI identity that plans and applies through
  OIDC, a private-only API endpoint reached through a VPN or bastion, the client's own image pipeline and domain, an
  upgrade runbook, and a handover session.

## Related work

Part of the [AWS DevOps portfolio](https://github.com/gamaware/aws-devops-portfolio). It backs the Upwork service
"your app on Kubernetes: Amazon EKS in Terraform, Helm deploys and Argo CD". Alex Garcia teaches Kubernetes and Helm in
hands-on labs as an adjunct professor at ITESO in Guadalajara, and this repository follows the same approach.

## License

[MIT](LICENSE)
