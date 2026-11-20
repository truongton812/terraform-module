# ============================================================================
# General
# ============================================================================
variable "project_name" {
  description = "Project name, used as a prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Deployment environment (e.g. dev, stg, prod)"
  type        = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "container_insights" {
  description = "Container Insights setting: enabled, disabled or enhanced"
  type        = string
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "disabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be one of: enabled, disabled, enhanced."
  }
}

variable "enable_execute_command_logging" {
  description = "Enable logging of ECS Exec sessions to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Retention period (in days) for ECS Exec logs"
  type        = number
  default     = 30
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt ECS Exec sessions and the log group (optional)"
  type        = string
  default     = null
}

variable "default_capacity_provider_strategy" {
  description = "Default capacity provider strategy for the cluster (FARGATE and/or FARGATE_SPOT)"
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [
    { capacity_provider = "FARGATE", weight = 1, base = 1 },
    { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 },
  ]

  validation {
    condition = alltrue([
      for s in var.default_capacity_provider_strategy :
      contains(["FARGATE", "FARGATE_SPOT"], s.capacity_provider)
    ])
    error_message = "capacity_provider must be FARGATE or FARGATE_SPOT."
  }
}
