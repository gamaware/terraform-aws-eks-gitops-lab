# private-access

Private access for the private-only live test (ADR 0006): a Session Manager relay instance with no public IP and no
inbound rules for port forwarding to the private API endpoint, an HTTPS rule on the cluster security group for that
relay, ECR pull-through cache rules for `public.ecr.aws` and `registry.k8s.io` with the node permissions to fill them,
and the Karpenter node instance profile (a VPC without internet has no IAM endpoint).

Tests: `tests/private_access.tftest.hcl` (mocked provider, runs offline with `terraform test`).

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
| [aws_ecr_pull_through_cache_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_pull_through_cache_rule) | resource |
| [aws_iam_instance_profile.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_instance_profile.karpenter_node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.pull_through](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.access_ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.access_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.cluster_from_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.access_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.pull_through](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_ssm_parameter.al2023_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_security\_group\_id | Cluster security group. It gets one HTTPS rule from the access instance. | `string` | n/a | yes |
| karpenter\_node\_role\_name | Karpenter node role. A private VPC has no IAM endpoint, so its instance profile is created here instead of by Karpenter. | `string` | n/a | yes |
| name | Name prefix, for example harbor-goods-dev. | `string` | n/a | yes |
| node\_role\_names | Node IAM roles allowed to fill pull-through cache repositories on first pull. | `list(string)` | n/a | yes |
| subnet\_id | Private subnet for the access instance. | `string` | n/a | yes |
| vpc\_cidr | IPv4 CIDR of the VPC. The access instance may only open HTTPS connections inside it. | `string` | n/a | yes |
| vpc\_id | VPC of the cluster. | `string` | n/a | yes |
| instance\_type | Instance type of the access instance. It only relays Session Manager port forwarding. | `string` | `"t4g.nano"` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| instance\_id | Instance ID of the Session Manager relay for port forwarding to the private API endpoint. |
| karpenter\_instance\_profile | Instance profile to set as spec.instanceProfile in the live EC2NodeClass. |
| pull\_through\_prefixes | Upstream registry to ECR repository prefix. |
| registry | ECR registry host that serves the pull-through cache repositories. |
<!-- END_TF_DOCS -->
