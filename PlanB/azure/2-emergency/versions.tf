# PlanB/azure/2-emergency/versions.tf

terraform {
  required_version = ">= 1.14.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
