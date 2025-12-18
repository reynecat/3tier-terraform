# aws/lambda-backup.tf
# RDS → S3 → Azure MySQL 백업 동기화

# =================================================
# Lambda IAM Role
# =================================================

resource "aws_iam_role" "backup_lambda" {
  name = "backup-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Lambda 기본 실행 권한
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.backup_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda VPC 접근 권한
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.backup_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# S3 및 RDS 접근 정책
resource "aws_iam_role_policy" "backup_lambda" {
  name = "backup-lambda-policy"
  role = aws_iam_role.backup_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots",
          "rds:CreateDBSnapshot"
        ]
        Resource = "*"
      }
    ]
  })
}

# =================================================
# Lambda Security Group
# =================================================

resource "aws_security_group" "backup_lambda" {
  name_prefix = "backup-lambda-sg-"
  description = "Security group for backup Lambda"
  vpc_id      = module.vpc.vpc_id

  # RDS 접근
  egress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.rds.db_security_group_id]
    description     = "MySQL to RDS"
  }

  # S3 접근 (VPC Endpoint 통해)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for S3"
  }

  tags = {
    Name = "backup-lambda-sg-${var.environment}"
  }
}

# =================================================
# Lambda Function
# =================================================

resource "aws_lambda_function" "db_backup" {
  filename         = "${path.module}/lambda/db_backup.zip"
  function_name    = "rds-backup-to-s3-${var.environment}"
  role            = aws_iam_role.backup_lambda.arn
  handler         = "index.handler"
  source_code_hash = filebase64sha256("${path.module}/lambda/db_backup.zip")
  runtime         = "python3.11"
  timeout         = 900  # 15분

  vpc_config {
    subnet_ids         = module.vpc.was_subnet_ids
    security_group_ids = [aws_security_group.backup_lambda.id]
  }

  environment {
    variables = {
      RDS_ENDPOINT  = module.rds.db_instance_endpoint
      RDS_DATABASE  = var.db_name
      RDS_USERNAME  = var.db_username
      S3_BUCKET     = aws_s3_bucket.backup.id
      ENVIRONMENT   = var.environment
    }
  }

  tags = {
    Name = "db-backup-lambda-${var.environment}"
  }
}

# RDS 비밀번호를 Lambda에 전달 (환경변수 대신 Secrets Manager 사용 권장)
resource "aws_lambda_function_event_invoke_config" "db_backup" {
  function_name = aws_lambda_function.db_backup.function_name

  maximum_retry_attempts = 2
}

# =================================================
# EventBridge 스케줄 (매 6시간마다 백업)
# =================================================

resource "aws_cloudwatch_event_rule" "backup_schedule" {
  name                = "rds-backup-schedule-${var.environment}"
  description         = "RDS 백업 스케줄 (6시간마다)"
  schedule_expression = "rate(6 hours)"

  tags = {
    Name = "backup-schedule-${var.environment}"
  }
}

resource "aws_cloudwatch_event_target" "backup_lambda" {
  rule      = aws_cloudwatch_event_rule.backup_schedule.name
  target_id = "BackupLambda"
  arn       = aws_lambda_function.db_backup.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.backup_schedule.arn
}

# =================================================
# S3 Bucket Notification (Azure 동기화 트리거)
# =================================================

# S3에 백업 파일 업로드 시 Azure Function 트리거
resource "aws_s3_bucket_notification" "backup_trigger" {
  bucket = aws_s3_bucket.backup.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.db_backup.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "backups/"
    filter_suffix       = ".sql.gz"
  }
}

# =================================================
# CloudWatch 알람
# =================================================

resource "aws_cloudwatch_metric_alarm" "backup_errors" {
  alarm_name          = "backup-lambda-errors-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "백업 Lambda 오류 감지"
  
  dimensions = {
    FunctionName = aws_lambda_function.db_backup.function_name
  }

  alarm_actions = []  # SNS Topic 추가 가능

  tags = {
    Name = "backup-errors-alarm-${var.environment}"
  }
}
