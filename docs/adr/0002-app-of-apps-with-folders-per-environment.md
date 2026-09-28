# 0002. Argo CD app-of-apps with one folder per environment

## Status

Accepted

## Context

Dev and prod run the same add-ons and the same application with different sizes, names and versions. Changes must be
reviewed in Git and promoted from dev to prod deliberately. A common pattern is one Git branch per environment, which
turns promotion into merges and lets the branches drift.

## Decision

One branch, one folder per environment. Terraform creates a single root Application per cluster that syncs
`gitops/environments/<env>`. That folder is a Kustomize root: it includes the shared AppProjects and the
environment-neutral Applications in `gitops/applications/`, then patches in the environment's values (cluster name,
queue name, replica counts, the path of its Karpenter pools and app values). Sync waves order the children:
controllers and namespaces first, NodePools second, the application last. A health check for the `Application` kind
makes each wave wait for the previous one.

## Consequences

- Promotion is a pull request that edits `gitops/environments/prod` after the same change ran in dev. The prod AMI
  release, for example, may never be newer than dev's.
- The base Applications carry an `ENVIRONMENT` placeholder that every environment must patch; a render test fails if
  one is left.
- Applications that read this repository carry a label, and the root Application re-points them at its own
  repository and revision, so a branch or fork under test is used end to end.

## Compliance

`tests/test_gitops.py` renders every environment with Kustomize and checks placeholders, paths, projects, waves and
labels. The `dev` and `prod` Terraform tests read the environment folders and fail if a name differs from what
Terraform creates. `kubeconform` validates the rendered Applications and AppProjects against their CRD schemas.

## Notes

Alternatives considered:

- Branch per environment: promotion by merge, conflicts and silent drift between branches.
- ApplicationSet with a cluster generator: fewer files, but values move into cluster secrets that Terraform must
  write, and the rendered result is harder to review in a pull request.
- A separate config repository: the Argo CD recommendation for larger teams; kept as a production adaptation because
  a single lab repository is easier to inspect.
