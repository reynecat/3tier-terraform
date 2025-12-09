# terraform/azure/outputs.tf

output "resource_group_name" {
  description = "Resource Group 이름"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.main.id
}

output "application_gateway_public_ip" {
  description = "Application Gateway 공개 IP"
  value       = azurerm_public_ip.appgw.ip_address
}

output "web_vm_public_ip" {
  description = "Web VM 공개 IP (관리용)"
  value       = azurerm_public_ip.web.ip_address
}

output "web_vm_private_ip" {
  description = "Web VM 사설 IP"
  value       = azurerm_network_interface.web.private_ip_address
}

output "was_vm_private_ip" {
  description = "WAS VM 사설 IP"
  value       = azurerm_network_interface.was.private_ip_address
}

output "mysql_fqdn" {
  description = "Azure MySQL FQDN"
  value       = azurerm_mysql_flexible_server.main.fqdn
}

output "vpn_gateway_public_ip" {
  description = "VPN Gateway 공개 IP"
  value       = azurerm_public_ip.vpn.ip_address
}

output "dr_site_url" {
  description = "DR Site 접속 URL"
  value       = "http://${azurerm_public_ip.appgw.ip_address}"
}

output "connection_info" {
  description = "연결 정보"
  value = {
    web_ssh  = "ssh ${var.admin_username}@${azurerm_public_ip.web.ip_address}"
    was_ssh  = "ssh ${var.admin_username}@${azurerm_network_interface.was.private_ip_address} (Web VM 경유)"
    app_url  = "http://${azurerm_public_ip.appgw.ip_address}"
    mysql    = azurerm_mysql_flexible_server.main.fqdn
  }
}
