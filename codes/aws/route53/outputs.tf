# aws/route53/outputs.tf

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].zone_id : ""
}

output "route53_zone_name" {
  description = "Route53 Hosted Zone 이름"
  value       = var.enable_custom_domain ? data.aws_route53_zone.main[0].name : ""
}

output "route53_failover_status" {
  description = "Failover 설정 상태"
  value = var.enable_custom_domain ? {
    primary_enabled   = local.alb_dns_name != null
    primary_alb_dns   = local.alb_dns_name != null ? local.alb_dns_name : "ALB not configured"
    secondary_enabled = var.azure_appgw_public_ip != ""
    secondary_ip      = var.azure_appgw_public_ip != "" ? var.azure_appgw_public_ip : "Not configured"
    domain            = var.domain_name
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

output "route53_primary_record" {
  description = "Primary Route53 레코드 정보"
  value = var.enable_custom_domain && local.alb_dns_name != null ? {
    name           = var.domain_name
    type           = "A (Alias)"
    target         = local.alb_dns_name
    set_identifier = "Primary-AWS-ALB"
    routing_policy = "FAILOVER-PRIMARY"
  } : {}
}

output "route53_secondary_record" {
  description = "Secondary Route53 레코드 정보"
  value = var.enable_custom_domain && var.azure_appgw_public_ip != "" ? {
    name           = var.domain_name
    type           = "A"
    target         = var.azure_appgw_public_ip
    set_identifier = "Secondary-Azure-AppGW"
    routing_policy = "FAILOVER-SECONDARY"
    ttl            = 60
  } : {}
}

output "monitoring_commands" {
  description = "모니터링 명령어"
  value = var.enable_custom_domain ? {
    primary_health   = length(aws_route53_health_check.primary) > 0 ? "aws route53 get-health-check-status --health-check-id ${aws_route53_health_check.primary[0].id}" : ""
    secondary_health = length(aws_route53_health_check.secondary) > 0 ? "aws route53 get-health-check-status --health-check-id ${aws_route53_health_check.secondary[0].id}" : ""
    list_health      = "aws route53 list-health-checks"
    dig_domain       = "dig ${var.domain_name}"
    nslookup_domain  = "nslookup ${var.domain_name}"
  } : {}
}
