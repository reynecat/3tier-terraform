# PlanB/azure/3-failover/main.tf
# 재해 시 배포: MySQL + AKS 클러스터 + PocketBank 배포

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

# Subnet 1: Application Gateway 전용 서브넷
data "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

# Subnet 2: Web Pod 서브넷 (AKS Web 노드풀용)
data "azurerm_subnet" "web" {
  name                 = "snet-web"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

# Subnet 3: WAS Pod 서브넷 (AKS WAS 노드풀용)
data "azurerm_subnet" "was" {
  name                 = "snet-was"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

# Subnet 4: DB 서브넷 (MySQL Flexible Server용)
data "azurerm_subnet" "db" {
  name                 = "snet-db"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_storage_account" "backups" {
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

# =================================================
# MySQL Flexible Server (백업 복구용) - Zone Redundant HA
# =================================================

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-dr-${var.environment}"
  location               = data.azurerm_resource_group.main.location
  resource_group_name    = data.azurerm_resource_group.main.name
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
  resource_group_name = data.azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# =================================================
# AKS Cluster - 가용영역 2개 (Zone 1, 2) 사용
# =================================================

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-dr-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  dns_prefix          = "aks-dr-${var.environment}"

  kubernetes_version = var.kubernetes_version

  # Web 노드풀 (default_node_pool) - 가용영역 1, 2에 분산
  default_node_pool {
    name                = "web"
    node_count          = var.web_node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = data.azurerm_subnet.web.id
    zones               = ["1", "2"]
    enable_auto_scaling = true
    min_count           = var.web_node_min_count
    max_count           = var.web_node_max_count

    node_labels = {
      "tier" = "web"
    }

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
# WAS 노드풀 - 가용영역 1, 2에 분산
# =================================================

resource "azurerm_kubernetes_cluster_node_pool" "was" {
  name                  = "was"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size
  node_count            = var.was_node_count
  vnet_subnet_id        = data.azurerm_subnet.was.id
  zones                 = ["1", "2"]
  enable_auto_scaling   = true
  min_count             = var.was_node_min_count
  max_count             = var.was_node_max_count

  node_labels = {
    "tier" = "was"
  }

  upgrade_settings {
    max_surge = "10%"
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
# Application Gateway (Route53 Secondary Endpoint) - Zone Redundant
# =================================================

# Public IP for Application Gateway - Zone Redundant
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2"]

  tags = var.tags
}

# Local variables for App Gateway configuration
locals {
  backend_address_pool_name      = "aks-backend-pool"
  frontend_port_name_http        = "http-port"
  frontend_ip_configuration_name = "appgw-frontend-ip"
  http_setting_name              = "aks-http-settings"
  listener_name                  = "http-listener"
  request_routing_rule_name      = "http-routing-rule"
  probe_name                     = "health-probe"
}

# Application Gateway - Zone Redundant (가용영역 1, 2에 배포)
resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
  zones               = ["1", "2"]

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = data.azurerm_subnet.appgw.id
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

  # Backend Pool - AKS PocketBank LoadBalancer
  backend_address_pool {
    name         = local.backend_address_pool_name
    ip_addresses = ["20.214.124.157"]
  }

  # HTTP Settings - AKS PocketBank용 (HTTP)
  backend_http_settings {
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 8080
    protocol              = "Http"
    request_timeout       = 60
    probe_name            = local.probe_name
  }

  # Health Probe - AKS PocketBank 점검
  probe {
    name                = local.probe_name
    protocol            = "Http"
    path                = "/"
    interval            = 30
    timeout             = 20
    unhealthy_threshold = 3
    host                = "20.214.124.157"
    port                = 8080

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

  # SSL Policy - Use modern TLS version
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  tags = var.tags
}
