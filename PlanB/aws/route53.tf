# PlanB/aws/route53.tf

# =================================================
# Variables
# =================================================

variable "azure_appgw_public_ip" {
  description = "Azure Application Gateway Public IP (2-emergency 배포 후 입력)"
  type        = string
  default     = ""
}

variable "alb_dns_name" {
  description = "Kubernetes Ingress ALB DNS (kubectl get ingress에서 확인)"
  type        = string
  default     = ""
}

# =================================================
# Data Source: ALB 정보 자동 조회 (선택사항)
# =================================================

# Ingress가 생성한 ALB를 자동으로 찾기
data "aws_lb" "ingress_alb" {
  count = var.enable_custom_domain && var.alb_dns_name != "" ? 1 : 0
  
  tags = {
    "elbv2.k8s.aws/cluster"      = module.eks.cluster_name
    "ingress.k8s.aws/stack"      = "web/web-ingress"
  }
}

# =================================================
# Failover Records
# =================================================

# Primary: AWS Ingress ALB
resource "aws_route53_record" "primary" {
  count = var.enable_custom_domain && var.alb_dns_name != "" ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  
  set_identifier = "Primary-AWS"
  
  alias {
    name                   = var.alb_dns_name
    zone_id                = "Z3W03O7B5YMIYP"  # ap-northeast-2 ELB Zone ID
    evaluate_target_health = true
  }
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary[0].id
  
  depends_on = [module.eks]
}

# Secondary: Azure Application Gateway
resource "aws_route53_record" "secondary" {
  count = var.enable_custom_domain && var.azure_appgw_public_ip != "" ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 60
  
  records = [var.azure_appgw_public_ip]
  
  set_identifier = "Secondary-Azure"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  health_check_id = aws_route53_health_check.secondary[0].id
}

# =================================================
# Health Checks
# =================================================

# Primary Health Check: AWS ALB
resource "aws_route53_health_check" "primary" {
  count = var.enable_custom_domain && var.alb_dns_name != "" ? 1 : 0
  
  type              = "HTTPS"
  resource_path     = "/health"
  fqdn              = var.alb_dns_name
  port              = 443
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name        = "${var.domain_name}-primary-health"
    Environment = var.environment
  }
}

# Secondary Health Check: Azure App Gateway
resource "aws_route53_health_check" "secondary" {
  count = var.enable_custom_domain && var.azure_appgw_public_ip != "" ? 1 : 0
  
  type              = "HTTP"
  ip_address        = var.azure_appgw_public_ip
  port              = 80
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name        = "${var.domain_name}-secondary-health"
    Environment = var.environment
  }
}