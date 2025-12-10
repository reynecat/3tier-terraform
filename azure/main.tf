# azure/main.tf
# Azure DR Site - VM 기반 구성 (AKS 제외)

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
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

# ========== Resource Group ==========

resource "azurerm_resource_group" "main" {
  name     = "rg-dr-${var.environment}"
  location = var.location
  
  tags = {
    Environment = var.environment
    Purpose     = "DR-Site"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ========== Virtual Network ==========

resource "azurerm_virtual_network" "main" {
  name                = "vnet-dr-${var.environment}"
  address_space       = ["172.16.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "appgw" {
  name                 = "subnet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["172.16.1.0/24"] 
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

# ========== Network Security Groups ==========

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

# WAS NSG
resource "azurerm_network_security_group" "was" {
  name                = "nsg-was-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  security_rule {
    name                       = "Allow-8080-from-Web"
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

# ========== Public IPs ==========

resource "azurerm_public_ip" "web" {
  name                = "pip-web-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ========== Network Interfaces ==========

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

# ========== Virtual Machines ==========

# Web VM (Nginx)
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
    storage_account_type = "Standard_LRS"
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  
  custom_data = base64encode(templatefile("${path.module}/scripts/web-init.sh", {
    was_ip = azurerm_network_interface.was.private_ip_address
  }))
}

# WAS VM (Spring Boot)
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
    storage_account_type = "Standard_LRS"
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
  
  custom_data = base64encode(templatefile("${path.module}/scripts/was-init.sh", {
    db_host     = azurerm_mysql_flexible_server.main.fqdn
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
  }))
}

# ========== MySQL Flexible Server ==========

resource "random_password" "mysql" {
  length  = 16
  special = true
}

resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-dr-${var.environment}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  administrator_login    = var.db_username
  administrator_password = var.db_password
  
  sku_name   = var.mysql_sku
  version    = "8.0.21"
  
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  
  delegated_subnet_id = azurerm_subnet.db.id
  
  storage {
    size_gb = 20
  }

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_mysql_flexible_database" "main" {
  name                = var.db_name
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# ========== VPN Gateway ==========

# VPN Gateway용 Public IP
resource "azurerm_public_ip" "vpn" {
  name                = "pip-vpn-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  tags = {
    Environment = var.environment
  }
}

# VPN Gateway (Site-to-Site 연결용)
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

# Local Network Gateway (AWS 측 정보)
resource "azurerm_local_network_gateway" "aws" {
  name                = "lng-aws-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  gateway_address     = var.aws_vpn_gateway_ip
  address_space       = [var.aws_vpc_cidr]
  
  tags = {
    Environment = var.environment
  }
}

# VPN Connection (Azure to AWS)
resource "azurerm_virtual_network_gateway_connection" "aws" {
  name                = "vpn-to-aws-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.main.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws.id
  
  shared_key = var.vpn_shared_key
  
  ipsec_policy {
    dh_group         = "DHGroup2"
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS2"
    sa_datasize      = 102400000
    sa_lifetime      = 27000
  }
  
  tags = {
    Environment = var.environment
  }
}

# ========== Application Gateway ==========

resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }
  
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = var.appgw_capacity
  }
  
  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
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
    request_timeout       = 20
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
}

# Application Gateway Backend Pool에 Web VM 추가
resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "web" {
  network_interface_id    = azurerm_network_interface.web.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = tolist(azurerm_application_gateway.main.backend_address_pool).0.id
}
