# aws/modules/eks/outputs.tf

output "cluster_id" {
  description = "EKS 클러스터 ID"
  value       = aws_eks_cluster.main.id
}

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS 클러스터 엔드포인트"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS 클러스터 CA 데이터"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "EKS 클러스터 보안 그룹 ID"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "web_node_group_id" {
  description = "Web Tier 노드 그룹 ID"
  value       = aws_eks_node_group.web.id
}

output "was_node_group_id" {
  description = "WAS Tier 노드 그룹 ID"
  value       = aws_eks_node_group.was.id
}

output "oidc_provider_url" {
  description = "EKS OIDC Provider URL"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "EKS OIDC Provider ARN"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
