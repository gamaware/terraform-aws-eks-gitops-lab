output "node_role_name" {
  description = "IAM role name to set as spec.role in the EC2NodeClass."
  value       = aws_iam_role.node.name
}

output "controller_role_arn" {
  description = "IAM role ARN the Karpenter controller assumes through EKS Pod Identity."
  value       = aws_iam_role.controller.arn
}

output "interruption_queue_name" {
  description = "SQS queue name to set as settings.interruptionQueue in the Karpenter chart."
  value       = aws_sqs_queue.interruption.name
}
