# aws/variables.tf
# AWS Primary Site 변수 정의

# =================================================
# 도메인 설정
# =================================================

variable "domain_name" {
  description = "등록된 도메인 이름 (예: example.com). 없으면 빈 문자열"
  type        = string
  default     = ""
}

variable "enable_custom_domain" {
  description = "사용자 지정 도메인 사용 여부 (true: 도메인 있음, false: ALB URL 직접 사용)"
  type        = bool
  default     = false
}

variable "create_hosted_zone" {
  description = "Route 53 Hosted Zone 생성 여부 (도메인이 이미 있으면 false)"
  type        = bool
  default     = false
}

# =================================================
# 기본 설정
# =================================================

variable "environment" {
  description = "환경 이름 (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_availability_zones" {
  description = "AWS 가용 영역 리스트"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "web_subnet_cidrs" {
  description = "Web Tier 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "was_subnet_cidrs" {
  description = "WAS Tier 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "rds_subnet_cidrs" {
  description = "RDS 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.0.31.0/24", "10.0.32.0/24"]
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "데이터베이스 관리자 사용자명"
  type        = string
  default     = "admin"
  sensitive   = true
}

# =================================================
# RDS 설정
# =================================================

variable "rds_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_allocated_storage" {
  description = "RDS 할당 스토리지 (GB)"
  type        = number
  default     = 100
}

variable "rds_max_allocated_storage" {
  description = "RDS 최대 스토리지 (GB)"
  type        = number
  default     = 200
}

variable "rds_multi_az" {
  description = "RDS Multi-AZ 배포 여부"
  type        = bool
  default     = true
}

variable "rds_backup_retention" {
  description = "RDS 백업 보관 기간 (일)"
  type        = number
  default     = 7
}

variable "rds_skip_final_snapshot" {
  description = "RDS 삭제 시 최종 스냅샷 생략 여부"
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "RDS 삭제 방지 활성화"
  type        = bool
  default     = true
}

# =================================================
# EKS 설정
# =================================================

variable "eks_node_instance_type" {
  description = "EKS 노드 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "eks_web_desired_size" {
  description = "EKS Web Tier 원하는 노드 수"
  type        = number
  default     = 2
}

variable "eks_web_min_size" {
  description = "EKS Web Tier 최소 노드 수"
  type        = number
  default     = 1
}

variable "eks_web_max_size" {
  description = "EKS Web Tier 최대 노드 수"
  type        = number
  default     = 4
}

variable "eks_was_desired_size" {
  description = "EKS WAS Tier 원하는 노드 수"
  type        = number
  default     = 2
}

variable "eks_was_min_size" {
  description = "EKS WAS Tier 최소 노드 수"
  type        = number
  default     = 1
}

variable "eks_was_max_size" {
  description = "EKS WAS Tier 최대 노드 수"
  type        = number
  default     = 4
}

# VPN 연결 설정
variable "azure_vpn_gateway_ip" {
  description = "Azure VPN Gateway Public IP"
  type        = string
  # Azure 배포 후 입력 필요
}

variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR (VPN 라우팅용)"
  type        = string
  default     = "172.16.0.0/16"
}

variable "vpn_shared_key" {
  description = "VPN 공유 키 (Pre-Shared Key)"
  type        = string
  sensitive   = true
  # Azure와 동일한 키 사용 (최소 16자 이상)
}

# 비용 관리 설정
variable "budget_alert_email" {
  description = "예산 알림을 받을 이메일 주소"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack Webhook URL (선택사항)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_cost_optimization" {
  description = "비용 최적화 기능 활성화 여부"
  type        = bool
  default     = true
}


# dms를 위한 변수들


variable "azure_mysql_private_ip" {
  description = "Azure MySQL Flexible Server Private IP"
  type        = string
}

variable "azure_mysql_username" {
  description = "Azure MySQL admin username"
  type        = string
  default     = "mysqladmin"
}

variable "azure_mysql_password" {
  description = "Azure MySQL admin password"
  type        = string
  sensitive   = true
}