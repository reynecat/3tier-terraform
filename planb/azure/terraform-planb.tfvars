# azure/terraform.tfvars.example

# SSH 키 생성:
#    ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_dr_key
#    cat ~/.ssh/azure_dr_key.pub

# =================================================
# 기본 설정
# =================================================

environment = "prod"
location    = "koreacentral"  # 서울 리전

# =================================================
# Storage Account (평상시 항상 실행)
# =================================================

# Storage Account 이름 (전역 고유, 소문자+숫자, 3-24자)
# 예: drbackup + 조직명 + 난수
storage_account_name = "drbackupsprodptuc"

# Blob Container 이름
backup_container_name = "mysql-backups"

# 백업 보관 기간 (일)
backup_retention_days = 30

# Storage 복제 타입
# - LRS: 로컬 복제 
storage_replication_type = "LRS"

# =================================================
# Azure 구독 정보 (필수)
# =================================================

# Azure 구독 아이디
subscription_id = "fdc2f63f-a7bc-4ac7-901a-c730f7d317e9"

# Azure 테넌트 아이디
tenant_id = "df9bad6f-9a31-4eec-b9fa-f6955eae81bd"

# Azure 구독 확인 명령어
# az account show --query "{subscriptionId:id, tenantId:tenantId}"

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

# 비밀번호 요구사항:
# - 8자 이상
# - 대문자, 소문자, 숫자, 특수문자 포함
db_password = "MyNewPassword123!"

# =================================================
# VM 설정 (재해 시 스크립트로 생성)
# =================================================

admin_username = "azureuser"

# SSH 공개 키 (cat ~/.ssh/azure_dr_key.pub)
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... your-email@example.com"

# VM 크기 (재해 시 생성)
web_vm_size = "Standard_B2s"   # 2 vCPU, 4GB RAM, $60/월
was_vm_size = "Standard_B2ms"  # 2 vCPU, 8GB RAM, $80/월

# =================================================
# MySQL 설정 (재해 시 생성)
# =================================================

mysql_sku        = "B_Standard_B2s"  # 2 vCPU, 4GB RAM, $50/월
mysql_storage_gb = 20                # 20GB, $2/월

# =================================================
# 모니터링 (Storage만 모니터링)
# =================================================

enable_monitoring = true

# =================================================
# 태그 (선택사항)
# =================================================

tags = {
  Environment = "Production"
  DRPlan      = "Plan-B-Pilot-Light"
  ManagedBy   = "Terraform"
  Purpose     = "Disaster-Recovery"
  Team        = "AWS2-Team"
  Project     = "KDT-Bespin-Multi-Cloud"
}

# 1. 이 파일을 terraform.tfvars로 복사
# 2. 모든 값 수정 (특히 subscription_id, tenant_id, ssh_public_key)
# 3. terraform init
# 4. terraform plan (Storage Account만 생성 확인)
# 5. terraform apply
# 6. Storage Account 정보를 AWS terraform.tfvars에 입력
# 7. AWS 백업 인스턴스 배포
