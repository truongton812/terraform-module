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

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Role
# ============================================================================
variable "role_name" {
  description = "Role name suffix; the full name is <project>-<env>-<role_name> (e.g. execution-role, task-role)"
  type        = string
}

variable "description" {
  description = "Description of the role"
  type        = string
  default     = null
}

variable "trusted_services" {
  description = "AWS service principals allowed to assume the role (e.g. ecs-tasks.amazonaws.com)"
  type        = list(string)

  validation {
    condition     = length(var.trusted_services) > 0
    error_message = "trusted_services must contain at least one service principal."
  }
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (3600-43200)"
  type        = number
  default     = 3600
}

# ============================================================================
# Policies
# ============================================================================

variable "inline_policies" {
  description = <<-EOT
    Map of inline policies embedded in the role.
    Key = inline policy name, value = policy document as an HCL object (the module calls jsonencode for you).
    Example: { s3_read = { Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = ["*"] }] } }
  EOT
  type        = any
  default     = {}

  validation {
    # Each value must be an object with a Statement attribute
    condition     = alltrue([for p in values(var.inline_policies) : can(p.Statement)])
    error_message = "Each inline policy must be an object with a Statement attribute, e.g. { Version = \"2012-10-17\", Statement = [...] }. Do not pass a JSON string or wrap it in jsonencode(...)."
  }

  validation {
    # Principal is only valid in resource-based policies (e.g. S3 bucket policy)
    condition     = alltrue([for p in values(var.inline_policies) : length(regexall("\"(Not)?Principal\"", jsonencode(p))) == 0])
    error_message = "Inline policies are identity-based and must not contain Principal/NotPrincipal."
  }
}

variable "managed_policy_arns" {
  description = "List of existing managed policy ARNs to attach (e.g. arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess)"
  type        = list(string)
  default     = []
}

variable "custom_policies" {
  description = <<-EOT
    Map of customer managed policies to create and attach.
    Key = policy name suffix (full name: <project>-<env>-<key>), value = policy document as an HCL object (the module calls jsonencode for you).
  EOT
  type        = any
  default     = {}

  validation {
    condition     = alltrue([for p in values(var.custom_policies) : can(p.Statement)])
    error_message = "Each custom policy must be an object with a Statement attribute, e.g. { Version = \"2012-10-17\", Statement = [...] }. Do not pass a JSON string or wrap it in jsonencode(...)."
  }

  validation {
    condition     = alltrue([for p in values(var.custom_policies) : length(regexall("\"(Not)?Principal\"", jsonencode(p))) == 0])
    error_message = "Custom policies are identity-based and must not contain Principal/NotPrincipal."
  }

  validation {
    # AWS limit: 6,144 characters per managed policy, whitespace excluded (jsonencode output is already minified)
    condition     = alltrue([for p in values(var.custom_policies) : length(jsonencode(p)) <= 6144])
    error_message = "Each custom policy must be at most 6,144 characters (minified JSON)."
  }
}

