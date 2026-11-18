locals {
  name_prefix      = "${var.project_name}-${var.environment}-${var.app_name}"
  container_cpu    = coalesce(var.container_cpu, var.task_cpu)
  container_memory = coalesce(var.container_memory, var.task_memory)
  env_file_key     = coalesce(var.env_file_key, "${var.project_name}-${var.environment}-${var.app_name}.env")
}

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = local.name_prefix
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.ecr_scan_on_push
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = merge(var.tags, {
    Name = local.name_prefix
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.this[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.lifecycle_keep_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.lifecycle_keep_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = local.name_prefix
  requires_compatibilities = var.requires_compatibilities
  network_mode             = var.network_mode
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions = jsonencode([
    {
      name         = var.container_name
      image        = var.container_image
      cpu          = local.container_cpu
      memory       = local.container_memory
      essential    = true
      portMappings = var.port_mappings
      environment = var.environment_variables != null ? [ for k, v in var.environment_variables: { name : k , value: v} ] : []
      secrets      = var.secrets != null ? [ for k, v in var.secrets: { name : k , valueFrom : v} ] : []
      environmentFiles = var.env_bucket_arn != null ? [
        {
          type  = "s3"
          value = "${var.env_bucket_arn}/${local.env_file_key}"
        }
      ] : []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = var.log_group_name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = local.name_prefix
        }
      }
    }
  ])
  lifecycle {
    ignore_changes = [
      container_definitions
    ]
  }
  tags = merge(var.tags, {
    Name = local.name_prefix
  })
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  name                               = local.name_prefix
  cluster                            = var.cluster_id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  enable_execute_command             = var.enable_execute_command
  launch_type                        = var.requires_compatibilities[0]
  availability_zone_rebalancing      = var.availability_zone_rebalancing
  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  # Only valid when the service is attached to a load balancer
  health_check_grace_period_seconds = var.enable_load_balancer ? var.health_check_grace_period_seconds : null

  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_groups
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = var.enable_load_balancer ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.container_name
      container_port = coalesce(var.container_port, try(var.port_mappings[0].containerPort, null))
 
    }
  }

  dynamic "service_registries" {
    for_each = var.enable_service_discovery ? [1] : []
    content {
      registry_arn = var.service_registry_arn
    }
  }

  dynamic "service_connect_configuration" {
      for_each = var.enable_service_connect ? [1] : []
      content {
        enabled   = true
        namespace = var.service_connect_namespace_arn

        service {
          port_name      = var.port_mappings[0].name
          discovery_name = coalesce(var.service_connect_discovery_name, var.service_connect_client_alias)

          client_alias {
            dns_name = coalesce(var.service_connect_client_alias, var.service_connect_discovery_name)
            port     = var.port_mappings[0].containerPort
          }
        }
      }
  }

  deployment_configuration {
    strategy = var.deployment_strategy
  }
  lifecycle {
    ignore_changes = [
      task_definition, desired_count
    ]

    precondition {
      condition     = !var.enable_load_balancer || var.target_group_arn != null
      error_message = "target_group_arn is required when enable_load_balancer = true."
    }

    precondition {
      condition     = !var.enable_service_discovery || var.service_registry_arn != null
      error_message = "service_registry_arn is required when enable_service_discovery = true."
    }
    precondition {
      condition     = !var.enable_load_balancer || var.container_port != null || length(var.port_mappings) > 0
      error_message = "container_port or port_mappings is required when enable_load_balancer = true."
    }
    precondition {
      condition = !var.enable_service_connect || (
        var.service_connect_namespace_arn != null &&
        try(var.port_mappings[0].name, null) != null &&
        (var.service_connect_client_alias != null || var.service_connect_discovery_name != null)
      )
      error_message = "Service Connect requires namespace_arn, port_mappings[0].name, and client_alias or discovery_name."
    }
  }
}

resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.ecs_max_capacity
  min_capacity       = var.ecs_min_capacity
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}


resource "aws_appautoscaling_policy" "ecs_policy_cpu" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.appautoscaling_policy_cpu_target_value
    scale_in_cooldown  = var.appautoscaling_policy_scale_in_cooldown
    scale_out_cooldown = var.appautoscaling_policy_scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "ecs_policy_memory" {
  count              = var.enable_autoscaling ? 1 : 0
  name               = "memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.appautoscaling_policy_memory_target_value
    scale_in_cooldown  = var.appautoscaling_policy_scale_in_cooldown
    scale_out_cooldown = var.appautoscaling_policy_scale_out_cooldown
  }
}