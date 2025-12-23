# aws/route53/outputs.tf

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : ""
}

output "route53_zone_name" {
  description = "Route53 Hosted Zone 이름"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].name : ""
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? aws_cloudfront_distribution.main[0].id : ""
}

output "cloudfront_domain_name" {
  description = "CloudFront Domain Name"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? aws_cloudfront_distribution.main[0].domain_name : ""
}

output "cloudfront_status" {
  description = "CloudFront Origin Failover 상태"
  value = var.enable_custom_domain && local.alb_dns_name != null ? {
    domain             = var.domain_name
    primary_origin     = local.alb_dns_name
    secondary_origin   = "${var.azure_storage_account_name}.z12.web.core.windows.net"
    acm_certificate    = length(data.aws_acm_certificate.main) > 0 ? data.aws_acm_certificate.main[0].arn : "Not configured"
    https_enabled      = length(data.aws_acm_certificate.main) > 0
  } : {
    enabled = false
    message = "Custom domain is disabled"
  }
}

output "deployment_summary" {
  description = "배포 요약"
  value       = var.enable_custom_domain && local.alb_dns_name != null ? "CloudFront + Route53 deployed successfully. Check cloudfront_distribution_id output for details." : "Custom domain is disabled"
}
