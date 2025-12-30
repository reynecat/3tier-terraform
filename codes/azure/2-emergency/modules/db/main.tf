# MySQL Flexible Server Module

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-dr-${var.environment}"
  location               = var.location
  resource_group_name    = var.resource_group_name
  administrator_login    = var.db_username
  administrator_password = var.db_password

  sku_name = var.mysql_sku
  version  = "8.0.21"

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # Zone 설정 (HA 비활성화 - Burstable edition은 HA 미지원)
  zone = "1"

  storage {
    size_gb = var.mysql_storage_gb
  }

  tags = var.tags
}

resource "azurerm_mysql_flexible_database" "main" {
  name                = var.db_name
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}
