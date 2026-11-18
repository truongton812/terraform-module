variable "project_name" {
  type = string
}

variable "environment" {
  type        = string
  description = "Environment type (Ex: dev, staging, production)"
}

variable "app_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# --- ECR ---
variable "create_ecr_repository" {
  type    = bool
  default = true
}

variable "image_tag_mutability" {
  type    = string
  default = "MUTABLE"
}

variable "ecr_scan_on_push" {
  type    = bool
  default = false
}

variable "lifecycle_keep_count" {
  type        = number
  default     = 20
  description = "The maximum number image is kept before expiring"
}

# --- Task definition ---

variable "requires_compatibilities" {
  type    = list(string)
  default = ["FARGATE"]
}

variable "network_mode" {
  type    = string
  default = "awsvpc"
}

variable "container_name" {
  type = string
  default = "container"
}

variable "container_image" {
  type = string
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "container_cpu" {
  type        = number
  default     = null
  description = "Default equal to task_cpu if this field is ignored"
}

variable "container_memory" {
  type        = number
  default     = null
  description = "Default equal to task_memory if this field is ignored"
}

variable "port_mappings" {
  type = list(object({
    containerPort = number
    name          = optional(string)
    hostPort      = optional(number)
    protocol      = optional(string, "tcp")
  }))
  default = []
}

variable "container_port" {
  type    = number
  default = null
}

variable "execution_role_arn" {
  type = string
}

variable "task_role_arn" {
  type = string
  default = null
}

variable "environment_variables" {
  type = map(string)
  description = "Define environment variables in ecs task"
  default = null
}

variable "secrets" {
  type = map(string)
  description = "Define environment variables in ecs task from secret"
  default = null
}

variable "env_bucket_arn" {
  type        = string
  description = "ARN of S3 bucket contains .env file"
  default = null
}

variable "env_file_key" {
  type        = string
  default     = null
  description = "Overwrite .env file name in S3 bucket. Default is '<project_name>-<environment>-<app_name>.env'"
}

variable "log_group_name" {
  type = string
}

# --- Cluster / Service ---
variable "cluster_id" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "enable_execute_command" {
  type    = bool
  default = true
}

variable "availability_zone_rebalancing" {
  type    = string
  default = "ENABLED"
}

variable "deployment_maximum_percent" {
  type    = number
  default = 200
}

variable "deployment_minimum_healthy_percent" {
  type    = number
  default = 100
}

variable "health_check_grace_period_seconds" {
  type    = number
  default = 90
}

variable "subnets" {
  type = list(string)
}

variable "security_groups" {
  type = list(string)
}

variable "assign_public_ip" {
  type    = bool
  default = false
}


variable "deployment_strategy" {
  type    = string
  default = "ROLLING"
}

# --- Load balancer (optional) ---
variable "enable_load_balancer" {
  type    = bool
  default = false
}

variable "target_group_arn" {
  type    = string
  default = null
}

# --- Service discovery (optional) ---
variable "enable_service_discovery" {
  type    = bool
  default = false
}

variable "service_registry_arn" {
  type    = string
  default = null
}

# --- Service connect (optional) ---
variable "enable_service_connect" {
  type    = bool
  default = false
}

variable "service_connect_namespace_arn" {
  type    = string
  default = null
}

variable "service_connect_client_alias" {
  type    = string
  default = null
}

variable "service_connect_discovery_name" {
  type    = string
  default = null
}


# ---App autoscaling---
variable "enable_autoscaling" {
  type    = bool
  default = false
}

variable "ecs_min_capacity" {
  type    = number
  default = 1
}

variable "ecs_max_capacity" {
  type    = number
  default = 2
}

variable "appautoscaling_policy_cpu_target_value" {
  type    = number
  default = 70
}

variable "appautoscaling_policy_memory_target_value" {
  type    = number
  default = 70
}

variable "appautoscaling_policy_scale_in_cooldown" {
  type    = number
  default = 300
}

variable "appautoscaling_policy_scale_out_cooldown" {
  type    = number
  default = 60
}


