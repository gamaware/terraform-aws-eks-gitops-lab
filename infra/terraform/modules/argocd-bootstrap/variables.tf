variable "environment" {
  description = "Environment folder under gitops/environments that the root Application syncs."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod, matching a folder in gitops/environments."
  }
}

variable "repo_url" {
  description = "HTTPS URL of the Git repository Argo CD reads."
  type        = string

  validation {
    condition     = can(regex("^https://", var.repo_url))
    error_message = "repo_url must be an HTTPS Git URL."
  }
}

variable "target_revision" {
  description = "Branch, tag or commit the root Application tracks."
  type        = string
  default     = "main"
}

variable "namespace" {
  description = "Namespace for Argo CD and its Application objects."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart."
  type        = string
  default     = "10.9.2"
}

variable "argocd_apps_chart_version" {
  description = "Version of the argocd-apps Helm chart that creates the root Application."
  type        = string
  default     = "2.0.5"
}
