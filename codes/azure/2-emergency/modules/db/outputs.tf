# DB Module Outputs

output "mysql_server_id" {
  description = "MySQL Server ID"
  value       = azurerm_mysql_flexible_server.main.id
}

output "mysql_server_name" {
  description = "MySQL Server Name"
  value       = azurerm_mysql_flexible_server.main.name
}

output "mysql_server_fqdn" {
  description = "MySQL Server FQDN"
  value       = azurerm_mysql_flexible_server.main.fqdn
}

output "mysql_database_name" {
  description = "MySQL Database Name"
  value       = azurerm_mysql_flexible_database.main.name
}
