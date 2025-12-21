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

locals {
  hosted_zone_id = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : null
}

# =================================================
# Health Checks
# =================================================

# Primary Health Check: AWS ALB
resource "aws_route53_health_check" "primary" {
  count = var.enable_custom_domain ? 1 : 0
  
  type              = "HTTPS"
  resource_path     = "/"
  fqdn              = module.eks.cluster_name != "" ? "k8s-web-webingre-xxxxx.${var.aws_region}.elb.amazonaws.com" : ""
  port              = 443
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name        = "${var.domain_name}-primary-aws"
    Environment = var.environment
  }
  
  # Note: ALB DNS는 Ingress 배포 후 수동으로 업데이트 필요
  lifecycle {
    ignore_changes = [fqdn]
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

# Primary Record: AWS ALB
resource "aws_route53_record" "primary" {
  count = var.enable_custom_domain ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  
  set_identifier = "Primary-AWS-ALB"
  
  # Note: ALB DNS와 Zone ID는 Ingress 배포 후 수동 업데이트 필요
  alias {
    name                   = "k8s-web-webingre-xxxxx.${var.aws_region}.elb.amazonaws.com"
    zone_id                = "ZWKZPGTI48KDX"  # ap-northeast-2 ALB Zone ID
    evaluate_target_health = false
  }
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary[0].id
  
  lifecycle {
    ignore_changes = [alias[0].name, alias[0].zone_id]
  }
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
    primary_enabled   = true
    secondary_enabled = var.azure_appgw_public_ip != ""
    domain            = var.domain_name
    primary_fqdn      = "AWS ALB (Ingress 배포 후 확인)"
    secondary_ip      = var.azure_appgw_public_ip != "" ? var.azure_appgw_public_ip : "Not configured"
  } : {
    enabled = false
    message = "Custom domain is disabled"
  }
}

output "route53_health_check_ids" {
  description = "Health Check IDs"
  value = var.enable_custom_domain ? {
    primary   = try(aws_route53_health_check.primary[0].id, "")
    secondary = try(aws_route53_health_check.secondary[0].id, "")
  } : {}
}
