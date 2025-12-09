# ==================== 공통 변수 ====================

variable "environment" {
  description = "환경 이름 (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "multi-cloud-dr"
}

# ==================== AWS 변수 ====================

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"  # 서울 리전
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


variable "db_engine_version" {
  description = "RDS MySQL engine version"
  type        = string
  default     = "8.0.35"
}
# ==================== Azure 변수 ====================

variable "azure_region" {
  description = "Azure 리전"
  type        = string
  default     = "koreacentral"  # 한국 중부
}

variable "azure_vnet_cidr" {
  description = "Azure VNet CIDR 블록"
  type        = string
  default     = "172.16.0.0/16"
}

variable "azure_availability_zones" {
  description = "Azure 가용 영역 리스트"
  type        = list(string)
  default     = ["1", "2"]
}

# ==================== 데이터베이스 변수 ====================

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

variable "db_instance_class" {
  description = "AWS RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.medium"
}

variable "azure_mysql_sku" {
  description = "Azure MySQL SKU"
  type        = string
  default     = "B_Standard_B1ms"  # Burstable 1 vCore
}

# ==================== 애플리케이션 변수 ====================

variable "app_image" {
  description = "애플리케이션 Docker 이미지"
  type        = string
  default     = "springcommunity/spring-petclinic:latest"
}

variable "web_image" {
  description = "웹 서버 Docker 이미지"
  type        = string
  default     = "nginx:latest"
}

variable "app_port" {
  description = "애플리케이션 포트"
  type        = number
  default     = 8080
}

variable "web_port" {
  description = "웹 서버 포트"
  type        = number
  default     = 80
}

# ==================== DNS 변수 ====================

variable "domain_name" {
  description = "Route53에서 관리할 도메인 이름"
  type        = string
  default     = "not-configured.local"
}

# ==================== EKS 변수 ====================

variable "eks_node_instance_type" {
  description = "EKS 노드 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

# Web Tier Node Group
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

# WAS Tier Node Group
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

# ==================== AKS 변수 ====================

variable "aks_node_count" {
  description = "AKS 노드 수 (Warm Standby)"
  type        = number
  default     = 1
}

variable "aks_node_size" {
  description = "AKS 노드 VM 사이즈"
  type        = string
  default     = "Standard_B2s"
}

variable "aks_min_nodes" {
  description = "AKS 최소 노드 수 (Auto Scaling)"
  type        = number
  default     = 1
}

variable "aks_max_nodes" {
  description = "AKS 최대 노드 수 (Auto Scaling)"
  type        = number
  default     = 5
}

# ==================== 모니터링 변수 ====================

variable "enable_cloudwatch" {
  description = "CloudWatch 모니터링 활성화 여부"
  type        = bool
  default     = true
}

variable "alarm_email" {
  description = "알람을 받을 이메일 주소"
  type        = string
  default     = "admin@example.com"
}

# ==================== 백업 변수 ====================

variable "backup_retention_days" {
  description = "백업 보관 기간 (일)"
  type        = number
  default     = 7
}

variable "snapshot_schedule" {
  description = "스냅샷 생성 스케줄 (cron 표현식)"
  type        = string
  default     = "cron(0 2 * * ? *)"  # 매일 오전 2시
}

# ==================== 태그 변수 ====================

variable "tags" {
  description = "모든 리소스에 적용할 공통 태그"
  type        = map(string)
  default = {
    Project     = "Multi-Cloud-DR"
    ManagedBy   = "Terraform"
    Team        = "DevOps"
  }
}
