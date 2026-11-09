# AWS Network (VPC) Terraform Module

Terraform module that creates a complete VPC network on AWS:

- VPC with DNS support and DNS hostnames enabled
- Internet Gateway
- Public, private and (optional) database subnets spread across the given availability zones
- NAT Gateway: none, one shared, or one per AZ
- Route tables and associations for every tier
- S3 Gateway endpoint (optional, free)
- Interface endpoints such as ECR, CloudWatch Logs and SSM (optional), with their own security group

Subnet CIDRs can be generated automatically from the VPC CIDR or passed in explicitly.

## Usage

### Minimal

```hcl
module "network" {
  source  = "<namespace>/network/aws"
  version = "~> 1.0"

  project_name = "myapp"
  environment  = "dev"
  aws_region   = "eu-west-1"

  vpc_cidr_block     = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b"]
}
```

This creates a VPC with one public and one private subnet per AZ (CIDRs generated automatically), **one NAT Gateway per AZ** and an S3 Gateway endpoint.

### Dev / staging: single NAT Gateway

```hcl
module "network" {
  source  = "<namespace>/network/aws"
  version = "~> 1.0"

  project_name = "myapp"
  environment  = "staging"
  aws_region   = "eu-west-1"

  vpc_cidr_block     = "10.10.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b"]

  single_nat_gateway = true

  common_tags = {
    Project     = "myapp"
    Environment = "staging"
    ManagedBy   = "terraform"
  }
}
```

### Production: NAT per AZ, database subnets and interface endpoints

```hcl
module "network" {
  source  = "<namespace>/network/aws"
  version = "~> 1.0"

  project_name = "myapp"
  environment  = "prod"
  aws_region   = "eu-west-1"

  vpc_cidr_block     = "10.20.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  create_nat_gateway = true
  single_nat_gateway = false

  create_db_subnet = true

  create_s3_endpoint  = true
  interface_endpoints = ["ecr.dkr", "ecr.api", "logs", "ssmmessages"]
}
```

### Custom subnet CIDRs

```hcl
module "network" {
  source  = "<namespace>/network/aws"
  version = "~> 1.0"

  project_name = "myapp"
  environment  = "dev"
  aws_region   = "eu-west-1"

  vpc_cidr_block     = "172.18.0.0/20"
  availability_zones = ["eu-west-1a", "eu-west-1c"]

  public_subnet_cidrs   = ["172.18.0.0/24", "172.18.1.0/24"]
  private_subnet_cidrs  = ["172.18.2.0/24", "172.18.3.0/24"]
  create_db_subnet      = true
  database_subnet_cidrs = ["172.18.4.0/24", "172.18.5.0/24"]

  create_nat_gateway = false
}
```

## Subnet CIDRs

Each tier (public, private, database) works independently:

- **List left empty (`[]`, the default):** the module generates one subnet per AZ with `cidrsubnet(vpc_cidr_block, subnet_newbits, offset + index)`.
- **List provided:** that exact list is used. Provide one CIDR per AZ, in the same order as `availability_zones`.

With the defaults (`subnet_newbits = 7`, offsets `0 / 16 / 32`), a `/16` VPC is split into `/23` subnets (512 IPs each). Each tier reserves room for 16 subnets:

| Tier     | Offset | AZ 1          | AZ 2          | AZ 3          |
|----------|--------|---------------|---------------|---------------|
| Public   | 0      | 10.0.0.0/23   | 10.0.2.0/23   | 10.0.4.0/23   |
| Private  | 16     | 10.0.32.0/23  | 10.0.34.0/23  | 10.0.36.0/23  |
| Database | 32     | 10.0.64.0/23  | 10.0.66.0/23  | 10.0.68.0/23  |

For a smaller VPC, lower `subnet_newbits` so that the subnets still fit. For example, with a `/20` VPC, `subnet_newbits = 4` gives `/24` subnets, and you may also want to lower `subnet_offsets`.

## NAT Gateway modes

| `create_nat_gateway` | `single_nat_gateway` | NAT Gateways | Private route tables                       | Use case                         |
|----------------------|----------------------|--------------|--------------------------------------------|----------------------------------|
| `false`              | any                  | 0            | 1 shared, no internet route                | No outbound internet needed, or tasks run in public subnets |
| `true`               | `true`               | 1            | 1 shared, `0.0.0.0/0` → the NAT            | Dev / staging, lower cost        |
| `true`               | `false` (default)    | 1 per AZ     | 1 per AZ, each to the NAT in its own AZ    | Production, survives an AZ outage |

NAT Gateways are billed per hour and per GB processed. One NAT per AZ costs more but keeps outbound traffic working if an AZ goes down.

## Database subnets

When `create_db_subnet = true`, the module creates one database subnet per AZ and a dedicated route table.

- By default the database route table has **no internet route**.
- `db_subnet_internet_access = true` adds a route to the Internet Gateway. This is only needed when the database must be publicly reachable (for example `publicly_accessible = true` on RDS). It is **not recommended for production**.

## VPC endpoints

- **S3 Gateway endpoint** (`create_s3_endpoint`, default `true`): free, and attached to the private route tables. Lets private subnets reach S3 without going through a NAT Gateway.
- **Interface endpoints** (`interface_endpoints`): each name is the part after `com.amazonaws.<region>.`, for example `ecr.dkr`. The module places them in one private subnet per AZ, enables private DNS, and creates a security group that allows HTTPS (443) from the VPC CIDR. Interface endpoints are billed per hour per AZ.

For ECS Fargate in private subnets without a NAT Gateway, the usual set is:

```hcl
interface_endpoints = ["ecr.dkr", "ecr.api", "logs"]  # plus "ssmmessages" for ECS Exec
```

together with `create_s3_endpoint = true`, because ECR stores image layers in S3.

## Resource naming

Names are built from a prefix:

- `include_environment_in_name = true` (default): `<project_name>-<environment>`, for example `myapp-prod`
- `include_environment_in_name = false`: `<project_name>`

| Resource                   | Name                                          |
|----------------------------|-----------------------------------------------|
| VPC                        | `<prefix>-vpc` (or `vpc_name` if set)         |
| Internet Gateway           | `<prefix>-igw`                                |
| Subnets                    | `<prefix>-public-subnet-1`, `<prefix>-private-subnet-1`, `<prefix>-database-subnet-1`, ... |
| NAT Gateway / Elastic IP   | `<prefix>-nat-gw-1`, `<prefix>-nat-eip-1`, ... |
| Route tables               | `<prefix>-public-route-table`, `<prefix>-private-route-table[-N]`, `<prefix>-database-route-table` |
| Endpoints                  | `<prefix>-vpc-s3-endpoint`, `<prefix>-vpc-ecr-dkr-endpoint`, ... |

`common_tags` is merged into the tags of every resource.

## Requirements

| Name      | Version  |
|-----------|----------|
| terraform | >= 1.5.0 |
| aws       | >= 5.0   |

## Inputs

### General

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `project_name` | Project name, used as a prefix for resource names | `string` | n/a | yes |
| `environment` | Environment: dev, staging, prod... | `string` | n/a | yes |
| `aws_region` | AWS region, used to build the service name of VPC endpoints | `string` | n/a | yes |
| `include_environment_in_name` | Whether to include the environment in resource names | `bool` | `true` | no |
| `vpc_name` | Custom VPC name. Leave `null` to use the generated name | `string` | `null` | no |
| `common_tags` | Common tags applied to all resources | `map(string)` | `{}` | no |

### Networking

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vpc_cidr_block` | VPC CIDR block, e.g. `10.0.0.0/16` | `string` | n/a | yes |
| `availability_zones` | Availability zones; subnets are distributed across them in order | `list(string)` | n/a | yes |
| `subnet_newbits` | Additional bits used when auto-generating subnet CIDRs | `number` | `7` | no |
| `subnet_offsets` | Starting netnum of each tier when auto-generating CIDRs | `object({ public = optional(number, 0), private = optional(number, 16), database = optional(number, 32) })` | `{}` | no |
| `public_subnet_cidrs` | Custom public subnet CIDRs. Leave `[]` to auto-generate | `list(string)` | `[]` | no |
| `private_subnet_cidrs` | Custom private subnet CIDRs. Leave `[]` to auto-generate | `list(string)` | `[]` | no |
| `map_public_ip_on_launch` | Automatically assign a public IP to instances launched in public subnets | `bool` | `false` | no |
| `create_db_subnet` | Whether to create database subnets | `bool` | `false` | no |
| `database_subnet_cidrs` | Custom database subnet CIDRs. Leave `[]` to auto-generate | `list(string)` | `[]` | no |
| `db_subnet_internet_access` | Route database subnets to the Internet Gateway (not recommended for production) | `bool` | `false` | no |

### NAT Gateway

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `create_nat_gateway` | Whether to create NAT Gateway(s) for private subnets | `bool` | `true` | no |
| `single_nat_gateway` | `true` = one shared NAT (cheaper), `false` = one NAT per AZ (HA) | `bool` | `false` | no |

### VPC Endpoints

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `create_s3_endpoint` | Create an S3 Gateway endpoint attached to the private route tables | `bool` | `true` | no |
| `interface_endpoints` | Interface endpoints to create (the part after `com.amazonaws.<region>.`) | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `internet_gateway_id` | ID of the Internet Gateway |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `database_subnet_ids` | List of database subnet IDs (empty if not created) |
| `public_route_table_id` | ID of the public route table |
| `private_route_table_ids` | List of private route table IDs currently in use |
| `database_route_table_id` | ID of the database route table (`null` if not created) |
| `nat_gateway_ids` | List of NAT Gateway IDs |
| `nat_public_ips` | List of public IPs of the NAT Gateways |
| `s3_endpoint_id` | ID of the S3 Gateway endpoint (`null` if not created) |
| `interface_endpoint_ids` | Map of service name to Interface endpoint ID |
| `vpc_endpoints_security_group_id` | ID of the security group for Interface endpoints (`null` if not created) |

## Notes

- Private subnets are always created, one per AZ (or one per entry in `private_subnet_cidrs`).
- Changing `availability_zones` or the subnet CIDRs of an existing VPC replaces the affected subnets, and everything running in them.
- Each AWS account has a default quota of 5 VPCs per region. Request an increase in Service Quotas if `CreateVpc` fails with `VpcLimitExceeded`.
