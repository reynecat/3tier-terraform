# aws/route53.tf
# Route 53 DNS 설정 (도메인 있을 때 / 없을 때 모두 지원)

# =================================================
# Route 53 Hosted Zone (도메인 있을 때만 생성)
# =================================================

resource "aws_route53_zone" "main" {
  count = var.enable_custom_domain && var.create_hosted_zone ? 1 : 0
  
  name    = var.domain_name
  comment = "Managed by Terraform for ${var.environment}"
  
  tags = {
    Name        = "${var.domain_name}-zone"
    Environment = var.environment
  }
}

# 기존 Hosted Zone 참조 (도메인은 있지만 Zone은 이미 생성된 경우)
data "aws_route53_zone" "existing" {
  count = var.enable_custom_domain && !var.create_hosted_zone ? 1 : 0
  
  name         = var.domain_name
  private_zone = false
}

# =================================================
# ALB에 대한 DNS A 레코드 (도메인 있을 때)
# =================================================

locals {
  hosted_zone_id = var.enable_custom_domain ? (
    var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  ) : null
}

resource "aws_route53_record" "alb" {
  count = var.enable_custom_domain ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# www 서브도메인도 추가 (선택사항)
resource "aws_route53_record" "www" {
  count = var.enable_custom_domain ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# =================================================
# Health Check (도메인 있을 때만)
# =================================================

resource "aws_route53_health_check" "alb" {
  count = var.enable_custom_domain ? 1 : 0
  
  type              = "HTTPS_STR_MATCH"
  resource_path     = "/actuator/health"
  fqdn              = aws_lb.main.dns_name
  port              = 443
  failure_threshold = 3
  request_interval  = 30
  measure_latency   = true
  search_string     = "UP"
  
  tags = {
    Name = "${var.environment}-alb-health-check"
  }
}

# =================================================
# CloudWatch Alarm for Health Check
# =================================================

resource "aws_cloudwatch_metric_alarm" "health_check" {
  count = var.enable_custom_domain ? 1 : 0
  
  alarm_name          = "${var.environment}-route53-health-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "This metric monitors Route53 health check status"
  
  dimensions = {
    HealthCheckId = var.enable_custom_domain ? aws_route53_health_check.alb[0].id : ""
  }
}

# =================================================
# Outputs
# =================================================

output "route53_nameservers" {
  description = "Route 53 네임서버 (도메인 등록업체에 설정 필요)"
  value = var.enable_custom_domain && var.create_hosted_zone ? (
    aws_route53_zone.main[0].name_servers
  ) : []
}

output "application_url" {
  description = "애플리케이션 접속 URL"
  value = var.enable_custom_domain ? (
    "https://${var.domain_name}"
  ) : (
    "http://${aws_lb.main.dns_name}"
  )
}

output "alb_dns_name" {
  description = "ALB DNS 이름 (도메인 없을 때 직접 사용)"
  value       = aws_lb.main.dns_name
}

# =================================================
# 안내 메시지 출력
# =================================================

output "setup_instructions" {
  description = "도메인 설정 안내"
  value = var.enable_custom_domain ? (
    var.create_hosted_zone ? 
    "✅ Route 53 Hosted Zone이 생성되었습니다.\n아래 네임서버를 도메인 등록업체(가비아, 후이즈 등)에 설정하세요:\n${join("\n", aws_route53_zone.main[0].name_servers)}" :
    "✅ 기존 Hosted Zone을 사용합니다.\nDNS 레코드가 자동으로 생성되었습니다."
  ) : (
    "ℹ️  도메인 없이 ALB URL로 접속합니다.\n접속 주소: http://${aws_lb.main.dns_name}\n\n나중에 도메인을 추가하려면:\n1. terraform.tfvars에서 enable_custom_domain = true\n2. domain_name = \"example.com\" 설정\n3. terraform apply 실행"
  )
}
