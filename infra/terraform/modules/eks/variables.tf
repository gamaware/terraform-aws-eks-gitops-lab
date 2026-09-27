variable "cluster_name" {
  description = "Name of the EKS cluster. Also the prefix for its IAM roles and KMS alias."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,37}$", var.cluster_name))
    error_message = "cluster_name must be 3-38 lowercase letters, digits or hyphens, starting with a letter, so derived IAM role names stay under 64 characters."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes minor version of the control plane, for example 1.35."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as 1.35."
  }
}

variable "support_type" {
  description = "EKS upgrade policy: STANDARD stops at end of standard support, EXTENDED keeps paying for extended support."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.support_type)
    error_message = "support_type must be STANDARD or EXTENDED."
  }
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane network interfaces and the system node group."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "EKS needs subnets in at least two Availability Zones."
  }
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Empty keeps the endpoint private only."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "The API endpoint must not be open to 0.0.0.0/0; list the operator or CI egress ranges instead."
  }

  validation {
    condition     = alltrue([for c in var.public_access_cidrs : can(cidrnetmask(c)) && tonumber(split("/", c)[1]) >= 16])
    error_message = "Every entry in public_access_cidrs must be an IPv4 CIDR block of /16 or narrower."
  }
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin through EKS access entries."
  type        = list(string)

  validation {
    condition     = length(var.admin_role_arns) > 0 && alltrue([for a in var.admin_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", a))])
    error_message = "admin_role_arns needs at least one IAM role ARN; with access entries only, nobody else can administer the cluster."
  }
}

variable "system_node_instance_types" {
  description = "Instance types for the managed system node group."
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
  default = {
    min     = 2
    max     = 3
    desired = 2
  }

  validation {
    condition     = var.system_node_count.min >= 1 && var.system_node_count.min <= var.system_node_count.desired && var.system_node_count.desired <= var.system_node_count.max
    error_message = "system_node_count must satisfy 1 <= min <= desired <= max."
  }
}

variable "node_disk_size_gib" {
  description = "Root volume size of the system nodes, in GiB."
  type        = number
  default     = 50
}

variable "logs_kms_key_arn" {
  description = "KMS key ARN that encrypts the control plane log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the control plane log group, in days."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
