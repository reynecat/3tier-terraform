# aws/main.tf
# AWS Primary Site 인프라 구성

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  
  # Terraform 상태 저장 백엔드 (S3 사용)
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "aws-primary/terraform.tfstate"
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
      Site        = "Primary"
    }
  }
}

# =================================================
# AWS VPC 및 네트워크
# =================================================

module "vpc" {
  source = "./modules/vpc"
  
  vpc_cidr           = var.aws_vpc_cidr
  availability_zones = var.aws_availability_zones
  environment        = var.environment
  region             = var.aws_region
}

# =================================================
# AWS Application Load Balancer
# =================================================

module "alb" {
  source = "./modules/alb"
  
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnets
  was_subnets     = module.vpc.was_subnets
  private_subnets = module.vpc.private_subnets
  environment     = var.environment
}

# =================================================
# AWS EKS 클러스터 (Web/WAS Tier)
# =================================================

module "eks" {
  source = "./modules/eks"
  
  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = module.vpc.vpc_cidr
  web_subnets             = module.vpc.web_subnets
  was_subnets             = module.vpc.was_subnets
  private_subnets         = module.vpc.private_subnets
  alb_security_group_id   = module.alb.external_alb_sg_id
  environment             = var.environment
  node_instance_type      = var.eks_node_instance_type
  
  # Web Tier 노드 그룹 설정
  web_desired_size = var.eks_web_desired_size
  web_min_size     = var.eks_web_min_size
  web_max_size     = var.eks_web_max_size
  
  # WAS Tier 노드 그룹 설정
  was_desired_size = var.eks_was_desired_size
  was_min_size     = var.eks_was_min_size
  was_max_size     = var.eks_was_max_size
}

# =================================================
# AWS RDS MySQL (Multi-AZ)
# =================================================

# DB 패스워드 생성
resource "random_password" "db_password" {
  length  = 16
  special = true
}

module "rds" {
  source = "./modules/rds"
  
  vpc_id             = module.vpc.vpc_id
  db_subnets         = module.vpc.db_subnets
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = random_password.db_password.result
  environment        = var.environment
  multi_az           = true
  backup_retention   = 7
}

# =================================================
# S3 Bucket for DB Backups
# =================================================

resource "aws_s3_bucket" "backup" {
  bucket = "dr-backup-${var.environment}-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name = "dr-backup-bucket"
  }
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# =================================================
# Site-to-Site VPN Gateway (Azure 연결용)
# =================================================

# Customer Gateway (Azure VPN Gateway 정보)
resource "aws_customer_gateway" "azure" {
  bgp_asn    = 65000
  ip_address = var.azure_vpn_gateway_ip
  type       = "ipsec.1"
  
  tags = {
    Name = "cgw-azure-${var.environment}"
  }
}

# Virtual Private Gateway
resource "aws_vpn_gateway" "main" {
  vpc_id = module.vpc.vpc_id
  
  tags = {
    Name = "vgw-${var.environment}"
  }
}

# VPN Gateway Attachment
resource "aws_vpn_gateway_attachment" "main" {
  vpc_id         = module.vpc.vpc_id
  vpn_gateway_id = aws_vpn_gateway.main.id
}

# VPN Connection
resource "aws_vpn_connection" "azure" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.azure.id
  type                = "ipsec.1"
  static_routes_only  = true
  
  # Pre-Shared Key
  tunnel1_preshared_key = var.vpn_shared_key
  tunnel2_preshared_key = var.vpn_shared_key
  
  # IPsec 설정
  tunnel1_ike_versions                 = ["ikev2"]
  tunnel1_phase1_dh_group_numbers      = [2]
  tunnel1_phase1_encryption_algorithms = ["AES256"]
  tunnel1_phase1_integrity_algorithms  = ["SHA256"]
  tunnel1_phase2_dh_group_numbers      = [2]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA256"]
  
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_dh_group_numbers      = [2]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA256"]
  tunnel2_phase2_dh_group_numbers      = [2]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA256"]
  
  tags = {
    Name = "vpn-to-azure-${var.environment}"
  }
}

# Static Route (Azure VNet CIDR)
resource "aws_vpn_connection_route" "azure" {
  destination_cidr_block = var.azure_vnet_cidr
  vpn_connection_id      = aws_vpn_connection.azure.id
}

# VPN Gateway Route Propagation
resource "aws_vpn_gateway_route_propagation" "private" {
  vpn_gateway_id = aws_vpn_gateway.main.id
  route_table_id = module.vpc.private_route_table_id
}

# =================================================
# 데이터 소스
# =================================================

data "aws_caller_identity" "current" {}
