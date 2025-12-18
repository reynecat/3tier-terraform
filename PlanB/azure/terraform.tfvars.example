# azure/terraform.tfvars.example

# =================================================
# 기본 설정
# =================================================

environment = "prod"
location    = "koreacentral"

# =================================================
# Storage Account (평상시 항상 실행)
# =================================================

storage_account_name      = "drbackuppetclinic2024"  # 전역 고유 이름
backup_container_name     = "mysql-backups"
backup_retention_days     = 30
storage_replication_type  = "LRS"

# =================================================
# Azure 구독 정보 (필수)
# =================================================

subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"

# 확인 명령어: az account show --query "{subscriptionId:id, tenantId:tenantId}"

# =================================================
# 네트워크 설정 (재해 시 사용)
# =================================================

vnet_cidr       = "172.16.0.0/16"
web_subnet_cidr = "172.16.11.0/24"
was_subnet_cidr = "172.16.21.0/24"
db_subnet_cidr  = "172.16.31.0/24"

# =================================================
# 데이터베이스 설정 (재해 시 사용)
# =================================================

db_name     = "petclinic"
db_username = "mysqladmin"
db_password = "MySecurePassword123!"  # 8자 이상, 대소문자+숫자+특수문자

# =================================================
# VM 설정 (재해 시 스크립트로 생성)
# =================================================

admin_username = "azureuser"
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E... your-email@example.com"

web_vm_size = "Standard_B2s"   # 2 vCPU, 4GB RAM
was_vm_size = "Standard_B2ms"  # 2 vCPU, 8GB RAM

# =================================================
# MySQL 설정 (재해 시 생성)
# =================================================

mysql_sku        = "B_Standard_B2s"
mysql_storage_gb = 20

# =================================================
# 모니터링
# =================================================

enable_monitoring = true

# =================================================
# 태그
# =================================================

tags = {
  Environment = "Production"
  DRPlan      = "Plan-B-Pilot-Light"
  ManagedBy   = "Terraform"
  Purpose     = "Disaster-Recovery"
  Team        = "AWS2-Team"
  Project     = "KDT-Bespin-Multi-Cloud"
}
