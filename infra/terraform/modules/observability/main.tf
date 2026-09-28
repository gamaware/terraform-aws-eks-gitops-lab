# Observability baseline: one customer-managed key for platform logs and the alarm topic,
# pre-created Container Insights log groups (so retention and encryption are ours, not the
# add-on's never-expire default), an SNS topic and a small set of actionable alarms.

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # Log groups the amazon-cloudwatch-observability add-on writes to.
  container_insights_log_groups = ["application", "dataplane", "host", "performance"]
}

# In a key policy, "Resource": "*" means this key only.
resource "aws_kms_key" "platform" {
  description             = "${var.cluster_name} platform logs and alarm notifications"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsUse"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Decrypt*", "kms:Describe*", "kms:Encrypt*", "kms:GenerateDataKey*", "kms:ReEncrypt*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:*"
          }
        }
      },
      {
        # CloudWatch alarms publish to the encrypted SNS topic.
        Sid       = "CloudWatchAlarmsPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.cluster_name}-platform"
  target_key_id = aws_kms_key.platform.key_id
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(local.container_insights_log_groups)

  name              = "/aws/containerinsights/${var.cluster_name}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.platform.arn

  tags = var.tags
}

resource "aws_sns_topic" "alarms" {
  name              = "${var.cluster_name}-alarms"
  kms_master_key_id = aws_kms_key.platform.id

  tags = var.tags
}

data "aws_iam_policy_document" "alarms_topic" {
  statement {
    sid       = "CloudWatchAlarmsPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.alarm_emails)

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = each.value
}

# --- Alarms on Container Insights metrics ----------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "failed_nodes" {
  alarm_name          = "${var.cluster_name}-failed-nodes"
  alarm_description   = "At least one node in ${var.cluster_name} is failing its kubelet health checks."
  namespace           = "ContainerInsights"
  metric_name         = "cluster_failed_node_count"
  dimensions          = { ClusterName = var.cluster_name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "node_utilization" {
  for_each = {
    cpu    = "node_cpu_utilization"
    memory = "node_memory_utilization"
  }

  alarm_name          = "${var.cluster_name}-node-${each.key}-high"
  alarm_description   = "Average node ${each.key} in ${var.cluster_name} above ${var.node_utilization_threshold}% for 15 minutes; check Karpenter limits and pending pods."
  namespace           = "ContainerInsights"
  metric_name         = each.value
  dimensions          = { ClusterName = var.cluster_name }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.node_utilization_threshold
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "running_pods" {
  for_each = var.min_running_pods

  alarm_name          = "${var.cluster_name}-${each.key}-running-pods-low"
  alarm_description   = "Fewer than ${each.value} running pods in namespace ${each.key} of ${var.cluster_name}."
  namespace           = "ContainerInsights"
  metric_name         = "namespace_number_of_running_pods"
  dimensions          = { ClusterName = var.cluster_name, Namespace = each.key }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "LessThanThreshold"
  threshold           = each.value
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
