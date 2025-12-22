# PlanB/azure/3-failover/variables.tf

variable "environment" {
  description = "환경 이름"
  type        = string
  default     = "prod"
}

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

# 1-always에서 생성된 리소스 참조
variable "resource_group_name" {
  description = "Resource Group 이름 (1-always에서 생성)"
  type        = string
  default     = "rg-dr-prod"
}

variable "vnet_name" {
  description = "VNet 이름 (1-always에서 생성)"
  type        = string
  default     = "vnet-dr-prod"
}

variable "storage_account_name" {
  description = "Storage Account 이름 (1-always에서 생성)"
  type        = string
}

# MySQL 설정
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

variable "mysql_sku" {
  description = "MySQL SKU"
  type        = string
  default     = "B_Standard_B2s"
}

variable "mysql_storage_gb" {
  description = "MySQL 스토리지 (GB)"
  type        = number
  default     = 20
}

# AKS 설정
variable "kubernetes_version" {
  description = "Kubernetes 버전"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "AKS 노드 수"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "최소 노드 수 (Auto Scaling)"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "최대 노드 수 (Auto Scaling)"
  type        = number
  default     = 5
}

variable "node_vm_size" {
  description = "노드 VM 크기"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
  default = {
    Environment = "Production"
    DRPlan      = "Plan-B-Pilot-Light"
    Phase       = "Full-Failover"
    ManagedBy   = "Terraform"
  }
}
