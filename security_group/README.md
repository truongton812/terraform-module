# AWS Security Group Terraform Module

Terraform module that creates one or more security groups in a VPC, together with their ingress and egress rules.

- Several security groups in a single module call, keyed by a short name (`alb`, `ecs`, `rds`, ...)
- Rules are managed as separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` resources, one per rule
- A rule can reference **another security group of the same module by its key** (`source_security_group = "alb"`). The module resolves the ID for you.
- Rules can also use an IPv4 CIDR, an IPv6 CIDR, a prefix list, or the ID of an external security group
- Egress defaults to allow all outbound IPv4 traffic

## Usage

### ALB → ECS → RDS

```hcl
module "security_groups" {
  source  = "<namespace>/security-group/aws"
  version = "~> 1.0"

  project_name = "myapp"
  environment  = "prod"
  vpc_id       = module.network.vpc_id

  security_groups = {
    alb = {
      description = "Public load balancer"
      ingress_rules = {
        http  = { from_port = 80, cidr_ipv4 = "0.0.0.0/0" }
        https = { from_port = 443, cidr_ipv4 = "0.0.0.0/0" }
      }
    }

    ecs = {
      description = "ECS tasks"
      ingress_rules = {
        api_from_alb = { from_port = 3000, source_security_group = "alb" }
      }
    }

    rds = {
      description = "PostgreSQL"
      ingress_rules = {
        postgres_from_ecs = { from_port = 5432, source_security_group = "ecs" }
      }
      egress_rules = {} # no outbound rules
    }
  }

  tags = {
    Project   = "myapp"
    ManagedBy = "terraform"
  }
}
```

This creates three security groups: `myapp-prod-alb`, `myapp-prod-ecs` and `myapp-prod-rds`. Each rule that uses `source_security_group` is wired to the ID of the named group.

Use the outputs in other resources:

```hcl
resource "aws_lb" "this" {
  # ...
  security_groups = [module.security_groups.security_group_ids["alb"]]
}
```

### Other rule types

```hcl
security_groups = {
  bastion = {
    ingress_rules = {
      ssh_office = { from_port = 22, cidr_ipv4 = "203.0.113.10/32", description = "Office" }
      ssh_ipv6   = { from_port = 22, cidr_ipv6 = "2001:db8::/32" }
      from_vpn   = { ip_protocol = "-1", referenced_security_group_id = "sg-0123456789abcdef0" }
    }
    egress_rules = {
      https_s3 = { from_port = 443, prefix_list_id = "pl-6da54004" }
      dns_udp  = { ip_protocol = "udp", from_port = 53, cidr_ipv4 = "10.0.0.2/32" }
    }
  }

  app = {
    ingress_rules = {
      ephemeral = { from_port = 32768, to_port = 65535, source_security_group = "bastion" }
    }
  }
}
```

## Rules

Each security group has two optional maps, `ingress_rules` and `egress_rules`. The map key is a short rule name. It is used in the resource address and in the rule's `Name` tag, so keep it stable.

| Attribute | Description | Default |
|-----------|-------------|---------|
| `description` | Rule description | `null` |
| `ip_protocol` | `tcp`, `udp`, `icmp`, a protocol number, or `-1` for all traffic | `"tcp"` |
| `from_port` | Start of the port range. Required unless `ip_protocol = "-1"` | `null` |
| `to_port` | End of the port range | same as `from_port` |
| `cidr_ipv4` | IPv4 CIDR | `null` |
| `cidr_ipv6` | IPv6 CIDR | `null` |
| `prefix_list_id` | Managed prefix list ID | `null` |
| `source_security_group` | **Key** of another security group in this module | `null` |
| `referenced_security_group_id` | **ID** of a security group outside this module | `null` |

Each rule must set **exactly one** of `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `source_security_group` or `referenced_security_group_id`. To allow both IPv4 and IPv6, write two rules.

When `ip_protocol = "-1"`, the ports are ignored.

### Default egress

If `egress_rules` is omitted, the group gets one rule, `all`, that allows all outbound IPv4 traffic (`0.0.0.0/0`, all protocols). Set `egress_rules = {}` for no outbound rules, or pass your own map to replace the default.

### Validation

`terraform plan` fails early with a clear message when:

- a rule sets zero or more than one source/destination
- `source_security_group` is not a key of `security_groups`
- `from_port` is missing on a rule whose `ip_protocol` is not `-1`

## Resource naming

| Resource | Name / `Name` tag |
|----------|-------------------|
| Security group | `<project_name>-<environment>-<sg_key>` |
| Ingress rule | `<project_name>-<environment>-<sg_key>-in-<rule_key>` |
| Egress rule | `<project_name>-<environment>-<sg_key>-out-<rule_key>` |

Resource addresses use the keys, for example:

```
aws_security_group.this["alb"]
aws_vpc_security_group_ingress_rule.this["alb.https"]
aws_vpc_security_group_egress_rule.this["alb.all"]
```

Adding or removing a rule only affects that rule. Renaming a security group key, or changing its `description`, **replaces** the security group.

`tags` is merged into the tags of every resource.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5.0 |
| aws       | >= 5.0   |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_name` | Project name, used as a prefix for resource names | `string` | n/a | yes |
| `environment` | Deployment environment (e.g. dev, stg, prod) | `string` | n/a | yes |
| `vpc_id` | ID of the VPC to create the security groups in | `string` | n/a | yes |
| `security_groups` | Map of security groups and their rules, see [Rules](#rules) | `map(object({ description = optional(string), ingress_rules = optional(map(object)), egress_rules = optional(map(object)) }))` | n/a | yes |
| `tags` | Common tags applied to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `security_group_ids` | Map of security group key to ID |
| `security_group_arns` | Map of security group key to ARN |
| `security_group_names` | Map of security group key to name |
| `ingress_rule_ids` | Map of `"<sg_key>.<rule_key>"` to ingress rule ID |
| `egress_rule_ids` | Map of `"<sg_key>.<rule_key>"` to egress rule ID |

## Notes

- Do not mix this module with inline `ingress` / `egress` blocks on the same security group, or with `aws_security_group_rule`. They conflict with `aws_vpc_security_group_*_rule` resources.
- Security groups that reference each other in both directions (A allows B and B allows A) work, because the rules are separate resources from the groups.
- A security group cannot be deleted while it is attached to a network interface or referenced by a rule in another group. Detach it first.
