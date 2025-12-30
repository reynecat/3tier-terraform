# AKS Module Variables

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

variable "resource_group_id" {
  description = "Resource Group ID"
  type        = string
}

variable "vnet_id" {
  description = "VNet ID"
  type        = string
}

variable "web_subnet_id" {
  description = "Web Subnet ID"
  type        = string
}

variable "was_subnet_id" {
  description = "WAS Subnet ID"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes 버전"
  type        = string
}

variable "node_vm_size" {
  description = "노드 VM 크기"
  type        = string
}

# Web 노드풀 설정
variable "web_node_count" {
  description = "Web 노드풀 노드 수"
  type        = number
}

variable "web_node_min_count" {
  description = "Web 노드풀 최소 노드 수"
  type        = number
}

variable "web_node_max_count" {
  description = "Web 노드풀 최대 노드 수"
  type        = number
}

# WAS 노드풀 설정
variable "was_node_count" {
  description = "WAS 노드풀 노드 수"
  type        = number
}

variable "was_node_min_count" {
  description = "WAS 노드풀 최소 노드 수"
  type        = number
}

variable "was_node_max_count" {
  description = "WAS 노드풀 최대 노드 수"
  type        = number
}

variable "tags" {
  description = "리소스 태그"
  type        = map(string)
}
