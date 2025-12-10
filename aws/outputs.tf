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

# ========== ALB Outputs ==========

output "alb_dns_name" {
  description = "ALB DNS 이름"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = module.alb.alb_zone_id
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

# ========== S3 Outputs ==========

output "backup_s3_bucket" {
  description = "백업용 S3 버킷 이름"
  value       = aws_s3_bucket.backup.id
}

output "backup_s3_arn" {
  description = "백업용 S3 버킷 ARN"
  value       = aws_s3_bucket.backup.arn
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

# ========== 배포 요약 ==========

output "deployment_summary" {
  description = "AWS Primary Site 배포 요약"
  value = <<-EOT
  
  ╔═══════════════════════════════════════════════════════════╗
  ║         AWS Primary Site 배포 완료!                        ║
  ╚═══════════════════════════════════════════════════════════╝
  
  Region: ${var.aws_region}
  
  Network:
    - VPC CIDR: ${module.vpc.vpc_cidr}
  
  Load Balancer:
    - ALB DNS: ${module.alb.alb_dns_name}
    - Access URL: http://${module.alb.alb_dns_name}
  
  EKS Cluster:
    - Name: ${module.eks.cluster_name}
    - Endpoint: ${module.eks.cluster_endpoint}
    - Connect: aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
  
  Database:
    - RDS Endpoint: ${module.rds.db_instance_endpoint}
    - Database: ${module.rds.db_name}
  
  Backup:
    - S3 Bucket: ${aws_s3_bucket.backup.id}
  
  VPN Gateway:
    - VPN Gateway ID: ${aws_vpn_gateway.main.id}
    - Tunnel 1 IP: ${aws_vpn_connection.azure.tunnel1_address}
    - Tunnel 2 IP: ${aws_vpn_connection.azure.tunnel2_address}
    - Connected to: Azure VNet ${var.azure_vnet_cidr}
  
  Next Steps:
    1. EKS 클러스터 접속: aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}
    2. Azure에 VPN IP 입력: ${aws_vpn_connection.azure.tunnel1_address}
    3. Azure 배포: cd ../azure && terraform apply
  
  EOT
}
