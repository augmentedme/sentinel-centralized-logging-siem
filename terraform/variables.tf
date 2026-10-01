variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "australiaeast"
}

variable "resource_group_name" {
  description = "Resource group that holds the SIEM platform and client VMs."
  type        = string
  default     = "rg-siem-demo"
}

variable "workspace_name" {
  description = "Log Analytics workspace name (Microsoft Sentinel is enabled on it)."
  type        = string
  default     = "law-siem"
}

variable "workspace_retention_days" {
  description = "Default interactive (hot) retention for all tables. 90 days is included with Sentinel."
  type        = number
  default     = 90

  validation {
    condition     = var.workspace_retention_days >= 30 && var.workspace_retention_days <= 730
    error_message = "Workspace retention must be between 30 and 730 days."
  }
}

variable "daily_cap_gb" {
  description = "Daily ingestion cap in GB. A cost safety net; -1 disables the cap."
  type        = number
  default     = 2
}

variable "table_retention" {
  description = <<-EOT
    Per-table retention. 'interactive' = hot tier (fast queries, alerts).
    'total' = interactive + long-term (cold) retention. Values above 730
    must be one of Azure's supported long-term values (e.g. 1095, 2556, 4383).
  EOT
  type = map(object({
    interactive = number
    total       = number
  }))
  default = {
    SecurityEvent = { interactive = 90, total = 365 }
    Event         = { interactive = 90, total = 180 }
    Syslog        = { interactive = 90, total = 180 }
    SigninLogs    = { interactive = 90, total = 365 }
    AuditLogs     = { interactive = 90, total = 365 }
    AzureActivity = { interactive = 90, total = 365 }
  }
}

variable "custom_table_retention" {
  description = "Retention for the custom log tables created by this project."
  type = map(object({
    interactive = number
    total       = number
  }))
  default = {
    NginxAccess_CL = { interactive = 30, total = 180 }
    WebAppAudit_CL = { interactive = 90, total = 365 }
  }
}

variable "manage_builtin_table_retention" {
  description = "Set per-table retention on built-in tables. Set to false if a table does not exist yet, then re-enable after its connector is running."
  type        = bool
  default     = true
}

variable "bruteforce_threshold" {
  description = "Failed logins from one IP (across all sources) that trigger the brute-force alert."
  type        = number
  default     = 5
}

variable "bruteforce_window_minutes" {
  description = "Look-back window for the brute-force alert, in minutes."
  type        = number
  default     = 10
}

variable "webscan_threshold" {
  description = "Requests for known-sensitive paths from one IP that trigger the web scanning alert."
  type        = number
  default     = 10
}

variable "webscan_window_minutes" {
  description = "Look-back window for the web scanning alert, in minutes."
  type        = number
  default     = 15
}

variable "create_budget" {
  description = "Create a subscription cost budget with email alerts."
  type        = bool
  default     = true
}

variable "budget_amount" {
  description = "Monthly budget amount in the subscription's billing currency."
  type        = number
  default     = 100
}

variable "budget_start_date" {
  description = "Budget start: first day of the current month, RFC3339 format."
  type        = string
  default     = "2026-09-01T00:00:00Z"
}

variable "alert_email" {
  description = "Email address for budget notifications. Set in terraform.tfvars (git-ignored)."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project     = "centralized-logging-siem"
    environment = "demo"
    managed_by  = "terraform"
  }
}
