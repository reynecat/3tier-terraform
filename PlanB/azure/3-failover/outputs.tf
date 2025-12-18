# PlanB/azure/3-failover/outputs.tf

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

output "appgw_public_ip" {
  description = "Application Gateway Public IP"
  value       = data.azurerm_public_ip.appgw.ip_address
}

output "mysql_fqdn" {
  description = "MySQL FQDN"
  value       = data.azurerm_mysql_flexible_server.main.fqdn
  sensitive   = true
}

output "deployment_summary" {
  description = "배포 요약"
  value = <<-EOT
  
  ========================================
  PlanB Azure 3-failover 배포 완료
  ========================================
  
  재해 대응 Phase 2: AKS + PetClinic 배포
  
  AKS 클러스터:
    - Name: ${azurerm_kubernetes_cluster.main.name}
    - Kubernetes: ${var.kubernetes_version}
    - Nodes: ${var.node_count} (min: ${var.node_min_count}, max: ${var.node_max_count})
    - VM Size: ${var.node_vm_size}
  
  Application Gateway:
    - Public IP: ${data.azurerm_public_ip.appgw.ip_address}
    - URL: http://${data.azurerm_public_ip.appgw.ip_address}
  
  MySQL:
    - FQDN: ${data.azurerm_mysql_flexible_server.main.fqdn}
  
  다음 단계:
    1. kubectl 설정
       ${self.aks_kubeconfig_command}
    
    2. PetClinic 배포
       cd scripts
       ./deploy-petclinic.sh
    
    3. 서비스 확인
       kubectl get pods -A
       kubectl get svc -A
    
    4. Application Gateway 업데이트 (AKS 연결)
       ./update-appgw.sh
  
  예상 배포 시간: 15-20분
  월 추가 비용: ~$300 (AKS 클러스터)
  
  ========================================
  EOT
}
