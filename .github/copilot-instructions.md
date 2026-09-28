# Copilot code review instructions

When reviewing pull requests in this repository:

- Flag any suppressed lint rule or scanner skip; findings are fixed, not silenced.
- Check that a name changed in `infra/terraform` is changed in `gitops/environments/<env>` too
  (cluster name, Karpenter queue and node role, VPC Name tag), and the reverse.
- Check that chart value changes keep `charts/catalog-api/values.schema.json` in step.
- Check that new third-party charts and images are pinned (chart version, image digest).
- Verify conventional commit format in PR titles.
- Reject real AWS account IDs, ARNs, IP addresses or emails; only documentation placeholders
  such as `111122223333` and `example.com` are allowed.
- Check that new shell scripts have shebangs, executable permissions and quoted variables.
