# aws/backup-instance.tf
# Plan B (Pilot Light): RDS → Azure Blob Storage 직접 백업
# S3 미사용 (AWS 리전 마비 시 접근 불가)

# =================================================
# IAM Role for Backup Instance
# =================================================

resource "aws_iam_role" "backup_instance" {
  name = "backup-instance-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "backup-instance-role"
  }
}

# RDS 연결 및 Secrets Manager 권한만 (S3 제거)
resource "aws_iam_role_policy" "backup_instance" {
  name = "backup-instance-policy"
  role = aws_iam_role.backup_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.backup_credentials.arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "backup_instance" {
  name = "backup-instance-profile-${var.environment}"
  role = aws_iam_role.backup_instance.name
}

# =================================================
# Security Group for Backup Instance
# =================================================

resource "aws_security_group" "backup_instance" {
  name_prefix = "backup-instance-sg-"
  description = "Security group for backup instance"
  vpc_id      = module.vpc.vpc_id

  # SSH 접근 (SSM Session Manager 권장)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access (use SSM in production)"
  }

  # RDS 접근
  egress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.rds.db_security_group_id]
    description     = "MySQL to RDS"
  }

  # HTTPS (Azure Blob Storage API, 패키지 다운로드)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for Azure and package downloads"
  }

  # HTTP (패키지 저장소)
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for package repositories"
  }

  tags = {
    Name = "backup-instance-sg-${var.environment}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Security Group에 백업 인스턴스 접근 허용 추가
resource "aws_security_group_rule" "rds_from_backup" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = module.rds.db_security_group_id
  source_security_group_id = aws_security_group.backup_instance.id
  description              = "MySQL from backup instance"
}

# =================================================
# SSH Key Pair
# =================================================

resource "aws_key_pair" "backup_instance" {
  key_name   = "backup-instance-key-${var.environment}"
  public_key = var.backup_instance_ssh_public_key

  tags = {
    Name = "backup-instance-key"
  }
}

# =================================================
# EC2 Instance for Backup
# =================================================

# 최신 Ubuntu 22.04 AMI 조회
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "backup_instance" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"  # 2 vCPU, 2GB RAM

  subnet_id                   = module.vpc.was_subnet_ids[0]  # Private 서브넷
  vpc_security_group_ids      = [aws_security_group.backup_instance.id]
  iam_instance_profile        = aws_iam_instance_profile.backup_instance.name
  key_name                    = aws_key_pair.backup_instance.key_name
  associate_public_ip_address = false  # Private 서브넷

  root_block_device {
    volume_type = "gp3"
    volume_size = 30  # GB
    encrypted   = true
  }

  user_data = templatefile("${path.module}/scripts/backup-init.sh", {
    region                = var.aws_region
    rds_endpoint          = module.rds.db_instance_endpoint
    rds_address           = module.rds.db_instance_address
    db_name               = var.db_name
    db_username           = var.db_username
    azure_storage_account = var.azure_storage_account_name
    azure_container       = var.azure_backup_container_name
    secret_arn            = aws_secretsmanager_secret.backup_credentials.arn
  })

  tags = {
    Name        = "backup-instance-${var.environment}"
    Environment = var.environment
    Purpose     = "RDS-to-Azure-Backup"
    DRPlan      = "Plan-B-Pilot-Light"
  }

  depends_on = [
    module.rds,
    aws_secretsmanager_secret_version.backup_credentials
  ]
}

# =================================================
# Secrets Manager for Credentials
# =================================================

resource "aws_secretsmanager_secret" "backup_credentials" {
  name        = "backup-credentials-${var.environment}"
  description = "Credentials for RDS and Azure Blob Storage backup"

  tags = {
    Name = "backup-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "backup_credentials" {
  secret_id = aws_secretsmanager_secret.backup_credentials.id

  secret_string = jsonencode({
    rds_password          = var.db_password
    azure_storage_account = var.azure_storage_account_name
    azure_storage_key     = var.azure_storage_account_key
    azure_tenant_id       = var.azure_tenant_id
    azure_subscription_id = var.azure_subscription_id
  })
}

# =================================================
# CloudWatch Alarms
# =================================================

resource "aws_cloudwatch_metric_alarm" "backup_instance_status" {
  alarm_name          = "backup-instance-status-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "백업 인스턴스 상태 체크 실패"

  dimensions = {
    InstanceId = aws_instance.backup_instance.id
  }

  alarm_actions = []

  tags = {
    Name = "backup-instance-alarm"
  }
}

# =================================================
# Outputs
# =================================================

output "backup_instance_id" {
  description = "백업 인스턴스 ID"
  value       = aws_instance.backup_instance.id
}

output "backup_instance_private_ip" {
  description = "백업 인스턴스 Private IP"
  value       = aws_instance.backup_instance.private_ip
}

output "backup_instance_ssh_command" {
  description = "SSM Session Manager 접속 명령어 (권장)"
  value       = "aws ssm start-session --target ${aws_instance.backup_instance.id}"
}

output "backup_logs_command" {
  description = "백업 로그 확인 명령어"
  value       = "sudo tail -f /var/log/mysql-backup-to-azure.log"
}

output "backup_summary" {
  description = "백업 설정 요약"
  value = <<-EOT
  
  ╔════════════════════════════════════════════════╗
  ║     Backup Instance (Plan B - Pilot Light)     ║
  ╚════════════════════════════════════════════════╝
  
  인스턴스:
    - ID: ${aws_instance.backup_instance.id}
    - Type: t3.small (2 vCPU, 2GB RAM)
    - Private IP: ${aws_instance.backup_instance.private_ip}
    - 비용: ~$15/월
  
  백업 설정:
    - 주기: 5분마다
    - 대상: ${module.rds.db_instance_endpoint}
    - 저장소: Azure Blob Storage (${var.azure_storage_account_name})
    - Container: ${var.azure_backup_container_name}
    - S3: 미사용 (Plan B - 리전 독립)
  
  접속:
    - SSM: aws ssm start-session --target ${aws_instance.backup_instance.id}
    - SSH: ssh ubuntu@${aws_instance.backup_instance.private_ip} (Bastion 필요)
  
  모니터링:
    - 로그: sudo tail -f /var/log/mysql-backup-to-azure.log
    - Cron: sudo crontab -l -u root
  
  Azure 백업 확인:
    az storage blob list \
      --account-name ${var.azure_storage_account_name} \
      --container-name ${var.azure_backup_container_name} \
      --output table
  
  주의:
    - AWS 리전 마비 시 이 인스턴스도 접근 불가
    - Azure Blob에 백업본만 남음 (RTO: 2-4시간)
    - S3 미사용으로 단일 실패 지점 제거
  
  EOT
}
