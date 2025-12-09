# aws/modules/rds/outputs.tf

output "db_instance_id" {
  description = "RDS 인스턴스 ID"
  value       = aws_db_instance.main.id
}

output "db_instance_endpoint" {
  description = "RDS 엔드포인트"
  value       = aws_db_instance.main.endpoint
}

output "db_instance_address" {
  description = "RDS 주소"
  value       = aws_db_instance.main.address
}

output "db_instance_arn" {
  description = "RDS ARN"
  value       = aws_db_instance.main.arn
}

output "db_security_group_id" {
  description = "RDS 보안 그룹 ID"
  value       = aws_security_group.rds.id
}

output "db_name" {
  description = "데이터베이스 이름"
  value       = aws_db_instance.main.db_name
}

output "db_port" {
  description = "데이터베이스 포트"
  value       = aws_db_instance.main.port
}
