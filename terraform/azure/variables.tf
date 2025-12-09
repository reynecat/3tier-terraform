# terraform/azure/variables.tf

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

variable "admin_username" {
  description = "VM 관리자 사용자명"
  type        = string
  default     = "azureuser"
}

variable "admin_ip" {
  description = "SSH 접속 허용 IP (관리자)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH 공개 키"
  type        = string
}

variable "web_vm_size" {
  description = "Web VM 크기"
  type        = string
  default     = "Standard_B2s"  # 2 vCPU, 4GB RAM
}

variable "was_vm_size" {
  description = "WAS VM 크기"
  type        = string
  default     = "Standard_B2ms" # 2 vCPU, 8GB RAM
}

variable "appgw_capacity" {
  description = "Application Gateway 용량"
  type        = number
  default     = 1
}

variable "mysql_sku" {
  description = "MySQL SKU"
  type        = string
  default     = "B_Standard_B2s"
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "데이터베이스 사용자명"
  type        = string
}

variable "db_password" {
  description = "데이터베이스 비밀번호"
  type        = string
  sensitive   = true
}
