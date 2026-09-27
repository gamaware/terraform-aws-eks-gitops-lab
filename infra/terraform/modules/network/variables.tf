variable "name" {
  description = "Name prefix for every network resource."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. Private subnets carry it in the karpenter.sh/discovery tag."
  type        = string
}

variable "cidr" {
  description = "IPv4 CIDR block of the VPC. A /16 leaves room for three /19 private subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.cidr)) && tonumber(split("/", var.cidr)[1]) <= 16
    error_message = "cidr must be a valid IPv4 block of /16 or larger."
  }
}

variable "azs" {
  description = "Availability Zones to spread subnets across. Listed explicitly so plans do not depend on a data source."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3
    error_message = "EKS needs subnets in at least two Availability Zones; this module supports two or three."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs (cheaper, one AZ is a single point of failure) instead of one per AZ."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN that encrypts the flow log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the VPC flow log group, in days."
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
