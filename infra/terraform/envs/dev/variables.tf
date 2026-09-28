variable "region" {
  description = "AWS Region for every resource."
  type        = string
  default     = "us-east-1"
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin. terraform.tfvars holds documentation placeholders."
  type        = list(string)
}

variable "kubernetes_api_url" {
  description = "Local end of the Session Manager port forward to the private API endpoint (scripts/api-tunnel.sh), for example https://127.0.0.1:8443. Null when Terraform runs inside the VPC."
  type        = string
  default     = null
}

variable "install_argocd" {
  description = "Install Argo CD. Set false on the first apply from outside the VPC; the relay must exist before the tunnel can open."
  type        = bool
  default     = true
}

variable "private_only" {
  description = "Live tests run private-only: scripts/test-live.sh sets true. No internet path and no Argo CD."
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
