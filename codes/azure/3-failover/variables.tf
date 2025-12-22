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

# 이전 단계에서 생성된 리소스 참조
variable "resource_group_name" {
  description = "Resource Group 이름"
  type        = string
  default     = "rg-dr-prod"
}

variable "vnet_name" {
  description = "VNet 이름"
  type        = string
  default     = "vnet-dr-prod"
}

variable "mysql_server_name" {
  description = "MySQL 서버 이름 (2-emergency에서 생성)"
  type        = string
  default     = "mysql-dr-prod"
}

variable "appgw_public_ip_name" {
  description = "App Gateway Public IP 이름 (2-emergency에서 생성)"
  type        = string
  default     = "pip-appgw-prod"
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
