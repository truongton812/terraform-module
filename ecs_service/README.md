# Module `ecs_service`

Terraform module that creates an ECS service (Fargate by default) along with its supporting resources:

| Resource | Created when |
|---|---|
| ECR repository + lifecycle policy | `create_ecr_repository = true` (default) |
| ECS task definition (single container) | Always |
| ECS service | Always |
| Load balancer attachment (target group) | `enable_load_balancer = true` |
| Service Discovery (Cloud Map registry) | `enable_service_discovery = true` |
| Service Connect | `enable_service_connect = true` |
| Auto scaling on CPU and memory | `enable_autoscaling = true` |

## Requirements

- Terraform >= 1.3 (the module uses `optional()` in variable types)
- AWS provider >= 6.0 (required for the `deployment_configuration { strategy }` block)

## Prerequisites (not created by this module)

- **ECS cluster**: pass it in via `cluster_id` and `ecs_cluster_name`.
- **CloudWatch Log Group**: pass it in via `log_group_name`.
- **IAM roles**:
  - `execution_role_arn` (required): needs permission to pull images from ECR and write logs. If you use `secrets`, it also needs `secretsmanager:GetSecretValue` and/or `ssm:GetParameters` (plus `kms:Decrypt` for a customer-managed KMS key). If you use `env_bucket_arn`, it also needs `s3:GetObject` on the `.env` file and `s3:GetBucketLocation` on the bucket.
  - `task_role_arn` (optional): permissions for the application to call AWS. If `enable_execute_command = true` (the default), this role needs the `ssmmessages:*` permissions for ECS Exec.
- **VPC, subnets, security groups**.
- **Target group** (when attaching a load balancer) and **Cloud Map namespace/service** (when using Service Discovery or Service Connect).

## Naming convention

All resources share the same prefix:

```
<project_name>-<environment>-<app_name>
```

For example, `project_name = "chat"`, `environment = "dev"`, `app_name = "api"` gives an ECR repo, task definition family and ECS service all named `chat-dev-api`. The prefix is also used as the `awslogs-stream-prefix`.

## Usage

### 1. Minimal

```hcl
module "api" {
  source = "truongton812/terraform-module/ecs_service"

  project_name = "chat"
  environment  = "dev"
  app_name     = "api"
  aws_region   = "ap-southeast-1"

  container_image    = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/chat-dev-api:latest"
  execution_role_arn = aws_iam_role.ecs_execution.arn
  log_group_name     = aws_cloudwatch_log_group.ecs.name

  cluster_id       = aws_ecs_cluster.main.id
  ecs_cluster_name = aws_ecs_cluster.main.name
  subnets          = module.vpc.private_subnet_ids
  security_groups  = [aws_security_group.api.id]

  port_mappings = [
    { containerPort = 8080 }
  ]
}
```

### 2. Full: load balancer, environment variables, secrets, auto scaling

```hcl
module "api" {
  source = "truongton812/terraform-module/ecs_service"

  project_name = "chat"
  environment  = "production"
  app_name     = "api"
  aws_region   = "ap-southeast-1"
  tags         = { Team = "backend" }

  # --- Task ---
  container_image    = "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/chat-production-api:latest"
  task_cpu           = 512
  task_memory        = 1024
  execution_role_arn = aws_iam_role.ecs_execution.arn
  task_role_arn      = aws_iam_role.api_task.arn
  log_group_name     = aws_cloudwatch_log_group.ecs.name

  port_mappings = [
    { containerPort = 8080, name = "http" }
  ]

  environment_variables = {
    NODE_ENV = "production"
    PORT     = "8080"
  }

  secrets = {
    DB_PASSWORD = aws_secretsmanager_secret.db_password.arn
    JWT_SECRET  = "arn:aws:ssm:ap-southeast-1:123456789012:parameter/chat/production/jwt-secret"
  }

  # .env file in S3: s3://<bucket>/chat-production-api.env
  env_bucket_arn = aws_s3_bucket.env.arn

  # --- Service ---
  cluster_id       = aws_ecs_cluster.main.id
  ecs_cluster_name = aws_ecs_cluster.main.name
  subnets          = module.vpc.private_subnet_ids
  security_groups  = [aws_security_group.api.id]
  desired_count    = 2

  # --- Load balancer ---
  enable_load_balancer              = true
  target_group_arn                  = aws_lb_target_group.api.arn
  health_check_grace_period_seconds = 120

  # --- Auto scaling ---
  enable_autoscaling                        = true
  ecs_min_capacity                          = 2
  ecs_max_capacity                          = 6
  appautoscaling_policy_cpu_target_value    = 60
  appautoscaling_policy_memory_target_value = 75
}
```

### 3. Service Connect (service-to-service calls)

```hcl
module "worker" {
  source = "truongton812/terraform-module/ecs_service"
  # ... required variables as in example 1 ...

  port_mappings = [
    { containerPort = 3000, name = "worker-http" } # `name` is required
  ]

  enable_service_connect         = true
  service_connect_namespace_arn  = aws_service_discovery_http_namespace.main.arn
  service_connect_discovery_name = "worker"
  service_connect_client_alias   = "worker" # other services call http://worker:3000
}
```

## Inputs

### General

| Name | Type | Default | Description |
|---|---|---|---|
| `project_name` | `string` | **required** | Project name, used in the name prefix |
| `environment` | `string` | **required** | Environment: `dev`, `staging`, `production`, ... |
| `app_name` | `string` | **required** | Application/service name |
| `aws_region` | `string` | **required** | Region for the `awslogs` configuration |
| `tags` | `map(string)` | `{}` | Tags applied to the ECR repo and task definition |

### ECR

| Name | Type | Default | Description |
|---|---|---|---|
| `create_ecr_repository` | `bool` | `true` | Whether to create the ECR repo |
| `image_tag_mutability` | `string` | `"MUTABLE"` | `MUTABLE` or `IMMUTABLE` |
| `ecr_scan_on_push` | `bool` | `false` | Scan images for vulnerabilities on push |
| `lifecycle_keep_count` | `number` | `20` | Maximum number of images to keep; older images expire |

### Task definition

| Name | Type | Default | Description |
|---|---|---|---|
| `container_image` | `string` | **required** | Container image URI |
| `execution_role_arn` | `string` | **required** | Task execution role ARN |
| `log_group_name` | `string` | **required** | CloudWatch Log Group name (must already exist) |
| `task_role_arn` | `string` | `null` | Task role ARN |
| `requires_compatibilities` | `list(string)` | `["FARGATE"]` | The first element is also used as the service `launch_type` |
| `network_mode` | `string` | `"awsvpc"` | Task network mode |
| `container_name` | `string` | `"container"` | Container name (also used for the load balancer attachment) |
| `task_cpu` | `number` | `256` | Task CPU units (1024 = 1 vCPU) |
| `task_memory` | `number` | `512` | Task memory (MiB) |
| `container_cpu` | `number` | `null` | Container CPU; defaults to `task_cpu` |
| `container_memory` | `number` | `null` | Container memory; defaults to `task_memory` |
| `port_mappings` | `list(object)` | `[]` | See [port_mappings](#port_mappings) |
| `container_port` | `number` | `null` | Port the load balancer forwards to; defaults to `port_mappings[0].containerPort` |
| `environment_variables` | `map(string)` | `null` | Environment variables as `{ NAME = "value" }` |
| `secrets` | `map(string)` | `null` | Environment variables from secrets: `{ NAME = "<Secrets Manager or SSM Parameter ARN>" }` |
| `env_bucket_arn` | `string` | `null` | ARN of the S3 bucket holding the `.env` file; leave empty to skip the env file |
| `env_file_key` | `string` | `null` | `.env` file name in the bucket; defaults to `<project_name>-<environment>-<app_name>.env` |

#### `port_mappings`

```hcl
port_mappings = [
  {
    containerPort = 8080           # required
    name          = "http"         # optional; REQUIRED when Service Connect is enabled
    hostPort      = 8080           # optional; with awsvpc it must equal containerPort or be omitted
    protocol      = "tcp"          # optional, defaults to "tcp"
  }
]
```

The load balancer and Service Connect both use the **first element** of the list.

### ECS service

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_id` | `string` | **required** | ECS cluster ID/ARN |
| `ecs_cluster_name` | `string` | **required** | ECS cluster name (used by auto scaling) |
| `subnets` | `list(string)` | **required** | Subnets to run tasks in |
| `security_groups` | `list(string)` | **required** | Security groups attached to tasks |
| `assign_public_ip` | `bool` | `false` | Assign a public IP to tasks (needs `true` in a public subnet without NAT) |
| `desired_count` | `number` | `1` | Number of tasks at creation time |
| `enable_execute_command` | `bool` | `true` | Enable ECS Exec |
| `availability_zone_rebalancing` | `string` | `"ENABLED"` | Automatically rebalance tasks across AZs |
| `deployment_maximum_percent` | `number` | `200` | Maximum percent of tasks during a deployment |
| `deployment_minimum_healthy_percent` | `number` | `100` | Minimum healthy percent of tasks during a deployment |
| `deployment_strategy` | `string` | `"ROLLING"` | `ROLLING` or `BLUE_GREEN` |

### Load balancer

| Name | Type | Default | Description |
|---|---|---|---|
| `enable_load_balancer` | `bool` | `false` | Attach the service to a target group |
| `target_group_arn` | `string` | `null` | Required when `enable_load_balancer = true` |
| `health_check_grace_period_seconds` | `number` | `90` | Only applied when a load balancer is attached |

### Service Discovery

| Name | Type | Default | Description |
|---|---|---|---|
| `enable_service_discovery` | `bool` | `false` | Register tasks in Cloud Map |
| `service_registry_arn` | `string` | `null` | ARN of the `aws_service_discovery_service`; required when enabled |

### Service Connect

| Name | Type | Default | Description |
|---|---|---|---|
| `enable_service_connect` | `bool` | `false` | Enable Service Connect |
| `service_connect_namespace_arn` | `string` | `null` | Cloud Map namespace ARN; required when enabled |
| `service_connect_discovery_name` | `string` | `null` | Name registered in the namespace; defaults to `client_alias` |
| `service_connect_client_alias` | `string` | `null` | DNS name other services use to call this one; defaults to `discovery_name` |

When Service Connect is enabled, at least one of `discovery_name` or `client_alias` must be set, and `port_mappings[0].name` must be set.

### Auto scaling

| Name | Type | Default | Description |
|---|---|---|---|
| `enable_autoscaling` | `bool` | `false` | Enable auto scaling on CPU and memory |
| `ecs_min_capacity` | `number` | `1` | Minimum number of tasks |
| `ecs_max_capacity` | `number` | `2` | Maximum number of tasks |
| `appautoscaling_policy_cpu_target_value` | `number` | `70` | Target CPU utilization (%) |
| `appautoscaling_policy_memory_target_value` | `number` | `70` | Target memory utilization (%) |
| `appautoscaling_policy_scale_in_cooldown` | `number` | `300` | Cooldown (seconds) after a scale-in |
| `appautoscaling_policy_scale_out_cooldown` | `number` | `60` | Cooldown (seconds) after a scale-out |

## Outputs

| Name | Description |
|---|---|
| `ecr_repository_name` | ECR repo name (`null` if not created) |
| `ecr_repository_url` | ECR repo URL for `docker push` (`null` if not created) |
| `ecr_repository_arn` | ECR repo ARN (`null` if not created) |
| `task_definition_arn` | ARN of the task definition Terraform created initially |
| `task_definition_family` | Task definition family |
| `service_id` | ECS service ID (ARN) |
| `service_name` | ECS service name |

## Important notes

### Terraform creates, CI/CD deploys

The module sets these `ignore_changes`:

- `aws_ecs_task_definition.container_definitions`
- `aws_ecs_service.task_definition` and `aws_ecs_service.desired_count`

As a result:

1. After the first `apply`, **changing `container_image`, `environment_variables`, `secrets`, `container_cpu`/`container_memory`, `port_mappings`, etc. in Terraform has no effect**. These changes must go through your CI/CD pipeline (register a new task definition revision, then update the service).
2. To make Terraform re-apply the container configuration, run:
   ```bash
   terraform apply -replace='module.api.aws_ecs_task_definition.this'
   ```
   The service keeps its current revision because `task_definition` is also ignored, so you must update the service to the new revision yourself.
3. `desired_count` only takes effect when the service is created. After that, the task count is managed by auto scaling or by operators.

### First deployment with a new ECR repo

If the module creates the ECR repo, the repo is empty at creation time and tasks keep failing because no image can be pulled. Either:

- Push an image to `ecr_repository_url` right after `apply`; the service will start tasks again on its own.
- Or set `desired_count = 0` for the first apply and let CI/CD scale it up.

### `.env` file in S3

- File path: `<env_bucket_arn>/<env_file_key>`, e.g. `arn:aws:s3:::my-env-bucket/chat-dev-api.env`.
- The file must exist before tasks start, otherwise they fail.
- If a variable is set in both `environment_variables` and the `.env` file, the value from `environment_variables` wins.

### Auto scaling

When `enable_autoscaling` is on, keep `desired_count` within `[ecs_min_capacity, ecs_max_capacity]`. The CPU and memory policies work together: the service scales out when **either** metric is above its target, and scales in only when **both** are below their targets.

### Input validation

The module uses `precondition` blocks to fail at `plan` time on incomplete configuration:

- `enable_load_balancer = true` without `target_group_arn`, or without both `container_port` and `port_mappings`
- `enable_service_discovery = true` without `service_registry_arn`
- `enable_service_connect = true` without a namespace, without `port_mappings[0].name`, or without both `client_alias` and `discovery_name`
