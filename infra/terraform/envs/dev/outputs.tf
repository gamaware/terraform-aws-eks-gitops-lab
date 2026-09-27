output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.platform.cluster_name
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.platform.vpc_id
}

output "alarm_topic_arn" {
  description = "SNS topic that receives every alarm."
  value       = module.platform.alarm_topic_arn
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for this cluster."
  value       = "aws eks update-kubeconfig --name ${module.platform.cluster_name} --region ${var.region}"
}
