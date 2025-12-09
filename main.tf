terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    # AWS 프로바이더 설정
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    
    # Azure 프로바이더 설정 - 비활성화
    # azurerm = {
    #   source  = "hashicorp/azurerm"
    #   version = "~> 3.0"
    # }
    
    # Random 프로바이더 (패스워드 생성용)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Terraform 상태 저장 백엔드 (S3 사용)
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "multi-cloud-dr/terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock"
  # }
}

# AWS 프로바이더 초기화
provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment = var.environment
      Project     = "Multi-Cloud-DR"
      ManagedBy   = "Terraform"
    }
  }
}

# Azure 프로바이더 초기화 - 비활성화
# provider "azurerm" {
#   features {
#     # 리소스 그룹 삭제 시 자동으로 모든 리소스 삭제
#     resource_group {
#       prevent_deletion_if_contains_resources = false
#     }
#   }
# }

# ==================== AWS Primary Site ====================

# AWS VPC 및 네트워크 모듈 호출
module "aws_vpc" {
  source = "./modules/vpc"
  
  vpc_cidr           = var.aws_vpc_cidr
  availability_zones = var.aws_availability_zones
  environment        = var.environment
  region             = var.aws_region
}

# AWS ALB (Application Load Balancer) 모듈
module "aws_alb" {
  source = "./modules/alb"
  
  vpc_id             = module.aws_vpc.vpc_id
  public_subnets     = module.aws_vpc.public_subnets
  private_subnets    = module.aws_vpc.private_subnets
  environment        = var.environment
}

# AWS EKS 클러스터 모듈 (Web/WAS Tier)
module "aws_eks" {
  source = "./modules/eks"
  
  vpc_id                  = module.aws_vpc.vpc_id
  vpc_cidr                = module.aws_vpc.vpc_cidr
  web_subnets             = module.aws_vpc.web_subnets
  was_subnets             = module.aws_vpc.was_subnets
  private_subnets         = module.aws_vpc.private_subnets
  alb_security_group_id   = module.aws_alb.external_alb_sg_id
  environment             = var.environment
  node_instance_type      = var.eks_node_instance_type
  
  # Web Tier 설정
  web_desired_size        = var.eks_web_desired_size
  web_min_size            = var.eks_web_min_size
  web_max_size            = var.eks_web_max_size
  
  # WAS Tier 설정
  was_desired_size        = var.eks_was_desired_size
  was_min_size            = var.eks_was_min_size
  was_max_size            = var.eks_was_max_size
}

# AWS RDS MySQL 모듈 (Multi-AZ)
module "aws_rds" {
  source = "./modules/rds"
  
  vpc_id             = module.aws_vpc.vpc_id
  db_subnets         = module.aws_vpc.db_subnets
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = random_password.db_password.result
  environment        = var.environment
  multi_az           = true
  backup_retention   = 7
}

# ==================== Azure DR Site - 비활성화 ====================

# Azure 리소스 그룹 생성 - 비활성화
# resource "azurerm_resource_group" "dr" {
#   name     = "rg-dr-${var.environment}"
#   location = var.azure_region
# }

# Azure Virtual Network 모듈 - 비활성화
# module "azure_vnet" {
#   source = "./modules/vpc"
#   
#   resource_group_name = azurerm_resource_group.dr.name
#   location            = var.azure_region
#   vnet_cidr           = var.azure_vnet_cidr
#   environment         = var.environment
# }

# Azure AKS (Kubernetes) 모듈 - 비활성화
# module "azure_aks" {
#   source = "./modules/aks"
#   
#   resource_group_name = azurerm_resource_group.dr.name
#   location            = var.azure_region
#   vnet_id             = module.azure_vnet.vnet_id
#   aks_subnet_id       = module.azure_vnet.aks_subnet_id
#   environment         = var.environment
#   node_count          = 1  # Warm Standby: 최소 노드 수
# }

# Azure MySQL Flexible Server 모듈 - 비활성화
# module "azure_mysql" {
#   source = "./modules/mysql"
#   
#   resource_group_name = azurerm_resource_group.dr.name
#   location            = var.azure_region
#   vnet_id             = module.azure_vnet.vnet_id
#   mysql_subnet_id     = module.azure_vnet.mysql_subnet_id
#   db_name             = var.db_name
#   db_username         = var.db_username
#   db_password         = random_password.db_password.result
#   environment         = var.environment
# }

# ==================== VPN Connection - 비활성화 ====================

# Site-to-Site VPN 모듈 - 비활성화
# module "vpn" {
#   source = "./modules/vpn"
#   
#   # AWS 측 정보
#   aws_vpc_id          = module.aws_vpc.vpc_id
#   aws_subnet_id       = module.aws_vpc.public_subnets[0]
#   aws_vpc_cidr        = var.aws_vpc_cidr
#   
#   # Azure 측 정보
#   azure_resource_group = azurerm_resource_group.dr.name
#   azure_location       = var.azure_region
#   azure_vnet_id        = module.azure_vnet.vnet_id
#   azure_vnet_cidr      = var.azure_vnet_cidr
#   azure_gateway_subnet = module.azure_vnet.gateway_subnet_id
#   
#   environment = var.environment
# }

# ==================== 공통 리소스 ====================

# 데이터베이스 패스워드 랜덤 생성
resource "random_password" "db_password" {
  length  = 16
  special = true
  # 특수문자 중 MySQL에서 문제될 수 있는 문자 제외
  override_special = "!#$%&*()-_=+[]{}<>?"
}

/*
# Route53 DNS Failover (Health Check 포함) - Azure 부분 비활성화
resource "aws_route53_zone" "main" {
  name = var.domain_name
  
  tags = {
    Environment = var.environment
  }
}

# AWS Primary Endpoint Health Check
resource "aws_route53_health_check" "primary" {
  fqdn              = module.aws_alb.external_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  
  tags = {
    Name = "primary-health-check"
  }
}

# Primary Record (AWS)
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  
  # Failover 라우팅 정책
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id
  
  alias {
    name                   = module.aws_alb.external_alb_dns
    zone_id                = module.aws_alb.external_alb_zone_id
    evaluate_target_health = true
  }
}

*/

# Secondary Record (Azure) - 비활성화
# resource "aws_route53_record" "secondary" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = var.domain_name
#   type    = "A"
#   
#   # Failover 라우팅 정책
#   failover_routing_policy {
#     type = "SECONDARY"
#   }
#   
#   set_identifier = "secondary"
#   ttl            = 60
#   records        = [module.azure_aks.app_gateway_public_ip]
# }

# ==================== Lambda for DB Sync ====================

# Lambda 함수 실행 역할
resource "aws_iam_role" "lambda_sync" {
  name = "lambda-db-sync-role"
  
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

# Lambda 실행 정책 연결
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_sync.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda VPC 접근 정책
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_sync.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# S3 접근 정책
resource "aws_iam_role_policy" "lambda_s3" {
  name = "lambda-s3-access"
  role = aws_iam_role.lambda_sync.id
  
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
      }
    ]
  })
}

# Lambda Security Group
resource "aws_security_group" "lambda" {
  name        = "lambda-db-sync-sg"
  description = "Security group for Lambda DB sync function"
  vpc_id      = module.aws_vpc.vpc_id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "lambda-db-sync-sg"
  }
}

# Lambda 함수 - 패키지 파일이 있을 때만 배포
# 패키지 생성: cd scripts/lambda-db-sync && ./package.sh && cd ../..
resource "aws_lambda_function" "db_sync" {
  filename         = "${path.module}/scripts/lambda-db-sync/lambda-package.zip"
  function_name    = "db-sync-function"
  role            = aws_iam_role.lambda_sync.arn
  handler         = "index.lambda_handler"
  source_code_hash = filebase64sha256("${path.module}/scripts/lambda-db-sync/lambda-package.zip")
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 256
  
  vpc_config {
    subnet_ids         = module.aws_vpc.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }
  
  environment {
    variables = {
      RDS_ENDPOINT = module.aws_rds.db_endpoint
      RDS_PORT     = module.aws_rds.db_port
      DB_NAME      = var.db_name
      DB_USERNAME  = var.db_username
      DB_PASSWORD  = random_password.db_password.result
      S3_BUCKET    = aws_s3_bucket.backup.id
      # Azure MySQL 정보 - 비활성화
      # AZURE_MYSQL_HOST = module.azure_mysql.mysql_fqdn
      # AZURE_MYSQL_PORT = 3306
    }
  }
  
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc
  ]
}

# EventBridge 규칙 (5분마다 실행)
resource "aws_cloudwatch_event_rule" "db_sync_schedule" {
  name                = "db-sync-schedule"
  description         = "5분마다 DB 동기화 실행"
  schedule_expression = "rate(5 minutes)"
}

# EventBridge 타겟 - Lambda가 있을 때만 생성
resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.db_sync_schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.db_sync.arn
}

# Lambda 실행 권한 - Lambda가 있을 때만 생성
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.db_sync_schedule.arn
}

# ==================== S3 Backup Bucket ====================

# S3 버킷 생성
resource "aws_s3_bucket" "backup" {
  bucket = "db-backup-${var.environment}-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "db-backup-bucket"
  }
}

# S3 버킷 버전 관리
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 버킷 라이프사이클 정책
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  
  rule {
    id     = "delete-old-backups"
    status = "Enabled"

    filter {
      prefix = "backups/"
    }
    
    expiration {
      days = var.backup_retention_days
    }
  }
}

# ==================== CloudWatch Dashboard ====================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "multi-cloud-dr-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
            [".", "DatabaseConnections", { stat = "Sum" }],
            [".", "FreeStorageSpace", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", { stat = "Average" }],
            [".", "RequestCount", { stat = "Sum" }],
            [".", "HealthyHostCount", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "ALB Metrics"
        }
      }
    ]
  })
}

# ==================== Data Sources ====================

# 현재 AWS 계정 정보
data "aws_caller_identity" "current" {}