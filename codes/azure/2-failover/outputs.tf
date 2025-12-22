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

output "deployment_summary" {
  description = "배포 요약"
  value = <<-EOT

  ========================================
  PlanB Azure 3-failover 배포 완료
  ========================================

  재해 대응: MySQL + AKS + PetClinic 배포

  MySQL:
    - Server: ${azurerm_mysql_flexible_server.main.name}
    - FQDN: ${azurerm_mysql_flexible_server.main.fqdn}
    - Database: ${azurerm_mysql_flexible_database.main.name}

  AKS 클러스터:
    - Name: ${azurerm_kubernetes_cluster.main.name}
    - Kubernetes: ${var.kubernetes_version}
    - Nodes: ${var.node_count} (min: ${var.node_min_count}, max: ${var.node_max_count})
    - VM Size: ${var.node_vm_size}

  다음 단계:
    1. MySQL 백업 복구
       cd scripts
       ./restore-db.sh

    2. kubectl 설정
       az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.main.name}

    3. PetClinic 배포
       cd scripts
       ./deploy-petclinic.sh

    4. 서비스 확인
       kubectl get pods -A
       kubectl get svc -A

    5. Route53 업데이트 (도메인 있을 경우)
       메인 도메인을 AKS LoadBalancer IP로 업데이트

  예상 배포 시간: 15-20분

  ========================================
  EOT
}
