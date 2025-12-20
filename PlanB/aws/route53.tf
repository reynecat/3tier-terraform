# aws/route53.tf
# Route 53 DNS 설정 - Ingress ALB 지원

# =================================================
# ACM 인증서 (HTTPS용, 도메인 있을 때만)
# =================================================

resource "aws_acm_certificate" "main" {
  count = var.enable_custom_domain ? 1 : 0
  
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
  
  lifecycle {
    create_before_destroy = true
  }
  
  tags = {
    Name        = "${var.domain_name}-certificate"
    Environment = var.environment
  }
}

# =================================================
# Route 53 Hosted Zone
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

# 기존 Hosted Zone 참조
data "aws_route53_zone" "existing" {
  count = var.enable_custom_domain && !var.create_hosted_zone ? 1 : 0
  
  name         = var.domain_name
  private_zone = false
}

locals {
  hosted_zone_id = var.enable_custom_domain ? (
    var.create_hosted_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  ) : null
}

# DNS 검증 레코드 생성
resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_custom_domain ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
  
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.hosted_zone_id
}

# 인증서 검증 대기
resource "aws_acm_certificate_validation" "main" {
  count = var.enable_custom_domain ? 1 : 0
  
  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


# =================================================
# Outputs
# =================================================


output "setup_instructions" {
  description = "DNS 설정 안내"
  value = var.enable_custom_domain ? (
    var.create_hosted_zone ? 
    <<-EOT
    ✅ Route 53 Hosted Zone이 생성되었습니다.
    
    1. 도메인 등록업체에서 네임서버를 다음으로 변경하세요:
    ${join("\n    ", aws_route53_zone.main[0].name_servers)}
    
    2. Kubernetes Ingress ALB가 생성되면:
       - ALB DNS: k8s-xxx-xxx.elb.amazonaws.com
       - Route 53에 CNAME 레코드 추가:
         * 이름: ${var.domain_name}
         * 타입: CNAME
         * 값: [Ingress ALB DNS]
    
    3. 또는 external-dns를 사용하여 자동화:
       helm install external-dns ...
    EOT
    :
    <<-EOT
    ✅ 기존 Hosted Zone을 사용합니다.
    
    Kubernetes Ingress ALB 생성 후:
    1. ALB DNS 확인: kubectl get ingress -n web
    2. Route 53에 CNAME 레코드 추가
    EOT
  ) : (
    <<-EOT

    
    현재 접속 방법:
    - Kubernetes Ingress ALB DNS로 직접 접속
    - kubectl get ingress -n web 명령어로 확인
    
    EOT
  )
}

# aws/route53.tf에 추가

# =================================================
# Failover 설정: Azure Application Gateway (Secondary)
# =================================================

# Azure App Gateway Public IP를 변수로 받음
variable "azure_appgw_public_ip" {
  description = "Azure Application Gateway Public IP (2-emergency 배포 후 입력)"
  type        = string
  default     = ""
}

# Primary: AWS Ingress ALB (현재 활성)
resource "aws_route53_record" "primary" {
  count = var.enable_custom_domain ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  
  set_identifier = "Primary-AWS"
  
  # Ingress ALB는 kubectl로 확인 후 수동으로 입력하거나 external-dns 사용
  # 임시로 더미 값 사용
  ttl     = 60
  records = ["0.0.0.0"]  # 실제 Ingress ALB IP로 교체 필요
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary[0].id
}

# Secondary: Azure Application Gateway (재해 시 활성)
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

# Primary Health Check: AWS Ingress ALB
resource "aws_route53_health_check" "primary" {
  count = var.enable_custom_domain ? 1 : 0
  
  type              = "HTTPS"
  resource_path     = "/"
  fqdn              = var.domain_name
  port              = 443
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name        = "${var.domain_name}-primary-health"
    Environment = var.environment
  }
}

# Secondary Health Check: Azure Application Gateway
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