# ============================================================================
# General
# ============================================================================
variable "project_name" {
  description = "Project name, used as a prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment: dev, staging, prod..."
  type        = string
}

variable "include_environment_in_name" {
  description = "Whether to include the environment in resource names"
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "AWS region, used to build the service name of VPC endpoints"
  type        = string
}

variable "vpc_name" {
  description = "Custom VPC name. Leave null to use the generated name"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Networking
# ============================================================================
variable "vpc_cidr_block" {
  description = "VPC CIDR block, e.g. 10.0.0.0/16"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR, e.g. 10.0.0.0/16."
  }
}

variable "availability_zones" {
  description = "List of availability zones; subnets are distributed across them in order"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "At least one availability zone is required."
  }
}

# -----------------------------------------------------------------------------
# Subnet
# -----------------------------------------------------------------------------

# --- Auto-generated CIDR mode -------------------------------------------------
variable "subnet_newbits" {
  description = <<-EOT
    Number of additional bits used when auto-generating subnet CIDRs.
    VPC /16 + 7 = /23 subnets (512 IPs). VPC /16 + 6 = /22 subnets (1024 IPs).
  EOT
  type        = number
  default     = 7
}

variable "subnet_offsets" {
  description = <<-EOT
    Starting position (netnum) of each tier when auto-generating CIDRs.
    By default tiers are 16 apart => each tier reserves room for 16 subnets.
  EOT
  type = object({
    public   = optional(number, 0)
    private  = optional(number, 16)
    database = optional(number, 32)
  })
  default = {}
}

# --- Custom CIDR mode ---------------------------------------------------------
# Leave empty [] => the module generates CIDRs with cidrsubnet.
# Provide a list => that exact list is used; its length must equal the number of AZs.
variable "public_subnet_cidrs" {
  description = "Custom public subnet CIDRs. Leave [] to auto-generate"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every element of public_subnet_cidrs must be a valid CIDR."
  }
  validation {
    condition     = length(var.public_subnet_cidrs) < length(var.availability_zones)
    error_message = "The number of public subnet must be equal or greater than number of availibility zones"
  }
}

variable "map_public_ip_on_launch" {
  description = "Automatically assign a public IP to instances launched in public subnets"
  type        = bool
  default     = false
}


variable "private_subnet_cidrs" {
  description = "Custom private subnet CIDRs. Leave [] to auto-generate"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.private_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every element of private_subnet_cidrs must be a valid CIDR."
  }
}

variable "create_db_subnet" {
  description = "Whether to create database subnets"
  type        = bool
  default     = false
}

variable "database_subnet_cidrs" {
  description = "Custom database subnet CIDRs. Leave [] to auto-generate"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.database_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Every element of database_subnet_cidrs must be a valid CIDR."
  }
}

variable "db_subnet_internet_access" {
  description = "Route database subnets to the Internet Gateway (NOT recommended for production)"
  type        = bool
  default     = false
}


# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------
variable "create_nat_gateway" {
  description = "Whether to create NAT Gateway(s) for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheaper). false = one NAT per AZ (HA)"
  type        = bool
  default     = false
}


# ============================================================================
# VPC Endpoints
# ============================================================================
variable "create_s3_endpoint" {
  description = "Create an S3 Gateway endpoint attached to the private route tables"
  type        = bool
  default     = true
}

variable "interface_endpoints" {
  description = <<-EOT
    List of Interface endpoints to create (the part after "com.amazonaws.<region>.").
    Example: ["ecr.dkr", "ecr.api", "logs", "ssm", "ssmmessages", "ec2messages"]
  EOT
  type        = list(string)
  default     = []
}

