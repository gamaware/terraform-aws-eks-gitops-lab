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

output "api_tunnel_command" {
  description = "Command that opens Session Manager port forwarding to the private API endpoint and writes a kubeconfig that uses it."
  value       = "scripts/api-tunnel.sh ${var.region} ${module.platform.cluster_name} ${module.platform.private_access.instance_id} ${module.platform.cluster_endpoint}"
}
