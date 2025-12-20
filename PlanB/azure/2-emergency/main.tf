# PlanB/azure/2-emergency/main.tf
# 재해 시 배포: MySQL + Application Gateway (점검 페이지 프록시)

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
# Data Sources (1-always에서 생성된 리소스)
# =================================================

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "db" {
  name                 = "snet-db"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_storage_account" "backups" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

# =================================================
# MySQL Flexible Server (백업 복구용)
# =================================================

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-dr-${var.environment}"
  location               = data.azurerm_resource_group.main.location
  resource_group_name    = data.azurerm_resource_group.main.name
  administrator_login    = var.db_username
  administrator_password = var.db_password
  
  sku_name   = var.mysql_sku
  version    = "8.0.21"
  
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  
  delegated_subnet_id = data.azurerm_subnet.db.id
  
  storage {
    size_gb = var.mysql_storage_gb
  }

  lifecycle {
    ignore_changes = [zone]
  }

  tags = var.tags
}

resource "azurerm_mysql_flexible_database" "main" {
  name                = var.db_name
  resource_group_name = data.azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# =================================================
# Public IP (Application Gateway용)
# =================================================

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# =================================================
# Application Gateway (Blob Storage 점검 페이지 프록시)
# =================================================

locals {
  backend_address_pool_name      = "blob-backend-pool"
  frontend_port_name             = "http-port"
  frontend_ip_configuration_name = "appgw-frontend-ip"
  http_setting_name              = "blob-http-settings"
  listener_name                  = "http-listener"
  request_routing_rule_name      = "routing-rule"
}

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }
  
  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = data.azurerm_subnet.appgw.id
  }
  
  frontend_port {
    name = local.frontend_port_name
    port = 80
  }
  
  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }
  
  # Backend Pool: Blob Storage Static Website
  backend_address_pool {
    name  = local.backend_address_pool_name
    fqdns = ["${var.storage_account_name}.z12.web.core.windows.net"]
  }
  
  
  # HTTP Settings
  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 20
    host_name             = "${var.storage_account_name}.z12.web.core.windows.net"
    
    probe_name = "health-probe"
  }
  
  # Health Probe
  probe {
    name                = "health-probe"
    protocol            = "Https"
    path                = "/"
    host                = "${var.storage_account_name}.z12.web.core.windows.net"
    interval            = 30
    timeout             = 20
    unhealthy_threshold = 3
  }
  
  # HTTP Listener
  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }
  
  # Routing Rule
  request_routing_rule {
    name                       = local.request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
    priority                   = 100
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"  # 최신 정책 사용
  }

  tags = var.tags
}
