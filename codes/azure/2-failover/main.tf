# PlanB/azure/3-failover/main.tf
# 재해 시 배포: MySQL + AKS 클러스터 + PetClinic 배포

terraform {
  required_version = ">= 1.14.0"

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

data "azurerm_subnet" "aks" {
  name                 = "snet-aks"
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

  #delegated_subnet_id = data.azurerm_subnet.db.id

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
# AKS Cluster
# =================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-dr-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "aks-dr-${var.environment}"

  kubernetes_version = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = data.azurerm_subnet.aks.id
    enable_auto_scaling = true
    min_count           = var.node_min_count
    max_count           = var.node_max_count

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled = true

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    service_cidr      = "10.240.0.0/16"
    dns_service_ip    = "10.240.0.10"
    load_balancer_sku = "standard"
  }

  tags = var.tags
}

# =================================================
# Role Assignments (AKS → VNet)
# =================================================

resource "azurerm_role_assignment" "aks_network" {
  scope                = data.azurerm_virtual_network.main.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "aks_rg_contributor" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# =================================================
# Application Gateway (Route53 Secondary Endpoint)
# =================================================

# Data Source - Web Subnet for App Gateway
data "azurerm_subnet" "web" {
  name                 = "snet-web"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

# Public IP for Application Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

# Local variables for App Gateway configuration
locals {
  blob_fqdn = "${var.storage_account_name}.z12.web.core.windows.net"

  backend_address_pool_name      = "blob-backend-pool"
  frontend_port_name_http        = "http-port"
  frontend_ip_configuration_name = "appgw-frontend-ip"
  http_setting_name              = "blob-http-settings"
  listener_name                  = "http-listener"
  request_routing_rule_name      = "http-routing-rule"
  probe_name                     = "health-probe"
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = data.azurerm_subnet.web.id
  }

  # Frontend IP Configuration
  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Frontend Port - HTTP
  frontend_port {
    name = local.frontend_port_name_http
    port = 80
  }

  # Backend Pool - 초기에는 Blob Storage를 가리킴
  backend_address_pool {
    name  = local.backend_address_pool_name
    fqdns = [local.blob_fqdn]
  }

  # HTTP Settings - Blob Storage용 (HTTPS)
  backend_http_settings {
    name                                = local.http_setting_name
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true
    probe_name                          = local.probe_name
  }

  # Health Probe - Blob Storage 점검
  probe {
    name                                      = local.probe_name
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 20
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  # HTTP Listener
  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name_http
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

  tags = var.tags

  lifecycle {
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      probe
    ]
  }
}
