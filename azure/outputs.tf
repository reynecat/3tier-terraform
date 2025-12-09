# azure/outputs.tf
# Azure DR Site 출력 값

output "resource_group_name" {
  description = "리소스 그룹 이름"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "가상 네트워크 ID"
  value       = azurerm_virtual_network.main.id
}

output "web_vm_public_ip" {
  description = "Web VM 공개 IP"
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
  description = "MySQL 서버 FQDN"
  value       = azurerm_mysql_flexible_server.main.fqdn
  sensitive   = true
}

output "appgw_public_ip" {
  description = "Application Gateway 공개 IP"
  value       = azurerm_public_ip.appgw.ip_address
}

output "vpn_gateway_public_ip" {
  description = "VPN Gateway 공개 IP"
  value       = azurerm_public_ip.vpn.ip_address
}

output "vpn_gateway_id" {
  description = "VPN Gateway ID"
  value       = azurerm_virtual_network_gateway.main.id
}

output "vpn_connection_status" {
  description = "VPN 연결 상태 확인 명령어"
  value       = "az network vpn-connection show --name vpn-to-aws-${var.environment} --resource-group ${azurerm_resource_group.main.name} --query connectionStatus"
}

output "deployment_summary" {
  description = "Azure DR Site 배포 요약"
  sensitive   = true
  value = <<-EOT
  
  ╔═══════════════════════════════════════════════════════════╗
  ║         Azure DR Site 배포 완료!                           ║
  ╚═══════════════════════════════════════════════════════════╝
  
  Region: ${var.location}
  
  Application Gateway:
    - Public IP: ${azurerm_public_ip.appgw.ip_address}
    - Access URL: http://${azurerm_public_ip.appgw.ip_address}
  
  Virtual Machines:
    - Web VM: ${azurerm_public_ip.web.ip_address} (${azurerm_network_interface.web.private_ip_address})
    - WAS VM: ${azurerm_network_interface.was.private_ip_address}
  
  Database:
    - MySQL: ${azurerm_mysql_flexible_server.main.fqdn}
    - Database: ${var.db_name}
  
  VPN Gateway:
    - Public IP: ${azurerm_public_ip.vpn.ip_address}
    - Status: az network vpn-connection show --name vpn-to-aws-${var.environment} --resource-group ${azurerm_resource_group.main.name}
    - Connected to: AWS VPC ${var.aws_vpc_cidr}
  
  SSH 접속:
    - Web VM: ssh ${var.admin_username}@${azurerm_public_ip.web.ip_address}
    - WAS VM: ssh ${var.admin_username}@${azurerm_network_interface.was.private_ip_address} (via Web VM)
  
  Next Steps:
    1. Web VM 상태 확인: ssh ${var.admin_username}@${azurerm_public_ip.web.ip_address}
    2. WAS VM 상태 확인: systemctl status petclinic
    3. 접속 테스트: http://${azurerm_public_ip.appgw.ip_address}
  
  EOT
}

output "ssh_commands" {
  description = "SSH 접속 명령어"
  value = {
    web = "ssh ${var.admin_username}@${azurerm_public_ip.web.ip_address}"
    was = "ssh ${var.admin_username}@${azurerm_network_interface.was.private_ip_address}"
  }
}
