variable "cluster_name" {
  description = "Name of the EKS cluster the alarms and log groups belong to."
  type        = string
}

variable "log_retention_days" {
  description = "Retention of the Container Insights log groups, in days."
  type        = number
  default     = 365
}

variable "alarm_emails" {
  description = "Email addresses subscribed to the alarm topic. Each must confirm the subscription."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.alarm_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Every entry in alarm_emails must be an email address."
  }
}

variable "node_utilization_threshold" {
  description = "Average node CPU or memory percentage that raises an alarm after 15 minutes."
  type        = number
  default     = 80

  validation {
    condition     = var.node_utilization_threshold > 0 && var.node_utilization_threshold < 100
    error_message = "node_utilization_threshold must be a percentage between 0 and 100."
  }
}

variable "min_running_pods" {
  description = "Minimum running pods per namespace; fewer raises an alarm. Keys are namespace names."
  type        = map(number)
  default     = {}
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
