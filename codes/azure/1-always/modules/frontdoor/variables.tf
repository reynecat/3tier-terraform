variable "environment" {
  description = "Environment name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "aws_alb_fqdn" {
  description = "AWS Application Load Balancer FQDN"
  type        = string
}

variable "azure_blob_fqdn" {
  description = "Azure Blob Storage static website FQDN"
  type        = string
}

variable "azure_appgw_ip" {
  description = "Azure Application Gateway Public IP"
  type        = string
}

variable "custom_domain" {
  description = "Custom domain name (e.g., blueisthenewblack.store)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
