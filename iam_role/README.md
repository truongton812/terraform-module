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
  source = "git::https://github.com/truongton812/terraform-module.git//iam_role?ref=iamrole-v1.0.0"

  project_name     = "cg-utils"
  environment      = "dev"
  role_name        = "task-role"
  trusted_services = ["ecs-tasks.amazonaws.com"]
}
```

### Full

```hcl
module "ecs_task_role" {
  source = "git::https://github.com/truongton812/terraform-module.git//iam_role?ref=iamrole-v1.0.0"

  project_name         = "cg-utils"
  environment          = "dev"
  role_name            = "task-role"
  description          = "Task role for cg-utils service" # Latin characters only
  trusted_services     = ["ecs-tasks.amazonaws.com"]
  max_session_duration = 3600

  common_tags = {
    Owner = "platform-team"
  }

  # 1. Existing policies: only the ARN is needed
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
  ]

  # 2. The module creates policy "cg-utils-dev-sqs-send" and attaches it to the role
  custom_policies = {
    sqs-send = {
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.main.arn]
      }]
    }
  }

  # 3. Inline policy embedded directly in the role
  inline_policies = {
    s3-read = {
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "ListBucket"
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = ["arn:aws:s3:::my-bucket"]
        },
        {
          Sid      = "ReadObjects"
          Effect   = "Allow"
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
  }
}

# Use the outputs in another module
resource "aws_ecs_task_definition" "app" {
  # ...
  task_role_arn = module.ecs_task_role.role_arn
}
```

## Writing policies (`custom_policies` / `inline_policies`)

Policies are written as **HCL objects**, not JSON strings. The module calls `jsonencode` on each value for you, so **do not** wrap a policy in `jsonencode(...)` or pass a JSON string: the module rejects it at `plan` time.

```hcl
<policy-name> = {
  Version   = "2012-10-17"                    # recommended; without it AWS falls back to 2008-10-17 and policy variables like ${aws:username} do not work
  Statement = [{
    Sid       = "ReadS3"                      # optional, letters and digits only
    Effect    = "Allow"                       # required: "Allow" or "Deny"
    Action    = ["s3:GetObject"]              # or NotAction
    Resource  = ["arn:aws:s3:::my-bucket/*"]  # or NotResource
    Condition = {                             # optional
      <operator> = { <condition-key> = [<value>, ...] }
    }
  }]
}
```

Rules to keep in mind:

- The document is sent to AWS as-is; the module adds no defaults. **`Effect` is required** in every statement, and `Version = "2012-10-17"` should always be set.
- Each statement sets **exactly one** of `Action`/`NotAction` and **exactly one** of `Resource`/`NotResource`.
- `Action`, `Resource` and condition values may be a single string or a list. Prefer lists for consistency: `Resource = ["*"]`.
- Statements can have different shapes (one with `Condition`, one without) within the same policy or across policies.
- **Do not use `Principal`/`NotPrincipal`.** These are identity-based policies; `Principal` belongs only in resource-based policies such as S3 bucket policies. The module rejects any policy that contains them.
- `custom_policies` are limited to 6,144 characters each (minified JSON); the module checks this at `plan` time.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_name` | Project name, used as a prefix | `string` | - | ✅ |
| `environment` | Environment (dev, stg, prod) | `string` | - | ✅ |
| `role_name` | Role name suffix; full name is `<project_name>-<environment>-<role_name>` | `string` | - | ✅ |
| `trusted_services` | Service principals allowed to assume the role (at least one) | `list(string)` | - | ✅ |
| `description` | Role description | `string` | `null` | |
| `max_session_duration` | Maximum session duration in seconds (3600-43200) | `number` | `3600` | |
| `common_tags` | Common tags for all resources | `map(string)` | `{}` | |
| `managed_policy_arns` | ARNs of existing policies to attach | `list(string)` | `[]` | |
| `custom_policies` | Map of `name suffix => policy object` to create and attach | `any` | `{}` | |
| `inline_policies` | Map of `inline policy name => policy object` embedded in the role | `any` | `{}` | |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the role |
| `role_name` | Name of the role |
| `role_id` | ID of the role |
| `custom_policy_arns` | Map of `key => ARN` for the created custom policies |
| `inline_policy_names` | List of inline policy names |

## Upgrading from `iamrole-v1.0.0`

In `v1.0.0`, policy values were JSON strings. From `v1.0.0` they are HCL objects:

```hcl
# v1.0.0
inline_policies = { s3 = jsonencode({ Statement = [...] }) }

# v1.0.0
inline_policies = { s3 = { Version = "2012-10-17", Statement = [...] } }
```

After changing `ref`, run `terraform init -upgrade` so Terraform downloads the new module version.
