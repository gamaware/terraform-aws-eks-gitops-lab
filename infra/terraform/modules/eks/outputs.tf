output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group EKS created for the control plane and nodes."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "system_node_group_ready" {
  description = "Node group ARN. Downstream Helm releases depend on it so they wait for schedulable nodes."
  value       = aws_eks_node_group.system.arn
}

output "pod_identity_role_arns" {
  description = "IAM role ARN per in-cluster controller that uses EKS Pod Identity."
  value       = { for k, r in aws_iam_role.pod_identity : k => r.arn }
}
