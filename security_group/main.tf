# ============================================================================
# Security Group Module
# ============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Flatten { sg = { rules = { rule = {...} } } } into { "sg.rule" = {...} }. For example:

  # From:
  # security_groups = {
  #   alb = {
  #     ingress_rules = {
  #       https = { from_port = 443 }
  #       http  = { from_port = 80 }
  #     }
  #   }
  #   ecs = {
  #     ingress_rules = {
  #       from_alb = { from_port = 3000 }
  #     }
  #   }
  # }
  # To:
  # security_groups = {
  #   "alb.http"     = { from_port = 80,...   sg_key = "alb", rule_key = "http" }
  #   "alb.https"    = { from_port = 443,...  sg_key = "alb", rule_key = "https" }
  #   "ecs.from_alb" = { from_port = 3000,... sg_key = "ecs", rule_key = "from_alb" }
  # }

  ingress_rules = merge([
    for sg_key, sg in var.security_groups : {
      for rule_key, rule in sg.ingress_rules : "${sg_key}.${rule_key}" => merge(rule, { sg_key = sg_key, rule_key = rule_key })
    }
  ]...)

  egress_rules = merge([
    for sg_key, sg in var.security_groups : {
      for rule_key, rule in sg.egress_rules : "${sg_key}.${rule_key}" => merge(rule, { sg_key = sg_key, rule_key = rule_key })
    }
  ]...)
}

# # -----------------------------------------------------------------------------
# # Security Group
# # -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = "${local.name_prefix}-${each.key}"
  description = coalesce(each.value.description, "Security group for ${local.name_prefix}-${each.key}")
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.key}"
  })
}


# # -----------------------------------------------------------------------------
# # Ingress rules
# # -----------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description

  ip_protocol = each.value.ip_protocol
  from_port   = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port     = each.value.ip_protocol == "-1" ? null : coalesce(each.value.to_port, each.value.from_port)

  cidr_ipv4      = each.value.cidr_ipv4
  cidr_ipv6      = each.value.cidr_ipv6
  prefix_list_id = each.value.prefix_list_id

  # source_security_group = key of another SG in this module; otherwise an external SG ID
  referenced_security_group_id = (
    each.value.source_security_group != null
    ? aws_security_group.this[each.value.source_security_group].id
    : each.value.referenced_security_group_id
  )

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.value.sg_key}-in-${each.value.rule_key}"
  })
}


# # -----------------------------------------------------------------------------
# # Egress rules
# # -----------------------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.egress_rules

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description

  ip_protocol = each.value.ip_protocol
  from_port   = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port     = each.value.ip_protocol == "-1" ? null : coalesce(each.value.to_port, each.value.from_port)

  cidr_ipv4      = each.value.cidr_ipv4
  cidr_ipv6      = each.value.cidr_ipv6
  prefix_list_id = each.value.prefix_list_id

  referenced_security_group_id = (
    each.value.source_security_group != null
    ? aws_security_group.this[each.value.source_security_group].id
    : each.value.referenced_security_group_id
  )

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-${each.value.sg_key}-out-${each.value.rule_key}"
  })
}
