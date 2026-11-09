output "security_group_ids" {
  description = "Map of security group key to ID"
  value       = { for k, v in aws_security_group.this : k => v.id }
}

output "security_group_arns" {
  description = "Map of security group key to ARN"
  value       = { for k, v in aws_security_group.this : k => v.arn }
}

output "security_group_names" {
  description = "Map of security group key to name"
  value       = { for k, v in aws_security_group.this : k => v.name }
}

output "ingress_rule_ids" {
  description = "Map of \"<sg_key>.<rule_key>\" to ingress rule ID"
  value       = { for k, v in aws_vpc_security_group_ingress_rule.this : k => v.security_group_rule_id }
}

output "egress_rule_ids" {
  description = "Map of \"<sg_key>.<rule_key>\" to egress rule ID"
  value       = { for k, v in aws_vpc_security_group_egress_rule.this : k => v.security_group_rule_id }
}
