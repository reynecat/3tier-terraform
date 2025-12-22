# aws/route53/variables.tf

# =================================================
# 기본 설정
# =================================================

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "환경 (dev/staging/prod)"
  type        = string
  default     = "blue"
}

# =================================================
# Route53 & Custom Domain
# =================================================

variable "enable_custom_domain" {
  description = "커스텀 도메인 활성화"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "도메인 이름 (예: example.com)"
  type        = string
}

# =================================================
# AWS Primary Site (EKS ALB)
# =================================================

variable "eks_cluster_name" {
  description = "EKS 클러스터 이름 (ALB 자동 검색용)"
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "AWS ALB DNS 이름 (aws/service 배포 후 입력)"
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "AWS ALB Hosted Zone ID (aws/service 배포 후 입력)"
  type        = string
  default     = ""
}

# =================================================
# Azure Secondary Site (Application Gateway)
# =================================================

variable "azure_appgw_public_ip" {
  description = "Azure Application Gateway Public IP (azure/2-failover 배포 후 입력)"
  type        = string
  default     = ""
}
