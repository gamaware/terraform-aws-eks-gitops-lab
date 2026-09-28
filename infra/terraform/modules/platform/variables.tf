variable "name" {
  description = "Workload name. The cluster is named after it plus the environment, for example harbor-goods-dev."
  type        = string
  default     = "harbor-goods"
}

variable "environment" {
  description = "Environment name; must match a folder in gitops/environments."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the control plane."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones for subnets."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (dev) instead of one per AZ (prod)."
  type        = bool
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Empty keeps it private."
  type        = list(string)
  default     = []

  validation {
    condition     = !(var.private_only && length(var.public_access_cidrs) > 0)
    error_message = "private_only keeps the API endpoint private; public_access_cidrs must be empty."
  }
}

variable "private_only" {
  description = "No internet path and no public API endpoint: VPC endpoints, a Session Manager relay and ECR pull-through caches instead, and no Argo CD. The live test sets it."
  type        = bool
  default     = false
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin through access entries."
  type        = list(string)
}

variable "system_node_instance_types" {
  description = "Instance types of the managed system node group."
  type        = list(string)
  default     = ["m7i.large"]
}

variable "system_node_count" {
  description = "Size of the managed system node group."
  type = object({
    min     = number
    max     = number
    desired = number
  })
}

variable "log_retention_days" {
  description = "Retention of every platform log group, in days."
  type        = number
  default     = 365
}

variable "alarm_emails" {
  description = "Email addresses subscribed to alarms."
  type        = list(string)
  default     = []
}

variable "min_running_pods" {
  description = "Minimum running pods per namespace before an alarm fires."
  type        = map(number)
  default     = {}
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the repository Argo CD syncs."
  type        = string
}

variable "gitops_target_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Tags added to every resource on top of the provider default tags."
  type        = map(string)
  default     = {}
}
