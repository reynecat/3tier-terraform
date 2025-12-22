# aws/modules/vpc/outputs.tf

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR 블록"
  value       = aws_vpc.main.cidr_block
}

output "private_route_table_id" {
  description = "Private Route table ID"
  value       = aws_route_table.private.id
}

output "public_subnet_ids" {
  description = "Public 서브넷 ID 리스트"
  value       = aws_subnet.public[*].id
}

output "web_subnet_ids" {
  description = "Web Tier 서브넷 ID 리스트"
  value       = aws_subnet.web[*].id
}

output "was_subnet_ids" {
  description = "WAS Tier 서브넷 ID 리스트"
  value       = aws_subnet.was[*].id
}

output "rds_subnet_ids" {
  description = "RDS 서브넷 ID 리스트"
  value       = aws_subnet.rds[*].id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}
