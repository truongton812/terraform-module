output "ecr_repository_name" {
  value = try(aws_ecr_repository.this[0].name, null)
}

output "ecr_repository_url" {
  value = try(aws_ecr_repository.this[0].repository_url, null)
}

output "ecr_repository_arn" {
  value = try(aws_ecr_repository.this[0].arn, null)
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.this.arn
}

output "task_definition_family" {
  value = aws_ecs_task_definition.this.family
}

output "service_id" {
  value = aws_ecs_service.this.id
}

output "service_name" {
  value = aws_ecs_service.this.name
}
