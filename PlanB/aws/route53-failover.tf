# Route 53 Failover 레코드 - Azure 연동

# Azure Application Gateway Public IP를 Variable로 받음
variable "azure_appgw_public_ip" {
  description = "Azure Application Gateway Public IP (2-emergency 배포 후 입력)"
  type        = string
  default     = ""  # 평상시 비어있음
}

# Primary: AWS EKS Ingress ALB
resource "aws_route53_record" "primary" {
  count = var.enable_custom_domain ? 1 : 0
  
  zone_id = local.hosted_zone_id
  name    = var.domain_name
  type    = "A"
  
  alias {
    name                   = "k8s-ingress-xxx.elb.amazonaws.com"  # Ingress ALB DNS
    zone_id                = "Z1234567890ABC"  # ALB Hosted Zone
    evaluate_target_health = true
  }
  
  set_identifier = "Primary-AWS"
  
  failover_routing_policy {
    type = "PRIMARY"
  }
}

# Secondary: Azure Application Gateway
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
  
  health_check_id = aws_route53_health_check.azure[0].id
}

# Health Check: Azure Application Gateway
resource "aws_route53_health_check" "azure" {
  count = var.enable_custom_domain && var.azure_appgw_public_ip != "" ? 1 : 0
  
  type              = "HTTP"
  ip_address        = var.azure_appgw_public_ip
  port              = 80
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name = "Azure-AppGW-HealthCheck"
  }
}

output "failover_status" {
  value = var.azure_appgw_public_ip != "" ? "Failover Configured" : "Failover Not Configured"
}