# network

VPC across two or three Availability Zones: private /19 subnets for nodes and pods, public /24 subnets for load
balancers and NAT gateways, one NAT gateway per AZ or one shared, VPC flow logs to an encrypted log group, and a
default security group with no rules. Subnets carry the tags the AWS Load Balancer Controller and Karpenter use for
discovery.

Tests: `tests/network.tftest.hcl` (mocked provider, runs offline with `terraform test`).

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
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_iam_policy_document.flow_logs_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| azs | Availability Zones to spread subnets across. Listed explicitly so plans do not depend on a data source. | `list(string)` | n/a | yes |
| cluster\_name | EKS cluster name. Private subnets carry it in the karpenter.sh/discovery tag. | `string` | n/a | yes |
| kms\_key\_arn | KMS key ARN that encrypts the flow log group. | `string` | n/a | yes |
| name | Name prefix for every network resource. | `string` | n/a | yes |
| cidr | IPv4 CIDR block of the VPC. A /16 leaves room for three /19 private subnets. | `string` | `"10.0.0.0/16"` | no |
| log\_retention\_days | Retention of the VPC flow log group, in days. | `number` | `365` | no |
| single\_nat\_gateway | Use one NAT gateway for all AZs (cheaper, one AZ is a single point of failure) instead of one per AZ. | `bool` | `false` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| nat\_gateway\_count | Number of NAT gateways created. |
| private\_subnet\_ids | Private subnet IDs, one per AZ. Nodes and pods run here. |
| public\_subnet\_ids | Public subnet IDs, one per AZ. Only internet-facing load balancers and NAT gateways use them. |
| vpc\_id | ID of the VPC. |
<!-- END_TF_DOCS -->
