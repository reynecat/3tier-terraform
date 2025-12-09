# terraform/azure/main.tf
# Azure DR Site - VM 기반 구성

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
}

# ==================== Resource Group ====================

resource "azurerm_resource_group" "main" {
  name     = "rg-dr-${var.environment}"
  location = var.location
  
  tags = {
    Environment = var.environment
    Purpose     = "DR-Site"
  }
}

# ==================== Virtual Network ====================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-dr-${var.environment}"
  address_space       = ["172.16.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  tags = {
    Environment = var.environment
  }
}

# Gateway Subnet (VPN용)
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.255.0/24"]
}

# Web Subnet
resource "azurerm_subnet" "web" {
  name                 = "subnet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.11.0/24"]
}

# WAS Subnet
resource "azurerm_subnet" "was" {
  name                 = "subnet-was"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.21.0/24"]
}

# DB Subnet
resource "azurerm_subnet" "db" {
  name                 = "subnet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.31.0/24"]
  
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

# ==================== Network Security Groups ====================

# Web NSG
resource "azurerm_network_security_group" "web" {
  name                = "nsg-web-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ip
    destination_address_prefix = "*"
  }
}

# WAS NSG
resource "azurerm_network_security_group" "was" {
  name                = "nsg-was-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "Allow-From-Web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "172.16.11.0/24"
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "Allow-SSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.admin_ip
    destination_address_prefix = "*"
  }
}

# DB NSG
resource "azurerm_network_security_group" "db" {
  name                = "nsg-db-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "Allow-MySQL-From-WAS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "172.16.21.0/24"
    destination_address_prefix = "*"
  }
}

# NSG 연결
resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "was" {
  subnet_id                 = azurerm_subnet.was.id
  network_security_group_id = azurerm_network_security_group.was.id
}

resource "azurerm_subnet_network_security_group_association" "db" {
  subnet_id                 = azurerm_subnet.db.id
  network_security_group_id = azurerm_network_security_group.db.id
}

# ==================== Application Gateway ====================

# Public IP for App Gateway
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = {
    Environment = var.environment
  }
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = var.appgw_capacity
  }
  
  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.web.id
  }
  
  frontend_port {
    name = "http-port"
    port = 80
  }
  
  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }
  
  backend_address_pool {
    name = "web-backend-pool"
  }
  
  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 30
    
    probe_name = "health-probe"
  }
  
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }
  
  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "web-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }
  
  probe {
    name                = "health-probe"
    protocol            = "Http"
    path                = "/health"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    host                = "127.0.0.1"
  }
  
  tags = {
    Environment = var.environment
  }
}

# ==================== Web VM ====================

# Public IP for Web VM (관리용)
resource "azurerm_public_ip" "web" {
  name                = "pip-web-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Interface for Web VM
resource "azurerm_network_interface" "web" {
  name                = "nic-web-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.web.id
  }
}

# Web VM
resource "azurerm_linux_virtual_machine" "web" {
  name                = "vm-web-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.web_vm_size
  admin_username      = var.admin_username
  
  network_interface_ids = [
    azurerm_network_interface.web.id
  ]
  
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 30
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  
  custom_data = base64encode(templatefile("${path.module}/scripts/web-init.sh", {
    was_ip = azurerm_network_interface.was.private_ip_address
  }))
  
  tags = {
    Environment = var.environment
    Tier        = "Web"
  }
}

# ==================== WAS VM ====================

# Network Interface for WAS VM
resource "azurerm_network_interface" "was" {
  name                = "nic-was-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.was.id
    private_ip_address_allocation = "Dynamic"
  }
}

# WAS VM
resource "azurerm_linux_virtual_machine" "was" {
  name                = "vm-was-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.was_vm_size
  admin_username      = var.admin_username
  
  network_interface_ids = [
    azurerm_network_interface.was.id
  ]
  
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 50
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
  
  custom_data = base64encode(templatefile("${path.module}/scripts/was-init.sh", {
    db_host     = azurerm_mysql_flexible_server.main.fqdn
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
  }))
  
  tags = {
    Environment = var.environment
    Tier        = "WAS"
  }
}

# App Gateway에 Web VM 연결
resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "web" {
  network_interface_id    = azurerm_network_interface.web.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = tolist(azurerm_application_gateway.main.backend_address_pool)[0].id
}

# ==================== Azure MySQL ====================

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-dr-${var.environment}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  administrator_login    = var.db_username
  administrator_password = var.db_password
  sku_name               = var.mysql_sku
  version                = "8.0.21"
  
  delegated_subnet_id = azurerm_subnet.db.id
  zone                = "1"
  
  high_availability {
    mode = "ZoneRedundant"
  }
  
  storage {
    size_gb = 20
    iops    = 360
  }
  
  backup_retention_days = 7
  
  tags = {
    Environment = var.environment
  }
}

# MySQL Database
resource "azurerm_mysql_flexible_database" "main" {
  name                = var.db_name
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# ==================== VPN Gateway ====================

# Public IP for VPN Gateway
resource "azurerm_public_ip" "vpn" {
  name                = "pip-vpn-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# VPN Gateway
resource "azurerm_virtual_network_gateway" "main" {
  name                = "vgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  type     = "Vpn"
  vpn_type = "RouteBased"
  
  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1"
  
  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }
  
  tags = {
    Environment = var.environment
  }
}
