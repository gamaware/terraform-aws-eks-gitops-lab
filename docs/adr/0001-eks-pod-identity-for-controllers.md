# 0001. EKS Pod Identity for in-cluster controllers

## Status

Accepted

## Context

Four in-cluster components call AWS APIs: the AWS Load Balancer Controller, Karpenter, the EBS CSI driver and the
CloudWatch agent. Each needs its own permissions, and none should reach the node role. Two mechanisms exist on EKS:
IAM roles for service accounts (IRSA), which trusts the cluster's OIDC provider and needs a role ARN annotation on
each service account, and EKS Pod Identity, which trusts `pods.eks.amazonaws.com` and binds a role to a namespace and
service account through an EKS API object.

## Decision

We use EKS Pod Identity. Terraform creates one role per controller, trusts `pods.eks.amazonaws.com` with
`aws:SourceAccount` and `aws:SourceArn` pinned to the cluster, and binds it with `aws_eks_pod_identity_association`
(or the add-on's `pod_identity_association` block). Nodes enforce IMDSv2 with a hop limit of 1, so pods cannot fall
back to the node role.

## Consequences

- The Helm values in `gitops/` contain no IAM role ARNs or account IDs for the controllers; the binding lives
  entirely in Terraform.
- The `eks-pod-identity-agent` add-on must run before any controller starts; it is installed with the networking
  add-ons, before the node group.
- A role bound to one cluster cannot be reused by another cluster's pods, because the trust policy names the cluster
  ARN.

## Compliance

`eks.tftest.hcl` (`controllers_get_one_role_each_through_pod_identity`, `nodes_block_pod_access_to_instance_credentials`)
and `karpenter.tftest.hcl` (`controller_role_binds_to_the_karpenter_service_account`) assert the bindings and the IMDS
settings. `tests/test_gitops.py` fails if an EC2NodeClass allows a hop limit above 1.

## Notes

Alternatives considered:

- IRSA: works everywhere, but every chart needs the role ARN, which puts account IDs into `gitops/` values and
  couples each environment folder to Terraform outputs.
- Node role for everything: one broad role shared by every pod on the node. Rejected.

The load balancer controller finds its VPC by the `Name` tag (`vpcTags`), because with a hop limit of 1 it cannot read
the VPC ID from instance metadata.
