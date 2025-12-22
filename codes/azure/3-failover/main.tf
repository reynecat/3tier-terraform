# PlanB/azure/3-failover/main.tf
# 재해 장기화 시: AKS 클러스터 + PetClinic 배포

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
# Data Sources
# =================================================

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  virtual_network_name = var.vnet_name
  resource_group_name  = var.resource_group_name
}

data "azurerm_mysql_flexible_server" "main" {
  name                = var.mysql_server_name
  resource_group_name = var.resource_group_name
}

data "azurerm_public_ip" "appgw" {
  name                = var.appgw_public_ip_name
  resource_group_name = var.resource_group_name
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

# =================================================
# Application Gateway Ingress Controller
# =================================================

resource "azurerm_role_assignment" "appgw_contributor" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "appgw_reader" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}
