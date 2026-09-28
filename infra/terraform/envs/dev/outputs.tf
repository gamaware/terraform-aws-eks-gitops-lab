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

output "cluster_endpoint" {
  description = "Kubernetes API endpoint. Private-only runs reach it through Session Manager port forwarding."
  value       = module.platform.cluster_endpoint
}

output "private_access" {
  description = "Session Manager relay, pull-through cache registry and Karpenter instance profile for private-only runs."
  value       = module.platform.private_access
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC. The private-only live run limits the internal ALB to it."
  value       = module.platform.vpc_cidr
}
