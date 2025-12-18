# aws/modules/alb/outputs.tf

output "alb_id" {
  description = "ALB ID"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS 이름"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID"
  value       = aws_lb.main.zone_id
}

output "alb_security_group_id" {
  description = "ALB 보안 그룹 ID"
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Web Target Group ARN"
  value       = aws_lb_target_group.web.arn
}

output "target_group_name" {
  description = "Web Target Group 이름"
  value       = aws_lb_target_group.web.name
}
