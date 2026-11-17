output "alb_arn" {
  description = "ARN of the load balancer (new or existing)"
  value       = local.lb_arn
}

output "alb_arn_suffix" {
  description = "ARN suffix of the load balancer (for CloudWatch metrics)"
  value       = local.lb_arn_suffix
}

output "alb_dns_name" {
  description = "DNS name of the load balancer"
  value       = local.lb_dns_name
}

output "alb_zone_id" {
  description = "Hosted zone ID of the load balancer (for Route53 alias records)"
  value       = local.lb_zone_id
}

output "http_listener_arn" {
  description = "ARN of the HTTP listener created by this module (null when reusing an existing ALB)"
  value       = try(aws_lb_listener.http[0].arn, null)
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener created by this module (null if not created)"
  value       = try(aws_lb_listener.https[0].arn, null)
}

output "rule_listener_arn" {
  description = "ARN of the listener the rules are attached to (new or existing)"
  value       = local.rule_listener_arn
}

output "target_group_arns" {
  description = "Map of target group key to ARN"
  value       = { for k, v in aws_lb_target_group.this : k => v.arn }
}

output "target_group_arn_suffixes" {
  description = "Map of target group key to ARN suffix (for CloudWatch metrics)"
  value       = { for k, v in aws_lb_target_group.this : k => v.arn_suffix }
}
