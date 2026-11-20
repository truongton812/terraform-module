output "role_arn" {
  description = "ARN of the role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role"
  value       = aws_iam_role.this.name
}

output "role_id" {
  description = "ID of the role"
  value       = aws_iam_role.this.id
}

output "custom_policy_arns" {
  description = "Map of custom policy key to the ARN of the created customer managed policy"
  value       = { for k, p in aws_iam_policy.custom : k => p.arn }
}

output "inline_policy_names" {
  description = "Names of the inline policies embedded in the role"
  value       = keys(aws_iam_role_policy.inline)
}
