variable "region" {
  description = "AWS Region for every resource."
  type        = string
  default     = "us-east-1"
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin. terraform.tfvars holds documentation placeholders."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Empty keeps it private."
  type        = list(string)
  default     = []

  validation {
    condition     = !(var.private_only && length(var.public_access_cidrs) > 0)
    error_message = "Live tests run private-only: public_access_cidrs must be empty when private_only is true."
  }
}

variable "private_only" {
  description = "Live tests run private-only: scripts/test-live.sh sets true. No internet path, no public API endpoint, no Argo CD."
  type        = bool
  default     = false
}

variable "gitops_repo_url" {
  description = "HTTPS URL of the repository Argo CD syncs."
  type        = string
  default     = "https://github.com/gamaware/terraform-aws-eks-gitops-lab.git"
}

variable "gitops_target_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}

variable "alarm_emails" {
  description = "Email addresses subscribed to alarms."
  type        = list(string)
  default     = []
}

variable "extra_tags" {
  description = "Additional default tags, for example purpose=portfolio-test during a live test."
  type        = map(string)
  default     = {}
}
