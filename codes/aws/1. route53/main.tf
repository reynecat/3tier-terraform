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

# CloudFront requires ACM certificates in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

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

  provider    = aws.us_east_1
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
# CloudFront Distribution (Origin Failover)
# =================================================

# CloudFront with Origin Failover
# Primary Origin: AWS ALB
# Secondary Origin: Azure Blob Storage → App Gateway (장애 장기화 시)

resource "aws_cloudfront_distribution" "main" {
  count = var.enable_custom_domain && local.alb_dns_name != null ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Multi-Cloud DR with Origin Failover"
  default_root_object = ""
  aliases             = [var.domain_name]

  # Origin Group - Automatic Failover
  origin_group {
    origin_id = "multi-cloud-failover-group"

    failover_criteria {
      status_codes = [500, 502, 503, 504]
    }

    member {
      origin_id = "primary-aws-alb"
    }

    member {
      origin_id = "secondary-azure"
    }
  }

  # Primary Origin: AWS ALB
  origin {
    domain_name = local.alb_dns_name
    origin_id   = "primary-aws-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name
    }
  }

  # Secondary Origin: Azure Blob Storage (초기) / App Gateway (장애 장기화)
  # lifecycle ignore_changes로 수동 변경 가능
  origin {
    domain_name = "${var.azure_storage_account_name}.z12.web.core.windows.net"
    origin_id   = "secondary-azure"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = var.domain_name
    }
  }

  # Default Cache Behavior - Origin Group 사용
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "multi-cloud-failover-group"

    forwarded_values {
      query_string = true
      headers      = ["Host", "CloudFront-Forwarded-Proto", "Origin"]

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Price Class
  price_class = "PriceClass_100"

  # Geo Restriction
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL Certificate (ACM)
  viewer_certificate {
    cloudfront_default_certificate = length(data.aws_acm_certificate.main) > 0 ? false : true
    acm_certificate_arn            = length(data.aws_acm_certificate.main) > 0 ? data.aws_acm_certificate.main[0].arn : null
    ssl_support_method             = length(data.aws_acm_certificate.main) > 0 ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.domain_name}-cloudfront-dr"
    Environment = var.environment
    Purpose     = "Multi-Cloud-DR-Failover"
  }

  lifecycle {
    ignore_changes = [
      origin
    ]
  }
}

# =================================================
# Route53 Health Checks
# =================================================

# Health Check for AWS ALB (Direct)
resource "aws_route53_health_check" "aws_alb" {
  count = var.enable_custom_domain && local.alb_dns_name != null ? 1 : 0

  fqdn              = local.alb_dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30
  measure_latency   = true

  tags = {
    Name        = "${var.environment}-aws-alb-health-check"
    Environment = var.environment
    Purpose     = "AWS-ALB-Direct-Monitoring"
  }
}

# Health Check for CloudFront (End-to-End)
resource "aws_route53_health_check" "cloudfront" {
  count = var.enable_custom_domain && var.domain_name != "" ? 1 : 0

  fqdn              = var.domain_name
  port              = 443
  type              = "HTTPS_STR_MATCH"
  resource_path     = "/"
  search_string     = var.health_check_search_string
  failure_threshold = 3
  request_interval  = 30
  measure_latency   = true
  enable_sni        = true

  tags = {
    Name        = "${var.environment}-cloudfront-health-check"
    Environment = var.environment
    Purpose     = "CloudFront-End-to-End-Monitoring"
  }
}

# Health Check for Azure Blob Storage (Secondary)
resource "aws_route53_health_check" "azure_blob" {
  count = var.enable_custom_domain && var.azure_storage_account_name != "" ? 1 : 0

  fqdn              = "${var.azure_storage_account_name}.z12.web.core.windows.net"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30
  measure_latency   = true
  enable_sni        = true

  tags = {
    Name        = "${var.environment}-azure-blob-health-check"
    Environment = var.environment
    Purpose     = "Azure-Blob-Storage-Monitoring"
  }
}

# =================================================
# Route53 Record - CloudFront Alias
# =================================================

# Route53 A Record pointing to CloudFront
resource "aws_route53_record" "main" {
  count = var.enable_custom_domain && local.alb_dns_name != null ? 1 : 0

  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main[0].domain_name
    zone_id                = aws_cloudfront_distribution.main[0].hosted_zone_id
    evaluate_target_health = false
  }
}
