# azure/terraform.tfvars.example

# =================================================
# 기본 설정
# =================================================

environment = "blue"
location    = "koreacentral"

# =================================================
# Storage Account (평상시 항상 실행)
# =================================================

storage_account_name      = "bloberry01"  
backup_container_name     = "mysql-backups"
backup_retention_days     = 30
storage_replication_type  = "LRS"

# =================================================
# Azure 구독 정보 (필수)
# =================================================

subscription_id = "fdc2f63f-a7bc-4ac7-901a-c730f7d317e9"
tenant_id       = "df9bad6f-9a31-4eec-b9fa-f6955eae81bd"

# 확인 명령어: azure shell에서 az account show --query "{subscriptionId:id, tenantId:tenantId}"

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

db_name     = "bluebase02"
db_username = "admin"
db_password = "MySecurePassword123!"  # 8자 이상, 대소문자+숫자+특수문자

# =================================================
# VM 설정 (재해 시 스크립트로 생성)
# =================================================

admin_username = "azureuser"
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDpbPN6AhLJpsRjUOMeixMTVFE7mHNTn7YIfus2TEYUXxsVgutW4Pjbmt7JQzOtP7ZeVPJImb9tDy8mdsVsVX2uDGM7144GM8AeXztzy52atLrZYMRc32n8MAdQXYOCm9c7wISWH7ybacGnL0Bqkj1Yan8N8LS0/0bcPjpkcpIHONg0paU7atOWwVeynod1ius9G55L6dvf7P9pLEhH3AyYmZ2LuAcMzMHOMVf3oTaZ5sCI0E7Le6GIQ94rYoXjume9KGCZ6FoyogTMkPvPm9hr+1lTOhIlx8NHAcNH/adds0SyIu3OyZ8wwBRNOBXcqlFN6vI2v+V1rrnZBf0GhaQLSnPp5WN0xJ4zUebmPLo/sec5vePNmCY9QKxGS+J/FQkq9dF1vyn24A+Ty4nRepLyNkALoerNQrCnh6YpO8CgCviQBIvpsZx6yXwOcE5jcQSNTy5zfPlOAAZotVldYC64sjWSkRT5ie9UwdHlGDSQCQGh/jqLJYeTImrCchkhNt0="

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
