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

variable "node_vm_size" {
  description = "노드 VM 크기"
  type        = string
  default     = "Standard_D2s_v3"
}

# Web 노드풀 설정 (가용영역 1, 2에 분산)
variable "web_node_count" {
  description = "Web 노드풀 노드 수"
  type        = number
  default     = 2
}

variable "web_node_min_count" {
  description = "Web 노드풀 최소 노드 수 (Auto Scaling)"
  type        = number
  default     = 2
}

variable "web_node_max_count" {
  description = "Web 노드풀 최대 노드 수 (Auto Scaling)"
  type        = number
  default     = 5
}

# WAS 노드풀 설정 (가용영역 1, 2에 분산)
variable "was_node_count" {
  description = "WAS 노드풀 노드 수"
  type        = number
  default     = 2
}

variable "was_node_min_count" {
  description = "WAS 노드풀 최소 노드 수 (Auto Scaling)"
  type        = number
  default     = 2
}

variable "was_node_max_count" {
  description = "WAS 노드풀 최대 노드 수 (Auto Scaling)"
  type        = number
  default     = 5
}

# Application Gateway 설정
variable "backend_ip_addresses" {
  description = "Application Gateway Backend IP 주소 리스트"
  type        = list(string)
  default     = ["20.214.124.157"]
}

variable "backend_port" {
  description = "Application Gateway Backend Port"
  type        = number
  default     = 8080
}

variable "health_probe_path" {
  description = "Application Gateway Health Probe Path"
  type        = string
  default     = "/"
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

variable "admin_ip" {
  description = "관리자 IP 주소 (MySQL 접근 허용, 비어있으면 규칙 생성 안함)"
  type        = string
  default     = ""
}
