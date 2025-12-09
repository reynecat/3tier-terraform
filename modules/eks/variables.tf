# modules/eks/variables.tf

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC cidr block"
  type        = string
}



variable "web_subnets" {
  description = "Web Tier 서브넷 ID 리스트"
  type        = list(string)
}

variable "was_subnets" {
  description = "WAS Tier 서브넷 ID 리스트"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private 서브넷 ID 리스트 (클러스터용)"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB Security Group ID"
  type        = string
}

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "node_instance_type" {
  description = "노드 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

# Web Tier Node Group 설정
variable "web_desired_size" {
  description = "Web Tier 원하는 노드 수"
  type        = number
  default     = 2
}

variable "web_min_size" {
  description = "Web Tier 최소 노드 수"
  type        = number
  default     = 1
}

variable "web_max_size" {
  description = "Web Tier 최대 노드 수"
  type        = number
  default     = 4
}

# WAS Tier Node Group 설정
variable "was_desired_size" {
  description = "WAS Tier 원하는 노드 수"
  type        = number
  default     = 2
}

variable "was_min_size" {
  description = "WAS Tier 최소 노드 수"
  type        = number
  default     = 1
}

variable "was_max_size" {
  description = "WAS Tier 최대 노드 수"
  type        = number
  default     = 4
}

variable "ssh_key_name" {
  description = "SSH Key 이름 (선택적)"
  type        = string
  default     = null
}
