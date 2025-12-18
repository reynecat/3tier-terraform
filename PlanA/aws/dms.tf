# aws/dms.tf
# AWS Database Migration Service (DMS) 설정
# RDS MySQL → Azure MySQL 실시간 복제

# =================================================
# DMS Replication Subnet Group
# =================================================

resource "aws_dms_replication_subnet_group" "main" {
  replication_subnet_group_id          = "dms-subnet-group-${var.environment}"
  replication_subnet_group_description = "DMS replication subnet group"
  
  subnet_ids = [
    aws_subnet.private_app_a.id,
    aws_subnet.private_app_c.id,
  ]
  
  tags = {
    Name = "dms-subnet-group-${var.environment}"
  }
}

# =================================================
# DMS Replication Instance
# =================================================

resource "aws_dms_replication_instance" "main" {
  replication_instance_id      = "dms-instance-${var.environment}"
  replication_instance_class   = "dms.t3.medium"  # 2 vCPU, 4GB RAM
  engine_version              = "3.5.2"
  
  allocated_storage           = 100  # GB
  storage_encrypted           = true
  multi_az                    = false  # 비용 절감
  publicly_accessible         = false
  
  replication_subnet_group_id = aws_dms_replication_subnet_group.main.id
  vpc_security_group_ids      = [aws_security_group.dms.id]
  
  # VPN을 통한 Azure 연결을 위한 설정
  availability_zone           = "ap-northeast-2a"
  
  tags = {
    Name = "dms-instance-${var.environment}"
  }
}

# =================================================
# DMS Source Endpoint (AWS RDS)
# =================================================

resource "aws_dms_endpoint" "source" {
  endpoint_id                 = "dms-source-rds-${var.environment}"
  endpoint_type              = "source"
  engine_name                = "mysql"
  
  # RDS 연결 정보
  server_name                = aws_db_instance.main.address
  port                       = 3306
  database_name              = var.database_name
  username                   = var.database_username
  password                   = var.database_password
  
  # SSL 연결
  ssl_mode                   = "require"
  
  extra_connection_attributes = "parallelLoadThreads=1;initstmt=SET FOREIGN_KEY_CHECKS=0"
  
  tags = {
    Name = "dms-source-rds"
  }
}

# =================================================
# DMS Target Endpoint (Azure MySQL)
# =================================================

resource "aws_dms_endpoint" "target" {
  endpoint_id                 = "dms-target-azure-${var.environment}"
  endpoint_type              = "target"
  engine_name                = "mysql"
  
  # Azure MySQL 연결 정보 (VPN을 통해 Private IP 사용)
  server_name                = var.azure_mysql_private_ip  # 172.16.31.x
  port                       = 3306
  database_name              = var.database_name
  username                   = var.azure_mysql_username
  password                   = var.azure_mysql_password
  
  # SSL 연결
  ssl_mode                   = "require"
  
  extra_connection_attributes = "targetDbType=SPECIFIC_DATABASE;parallelLoadThreads=1"
  
  tags = {
    Name = "dms-target-azure"
  }
  
  # VPN 연결 후 생성
  depends_on = [
    aws_vpn_connection.to_azure,
  ]
}

# =================================================
# DMS Replication Task
# =================================================

resource "aws_dms_replication_task" "main" {
  replication_task_id      = "dms-task-${var.environment}"
  migration_type           = "cdc"  # Change Data Capture (실시간 복제)
  
  replication_instance_arn = aws_dms_replication_instance.main.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn
  
  table_mappings = jsonencode({
    rules = [
      {
        rule-type = "selection"
        rule-id   = "1"
        rule-name = "replicate-all-tables"
        object-locator = {
          schema-name = var.database_name
          table-name  = "%"  # 모든 테이블
        }
        rule-action = "include"
      }
    ]
  })
  
  replication_task_settings = jsonencode({
    TargetMetadata = {
      TargetSchema                  = var.database_name
      SupportLobs                   = true
      FullLobMode                   = false
      LobChunkSize                  = 64
      LimitedSizeLobMode            = true
      LobMaxSize                    = 32
    }
    FullLoadSettings = {
      TargetTablePrepMode           = "DROP_AND_CREATE"
      CreatePkAfterFullLoad         = true
      StopTaskCachedChangesApplied  = false
      StopTaskCachedChangesNotApplied = false
      MaxFullLoadSubTasks           = 8
      TransactionConsistencyTimeout = 600
      CommitRate                    = 10000
    }
    Logging = {
      EnableLogging = true
      LogComponents = [
        {
          Id       = "SOURCE_CAPTURE"
          Severity = "LOGGER_SEVERITY_INFO"
        },
        {
          Id       = "TARGET_APPLY"
          Severity = "LOGGER_SEVERITY_INFO"
        }
      ]
    }
    ChangeProcessingTuning = {
      BatchApplyPreserveTransaction = true
      BatchApplyTimeoutMin          = 1
      BatchApplyTimeoutMax          = 30
      BatchApplyMemoryLimit         = 500
      BatchSplitSize                = 0
      MinTransactionSize            = 1000
      CommitTimeout                 = 1
      MemoryLimitTotal              = 1024
      MemoryKeepTime                = 60
      StatementCacheSize            = 50
    }
  })
  
  tags = {
    Name = "dms-task-${var.environment}"
  }
  
  # 자동 시작
  start_replication_task = true
}

# =================================================
# DMS Security Group
# =================================================

resource "aws_security_group" "dms" {
  name        = "dms-sg-${var.environment}"
  description = "Security group for DMS replication instance"
  vpc_id      = aws_vpc.main.id
  
  # RDS로부터 트래픽 수신
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
    description     = "MySQL from RDS"
  }
  
  # Azure MySQL로 트래픽 송신 (VPN을 통해)
  egress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.azure_vnet_cidr]  # 172.16.0.0/16
    description = "MySQL to Azure"
  }
  
  # CloudWatch Logs로 로그 전송
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for CloudWatch"
  }
  
  tags = {
    Name = "dms-sg-${var.environment}"
  }
}

# =================================================
# RDS Security Group 업데이트 (DMS 허용)
# =================================================

resource "aws_security_group_rule" "rds_from_dms" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_security_group.dms.id
  description              = "MySQL from DMS"
}

# =================================================
# CloudWatch Log Group for DMS
# =================================================

resource "aws_cloudwatch_log_group" "dms" {
  name              = "/aws/dms/${var.environment}"
  retention_in_days = 7
  
  tags = {
    Name = "dms-logs"
  }
}

# =================================================
# CloudWatch Alarms for DMS
# =================================================

# DMS 복제 지연 알람
resource "aws_cloudwatch_metric_alarm" "dms_replication_lag" {
  alarm_name          = "dms-replication-lag-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CDCLatencySource"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "60"  # 60초 초과 시 알람
  alarm_description   = "DMS replication lag is too high"
  treat_missing_data  = "notBreaching"
  
  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
    ReplicationTaskIdentifier     = aws_dms_replication_task.main.replication_task_id
  }
  
  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}

# DMS CPU 사용률 알람
resource "aws_cloudwatch_metric_alarm" "dms_cpu" {
  alarm_name          = "dms-cpu-high-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/DMS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "DMS CPU utilization is too high"
  
  dimensions = {
    ReplicationInstanceIdentifier = aws_dms_replication_instance.main.replication_instance_id
  }
  
  alarm_actions = [aws_sns_topic.budget_alerts.arn]
}

# =================================================
# Variables
# =================================================

# variables.tf에 추가할 내용:
# variable "azure_mysql_private_ip" {
#   description = "Azure MySQL의 Private IP 주소 (VPN을 통해 연결)"
#   type        = string
# }
# 
# variable "azure_mysql_username" {
#   description = "Azure MySQL 관리자 사용자명"
#   type        = string
# }
# 
# variable "azure_mysql_password" {
#   description = "Azure MySQL 관리자 비밀번호"
#   type        = string
#   sensitive   = true
# }

# =================================================
# Outputs
# =================================================

output "dms_replication_instance_arn" {
  description = "DMS Replication Instance ARN"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "dms_replication_instance_private_ip" {
  description = "DMS Replication Instance Private IP"
  value       = aws_dms_replication_instance.main.replication_instance_private_ips
}

output "dms_task_arn" {
  description = "DMS Replication Task ARN"
  value       = aws_dms_replication_task.main.replication_task_arn
}

output "dms_task_status" {
  description = "DMS Replication Task 상태 확인 명령어"
  value       = "aws dms describe-replication-tasks --filters Name=replication-task-arn,Values=${aws_dms_replication_task.main.replication_task_arn}"
}

output "dms_monitoring_url" {
  description = "DMS 모니터링 대시보드 URL"
  value       = "https://console.aws.amazon.com/dms/v2/home?region=${var.aws_region}#replicationInstanceDetails/${aws_dms_replication_instance.main.replication_instance_id}"
}
