# eks

EKS control plane with Secrets envelope encryption, all five control plane log types, access entries instead of the
aws-auth ConfigMap, a managed system node group on a launch template that enforces IMDSv2 with a hop limit of 1, EKS
managed add-ons, and EKS Pod Identity roles for the AWS Load Balancer Controller, the EBS CSI driver and the
CloudWatch agent.

Tests: `tests/eks.tftest.hcl` (mocked provider, runs offline with `terraform test`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11.0 |
| aws | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.0, < 7.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ec2_tag.cluster_security_group_discovery](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_tag) | resource |
| [aws_eks_access_entry.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_access_policy_association.admin](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_policy_association) | resource |
| [aws_eks_addon.before_compute](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_node_group) | resource |
| [aws_eks_pod_identity_association.load_balancer_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_policy.load_balancer_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.pod_identity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.load_balancer_controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.pod_identity_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_eks_addon_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon_version) | data source |
| [aws_iam_policy_document.cluster_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.node_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.pod_identity_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| admin\_role\_arns | IAM role ARNs granted cluster-admin through EKS access entries. | `list(string)` | n/a | yes |
| cluster\_name | Name of the EKS cluster. Also the prefix for its IAM roles and KMS alias. | `string` | n/a | yes |
| kubernetes\_version | Kubernetes minor version of the control plane, for example 1.35. | `string` | n/a | yes |
| logs\_kms\_key\_arn | KMS key ARN that encrypts the control plane log group. | `string` | n/a | yes |
| subnet\_ids | Private subnet IDs for the control plane network interfaces and the system node group. | `list(string)` | n/a | yes |
| log\_retention\_days | Retention of the control plane log group, in days. | `number` | `365` | no |
| node\_disk\_size\_gib | Root volume size of the system nodes, in GiB. | `number` | `50` | no |
| public\_access\_cidrs | CIDR blocks allowed to reach the public API endpoint. Empty keeps the endpoint private only. | `list(string)` | `[]` | no |
| support\_type | EKS upgrade policy: STANDARD stops at end of standard support, EXTENDED keeps paying for extended support. | `string` | `"STANDARD"` | no |
| system\_node\_count | Size of the managed system node group. | ```object({ min = number max = number desired = number })``` | ```{ "desired": 2, "max": 3, "min": 2 }``` | no |
| system\_node\_instance\_types | Instance types for the managed system node group. | `list(string)` | ```[ "m7i.large" ]``` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | ARN of the EKS cluster. |
| cluster\_certificate\_authority\_data | Base64-encoded cluster CA certificate. |
| cluster\_endpoint | Kubernetes API endpoint. |
| cluster\_name | Name of the EKS cluster. |
| cluster\_security\_group\_id | Security group EKS created for the control plane and nodes. |
| pod\_identity\_role\_arns | IAM role ARN per in-cluster controller that uses EKS Pod Identity. |
| system\_node\_group\_ready | Node group ARN. Downstream Helm releases depend on it so they wait for schedulable nodes. |
<!-- END_TF_DOCS -->
