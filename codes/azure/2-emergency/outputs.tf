# PlanB/azure/2-emergency/outputs.tf

# MySQL Outputs
output "mysql_fqdn" {
  description = "MySQL 서버 FQDN"
  value       = module.db.mysql_server_fqdn
  sensitive   = true
}

output "mysql_server_name" {
  description = "MySQL 서버 이름"
  value       = module.db.mysql_server_name
}

output "mysql_database_name" {
  description = "MySQL 데이터베이스 이름"
  value       = module.db.mysql_database_name
}

# AKS Outputs
output "aks_cluster_name" {
  description = "AKS 클러스터 이름"
  value       = module.aks.aks_cluster_name
}

output "aks_cluster_id" {
  description = "AKS 클러스터 ID"
  value       = module.aks.aks_cluster_id
}

output "aks_fqdn" {
  description = "AKS FQDN"
  value       = module.aks.aks_cluster_fqdn
}

output "aks_kubeconfig_command" {
  description = "AKS kubeconfig 설정 명령어"
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${module.aks.aks_cluster_name}"
}

# Application Gateway Outputs
output "appgw_public_ip" {
  description = "Application Gateway Public IP (CloudFront Origin으로 사용)"
  value       = module.appgw.appgw_public_ip
}

output "appgw_name" {
  description = "Application Gateway 이름"
  value       = module.appgw.appgw_name
}

output "appgw_id" {
  description = "Application Gateway ID"
  value       = module.appgw.appgw_id
}

output "resource_group_name" {
  description = "Resource Group 이름"
  value       = data.azurerm_resource_group.main.name
}

output "deployment_summary" {
  description = "배포 요약"
  value = <<-EOT

  ========================================
  PlanB Azure 2-emergency 배포 완료
  ========================================

  재해 대응: MySQL + AKS + Application Gateway

  MySQL:
    - Server: ${module.db.mysql_server_name}
    - FQDN: ${module.db.mysql_server_fqdn}
    - Database: ${module.db.mysql_database_name}

  AKS 클러스터:
    - Name: ${module.aks.aks_cluster_name}
    - Kubernetes: ${var.kubernetes_version}
    - Web Nodes: ${var.web_node_count} (min: ${var.web_node_min_count}, max: ${var.web_node_max_count})
    - WAS Nodes: ${var.was_node_count} (min: ${var.was_node_min_count}, max: ${var.was_node_max_count})
    - VM Size: ${var.node_vm_size}

  Application Gateway:
    - Name: ${module.appgw.appgw_name}
    - Public IP: ${module.appgw.appgw_public_ip}
    - Backend: ${join(", ", var.backend_ip_addresses)}
    - Backend Port: ${var.backend_port}

  다음 단계:
    1. MySQL 백업 복구
       cd scripts
       ./restore-db.sh

    2. kubectl 설정
       az aks get-credentials --resource-group ${var.resource_group_name} --name ${module.aks.aks_cluster_name}

    3. Kubernetes 리소스 배포
       kubectl apply -f k8s-manifests/namespaces.yaml
       kubectl apply -f k8s-manifests/was/
       kubectl apply -f k8s-manifests/web/

    4. LoadBalancer Service IP 확인 후 AppGW Backend 업데이트
       kubectl get svc -n pocketbank -w
       # LoadBalancer External IP를 확인한 후
       # terraform.tfvars에서 backend_ip_addresses 업데이트
       # terraform apply 재실행

    5. CloudFront Origin 업데이트
       Application Gateway Public IP: ${module.appgw.appgw_public_ip}

  트래픽 흐름:
    User → CloudFront → Application Gateway → AKS LoadBalancer → Pods

  예상 배포 시간: 15-20분

  ========================================
  EOT
}
