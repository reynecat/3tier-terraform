# aws/variables.tf
# Plan B (Pilot Light) 전용 변수

# =================================================
# Azure 연동 변수 (Blob Storage)
# =================================================

variable "azure_storage_account_name" {
  description = "Azure Storage Account 이름"
  type        = string
}

variable "azure_storage_account_key" {
  description = "Azure Storage Account Key"
  type        = string
  sensitive   = true
}

variable "azure_backup_container_name" {
  description = "Azure Blob Container 이름 (백업용)"
  type        = string
  default     = "mysql-backups"
}

variable "azure_tenant_id" {
  description = "Azure Tenant ID"
  type        = string
}

variable "azure_subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

# =================================================
# 백업 인스턴스 설정
# =================================================

variable "backup_instance_ssh_public_key" {
  description = "백업 인스턴스 SSH 공개 키"
  type        = string
}

variable "enable_backup_instance" {
  description = "백업 인스턴스 활성화 여부"
  type        = bool
  default     = true
}
