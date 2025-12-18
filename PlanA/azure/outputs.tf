# azure/outputs.tf
# Azure DR Site 출력 값 (유지보수 모드)

output "resource_group_name" {
  description = "리소스 그룹 이름"
  value       = azurerm_resource_group.main.name
}

output "vnet_id" {
  description = "가상 네트워크 ID"
  value       = azurerm_virtual_network.main.id
}

output "web_vm_public_ip" {
  description = "Web VM 공개 IP (유지보수 페이지)"
  value       = azurerm_public_ip.web.ip_address
}

output "web_vm_private_ip" {
  description = "Web VM 사설 IP"
  value       = azurerm_network_interface.web.private_ip_address
}

output "was_vm_private_ip" {
  description = "WAS VM 사설 IP (유지보수 API)"
  value       = azurerm_network_interface.was.private_ip_address
}

output "mysql_fqdn" {
  description = "MySQL 서버 FQDN (데이터 보존용)"
  value       = azurerm_mysql_flexible_server.main.fqdn
  sensitive   = true
}

output "appgw_public_ip" {
  description = "Application Gateway 공개 IP (유지보수 페이지 접속)"
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
  description = "Azure DR Site 배포 요약 (유지보수 모드)"
  value = <<-EOT
  
  ╔═══════════════════════════════════════════════════════════╗
  ║      Azure DR Site 배포 완료 (유지보수 모드)              ║
  ╚═══════════════════════════════════════════════════════════╝
  
  Region: ${var.location}
  Mode: Warm Standby (유지보수 페이지)
  
  유지보수 페이지 접속:
    - Application Gateway: http://${azurerm_public_ip.appgw.ip_address}
    - Web VM Direct: http://${azurerm_public_ip.web.ip_address}
  
  Virtual Machines:
    - Web VM: ${azurerm_public_ip.web.ip_address} (${azurerm_network_interface.web.private_ip_address})
      역할: 유지보수 페이지 제공 (Nginx)
    
    - WAS VM: ${azurerm_network_interface.was.private_ip_address}
      역할: 유지보수 API 서버 (Flask)
  
  유지보수 API 엔드포인트:
    - GET /api/status - 시스템 상태 확인
    - GET /health - Health Check
  
  Database (데이터 보존):
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
    1. 유지보수 페이지 확인: http://${azurerm_public_ip.appgw.ip_address}
    2. API 상태 확인: http://${azurerm_public_ip.web.ip_address}/api/status
    3. VPN 연결 확인: az network vpn-connection show --name vpn-to-aws-${var.environment} --resource-group ${azurerm_resource_group.main.name}
  
  주요 변경사항:
    - PetClinic 애플리케이션 제거
    - 유지보수 페이지로 대체
    - WAS는 간단한 API 서버로 실행
    - MySQL은 데이터 보존을 위해 유지
  
  EOT
}

output "maintenance_page_url" {
  description = "유지보수 페이지 URL"
  value       = "http://${azurerm_public_ip.appgw.ip_address}"
}

output "maintenance_api_endpoints" {
  description = "유지보수 API 엔드포인트"
  value = {
    status = "http://${azurerm_public_ip.web.ip_address}/api/status"
    health = "http://${azurerm_public_ip.web.ip_address}/health"
  }
}

output "ssh_commands" {
  description = "SSH 접속 명령어"
  value = {
    web = "ssh ${var.admin_username}@${azurerm_public_ip.web.ip_address}"
    was = "ssh ${var.admin_username}@${azurerm_network_interface.was.private_ip_address}"
  }
}
