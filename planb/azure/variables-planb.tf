# azure/variables.tf
# Plan B (Pilot Light) - Azure 변수 정의
# 평상시: Storage Account만 사용
# 재해 시: 스크립트로 VM, MySQL 배포

# =================================================
# 기본 설정
# =================================================

variable "environment" {
  description = "환경 이름"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure 리전"
  type        = string
  default     = "koreacentral"
}

# =================================================
# Storage Account 설정 (평상시 항상 실행)
# =================================================

variable "storage_account_name" {
  description = "Storage Account 이름 (전역 고유, 소문자+숫자, 3-24자)"
  type        = string
  
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage Account 이름은 소문자와 숫자만 사용, 3-24자여야 합니다."
  }
}

variable "backup_container_name" {
  description = "백업 Blob Container 이름"
  type        = string
  default     = "mysql-backups"
}

variable "backup_retention_days" {
  description = "백업 보관 기간 (일)"
  type        = number
  default     = 30
}

# =================================================
# 네트워크 설정 (예약만, 리소스 생성 안 함)
# =================================================

variable "vnet_cidr" {
  description = "VNet CIDR (재해 시 사용)"
  type        = string
  default     = "172.16.0.0/16"
}

variable "web_subnet_cidr" {
  description = "Web Subnet CIDR"
  type        = string
  default     = "172.16.11.0/24"
}

variable "was_subnet_cidr" {
  description = "WAS Subnet CIDR"
  type        = string
  default     = "172.16.21.0/24"
}

variable "db_subnet_cidr" {
  description = "DB Subnet CIDR"
  type        = string
  default     = "172.16.31.0/24"
}

# =================================================
# 데이터베이스 설정 (재해 시 사용)
# =================================================

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "MySQL 관리자 사용자명"
  type        = string
  default     = "mysqladmin"
  sensitive   = true
}

variable "db_password" {
  description = "MySQL 관리자 비밀번호"
  type        = string
  sensitive   = true
}

# =================================================
# VM 설정 (재해 시 스크립트로 생성)
# =================================================

variable "admin_username" {
  description = "VM 관리자 사용자명"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH 공개 키 (재해 시 VM 접속용)"
  type        = string
}

variable "web_vm_size" {
  description = "Web VM 크기 (재해 시 생성)"
  type        = string
  default     = "Standard_B2s"  # 2 vCPU, 4GB RAM
}

variable "was_vm_size" {
  description = "WAS VM 크기 (재해 시 생성)"
  type        = string
  default     = "Standard_B2ms"  # 2 vCPU, 8GB RAM
}

# =================================================
# MySQL 설정 (재해 시 생성)
# =================================================

variable "mysql_sku" {
  description = "MySQL SKU (재해 시 생성)"
  type        = string
  default     = "B_Standard_B2s"  # 2 vCPU, 4GB RAM
}

variable "mysql_storage_gb" {
  description = "MySQL 스토리지 (GB)"
  type        = number
  default     = 20
}

# =================================================
# 태그
# =================================================

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
  default = {
    Environment = "Production"
    DRPlan      = "Plan-B-Pilot-Light"
    ManagedBy   = "Terraform"
    Purpose     = "Disaster-Recovery"
  }
}

# =================================================
# 비용 최적화
# =================================================

variable "enable_monitoring" {
  description = "Azure Monitor 활성화 (Storage만 모니터링)"
  type        = bool
  default     = true
}

variable "storage_replication_type" {
  description = "Storage 복제 타입 (LRS: 로컬, GRS: 지역)"
  type        = string
  default     = "LRS"  # 비용 절감
  
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "유효한 복제 타입: LRS, GRS, RAGRS, ZRS"
  }
}

# =================================================
# Azure 구독 정보
# =================================================

variable "subscription_id" {
  description = "Azure 구독 ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure 테넌트 ID"
  type        = string
  sensitive   = true
}

# =================================================
# 출력 참고
# =================================================

# 이 변수들은 terraform.tfvars에서 값을 설정해야 합니다.
# terraform.tfvars.example 파일을 참고하세요.
