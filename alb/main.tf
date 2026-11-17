# ============================================================================
# Application Load Balancer Module
# - create_aws_lb = true : create a new ALB + listeners + target groups + rules
# - create_aws_lb = false: reuse an existing ALB/listener (existing_lb), only
#                          create target groups + rules (+ optional SNI certs)
# ============================================================================

locals {
  name_prefix           = "${var.project_name}-${var.environment}"
  create_https_listener = var.create_aws_lb && var.certificate_arn != null

  # Existing ALB can be passed by name or by ARN
  existing_lb_is_arn = var.existing_lb != null && startswith(coalesce(var.existing_lb, "-"), "arn:")

  # Attributes of whichever ALB is in use (new or existing)
  lb_arn        = var.create_aws_lb ? aws_lb.this[0].arn : data.aws_lb.existing[0].arn
  lb_arn_suffix = var.create_aws_lb ? aws_lb.this[0].arn_suffix : data.aws_lb.existing[0].arn_suffix
  lb_dns_name   = var.create_aws_lb ? aws_lb.this[0].dns_name : data.aws_lb.existing[0].dns_name
  lb_zone_id    = var.create_aws_lb ? aws_lb.this[0].zone_id : data.aws_lb.existing[0].zone_id

  # Listener that new rules (and extra certificates) are attached to:
  # - new ALB: HTTPS when a certificate is set, otherwise HTTP
  # - existing ALB: the listener on existing_listener_port
  rule_listener_arn = (
    !var.create_aws_lb ? data.aws_lb_listener.existing[0].arn :
    local.create_https_listener ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
  )
  rule_listener_is_https = (
    var.create_aws_lb ? local.create_https_listener : data.aws_lb_listener.existing[0].protocol == "HTTPS"
  )

  routed_target_groups = {
    for k, tg in var.target_groups : k => tg
    if length(tg.host_headers) > 0 || length(tg.path_patterns) > 0
  }

  # Target group marked default = true (at most one, enforced by validation).
  # Requests matching no rule are forwarded there instead of returning 404.
  default_target_group = one([for k, tg in var.target_groups : k if tg.default])

  # Default action of the listener that serves traffic (HTTPS if present, else HTTP)
  default_action_type = local.default_target_group != null ? "forward" : "fixed-response"
  default_action_tg_arn = (
    local.default_target_group != null ? aws_lb_target_group.this[local.default_target_group].arn : null
  )
}

# -----------------------------------------------------------------------------
# Existing Load Balancer (create_aws_lb = false)
# -----------------------------------------------------------------------------
data "aws_lb" "existing" {
  count = var.create_aws_lb ? 0 : 1

  arn  = local.existing_lb_is_arn ? var.existing_lb : null
  name = local.existing_lb_is_arn ? null : var.existing_lb

  lifecycle {
    precondition {
      condition     = var.existing_lb != null
      error_message = "existing_lb (name or ARN) is required when create_aws_lb = false."
    }
  }
}

data "aws_lb_listener" "existing" {
  count = var.create_aws_lb ? 0 : 1

  load_balancer_arn = data.aws_lb.existing[0].arn
  port              = var.existing_listener_port
}

# -----------------------------------------------------------------------------
# Load Balancer (create_aws_lb = true)
# -----------------------------------------------------------------------------
resource "aws_lb" "this" {
  count = var.create_aws_lb ? 1 : 0

  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = var.internal
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids
  idle_timeout       = var.idle_timeout

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-alb"
  })

  lifecycle {
    precondition {
      condition     = length(var.subnet_ids) >= 2 && length(var.security_group_ids) > 0
      error_message = "subnet_ids (at least 2) and security_group_ids are required when create_aws_lb = true."
    }
  }
}

# -----------------------------------------------------------------------------
# Listeners (create_aws_lb = true)
# -----------------------------------------------------------------------------

# HTTP listener:
# - certificate set     : redirect to HTTPS
# - no certificate      : forward to the default target group, or 404 if none
resource "aws_lb_listener" "http" {
  count = var.create_aws_lb ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = local.create_https_listener ? "redirect" : local.default_action_type
    target_group_arn = local.create_https_listener ? null : local.default_action_tg_arn

    dynamic "redirect" {
      for_each = local.create_https_listener ? [1] : []

      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = !local.create_https_listener && local.default_target_group == null ? [1] : []

      content {
        content_type = "text/plain"
        status_code  = "404"
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-http-listener"
  })
}

# HTTPS listener: forward to the default target group, or 404 if none
resource "aws_lb_listener" "https" {
  count = local.create_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.certificate_arn

  default_action {
    type             = local.default_action_type
    target_group_arn = local.default_action_tg_arn

    dynamic "fixed_response" {
      for_each = local.default_target_group == null ? [1] : []

      content {
        content_type = "text/plain"
        status_code  = "404"
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-https-listener"
  })
}

# Extra SNI certificates, on the new HTTPS listener or the existing one
resource "aws_lb_listener_certificate" "this" {
  for_each = var.additional_certificate_arns

  listener_arn    = local.rule_listener_arn
  certificate_arn = each.value

  lifecycle {
    precondition {
      condition     = local.rule_listener_is_https
      error_message = "additional_certificate_arns requires an HTTPS listener (set certificate_arn, or point existing_listener_port at an HTTPS listener)."
    }
  }
}

# -----------------------------------------------------------------------------
# Target Groups
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name                 = coalesce(each.value.name, "${local.name_prefix}-${each.key}-tg")
  port                 = each.value.port
  protocol             = each.value.protocol
  vpc_id               = var.vpc_id
  target_type          = each.value.target_type
  deregistration_delay = each.value.deregistration_delay

  health_check {
    enabled             = true
    path                = each.value.health_check.path
    port                = each.value.health_check.port
    protocol            = each.value.health_check.protocol
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(var.tags, {
    Name = coalesce(each.value.name, "${local.name_prefix}-${each.key}-tg")
  })
}

# -----------------------------------------------------------------------------
# Listener Rules (only for target groups with host_headers or path_patterns)
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "this" {
  for_each = local.routed_target_groups

  listener_arn = local.rule_listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  dynamic "condition" {
    for_each = length(each.value.host_headers) > 0 ? [1] : []

    content {
      host_header {
        values = each.value.host_headers
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.path_patterns) > 0 ? [1] : []

    content {
      path_pattern {
        values = each.value.path_patterns
      }
    }
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.key}-rule"
  })
}
