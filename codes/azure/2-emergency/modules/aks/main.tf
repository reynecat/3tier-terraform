# AKS Cluster Module

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-dr-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-dr-${var.environment}"

  kubernetes_version = var.kubernetes_version

  # Web 노드풀 (default_node_pool) - 가용영역 1, 2에 분산
  default_node_pool {
    name                = "web"
    node_count          = var.web_node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = var.web_subnet_id
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

# WAS 노드풀 - 가용영역 1, 2에 분산
resource "azurerm_kubernetes_cluster_node_pool" "was" {
  name                  = "was"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size
  node_count            = var.was_node_count
  vnet_subnet_id        = var.was_subnet_id
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

# Role Assignments are automatically created by AKS with SystemAssigned identity
# Removed to avoid conflicts with Azure-managed role assignments
