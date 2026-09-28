# 0005. What offline verification proves, and what only the live test proves

## Status

Accepted

## Context

Anyone reviewing this repository should be able to run its checks in minutes with no AWS account. Mocked tests,
rendered manifests and scanners can prove a lot, but not that EKS accepts the configuration, that IAM grants are
enough at run time, or that Argo CD converges.

## Decision

`make verify` is the offline gate, run the same way locally and in CI: Terraform fmt, validate, tflint and mocked
`terraform test`; `helm lint`; `kubeconform` on every rendered manifest, including Argo CD and Karpenter CRDs; pytest
render assertions; Checkov and Trivy. `make test-live` is separate, manual and never run by CI: it applies dev to
the `dev` AWS profile, waits for Argo CD, Karpenter and the storefront, runs the chart's connection test pod and
destroys everything on exit.

## Consequences

- A green badge means the documented offline checks passed, not that the stack was deployed.
- Mock values are fixed (see `infra/terraform/tests/mocks/aws.tfmock.hcl`), so tests assert inputs and wiring, not
  AWS behaviour.
- The dev values use a placeholder ACM certificate, so the live test checks the service through the connection pod,
  not the public HTTPS endpoint.

## Compliance

CI runs `make verify` plus the shared reusable workflows. `scripts/test-live.sh` asks for the account ID before
creating anything, tags every resource `purpose=portfolio-test`, keeps the state if a destroy fails and lists any
tagged resources left afterwards.

## Notes

Alternatives considered:

- Terratest against a real account in CI: stronger evidence, but needs cloud credentials in pipelines and costs money
  on every change.
- LocalStack: does not emulate EKS well enough to be meaningful here.
