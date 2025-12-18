# azure/minimal-infrastructure.tf
# Azure Pilot Light - 최소 인프라 (Storage만)

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# =================================================
# Resource Group
# =================================================

resource "azurerm_resource_group" "main" {
  name     = "rg-dr-${var.environment}"
  location = var.location
  
  tags = {
    Environment = var.environment
    Purpose     = "DR-Pilot-Light"
    Mode        = "Minimal"
    CostCenter  = "DR-Backup"
  }
}

# =================================================
# Virtual Network 
# =================================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-dr-${var.environment}"
  address_space       = ["172.16.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = {
    Environment = var.environment
    Purpose     = "DR-Network-Reserved"
  }
}

# Subnet 예약 (리소스 없음)
resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.11.0/24"]
}

resource "azurerm_subnet" "was" {
  name                 = "subnet-was"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.21.0/24"]
}

resource "azurerm_subnet" "db" {
  name                 = "subnet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.31.0/24"]
  
  # MySQL Flexible Server를 위한 delegation (예비)
  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# =================================================
# Storage Account
# =================================================

resource "azurerm_storage_account" "backups" {
  name                     = "drbackups${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"  # 비용 절감
  
  # 보안 설정
  min_tls_version                = "TLS1_2"
  allow_nested_items_to_be_public = false
  enable_https_traffic_only      = true
  
  # Blob 속성
  blob_properties {
    # 소프트 삭제 (복구 가능)
    delete_retention_policy {
      days = 7
    }
    
    # 버전 관리
    versioning_enabled = true
  }
  
  tags = {
    Environment = var.environment
    Purpose     = "MySQL-Backups"
    Critical    = "Yes"
  }
}

# Random suffix for unique storage account name
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# Blob Container - MySQL Backups
resource "azurerm_storage_container" "mysql_backups" {
  name                  = "mysql-backups"
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# Lifecycle Management - 30일 후 자동 삭제
resource "azurerm_storage_management_policy" "backup_lifecycle" {
  storage_account_id = azurerm_storage_account.backups.id
  
  rule {
    name    = "deleteOldBackups"
    enabled = true
    
    filters {
      prefix_match = ["mysql-backups/backups/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }
  
  rule {
    name    = "archiveOldBackups"
    enabled = true
    
    filters {
      prefix_match = ["mysql-backups/backups/"]
      blob_types   = ["blockBlob"]
    }
    
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 7
        tier_to_archive_after_days_since_modification_greater_than = 14
      }
    }
  }
}

# =================================================
# Storage Account for Emergency Scripts
# =================================================

resource "azurerm_storage_container" "scripts" {
  name                  = "emergency-scripts"
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# Upload emergency deployment scripts
resource "azurerm_storage_blob" "deploy_maintenance" {
  name                   = "deploy-maintenance.sh"
  storage_account_name   = azurerm_storage_account.backups.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/scripts/deploy-maintenance.sh"
}

resource "azurerm_storage_blob" "restore_database" {
  name                   = "restore-database.sh"
  storage_account_name   = azurerm_storage_account.backups.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/scripts/restore-database.sh"
}

resource "azurerm_storage_blob" "deploy_petclinic" {
  name                   = "deploy-petclinic.sh"
  storage_account_name   = azurerm_storage_account.backups.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/scripts/deploy-petclinic.sh"
}

# =================================================
# Azure Monitor (Blob 저장 모니터링)
# =================================================

resource "azurerm_monitor_metric_alert" "no_recent_backup" {
  name                = "no-recent-backup-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_storage_account.backups.id]
  description         = "최근 10분간 백업 없음"
  
  criteria {
    metric_namespace = "Microsoft.Storage/storageAccounts"
    metric_name      = "Transactions"
    aggregation      = "Total"
    operator         = "LessThan"
    threshold        = 1
  }
  
  frequency   = "PT5M"
  window_size = "PT5M"
  severity    = 1
  
  action {
    action_group_id = azurerm_monitor_action_group.dr_alerts.id
  }
}

# Action Group for Alerts
resource "azurerm_monitor_action_group" "dr_alerts" {
  name                = "dr-alerts-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "dr-alert"
  
  email_receiver {
    name          = "admin"
    email_address = var.admin_email
  }
  
  # Slack Webhook (선택사항)
  dynamic "webhook_receiver" {
    for_each = var.slack_webhook_url != "" ? [1] : []
    content {
      name        = "slack"
      service_uri = var.slack_webhook_url
    }
  }
}

# =================================================
# Outputs
# =================================================

output "storage_account_name" {
  description = "Storage Account 이름"
  value       = azurerm_storage_account.backups.name
}

output "storage_account_primary_key" {
  description = "Storage Account Primary Key"
  value       = azurerm_storage_account.backups.primary_access_key
  sensitive   = true
}

output "storage_account_connection_string" {
  description = "Storage Account Connection String"
  value       = azurerm_storage_account.backups.primary_connection_string
  sensitive   = true
}

output "mysql_backups_container_name" {
  description = "MySQL 백업 컨테이너 이름"
  value       = azurerm_storage_container.mysql_backups.name
}

output "resource_group_name" {
  description = "Resource Group 이름"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "Virtual Network ID (예비)"
  value       = azurerm_virtual_network.main.id
}


# =================================================
# Variables
# =================================================


variable "admin_email" {
  description = "관리자 이메일 (알림용)"
  default     = "reyne7055@gmail.com"
  type        = string
}

variable "slack_webhook_url" {
  description = "Slack Webhook URL (선택사항)"
  type        = string
  default     = ""
  sensitive   = true
}
