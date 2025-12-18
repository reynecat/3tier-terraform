# aws/outputs.tf
# AWS Primary Site 출력 값

# ========== VPC Outputs ==========

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = module.vpc.vpc_cidr
}


# ========== EKS Outputs ==========

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS 클러스터 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS 클러스터 CA 인증서"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# ========== RDS Outputs ==========

output "rds_endpoint" {
  description = "RDS 엔드포인트"
  value       = module.rds.db_instance_endpoint
  sensitive   = true
}

output "rds_address" {
  description = "RDS 주소"
  value       = module.rds.db_instance_address
  sensitive   = true
}

output "rds_database_name" {
  description = "RDS 데이터베이스 이름"
  value       = module.rds.db_name
}

# ========== VPN Outputs ==========

output "vpn_gateway_id" {
  description = "VPN Gateway ID"
  value       = aws_vpn_gateway.main.id
}

output "vpn_connection_id" {
  description = "VPN Connection ID"
  value       = aws_vpn_connection.azure.id
}

output "vpn_connection_tunnel1_address" {
  description = "VPN Tunnel 1 Public IP"
  value       = aws_vpn_connection.azure.tunnel1_address
}

output "vpn_connection_tunnel2_address" {
  description = "VPN Tunnel 2 Public IP"
  value       = aws_vpn_connection.azure.tunnel2_address
}

output "customer_gateway_id" {
  description = "Customer Gateway ID (Azure)"
  value       = aws_customer_gateway.azure.id
}

# ========== EKS 접속 명령어 ==========

output "eks_update_kubeconfig_command" {
  description = "EKS 클러스터 kubeconfig 업데이트 명령어"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}


