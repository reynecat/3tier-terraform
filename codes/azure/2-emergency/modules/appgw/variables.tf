# Application Gateway Module Variables

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "location" {
  description = "Azure 리전"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group 이름"
  type        = string
}

variable "appgw_subnet_id" {
  description = "Application Gateway Subnet ID"
  type        = string
}

variable "backend_ip_addresses" {
  description = "Backend IP 주소 리스트"
  type        = list(string)
  default     = ["20.214.124.157"]
}

variable "backend_port" {
  description = "Backend Port"
  type        = number
  default     = 8080
}

variable "health_probe_path" {
  description = "Health Probe Path"
  type        = string
  default     = "/"
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
}
