# ============================================================================
# VPC Module - Network Infrastructure
# ============================================================================

locals {
  name_prefix = var.include_environment_in_name ? "${var.project_name}-${var.environment}" : var.project_name

  vpc_name = coalesce(var.vpc_name, "${local.name_prefix}-vpc")

  public_subnet_cidrs = length(var.public_subnet_cidrs) == 0 ? [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, var.subnet_offsets.public + i)] : var.public_subnet_cidrs

  private_subnet_cidrs = length(var.private_subnet_cidrs) == 0 ? [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, var.subnet_offsets.private + i)] : var.private_subnet_cidrs

  database_subnet_cidrs = length(var.database_subnet_cidrs) == 0 ? [for i in range(length(var.availability_zones)) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, var.subnet_offsets.database + i)] : var.database_subnet_cidrs

  nat_count = var.create_nat_gateway ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0

  use_per_az_rt = var.create_nat_gateway && !var.single_nat_gateway

  private_route_table_ids = local.use_per_az_rt ? aws_route_table.per_az[*].id : [aws_route_table.share_rt[0].id]

  private_subnets_by_az = {
    for s in aws_subnet.private_subnet : s.availability_zone => s.id...
  }

  endpoint_subnet_ids = [for az, ids in local.private_subnets_by_az : ids[0]]
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = local.vpc_name
  })
}
# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# -----------------------------------------------------------------------------
# Public Subnet
# -----------------------------------------------------------------------------
resource "aws_subnet" "public_subnet" {
  count                   = length(local.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index % length(var.availability_zones)]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-public-subnet-${count.index + 1}"
  })
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-public-route-table"
  })
}

resource "aws_route_table_association" "public_associate" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------
resource "aws_eip" "eip" {
  count  = local.nat_count
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  })
}

resource "aws_nat_gateway" "nat_gw" {
  count         = local.nat_count
  allocation_id = aws_eip.eip[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-nat-gw-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this]
}

# -----------------------------------------------------------------------------
# Private Subnet
# -----------------------------------------------------------------------------
resource "aws_subnet" "private_subnet" {
  count             = length(local.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-private-subnet-${count.index + 1}"
  })
}

# Shared route table (single NAT or no NAT)
resource "aws_route_table" "share_rt" {
  count  = local.use_per_az_rt ? 0 : 1
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.create_nat_gateway && var.single_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat_gw[0].id
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-private-route-table"
  })
}

# Separate route table for each NAT (multi NAT)
resource "aws_route_table" "per_az" {
  count  = local.use_per_az_rt ? local.nat_count : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[count.index].id
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-private-route-table-${count.index + 1}"
  })
}

resource "aws_route_table_association" "share_private_associate" {
  count          = local.use_per_az_rt ? 0 : length(aws_subnet.private_subnet)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.share_rt[0].id
}

resource "aws_route_table_association" "per_az_private_associate" {
  count          = local.use_per_az_rt ? length(aws_subnet.private_subnet) : 0
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.per_az[count.index % local.nat_count].id
}

# -----------------------------------------------------------------------------
# Database Subnet
# -----------------------------------------------------------------------------
resource "aws_subnet" "db_subnet" {
  count             = var.create_db_subnet ? length(local.database_subnet_cidrs) : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.database_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index % length(var.availability_zones)]

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-database-subnet-${count.index + 1}"
  })
}

resource "aws_route_table" "rds" {
  count  = var.create_db_subnet ? 1 : 0
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.db_subnet_internet_access ? [1] : []
    content {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.this.id
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-database-route-table"
  })
}

resource "aws_route_table_association" "db_associate" {
  count          = var.create_db_subnet ? length(local.database_subnet_cidrs) : 0
  subnet_id      = aws_subnet.db_subnet[count.index].id
  route_table_id = aws_route_table.rds[0].id
}

# -----------------------------------------------------------------------------
# VPC S3 Gateway Endpoint
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  count             = var.create_s3_endpoint ? 1 : 0
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.private_route_table_ids

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-vpc-s3-endpoint"
  })
}

# -----------------------------------------------------------------------------
# VPC Interface Endpoints (ECR, CloudWatch Logs, SSM...)
# -----------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  count       = length(var.interface_endpoints) > 0 ? 1 : 0
  name        = "${local.name_prefix}-vpc-endpoints-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoints)
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.endpoint_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${local.name_prefix}-vpc-${replace(each.value, ".", "-")}-endpoint"
  })
}
