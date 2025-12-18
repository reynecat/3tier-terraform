# aws/terraform.tfvars (Plan B - Pilot Light)

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
# Azure 연동 (Blob Storage 백업용)
# =================================================

# Azure Storage Account 정보
azure_storage_account_name = ""  # 실제 값으로 변경
azure_storage_account_key  = "="  # Azure에서 생성 후 입력
azure_backup_container_name = "mysql-backups"

# Azure 인증 정보
azure_tenant_id       = ""
azure_subscription_id = ""

# =================================================
# 백업 인스턴스 설정
# =================================================

enable_backup_instance = true

# SSH 공개 키 (로컬에서 생성: ssh-keygen -t rsa -b 4096)
backup_instance_ssh_public_key = ""

# =================================================
# 데이터베이스 설정
# =================================================

db_name     = "petclinic"
db_username = "admin"
# db_password는 terraform apply 시 입력

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
rds_deletion_protection   = false  # 테스트용
rds_skip_final_snapshot   = true   # 테스트용

# =================================================
# 비용 관리
# =================================================

budget_alert_email = "reyne7055@gmail.com"

# =================================================
# Plan B 배포 가이드
# =================================================

# 1. Azure Storage Account 먼저 생성:
#    cd ../azure
#    terraform apply -target=azurerm_storage_account.backups
#    terraform apply -target=azurerm_storage_container.mysql_backups

# 2. Azure 정보를 이 파일에 입력:
#    - azure_storage_account_name
#    - azure_storage_account_key
#    - azure_tenant_id
#    - azure_subscription_id

# 3. AWS 인프라 배포:
#    cd ../aws
#    terraform init
#    terraform plan
#    terraform apply

# 4. 백업 확인:
#    aws ssm start-session --target <backup-instance-id>
#    sudo tail -f /var/log/mysql-backup-to-azure.log

# 5. Azure에서 백업 확인:
#    az storage blob list \
#      --account-name drbackupsprod1234 \
#      --container-name mysql-backups \
#      --output table
