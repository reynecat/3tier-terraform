# =================================================
# 기본 설정
# =================================================

environment = "prod"
aws_region  = "ap-northeast-2"

# =================================================
# 도메인 설정 (도메인 없이 사용)
# =================================================

enable_custom_domain = false
domain_name          = ""
create_hosted_zone   = false

# =================================================
# VPN 설정 (Azure 연결)
# =================================================

# Azure VPN Gateway Public IP (현재 값 유지)
azure_vpn_gateway_ip = "1.1.1.1"

# Azure VNet CIDR
azure_vnet_cidr = "172.16.0.0/16"

# VPN Shared Key (AWS와 Azure 동일해야 함)
vpn_shared_key = "MySecureVPNKey123456789012345678"

# =================================================
# 데이터베이스 설정
# =================================================

db_name     = "petclinic"
db_username = "admin"
# db_password는 terraform apply 시 입력하거나 환경변수 사용

# =================================================
# VPC 설정
# =================================================

aws_vpc_cidr = "10.0.0.0/16"

aws_availability_zones = [
  "ap-northeast-2a",
  "ap-northeast-2c"
]

public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
web_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/24"]
was_subnet_cidrs    = ["10.0.21.0/24", "10.0.22.0/24"]
rds_subnet_cidrs    = ["10.0.31.0/24", "10.0.32.0/24"]

# =================================================
# EKS 노드 설정
# =================================================

eks_node_instance_type = "t3.small"

# Web Tier
eks_web_desired_size = 2
eks_web_min_size     = 1
eks_web_max_size     = 4

# WAS Tier
eks_was_desired_size = 2
eks_was_min_size     = 1
eks_was_max_size     = 4

# =================================================
# RDS 설정
# =================================================

rds_instance_class        = "db.t3.medium"
rds_allocated_storage     = 100
rds_max_allocated_storage = 200
rds_multi_az              = true
rds_backup_retention      = 7
rds_deletion_protection   = false  # 테스트를 위해 false
rds_skip_final_snapshot   = true   # 테스트를 위해 true

# =================================================
# 비용 관리
# =================================================

budget_alert_email = "reyne7055@gmail.com"


# dms를 위한 변수들

azure_mysql_private_ip  = "172.20.0.10"
azure_mysql_username    = "mysqladmin"
azure_mysql_password    = "MyNewPassword123!" 