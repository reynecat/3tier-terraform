# PlanB/azure/2-emergency/outputs.tf

output "mysql_fqdn" {
  description = "MySQL 서버 FQDN"
  value       = azurerm_mysql_flexible_server.main.fqdn
  sensitive   = true
}

output "mysql_server_name" {
  description = "MySQL 서버 이름"
  value       = azurerm_mysql_flexible_server.main.name
}

output "appgw_public_ip" {
  description = "Application Gateway 공개 IP (점검 페이지 접속)"
  value       = azurerm_public_ip.appgw.ip_address
}

output "maintenance_page_url" {
  description = "점검 페이지 URL (Application Gateway 경유)"
  value       = "http://${azurerm_public_ip.appgw.ip_address}"
}

output "deployment_summary" {
  description = "배포 요약"
  value = <<-EOT
  
  ========================================
  PlanB Azure 2-emergency 배포 완료
  ========================================
  
  재해 대응 Phase 1: 점검 페이지 + MySQL 복구
  
  점검 페이지:
    - URL: http://${azurerm_public_ip.appgw.ip_address}
    - Application Gateway가 Blob Storage로 프록시
  
  MySQL:
    - Server: ${azurerm_mysql_flexible_server.main.name}
    - FQDN: ${azurerm_mysql_flexible_server.main.fqdn}
    - Database: ${var.db_name}
  
  다음 단계:
    1. 브라우저에서 점검 페이지 확인
    2. MySQL 백업 복구 (./scripts/restore-db.sh)
    3. Route53 업데이트 (도메인 있을 경우)
  
  백업 복구 명령어:
    cd scripts
    ./restore-db.sh
  
  월 추가 비용: ~$50 (MySQL + App Gateway)
  
  ========================================
  EOT
}
