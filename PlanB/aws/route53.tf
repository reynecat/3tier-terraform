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
# Ingress ALB를 위한 안내 (실제 DNS는 Kubernetes에서 관리)
# =================================================

# Ingress Controller가 생성하는 ALB의 DNS를 Route 53에 연결하려면
# Kubernetes Ingress 매니페스트에 external-dns 어노테이션을 추가하거나
# 수동으로 CNAME 레코드를 생성해야 합니다

# external-dns 설치 방법:
# https://github.com/kubernetes-sigs/external-dns

# =================================================
# Outputs
# =================================================

output "route53_nameservers" {
  description = "Route 53 네임서버 (도메인 등록업체에 설정 필요)"
  value = var.enable_custom_domain && var.create_hosted_zone ? (
    aws_route53_zone.main[0].name_servers
  ) : []
}

output "hosted_zone_id" {
  description = "Route 53 Hosted Zone ID"
  value       = local.hosted_zone_id
}

output "acm_certificate_arn" {
  description = "ACM 인증서 ARN (HTTPS용)"
  value       = var.enable_custom_domain ? aws_acm_certificate.main[0].arn : null
}

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
    ℹ️  도메인 설정이 비활성화되어 있습니다.
    
    현재 접속 방법:
    - Kubernetes Ingress ALB DNS로 직접 접속
    - kubectl get ingress -n web 명령어로 확인
    
    도메인을 추가하려면:
    1. terraform.tfvars에서 enable_custom_domain = true
    2. domain_name = "example.com" 설정
    3. terraform apply 실행
    EOT
  )
}