# AWS Application Load Balancer Terraform module

Terraform module that creates target groups and host- or path-based routing rules on an AWS Application Load Balancer (ALB). It works in two modes:

| Mode | `create_aws_lb` | What the module creates |
|---|---|---|
| **New ALB** | `true` (default) | ALB, HTTP listener (`:80`), HTTPS listener (`:443`, when `certificate_arn` is set), target groups, listener rules, extra SNI certificates |
| **Existing ALB** | `false` | Target groups, listener rules and extra SNI certificates on a listener of an ALB you already have |

## Features

- **Host- and path-based routing.** A listener rule is created for each target group that sets `host_headers` and/or `path_patterns`.
- **Default target group.** Mark one target group `default = true` to receive every request that matches no rule. Without one, unmatched requests get a `404`.
- **Automatic HTTP → HTTPS redirect** when a certificate is provided.
- **Multiple certificates (SNI)** through `additional_certificate_arns`.
- **Sensible health check defaults.** Every health check field is optional.
- **Reuse an existing ALB** by name or ARN, so several stacks can share one load balancer.

## Usage

### New ALB with HTTPS

```hcl
module "alb" {
  source  = "truongton812/terraform-module/alb"
  version = "~> 1.0"

  project_name = "myapp"
  environment  = "prod"

  vpc_id             = "vpc-0123456789abcdef0"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"] # at least 2 AZs
  security_group_ids = ["sg-0123456789abcdef0"]

  certificate_arn = "arn:aws:acm:ap-southeast-1:111122223333:certificate/xxxx"

  target_groups = {
    web = {
      port         = 80
      default      = true                  # catches all unmatched requests
      priority     = 100
      host_headers = ["example.com"]
      health_check = { path = "/health" }
    }

    api = {
      port          = 8080
      priority      = 110
      host_headers  = ["example.com"]
      path_patterns = ["/api/*"]
      health_check  = { path = "/api/health", matcher = "200-399" }
    }
  }

  tags = {
    Owner = "platform-team"
  }
}
```

The module produces:

| Request | Result |
|---|---|
| `http://…` (any) | `301` redirect to HTTPS |
| `https://example.com/api/…` | `api` target group |
| `https://example.com/…` | `web` target group |
| `https://anything-else/…` | `web` target group (default) |

### New ALB without HTTPS

Leave `certificate_arn` unset. The module then creates no HTTPS listener and attaches the rules to the HTTP listener. Unmatched requests go to the default target group, or get a `404` if none is set.

```hcl
module "alb" {
  source  = "truongton812/terraform-module/alb"
  version = "~> 1.0"

  project_name       = "myapp"
  environment        = "dev"
  vpc_id             = "vpc-0123456789abcdef0"
  subnet_ids         = ["subnet-aaa", "subnet-bbb"]
  security_group_ids = ["sg-0123456789abcdef0"]
  internal           = true

  target_groups = {
    app = {
      port    = 3000
      default = true
    }
  }
}
```

### Add services to an existing ALB

```hcl
module "alb_erp" {
  source  = "truongton812/terraform-module/alb"
  version = "~> 1.0"

  project_name = "erp"
  environment  = "prod"
  vpc_id       = "vpc-0123456789abcdef0"

  create_aws_lb          = false
  existing_lb            = "shared-prod-alb" # name or ARN
  existing_listener_port = 443

  target_groups = {
    erp = {
      port         = 8080
      priority     = 200 # must not clash with rules already on the listener
      host_headers = ["erp.example.com"]
    }
  }

  # Optional: add the certificate for erp.example.com to the shared listener
  additional_certificate_arns = {
    erp = "arn:aws:acm:ap-southeast-1:111122223333:certificate/yyyy"
  }
}
```

### Attach an ECS service

```hcl
resource "aws_ecs_service" "web" {
  # ...
  load_balancer {
    target_group_arn = module.alb.target_group_arns["web"]
    container_name   = "web"
    container_port   = 80
  }
}
```

### Route 53 alias record

```hcl
resource "aws_route53_record" "app" {
  zone_id = "Z0123456789ABC"
  name    = "example.com"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}
```

## Target group reference

Each entry in `target_groups` is keyed by a short, static name, for example `web` or `api`. That key is used in resource names and in the output maps.

| Attribute | Type | Default | Description |
|---|---|---|---|
| `port` | `number` | **required** | Port the targets listen on |
| `name` | `string` | `<project>-<env>-<key>-tg` | Override the target group name (max 32 characters) |
| `protocol` | `string` | `"HTTP"` | `HTTP` or `HTTPS` (uppercase) |
| `target_type` | `string` | `"ip"` | `ip`, `instance` or `lambda`. Use `ip` for ECS Fargate |
| `deregistration_delay` | `number` | `300` | Seconds to drain connections before a target is deregistered |
| `host_headers` | `list(string)` | `[]` | Host names that route to this target group, e.g. `["example.com", "*.example.com"]` |
| `path_patterns` | `list(string)` | `[]` | URL paths that route to this target group, e.g. `["/api/*"]` |
| `priority` | `number` | `null` (AWS assigns one) | Rule priority, 1–50000. Lower numbers are evaluated first |
| `default` | `bool` | `false` | Forward unmatched requests here. At most one target group can set it |
| `health_check` | `object` | see below | Health check settings |

When both `host_headers` and `path_patterns` are set, a request must match **both**. A target group with neither and without `default = true` gets no traffic.

### Health check

Every field is optional. Leaving out `health_check` gives a `GET /` on the traffic port that expects `200`.

| Attribute | Default |
|---|---|
| `path` | `"/"` |
| `port` | `"traffic-port"` |
| `protocol` | `"HTTP"` |
| `matcher` | `"200"` |
| `interval` | `30` (provider default) |
| `timeout` | `5` (provider default) |
| `healthy_threshold` | `3` (provider default) |
| `unhealthy_threshold` | `3` (provider default) |

> **Tip:** many applications answer `/` with a redirect (`302`) to a login page, and that fails the default `200` matcher. Point `path` at a health endpoint, or widen the matcher, e.g. `matcher = "200-399"`. If the target group uses `protocol = "HTTPS"`, set `health_check.protocol = "HTTPS"` as well.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `project_name` | Project name, used as a prefix for resource names | `string` | n/a | yes |
| `environment` | Deployment environment (e.g. `dev`, `stg`, `prod`) | `string` | n/a | yes |
| `vpc_id` | ID of the VPC for the target groups | `string` | n/a | yes |
| `tags` | Common tags applied to all resources | `map(string)` | `{}` | no |
| `create_aws_lb` | Create a new ALB and listeners. Set `false` to reuse `existing_lb` | `bool` | `true` | no |
| `existing_lb` | Name or ARN of an existing ALB (required when `create_aws_lb = false`) | `string` | `null` | no |
| `existing_listener_port` | Port of the existing listener that rules attach to | `number` | `443` | no |
| `subnet_ids` | Subnets for the ALB, at least 2 AZs (required when `create_aws_lb = true`) | `list(string)` | `[]` | no |
| `security_group_ids` | Security groups for the ALB (required when `create_aws_lb = true`) | `list(string)` | `[]` | no |
| `internal` | Create an internal ALB instead of an internet-facing one | `bool` | `false` | no |
| `idle_timeout` | Idle timeout in seconds | `number` | `60` | no |
| `enable_deletion_protection` | Prevent the ALB from being deleted | `bool` | `false` | no |
| `certificate_arn` | Default ACM certificate. When `null`, no HTTPS listener is created | `string` | `null` | no |
| `additional_certificate_arns` | Extra ACM certificates (SNI), keyed by a static name | `map(string)` | `{}` | no |
| `ssl_policy` | SSL policy of the HTTPS listener | `string` | `"ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"` | no |
| `target_groups` | Target groups and their routing rules (see [Target group reference](#target-group-reference)) | `map(object)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `alb_arn` | ARN of the load balancer (new or existing) |
| `alb_arn_suffix` | ARN suffix of the load balancer (for CloudWatch metrics) |
| `alb_dns_name` | DNS name of the load balancer |
| `alb_zone_id` | Hosted zone ID of the load balancer (for Route 53 alias records) |
| `http_listener_arn` | ARN of the HTTP listener created by this module (`null` when reusing an existing ALB) |
| `https_listener_arn` | ARN of the HTTPS listener created by this module (`null` if not created) |
| `rule_listener_arn` | ARN of the listener the rules are attached to (new or existing) |
| `target_group_arns` | Map of target group key to ARN |
| `target_group_arn_suffixes` | Map of target group key to ARN suffix (for CloudWatch metrics) |

## Resources

| Resource | Created when |
|---|---|
| `aws_lb.this` | `create_aws_lb = true` |
| `aws_lb_listener.http` | `create_aws_lb = true` |
| `aws_lb_listener.https` | `create_aws_lb = true` and `certificate_arn` is set |
| `aws_lb_listener_certificate.this` | one per entry in `additional_certificate_arns` |
| `aws_lb_target_group.this` | one per entry in `target_groups` |
| `aws_lb_listener_rule.this` | one per target group with `host_headers` or `path_patterns` |
| `data.aws_lb.existing` | `create_aws_lb = false` |
| `data.aws_lb_listener.existing` | `create_aws_lb = false` |

## Requirements

| Name | Version |
|---|---|
| terraform | `>= 1.5.0` |
| aws | `>= 5.0` |

## Notes and limitations

- **Existing ALB:** a listener must already exist on `existing_listener_port`, or `terraform plan` fails. The module does not change that listener's default action, so `default = true` has no effect in this mode.
- **Rule priorities** must be unique per listener. On a shared ALB, choose priorities that do not clash with rules owned by other stacks.
- **Name length:** AWS limits target group names to 32 characters. `<project>-<env>-<key>-tg` is checked at plan time; set `name` or use a shorter key if it is too long.
- **Values are case-sensitive and must be quoted:** write `protocol = "HTTP"` and `target_type = "ip"`, not `http` or `ip` without quotes.
- `additional_certificate_arns` needs an HTTPS listener: set `certificate_arn` (new ALB) or point `existing_listener_port` at an HTTPS listener (existing ALB).
