# # ============================================================================
# # General
# # ============================================================================
# variable "project_name" {
#   description = "Project name, used as a prefix for resource names"
#   type        = string
# }

# variable "environment" {
#   description = "Deployment environment (e.g. dev, stg, prod)"
#   type        = string
# }

# variable "module_name" {
#   description = "Component this security group belongs to (e.g. alb, app, rds); appended to the name"
#   type        = string
# }

# variable "tags" {
#   description = "Common tags applied to all resources"
#   type        = map(string)
#   default     = {}
# }

# # ============================================================================
# # Security Group
# # ============================================================================
# variable "vpc_id" {
#   description = "ID of the VPC to create the security group in"
#   type        = string
# }

# variable "description" {
#   description = "Description of the security group. Changing it forces replacement. Defaults to \"Security group for <name>\""
#   type        = string
#   default     = null
# }

# # ============================================================================
# # Rules
# # Each rule must set exactly one source/destination:
# #   cidr_ipv4 | cidr_ipv6 | referenced_security_group_id | prefix_list_id
# # ip_protocol = "-1" means all traffic (ports are ignored).
# # to_port defaults to from_port when omitted.
# # ============================================================================
# variable "ingress_rules" {
#   description = "Map of ingress rules, keyed by a short rule name"
#   type = map(object({
#     description                  = optional(string)
#     ip_protocol                  = optional(string, "tcp")
#     from_port                    = optional(number)
#     to_port                      = optional(number)
#     cidr_ipv4                    = optional(string)
#     cidr_ipv6                    = optional(string)
#     referenced_security_group_id = optional(string)
#     prefix_list_id               = optional(string)
#   }))
#   default = {}

#   validation {
#     condition = alltrue([
#       for r in values(var.ingress_rules) : length(compact([
#         r.cidr_ipv4, r.cidr_ipv6, r.referenced_security_group_id, r.prefix_list_id
#       ])) == 1
#     ])
#     error_message = "Each ingress rule must set exactly one of cidr_ipv4, cidr_ipv6, referenced_security_group_id, prefix_list_id."
#   }

#   validation {
#     condition = alltrue([
#       for r in values(var.ingress_rules) : r.ip_protocol == "-1" || r.from_port != null
#     ])
#     error_message = "Each ingress rule must set from_port unless ip_protocol is \"-1\"."
#   }
# }

# variable "egress_rules" {
#   description = "Map of egress rules, keyed by a short rule name. Defaults to allow all outbound IPv4 traffic"
#   type = map(object({
#     description                  = optional(string)
#     ip_protocol                  = optional(string, "tcp")
#     from_port                    = optional(number)
#     to_port                      = optional(number)
#     cidr_ipv4                    = optional(string)
#     cidr_ipv6                    = optional(string)
#     referenced_security_group_id = optional(string)
#     prefix_list_id               = optional(string)
#   }))
#   default = {
#     all = {
#       description = "Allow all outbound traffic"
#       ip_protocol = "-1"
#       cidr_ipv4   = "0.0.0.0/0"
#     }
#   }

#   validation {
#     condition = alltrue([
#       for r in values(var.egress_rules) : length(compact([
#         r.cidr_ipv4, r.cidr_ipv6, r.referenced_security_group_id, r.prefix_list_id
#       ])) == 1
#     ])
#     error_message = "Each egress rule must set exactly one of cidr_ipv4, cidr_ipv6, referenced_security_group_id, prefix_list_id."
#   }

#   validation {
#     condition = alltrue([
#       for r in values(var.egress_rules) : r.ip_protocol == "-1" || r.from_port != null
#     ])
#     error_message = "Each egress rule must set from_port unless ip_protocol is \"-1\"."
#   }
# }

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

variable "vpc_id" {
  description = "ID of the VPC to create the security groups in"
  type        = string
}

# ============================================================================
# Security groups, keyed by a short name (e.g. alb, ecs, rds).
# Each rule must set exactly one source/destination:
#   cidr_ipv4 | cidr_ipv6 | prefix_list_id
#   | source_security_group        (key of another SG in this module)
#   | referenced_security_group_id (ID of an SG outside this module)
# ip_protocol = "-1" means all traffic (ports are ignored).
# to_port defaults to from_port when omitted.
# egress_rules defaults to allow all outbound IPv4 traffic.
# ============================================================================
variable "security_groups" {
  description = "Map of security groups and their rules"
  type = map(object({
    description = optional(string)

    ingress_rules = optional(map(object({
      description                  = optional(string)
      ip_protocol                  = optional(string, "tcp")
      from_port                    = optional(number)
      to_port                      = optional(number)
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      prefix_list_id               = optional(string)
      source_security_group        = optional(string)
      referenced_security_group_id = optional(string)
    })), {})

    egress_rules = optional(map(object({
      description                  = optional(string)
      ip_protocol                  = optional(string, "tcp")
      from_port                    = optional(number)
      to_port                      = optional(number)
      cidr_ipv4                    = optional(string)
      cidr_ipv6                    = optional(string)
      prefix_list_id               = optional(string)
      source_security_group        = optional(string)
      referenced_security_group_id = optional(string)
      })), {
      all = { description = "Allow all outbound traffic", ip_protocol = "-1", cidr_ipv4 = "0.0.0.0/0" }
    })
  }))

  validation {
    condition = alltrue(flatten([
      for sg in values(var.security_groups) : [
        for r in concat(values(sg.ingress_rules), values(sg.egress_rules)) : length(compact([
          r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.source_security_group, r.referenced_security_group_id
        ])) == 1
      ]
    ]))
    error_message = "Each rule must set exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id, source_security_group, referenced_security_group_id."
  }

  validation {
    condition = alltrue(flatten([
      for sg in values(var.security_groups) : [
        for r in concat(values(sg.ingress_rules), values(sg.egress_rules)) :
        r.source_security_group == null ? true : contains(keys(var.security_groups), r.source_security_group)
      ]
    ]))
    error_message = "source_security_group must be the key of another security group in this module."
  }

  validation {
    condition = alltrue(flatten([
      for sg in values(var.security_groups) : [
        for r in concat(values(sg.ingress_rules), values(sg.egress_rules)) : r.ip_protocol == "-1" || r.from_port != null
      ]
    ]))
    error_message = "Each rule must set from_port unless ip_protocol is \"-1\"."
  }
}


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


# {
#   "alb.http"     = { from_port = 80,   sg_key = "alb", rule_key = "http" }
#   "alb.https"    = { from_port = 443,  sg_key = "alb", rule_key = "https" }
#   "ecs.from_alb" = { from_port = 3000, sg_key = "ecs", rule_key = "from_alb" }
# }
