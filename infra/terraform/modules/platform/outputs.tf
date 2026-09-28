output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_certificate_authority_data
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "nat_gateway_count" {
  description = "Number of NAT gateways."
  value       = module.network.nat_gateway_count
}

output "karpenter_node_role_name" {
  description = "Role name referenced by the EC2NodeClass in the environment folder under gitops/environments."
  value       = module.karpenter.node_role_name
}

output "karpenter_interruption_queue_name" {
  description = "Queue name referenced by the Karpenter Application patch in the environment folder under gitops/environments."
  value       = module.karpenter.interruption_queue_name
}

output "alarm_topic_arn" {
  description = "SNS topic that receives every alarm."
  value       = module.observability.alarm_topic_arn
}

output "argocd_root_path" {
  description = "Repository path the root Application syncs; null when private_only is true (no Argo CD)."
  value       = one(module.argocd[*].root_application_path)
}

output "private_access" {
  description = "Session Manager relay instance; pull-through cache registry, prefixes and Karpenter instance profile when private_only is true."
  value = {
    instance_id                = module.private_access.instance_id
    registry                   = module.private_access.registry
    pull_through_prefixes      = module.private_access.pull_through_prefixes
    karpenter_instance_profile = module.private_access.karpenter_instance_profile
  }
}

output "endpoint_public_access" {
  description = "Whether the Kubernetes API endpoint is reachable from outside the VPC."
  value       = module.eks.endpoint_public_access
}

output "public_subnet_count" {
  description = "Number of public subnets; zero when private_only is true."
  value       = length(module.network.public_subnet_ids)
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  value       = module.network.vpc_cidr
}
