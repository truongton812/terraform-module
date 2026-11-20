locals {
  cluster_name  = "${var.project_name}-${var.environment}"
}

################################################################################
# CloudWatch Log Group for ECS Exec
################################################################################

resource "aws_cloudwatch_log_group" "exec" {
  count = var.enable_execute_command_logging ? 1 : 0

  name              = "/aws/ecs/${local.cluster_name}/exec"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

################################################################################
# ECS Cluster
################################################################################

resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  dynamic "configuration" {
    for_each = var.enable_execute_command_logging ? [1] : []

    content {
      execute_command_configuration {
        kms_key_id = var.kms_key_arn
        logging    = "OVERRIDE"

        log_configuration {
          cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec[0].name
          cloud_watch_encryption_enabled = var.kms_key_arn != null
        }
      }
    }
  }

  tags = var.tags
}

################################################################################
# Fargate capacity providers
################################################################################

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy

    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}
