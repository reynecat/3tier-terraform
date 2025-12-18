# PlanB/azure/1-always/versions.tf
# Terraform 버전 및 Provider 버전 고정

terraform {
  required_version = ">= 1.14.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
