# 0004. Plain resources in small local modules instead of the community EKS module

Status: Accepted

## Context

`terraform-aws-modules/eks` and `terraform-aws-modules/vpc` cover most EKS setups and are widely used. They are also
large, expose hundreds of inputs, and change defaults between major versions. This lab has to show each security
decision in code and test it offline with mocked providers.

## Decision

Five local modules built from plain `aws_*` resources: `network`, `eks`, `karpenter`, `observability` and
`argocd-bootstrap`, composed by `platform`. Environment roots in `envs/` only choose sizes, CIDR ranges and the
Kubernetes version. Provider versions are pinned in the environment roots and locked for Linux and macOS.

## Alternatives

- Community modules: less code to own, faster to start. A client already on them keeps them; the tests here move over
  with small changes.
- One flat root per environment: duplicates every resource between dev and prod.

## Consequences

- About 2,000 lines of module Terraform to maintain, each resource visible and reviewable.
- Every behaviour worth keeping has a `terraform test` assertion that runs without AWS credentials.
- Upstream fixes to the community modules do not arrive automatically.

## Compliance

`make terraform` runs `terraform fmt`, `validate`, `tflint` (terraform and aws rulesets) and `terraform test` in every
module with a `tests/` folder and in both roots; the roots' tests cover the `platform` composition. Checkov and
Trivy scan the same code with no skips.
