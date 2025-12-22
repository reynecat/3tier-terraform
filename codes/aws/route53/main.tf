# aws/route53/main.tf
# Route53 Failover 설정: Primary(AWS ALB) → Secondary(Azure)

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Multi-Cloud-DR"
      ManagedBy   = "Terraform"
      Component   = "Route53-Failover"
    }
  }
}

# =================================================
# Data Sources
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

# ALB 정보를 가져오기 (EKS Ingress가 생성한 ALB)
# alb_dns_name이 비어있을 때만 태그로 검색
data "aws_lb" "ingress_alb" {
  count = var.enable_custom_domain && var.alb_dns_name == "" && var.eks_cluster_name != "" ? 1 : 0

  tags = {
    "elbv2.k8s.aws/cluster" = var.eks_cluster_name
  }
}

# 외부에서 ALB DNS를 직접 입력받는 경우를 위한 locals
locals {
  hosted_zone_id = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : null

  # ALB 정보: data source에서 가져오거나 변수로 직접 입력
  alb_dns_name = var.alb_dns_name != "" ? var.alb_dns_name : (
    length(data.aws_lb.ingress_alb) > 0 ? data.aws_lb.ingress_alb[0].dns_name : null
  )
  alb_zone_id = var.alb_zone_id != "" ? var.alb_zone_id : (
    length(data.aws_lb.ingress_alb) > 0 ? data.aws_lb.ingress_alb[0].zone_id : null
  )
}

# =================================================
# Health Checks
# =================================================

# Primary Health Check: ALB HTTP 체크
resource "aws_route53_health_check" "primary" {
  count = var.enable_custom_domain && local.alb_dns_name != null ? 1 : 0

  type              = "HTTP"
  resource_path     = "/"
  fqdn              = local.alb_dns_name
  port              = 80
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "${var.domain_name}-primary-alb-http"
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
