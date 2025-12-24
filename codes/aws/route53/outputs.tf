# aws/route53/outputs.tf
# CloudFront + Route53 배포 정보

# =================================================
# Route53 정보
# =================================================

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : ""
}

output "route53_zone_name" {
  description = "Route53 Hosted Zone 이름"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].name : ""
}

output "dns_record" {
  description = "Route53 DNS 레코드 정보"
  value = var.enable_custom_domain && local.alb_dns_name != null ? {
    domain     = var.domain_name
    type       = "A (Alias to CloudFront)"
    target     = aws_cloudfront_distribution.main[0].domain_name
    status     = "Active"
  } : {
    status = "Not configured"
  }
}

# =================================================
# CloudFront 정보
# =================================================

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? aws_cloudfront_distribution.main[0].id : ""
}

output "cloudfront_domain_name" {
  description = "CloudFront Domain Name (CDN endpoint)"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? aws_cloudfront_distribution.main[0].domain_name : ""
}

output "cloudfront_url" {
  description = "CloudFront HTTPS URL"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? "https://${var.domain_name}" : ""
}

output "cloudfront_status" {
  description = "CloudFront Distribution 상태"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? aws_cloudfront_distribution.main[0].status : "Not deployed"
}

# =================================================
# Origin Failover 설정 정보
# =================================================

output "origin_failover_config" {
  description = "CloudFront Origin Failover 구성"
  value = var.enable_custom_domain && local.alb_dns_name != null ? {
    failover_enabled   = true
    primary_origin     = local.alb_dns_name
    secondary_origin   = "${var.azure_storage_account_name}.z12.web.core.windows.net"
    failover_codes     = [500, 502, 503, 504]
    origin_group_id    = "multi-cloud-failover-group"
  } : {
    failover_enabled = false
    message          = "Custom domain is disabled or ALB not configured"
  }
}

output "ssl_certificate_info" {
  description = "SSL 인증서 정보"
  value = var.enable_custom_domain && length(data.aws_acm_certificate.main) > 0 ? {
    arn              = data.aws_acm_certificate.main[0].arn
    domain           = data.aws_acm_certificate.main[0].domain
    status           = data.aws_acm_certificate.main[0].status
    https_enabled    = true
    certificate_type = "ACM (us-east-1)"
  } : {
    https_enabled = false
    message       = "ACM certificate not found in us-east-1"
  }
}

# =================================================
# 관리 명령어
# =================================================

output "management_commands" {
  description = "CloudFront 관리 명령어"
  value = var.enable_custom_domain && local.alb_dns_name != null ? {
    cache_invalidation = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main[0].id} --paths '/*'"
    get_distribution   = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.main[0].id}"
    list_invalidations = "aws cloudfront list-invalidations --distribution-id ${aws_cloudfront_distribution.main[0].id}"
    update_origin      = "aws cloudfront get-distribution-config --id ${aws_cloudfront_distribution.main[0].id} > dist-config.json"
  } : {}
}

output "monitoring_commands" {
  description = "모니터링 및 확인 명령어"
  value = var.enable_custom_domain && local.alb_dns_name != null ? {
    dns_lookup       = "dig ${var.domain_name}"
    curl_test        = "curl -I https://${var.domain_name}"
    check_cloudfront = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.main[0].id} --query 'Distribution.Status'"
    check_origins    = "aws cloudfront get-distribution --id ${aws_cloudfront_distribution.main[0].id} --query 'Distribution.DistributionConfig.Origins'"
  } : {}
}

# =================================================
# 배포 요약
# =================================================

output "deployment_summary" {
  description = "배포 요약 정보"
  value = var.enable_custom_domain && local.alb_dns_name != null ? <<-EOT

  ╔════════════════════════════════════════════════════════════════╗
  ║          CloudFront + Route53 배포 완료                        ║
  ╚════════════════════════════════════════════════════════════════╝

  🌐 Domain:           ${var.domain_name}
  📡 CloudFront ID:    ${aws_cloudfront_distribution.main[0].id}
  🔗 CloudFront URL:   ${aws_cloudfront_distribution.main[0].domain_name}
  ✅ Status:           ${aws_cloudfront_distribution.main[0].status}

  🎯 Origin Failover:
     Primary (AWS):    ${local.alb_dns_name}
     Secondary (Azure): ${var.azure_storage_account_name}.z12.web.core.windows.net
     Failover Codes:   500, 502, 503, 504

  🔐 SSL Certificate:
     Status:           ${length(data.aws_acm_certificate.main) > 0 ? "Enabled" : "Not configured"}
     ${length(data.aws_acm_certificate.main) > 0 ? "ARN:              ${data.aws_acm_certificate.main[0].arn}" : ""}

  📝 다음 단계:
     1. DNS 전파 확인: dig ${var.domain_name}
     2. 접속 테스트:   curl -I https://${var.domain_name}
     3. 캐시 삭제:     aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main[0].id} --paths '/*'

  ⚠️  CloudFront 배포 완료까지 약 15-20분 소요됩니다.
  EOT
  : "Custom domain is disabled or ALB not configured. Please check terraform.tfvars."
}
