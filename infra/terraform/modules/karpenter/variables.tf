variable "cluster_name" {
  description = "Name of the EKS cluster Karpenter provisions nodes for."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster. Scopes the controller trust policy and eks:DescribeCluster."
  type        = string
}

variable "namespace" {
  description = "Namespace of the Karpenter controller service account."
  type        = string
  default     = "kube-system"
}

variable "service_account" {
  description = "Name of the Karpenter controller service account."
  type        = string
  default     = "karpenter"
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
