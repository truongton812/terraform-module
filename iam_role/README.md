# IAM Role Module

Creates an IAM role for an AWS service (ECS task, Lambda, EC2, ...) and grants it permissions in three ways:

| Method | Variable | When to use |
|--------|----------|-------------|
| Attach an existing policy | `managed_policy_arns` | AWS managed policies (`AmazonS3ReadOnlyAccess`, ...) or policies created elsewhere |
| Create a policy and attach it | `custom_policies` | Reusable policies that need their own ARN and show up in the IAM console |
| Embed a policy in the role | `inline_policies` | Permissions that belong to this role only; deleted together with the role |

## Resources created

| Resource | Count | Name |
|----------|-------|------|
| `aws_iam_role.this` | 1 | `<project_name>-<environment>-<role_name>` |
| `aws_iam_role_policy_attachment.managed` | one per ARN in `managed_policy_arns` | - |
| `aws_iam_policy.custom` | one per key in `custom_policies` | `<project_name>-<environment>-<key>` |
| `aws_iam_role_policy_attachment.custom` | one per key in `custom_policies` | - |
| `aws_iam_role_policy.inline` | one per key in `inline_policies` | `<key>` |

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5.0 |
| AWS provider | >= 5.0 |

## Usage

### Minimal

```hcl
module "ecs_task_role" {
  source = "truongton812/terraform-module/ecs_service/iam_role"

  project_name     = "cg-utils"
  environment      = "dev"
  role_name        = "task-role"
  trusted_services = ["ecs-tasks.amazonaws.com"]
}
```

### Full

```hcl
module "ecs_task_role" {
  source = "truongton812/terraform-module/ecs_service/iam_role"

  project_name         = "cg-utils"
  environment          = "dev"
  role_name            = "task-role"
  description          = "Task role for cg-utils service"   # Latin characters only
  trusted_services     = ["ecs-tasks.amazonaws.com"]
  max_session_duration = 3600

  tags = {
    Owner = "platform-team"
  }

  # 1. Existing policies: only the ARN is needed
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
  ]

  # 2. The module creates policy "cg-utils-dev-sqs-send" and attaches it to the role
  custom_policies = {
    sqs-send = {
      Statement = [{
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.main.arn]
      }]
    }
    s3-read = {...}
  }

  # 3. Inline policy embedded directly in the role
  inline_policies = {
    s3-read = {
      Statement = [
        {
          Sid      = "ListBucket"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::my-bucket"]
        },
        {
          Sid      = "ReadObjects"
          Action   = ["s3:GetObject"]
          Resource = ["arn:aws:s3:::my-bucket/*"]
          Condition = {
            StringEquals = {
              "aws:RequestedRegion" = ["ap-southeast-1"]
            }
          }
        },
      ]
    }
    cloudwatch-write = {...}
  }
}

# Use the outputs in another module
resource "aws_ecs_task_definition" "app" {
  # ...
  task_role_arn = module.ecs_task_role.role_arn
}
```

## Writing policies (`custom_policies` / `inline_policies`)

Policies are written as **HCL objects**, not JSON strings. The module runs `jsonencode` and drops any field you leave out (`null`).

```hcl
<policy-name> = {
  Version   = "2012-10-17"          # optional, defaults to "2012-10-17"
  Statement = [{
    Sid         = "ReadS3"          # optional, letters and digits only
    Effect      = "Allow"           # optional, defaults to "Allow"; "Allow" or "Deny"
    Action      = ["s3:GetObject"]  # or NotAction
    Resource    = ["arn:aws:s3:::my-bucket/*"]  # or NotResource
    Condition   = {                 # optional
      <operator> = { <condition-key> = [<value>, ...] }
    }
  }]
}
```

Rules to keep in mind:

- `Action`, `NotAction`, `Resource`, `NotResource` and the values inside `Condition` are **always lists**, even with a single element:
  `Resource = ["*"]` ✅, `Resource = "*"` ❌ (fails with `list of string required`).
- Each statement sets **exactly one** of `Action`/`NotAction` and **exactly one** of `Resource`/`NotResource`.
- **Do not use `Principal`.** These are identity-based policies; `Principal` belongs only in resource-based policies such as S3 bucket policies. Any field outside the structure above (`Principal`, ...) is **silently dropped** by Terraform.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_name` | Project name, used as a prefix | `string` | - | ✅ |
| `environment` | Environment (dev, test, stg, prod) | `string` | - | ✅ |
| `role_name` | Role name suffix | `string` | - | ✅ |
| `trusted_services` | Service principals allowed to assume the role | `list(string)` | - | ✅ |
| `description` | Role description | `string` | `null` | |
| `max_session_duration` | Maximum session duration (seconds) | `number` | `3600` | |
| `tags` | Common tags for all resources | `map(string)` | `{}` | |
| `managed_policy_arns` | ARNs of existing policies to attach | `list(string)` | `[]` | |
| `custom_policies` | Policies to create and attach | `map(object)` | `{}` | |
| `inline_policies` | Inline policies embedded in the role | `map(object)` | `{}` | |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the role |
| `role_name` | Name of the role |
| `role_id` | ID of the role |
| `custom_policy_arns` | Map of `key => ARN` for the created custom policies |
| `inline_policy_names` | List of inline policy names |
