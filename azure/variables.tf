# azure/variables.tf
# Azure DR Site 변수 정의 (유지보수 모드)

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
  description = "SSH 접속 허용 IP (관리자 IP)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH 공개 키"
  type        = string
}

variable "web_vm_size" {
  description = "Web VM 크기 (유지보수 페이지용)"
  type        = string
  default     = "Standard_B2s"  # 2 vCPU, 4GB RAM
}

variable "was_vm_size" {
  description = "WAS VM 크기 (유지보수 API용, 축소됨)"
  type        = string
  default     = "Standard_B1s"  # 1 vCPU, 1GB RAM (비용 절감)
}

variable "appgw_capacity" {
  description = "Application Gateway 용량"
  type        = number
  default     = 1
}

variable "mysql_sku" {
  description = "MySQL SKU (데이터 보존용, 축소됨)"
  type        = string
  default     = "B_Standard_B1s"  # 최소 사양 (비용 절감)
}

variable "db_name" {
  description = "데이터베이스 이름"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "데이터베이스 사용자명"
  type        = string
  default     = "mysqladmin"
  sensitive   = true
}

variable "db_password" {
  description = "데이터베이스 비밀번호"
  type        = string
  sensitive   = true
}

# VPN 연결 설정
variable "aws_vpn_gateway_ip" {
  description = "AWS VPN Gateway Public IP"
  type        = string
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR (VPN 라우팅용)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpn_shared_key" {
  description = "VPN 공유 키 (Pre-Shared Key)"
  type        = string
  sensitive   = true
}