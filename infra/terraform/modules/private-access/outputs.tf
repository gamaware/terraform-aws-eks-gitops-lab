output "instance_id" {
  description = "Instance ID of the Session Manager relay for port forwarding to the private API endpoint."
  value       = aws_instance.access.id
}

output "registry" {
  description = "ECR registry host that serves the pull-through cache repositories; null unless pull_through_cache is true."
  value       = var.pull_through_cache ? "${local.account}.dkr.ecr.${local.region}.amazonaws.com" : null
}

output "pull_through_prefixes" {
  description = "Upstream registry to ECR repository prefix."
  value       = { for prefix, upstream in local.pull_through : upstream => prefix }
}

output "karpenter_instance_profile" {
  description = "Instance profile to set as spec.instanceProfile in the live EC2NodeClass; null unless pull_through_cache is true."
  value       = one(aws_iam_instance_profile.karpenter_node[*].name)
}
