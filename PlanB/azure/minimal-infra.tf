# azure/minimal-infra.tf
# Plan B (Pilot Light) - Azure 최소 인프라
# 평상시: Storage Account만 사용
# 재해 시: 스크립트로 VM, MySQL 배포

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

# =================================================
# Resource Group
# =================================================

resource "azurerm_resource_group" "main" {
  name     = "rg-dr-${var.environment}"
  location = var.location

  tags = var.tags
}

# =================================================
# Virtual Network (예약만, 리소스 생성 안 함)
# =================================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-dr-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.web_subnet_cidr]
}

resource "azurerm_subnet" "was" {
  name                 = "snet-was"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.was_subnet_cidr]
}

resource "azurerm_subnet" "db" {
  name                 = "snet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.db_subnet_cidr]
  
  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# =================================================
# Storage Account (평상시 항상 실행)
# =================================================

resource "azurerm_storage_account" "backups" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  
  blob_properties {
    versioning_enabled = true
  }

  tags = var.tags
}

resource "azurerm_storage_container" "mysql_backups" {
  name                  = var.backup_container_name
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# =================================================
# Lifecycle Management - 30일 후 자동 삭제
# =================================================

resource "azurerm_storage_management_policy" "backup_lifecycle" {
  storage_account_id = azurerm_storage_account.backups.id
  
  rule {
    name    = "deleteOldBackups"
    enabled = true
    
    filters {
      prefix_match = ["${var.backup_container_name}/backups/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention_days
      }
    }
  }
}

# =================================================
# Outputs
# =================================================

output "resource_group_name" {
  description = "Resource Group 이름"
  value       = azurerm_resource_group.main.name
}

output "storage_account_name" {
  description = "Storage Account 이름"
  value       = azurerm_storage_account.backups.name
}

output "storage_account_key" {
  description = "Storage Account Key (민감 정보)"
  value       = azurerm_storage_account.backups.primary_access_key
  sensitive   = true
}

output "blob_container_url" {
  description = "Blob Container URL"
  value       = "https://${azurerm_storage_account.backups.name}.blob.core.windows.net/${var.backup_container_name}"
}

output "vnet_id" {
  description = "VNet ID (재해 시 사용)"
  value       = azurerm_virtual_network.main.id
}

output "web_subnet_id" {
  description = "Web Subnet ID (재해 시 사용)"
  value       = azurerm_subnet.web.id
}

output "was_subnet_id" {
  description = "WAS Subnet ID (재해 시 사용)"
  value       = azurerm_subnet.was.id
}

output "db_subnet_id" {
  description = "DB Subnet ID (재해 시 사용)"
  value       = azurerm_subnet.db.id
}

output "estimated_monthly_cost" {
  description = "예상 월 비용"
  value = "Storage: $10/월 (100GB) + Network: $2/월 = 총 $12/월"
}
