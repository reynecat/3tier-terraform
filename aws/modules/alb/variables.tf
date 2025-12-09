# aws/modules/alb/variables.tf

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public 서브넷 ID 리스트"
  type        = list(string)
}

variable "deletion_protection" {
  description = "삭제 방지 활성화"
  type        = bool
  default     = false
}

variable "enable_https" {
  description = "HTTPS 활성화 여부 (도메인 있을 때)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM 인증서 ARN (HTTPS용)"
  type        = string
  default     = ""
}
