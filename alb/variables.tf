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

# ============================================================================
# Load Balancer
# ============================================================================
variable "vpc_id" {
  description = "ID of the VPC for the target groups"
  type        = string
}

variable "create_aws_lb" {
  description = "Create a new load balancer and listeners. Set false to reuse existing_lb and only add target groups and rules"
  type        = bool
  default     = true
}

variable "existing_lb" {
  description = "Name or ARN of an existing load balancer (required when create_aws_lb = false)"
  type        = string
  default     = null
}

variable "existing_listener_port" {
  description = "Port of the existing listener that new rules attach to (when create_aws_lb = false)"
  type        = number
  default     = 443
}

variable "subnet_ids" {
  description = "Subnets for the load balancer (public subnets for an internet-facing ALB), at least two AZs. Required when create_aws_lb = true"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security groups attached to the load balancer. Required when create_aws_lb = true"
  type        = list(string)
  default     = []
}

variable "internal" {
  description = "Create an internal load balancer instead of an internet-facing one"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "Idle timeout in seconds"
  type        = number
  default     = 60
}

variable "enable_deletion_protection" {
  description = "Prevent the load balancer from being deleted"
  type        = bool
  default     = false
}

# ============================================================================
# Listeners
# ============================================================================
variable "certificate_arn" {
  description = "Default ACM certificate for the HTTPS listener. When null, no HTTPS listener is created and rules attach to HTTP"
  type        = string
  default     = null
}

variable "additional_certificate_arns" {
  description = "Map of extra ACM certificates (SNI) for the HTTPS listener, keyed by a static name"
  type        = map(string)
  default     = {}
}

variable "ssl_policy" {
  description = "SSL policy of the HTTPS listener"
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
}

# ============================================================================
# Target Groups
# Name defaults to <project>-<env>-<key>-tg (max 32 characters); set name to override.
# A listener rule is created when host_headers or path_patterns is set.
# Health check attributes left null use the AWS defaults.
# ============================================================================
variable "target_groups" {
  description = "Map of target groups and their routing rules"
  type = map(object({
    name                 = optional(string)
    port                 = number
    protocol             = optional(string, "HTTP")
    target_type          = optional(string, "ip")
    deregistration_delay = optional(number, 300)

    health_check = optional(object({
      path                = optional(string, "/")
      port                = optional(string, "traffic-port")
      protocol            = optional(string, "HTTP")
      matcher             = optional(string, "200")
      interval            = optional(number)
      timeout             = optional(number)
      healthy_threshold   = optional(number)
      unhealthy_threshold = optional(number)
    }), {})

    host_headers  = optional(list(string), [])
    path_patterns = optional(list(string), [])
    priority      = optional(number)

    # Forward requests that match no rule to this target group (only one allowed;
    # applies to listeners created by this module, not to an existing ALB)
    default = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = length([for tg in var.target_groups : tg if tg.default]) <= 1
    error_message = "At most one target group can have default = true."
  }

  validation {
    condition = alltrue([
      for k, tg in var.target_groups : length(coalesce(tg.name, "${var.project_name}-${var.environment}-${k}-tg")) <= 32
    ])
    error_message = "Target group names must be at most 32 characters; shorten the key or set name."
  }
}
