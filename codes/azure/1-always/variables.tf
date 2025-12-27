# PlanB/azure/1-always/variables.tf

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

variable "storage_replication_type" {
  description = "Storage 복제 타입"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS"], var.storage_replication_type)
    error_message = "유효한 복제 타입: LRS, GRS, RAGRS, ZRS"
  }
}

variable "vnet_cidr" {
  description = "VNet CIDR"
  type        = string
  default     = "172.16.0.0/16"
}

variable "appgw_subnet_cidr" {
  description = "Application Gateway Subnet CIDR"
  type        = string
  default     = "172.16.1.0/24"
}

variable "web_subnet_cidr" {
  description = "Web Pod Subnet CIDR (AKS Web 노드풀용)"
  type        = string
  default     = "172.16.11.0/24"
}

variable "was_subnet_cidr" {
  description = "WAS Pod Subnet CIDR (AKS WAS 노드풀용)"
  type        = string
  default     = "172.16.21.0/24"
}

variable "db_subnet_cidr" {
  description = "DB Subnet CIDR (MySQL Flexible Server용)"
  type        = string
  default     = "172.16.31.0/24"
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

# Route53 관련 변수
variable "aws_region" {
  description = "AWS 리전 (Route53용)"
  type        = string
  default     = "us-east-1"
}

variable "enable_route53" {
  description = "Route53 CNAME 레코드 생성 여부"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Route53 호스팅 존 도메인 이름 (예: example.com)"
  type        = string
  default     = ""
}

variable "subdomain_name" {
  description = "Azure 점검 페이지 서브도메인 (예: maintenance.example.com)"
  type        = string
  default     = ""
}

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
