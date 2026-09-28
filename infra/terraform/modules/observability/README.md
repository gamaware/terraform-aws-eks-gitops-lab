# observability

Customer-managed KMS key for platform logs and the alarm topic, pre-created Container Insights log groups with a
retention period, an encrypted SNS topic with optional email subscriptions, and alarms for failed nodes, node CPU and
memory, and running pods per namespace.

Tests: `tests/observability.tftest.hcl` (mocked provider, runs offline with `terraform test`).

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
| [aws_cloudwatch_log_group.container_insights](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.failed_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.node_utilization](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.running_pods](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_kms_alias.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.alarms_topic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster\_name | Name of the EKS cluster the alarms and log groups belong to. | `string` | n/a | yes |
| alarm\_emails | Email addresses subscribed to the alarm topic. Each must confirm the subscription. | `list(string)` | `[]` | no |
| log\_retention\_days | Retention of the Container Insights log groups, in days. | `number` | `365` | no |
| min\_running\_pods | Minimum running pods per namespace; fewer raises an alarm. Keys are namespace names. | `map(number)` | `{}` | no |
| node\_utilization\_threshold | Average node CPU or memory percentage that raises an alarm after 15 minutes. | `number` | `80` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alarm\_names | Names of the alarms created. |
| alarm\_topic\_arn | ARN of the SNS topic that receives every alarm. |
| kms\_key\_arn | ARN of the platform key for log groups and the alarm topic. |
<!-- END_TF_DOCS -->
