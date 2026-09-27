# platform

Composition used by every environment root: `observability`, `network`, `eks`, `karpenter` and `argocd-bootstrap`,
wired together. Environment roots in `../../envs/` choose only sizes, ranges and the Kubernetes version. Tested
through the environment roots (`envs/<env>/tests/`), which also check that Terraform names match the values in
`gitops/`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| argocd | ../argocd-bootstrap | n/a |
| eks | ../eks | n/a |
| karpenter | ../karpenter | n/a |
| network | ../network | n/a |
| observability | ../observability | n/a |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| admin\_role\_arns | IAM role ARNs granted cluster-admin through access entries. | `list(string)` | n/a | yes |
| azs | Availability Zones for subnets. | `list(string)` | n/a | yes |
| environment | Environment name; must match a folder in gitops/environments. | `string` | n/a | yes |
| gitops\_repo\_url | HTTPS URL of the repository Argo CD syncs. | `string` | n/a | yes |
| kubernetes\_version | Kubernetes minor version of the control plane. | `string` | n/a | yes |
| single\_nat\_gateway | One shared NAT gateway (dev) instead of one per AZ (prod). | `bool` | n/a | yes |
| system\_node\_count | Size of the managed system node group. | ```object({ min = number max = number desired = number })``` | n/a | yes |
| alarm\_emails | Email addresses subscribed to alarms. | `list(string)` | `[]` | no |
| gitops\_target\_revision | Branch, tag or commit Argo CD tracks. | `string` | `"main"` | no |
| log\_retention\_days | Retention of every platform log group, in days. | `number` | `365` | no |
| min\_running\_pods | Minimum running pods per namespace before an alarm fires. | `map(number)` | `{}` | no |
| name | Workload name. The cluster is named after it plus the environment, for example harbor-goods-dev. | `string` | `"harbor-goods"` | no |
| public\_access\_cidrs | CIDR blocks allowed to reach the public API endpoint. Empty keeps it private. | `list(string)` | `[]` | no |
| system\_node\_instance\_types | Instance types of the managed system node group. | `list(string)` | ```[ "m7i.large" ]``` | no |
| tags | Tags added to every resource on top of the provider default tags. | `map(string)` | `{}` | no |
| vpc\_cidr | IPv4 CIDR block of the VPC. | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alarm\_topic\_arn | SNS topic that receives every alarm. |
| argocd\_root\_path | Repository path the root Application syncs. |
| cluster\_certificate\_authority\_data | Base64-encoded cluster CA certificate. |
| cluster\_endpoint | Kubernetes API endpoint. |
| cluster\_name | Name of the EKS cluster. |
| karpenter\_interruption\_queue\_name | Queue name referenced by the Karpenter Application patch in the environment folder under gitops/environments. |
| karpenter\_node\_role\_name | Role name referenced by the EC2NodeClass in the environment folder under gitops/environments. |
| nat\_gateway\_count | Number of NAT gateways. |
| vpc\_id | ID of the VPC. |
<!-- END_TF_DOCS -->
