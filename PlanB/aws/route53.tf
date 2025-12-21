# aws/route53.tf
# Route53 Failover 설정: Primary(AWS) → Secondary(Azure)

variable "azure_appgw_public_ip" {
  description = "Azure Application Gateway Public IP (2-emergency 배포 후 입력)"
  type        = string
  default     = ""
}

# =================================================
# Data Sources: 기존 리소스 참조
# =================================================

data "aws_route53_zone" "main" {
  count = var.enable_custom_domain ? 1 : 0
  
  name         = var.domain_name
  private_zone = false
}

data "aws_acm_certificate" "main" {
  count = var.enable_custom_domain ? 1 : 0
  
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# Ingress가 생성한 ALB 조회 (없으면 skip)
data "aws_lb" "ingress_alb" {
  count = var.enable_custom_domain ? 1 : 0
  
  tags = {
    "elbv2.k8s.aws/cluster"    = module.eks.cluster_name
    "ingress.k8s.aws/stack"    = "web/web-ingress"
    "ingress.k8s.aws/resource" = "LoadBalancer"
  }
  
  depends_on = [module.eks]
}

locals {
  hosted_zone_id = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : null
  # ALB가 있으면 사용, 없으면 null
  alb_dns_name   = var.enable_custom_domain && length(data.aws_lb.ingress_alb) > 0 ? data.aws_lb.ingress_alb[0].dns_name : null
  alb_zone_id    = var.enable_custom_domain && length(data.aws_lb.ingress_alb) > 0 ? data.aws_lb.ingress_alb[0].zone_id : null
}

# =================================================
# Health Checks
# =================================================

# Primary Health Check: AWS ALB (ALB가 있을 때만 생성)
resource "aws_route53_health_check" "primary" {
  count = var.enable_custom_domain && local.alb_dns_name != null ? 1 : 0
  
  type              = "HTTPS"
  resource_path     = "/"
  fqdn              = local.alb_dns_name
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
# Failover Records (ALB가 있을 때만 생성)
# =================================================

# Primary Record: AWS ALB
resource "aws_route53_record" "primary" {
  count = var.enable_custom_domain && local.alb_dns_name != null ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  
  set_identifier = "Primary-AWS-ALB"
  
  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = false
  }
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary[0].id
}

# Secondary Record: Azure App Gateway
resource "aws_route53_record" "secondary" {
  count = var.enable_custom_domain && var.azure_appgw_public_ip != "" ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 60
  
  records = [var.azure_appgw_public_ip]
  
  set_identifier = "Secondary-Azure-AppGW"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  health_check_id = aws_route53_health_check.secondary[0].id
}

# =================================================
# Outputs
# =================================================

output "route53_failover_status" {
  description = "Failover 설정 상태"
  value = var.enable_custom_domain ? {
    primary_enabled   = local.alb_dns_name != null
    primary_alb_dns   = local.alb_dns_name != null ? local.alb_dns_name : "ALB not found - Deploy Ingress first"
    secondary_enabled = var.azure_appgw_public_ip != ""
    domain            = var.domain_name
    secondary_ip      = var.azure_appgw_public_ip != "" ? var.azure_appgw_public_ip : "Not configured"
  } : {
    enabled = false
    message = "Custom domain is disabled"
  }
}

output "route53_health_check_ids" {
  description = "Health Check IDs"
  value = var.enable_custom_domain ? {
    primary   = length(aws_route53_health_check.primary) > 0 ? aws_route53_health_check.primary[0].id : ""
    secondary = length(aws_route53_health_check.secondary) > 0 ? aws_route53_health_check.secondary[0].id : ""
  } : {}
}

output "route53_alb_info" {
  description = "Ingress ALB 정보"
  value = var.enable_custom_domain ? {
    dns_name = local.alb_dns_name != null ? local.alb_dns_name : "ALB not found"
    zone_id  = local.alb_zone_id != null ? local.alb_zone_id : ""
    arn      = length(data.aws_lb.ingress_alb) > 0 ? data.aws_lb.ingress_alb[0].arn : ""
  } : {}
}