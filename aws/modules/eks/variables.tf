# aws/modules/eks/variables.tf

variable "environment" {
  description = "환경 이름"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes 버전"
  type        = string
  default     = "1.28"
}

variable "web_subnet_ids" {
  description = "Web Tier 서브넷 ID 리스트"
  type        = list(string)
}

variable "was_subnet_ids" {
  description = "WAS Tier 서브넷 ID 리스트"
  type        = list(string)
}

variable "node_instance_type" {
  description = "노드 인스턴스 타입"
  type        = string
}

variable "web_desired_size" {
  description = "Web Tier 노드 희망 개수"
  type        = number
}

variable "web_min_size" {
  description = "Web Tier 노드 최소 개수"
  type        = number
}

variable "web_max_size" {
  description = "Web Tier 노드 최대 개수"
  type        = number
}

variable "was_desired_size" {
  description = "WAS Tier 노드 희망 개수"
  type        = number
}

variable "was_min_size" {
  description = "WAS Tier 노드 최소 개수"
  type        = number
}

variable "was_max_size" {
  description = "WAS Tier 노드 최대 개수"
  type        = number
}
