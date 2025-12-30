# Application Gateway Module Outputs

output "appgw_id" {
  description = "Application Gateway ID"
  value       = azurerm_application_gateway.main.id
}

output "appgw_name" {
  description = "Application Gateway Name"
  value       = azurerm_application_gateway.main.name
}

output "appgw_public_ip" {
  description = "Application Gateway Public IP"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_public_ip_id" {
  description = "Application Gateway Public IP ID"
  value       = azurerm_public_ip.appgw.id
}
