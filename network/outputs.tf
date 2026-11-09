output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public_subnet[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private_subnet[*].id
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value       = aws_subnet.db_subnet[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public_route_table.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs currently in use"
  value       = local.private_route_table_ids
}

output "database_route_table_id" {
  description = "ID of the database route table (null if not created)"
  value       = try(aws_route_table.rds[0].id, null)
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.nat_gw[*].id
}

output "nat_public_ips" {
  description = "List of public IPs of the NAT Gateways"
  value       = aws_eip.eip[*].public_ip
}

output "s3_endpoint_id" {
  description = "ID of the S3 Gateway endpoint (null if not created)"
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "interface_endpoint_ids" {
  description = "Map of service name to Interface endpoint ID"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group for Interface endpoints (null if not created)"
  value       = try(aws_security_group.vpc_endpoints[0].id, null)
}
