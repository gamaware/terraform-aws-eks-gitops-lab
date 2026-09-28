output "kms_key_arn" {
  description = "ARN of the platform key for log groups and the alarm topic."
  value       = aws_kms_key.platform.arn
}

output "alarm_topic_arn" {
  description = "ARN of the SNS topic that receives every alarm."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Names of the alarms created."
  value = concat(
    [aws_cloudwatch_metric_alarm.failed_nodes.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.node_utilization : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.running_pods : a.alarm_name],
  )
}
