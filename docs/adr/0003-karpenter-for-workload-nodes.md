# 0003. Karpenter for workload nodes, a managed node group for the system

## Status

Accepted

## Context

The catalog API scales with an HPA; pods that do not fit need new nodes. Cluster Autoscaler scales existing node groups
of fixed instance types. Karpenter launches instances directly from pending pod requirements and consolidates
underused nodes, but it cannot run on nodes it manages.

## Decision

A small EKS managed node group (`system`) runs CoreDNS, Argo CD, Karpenter, the load balancer controller and
metrics-server. Karpenter provisions everything else through one NodePool, `workloads`, on current-generation c, m
and r instances. Dev allows Spot and On-Demand capacity; prod uses On-Demand only. Each NodePool has CPU and memory
limits and a 10% disruption budget, and nodes expire after 30 days. The AMI alias is pinned per environment.

## Consequences

- Two layers of scaling to reason about: the HPA adds pods, Karpenter adds nodes. The PDB and disruption budget keep
  consolidation from draining every replica.
- The Karpenter controller's IAM policy follows the upstream v1.14 reference, scoped by the cluster ownership tag;
  upgrading Karpenter means diffing that policy.
- Nodes are replaced at least monthly, which also rolls in new AMIs.

## Compliance

`karpenter.tftest.hcl` checks tag scoping, `iam:PassRole` limited to the node role and the interruption queue.
`tests/test_gitops.py` checks that AMI aliases are pinned, NodePools have limits and the catalog API's node selector
matches the NodePool name. `tests/test_chart.py` checks that the PDB leaves room to drain.

## Notes

Alternatives considered:

- Cluster Autoscaler: well understood, but needs a node group per instance shape and scales more slowly.
- Karpenter for everything, including its own controller on Fargate: removes the node group but adds a Fargate
  profile and its limits.
