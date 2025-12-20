# aws/route53.tf
# 기존 Route53 Hosted Zone 및 ACM Certificate 사용

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
# Data Sources: 기존 리소스 참조
# =================================================

# 기존 Route53 Hosted Zone 참조
data "aws_route53_zone" "main" {
  count = var.enable_custom_domain ? 1 : 0
  
  name         = var.domain_name
  private_zone = false
}

# 기존 ACM Certificate 참조
data "aws_acm_certificate" "main" {
  count = var.enable_custom_domain ? 1 : 0
  
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Hosted Zone ID
locals {
  hosted_zone_id = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : null
}

# =================================================
# Health Checks
# =================================================

# Primary Health Check: AWS ALB
resource "aws_route53_health_check" "primary" {
  count = var.enable_custom_domain && var.alb_dns_name != "" ? 1 : 0
  
  type              = "HTTPS"
  resource_path     = "/"
  fqdn              = var.alb_dns_name
  port              = 443
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name        = "${var.domain_name}-primary-aws"
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
    Name        = "${var.domain_name}-secondary-azure"
    Environment = var.environment
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
    zone_id                = "Z3W03O7B5YMIYP"  # ap-northeast-2 ELB Hosted Zone ID
    evaluate_target_health = true
  }
  
  failover_routing_policy {
    type = "PRIMARY"
  }
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
# Outputs
# =================================================

output "route53_zone_id" {
  description = "Route 53 Hosted Zone ID"
  value       = try(local.hosted_zone_id, null)
}

output "route53_nameservers" {
  description = "Route 53 Name Servers"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].name_servers : []
}

output "acm_certificate_arn" {
  description = "ACM Certificate ARN"
  value       = var.enable_custom_domain ? data.aws_acm_certificate.main[0].arn : null
}

output "failover_summary" {
  description = "Failover 설정 요약"
  value = var.enable_custom_domain ? {
    domain               = var.domain_name
    hosted_zone_id       = local.hosted_zone_id
    primary_configured   = var.alb_dns_name != ""
    secondary_configured = var.azure_appgw_public_ip != ""
    primary_endpoint     = var.alb_dns_name
    secondary_endpoint   = var.azure_appgw_public_ip
  } : null
}

