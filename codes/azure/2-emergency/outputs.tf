# PlanB/azure/3-failover/outputs.tf

# MySQL Outputs
output "mysql_fqdn" {
  description = "MySQL 서버 FQDN"
  value       = azurerm_mysql_flexible_server.main.fqdn
  sensitive   = true
}

output "mysql_server_name" {
  description = "MySQL 서버 이름"
  value       = azurerm_mysql_flexible_server.main.name
}

output "mysql_database_name" {
  description = "MySQL 데이터베이스 이름"
  value       = azurerm_mysql_flexible_database.main.name
}

# AKS Outputs
output "aks_cluster_name" {
  description = "AKS 클러스터 이름"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "AKS 클러스터 ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_fqdn" {
  description = "AKS FQDN"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "aks_kubeconfig_command" {
  description = "AKS kubeconfig 설정 명령어"
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.main.name}"
}

# Application Gateway Outputs
output "appgw_public_ip" {
  description = "Application Gateway Public IP (Route53 Secondary에 입력)"
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_name" {
  description = "Application Gateway 이름"
  value       = azurerm_application_gateway.main.name
}

output "appgw_id" {
  description = "Application Gateway ID"
  value       = azurerm_application_gateway.main.id
}

output "resource_group_name" {
  description = "Resource Group 이름"
  value       = data.azurerm_resource_group.main.name
}

output "deployment_summary" {
  description = "배포 요약"
  value = <<-EOT

  ========================================
  PlanB Azure 2-failover 배포 완료
  ========================================

  재해 대응: MySQL + AKS + Application Gateway

  MySQL:
    - Server: ${azurerm_mysql_flexible_server.main.name}
    - FQDN: ${azurerm_mysql_flexible_server.main.fqdn}
    - Database: ${azurerm_mysql_flexible_database.main.name}

  AKS 클러스터:
    - Name: ${azurerm_kubernetes_cluster.main.name}
    - Kubernetes: ${var.kubernetes_version}
    - Web Nodes: ${var.web_node_count} (min: ${var.web_node_min_count}, max: ${var.web_node_max_count})
    - WAS Nodes: ${var.was_node_count} (min: ${var.was_node_min_count}, max: ${var.was_node_max_count})
    - VM Size: ${var.node_vm_size}

  Application Gateway:
    - Name: ${azurerm_application_gateway.main.name}
    - Public IP: ${azurerm_public_ip.appgw.ip_address}
    - Backend: Blob Storage (초기)
    - 상태: 점검 페이지 제공 중

  다음 단계:
    1. MySQL 백업 복구
       cd scripts
       ./restore-db.sh

    2. kubectl 설정
       az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.main.name}

    3. PocketBank 배포
       cd scripts
       ./deploy-pocketbank.sh

    4. App Gateway를 AKS로 전환
       cd scripts
       ./update-appgw.sh

    5. Route53 Secondary 업데이트
       App Gateway Public IP를 Route53에 등록:
       ${azurerm_public_ip.appgw.ip_address}

       codes/aws/route53/terraform.tfvars 수정:
       azure_appgw_public_ip = "${azurerm_public_ip.appgw.ip_address}"

       cd ../../../aws/route53
       terraform apply

  트래픽 흐름:
    - 초기: User → App Gateway → Blob Storage (점검 페이지)
    - 전환 후: User → App Gateway → AKS LoadBalancer → Pods

  예상 배포 시간: 15-20분

  ========================================
  EOT
}
