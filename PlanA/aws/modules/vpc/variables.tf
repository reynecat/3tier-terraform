# aws/modules/vpc/variables.tf

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}

variable "availability_zones" {
  description = "가용 영역 리스트"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public 서브넷 CIDR 리스트"
  type        = list(string)
}

variable "web_subnet_cidrs" {
  description = "Web Tier 서브넷 CIDR 리스트"
  type        = list(string)
}

variable "was_subnet_cidrs" {
  description = "WAS Tier 서브넷 CIDR 리스트"
  type        = list(string)
}

variable "rds_subnet_cidrs" {
  description = "RDS 서브넷 CIDR 리스트"
  type        = list(string)
}
