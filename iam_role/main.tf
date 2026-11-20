# ============================================================================
# IAM Role Module
# ============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name                 = "${local.name_prefix}-${var.role_name}"
  description          = var.description
  max_session_duration = var.max_session_duration

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = var.trusted_services
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-${var.role_name}"
  })
}

# -----------------------------------------------------------------------------
# Inline policies (embedded directly in the role)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = jsonencode(each.value)
}

# -----------------------------------------------------------------------------
# Managed policy attachments (AWS managed / pre-existing policies)
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# Custom (customer managed) policies: create, then attach to the role
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "custom" {
  for_each = var.custom_policies

  name        = "${local.name_prefix}-${each.key}"
  description = "Custom policy ${each.key} for role ${local.name_prefix}-${var.role_name}"
  policy      = jsonencode(each.value)

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-${each.key}"
  })
}

resource "aws_iam_role_policy_attachment" "custom" {
  for_each = aws_iam_policy.custom

  role       = aws_iam_role.this.name
  policy_arn = each.value.arn
}




