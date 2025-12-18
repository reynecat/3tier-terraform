# aws/main.tf
# AWS Primary Site 인프라 구성

terraform {
  required_version = ">= 1.14.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  
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
  
  environment        = var.environment
  vpc_cidr           = var.aws_vpc_cidr
  availability_zones = var.aws_availability_zones
  
  public_subnet_cidrs = var.public_subnet_cidrs
  web_subnet_cidrs    = var.web_subnet_cidrs
  was_subnet_cidrs    = var.was_subnet_cidrs
  rds_subnet_cidrs    = var.rds_subnet_cidrs
}


# =================================================
# AWS EKS 클러스터 (Web/WAS Tier)
# =================================================

module "eks" {
  source = "./modules/eks"
  
  environment         = var.environment
  web_subnet_ids      = module.vpc.web_subnet_ids
  was_subnet_ids      = module.vpc.was_subnet_ids
  node_instance_type  = var.eks_node_instance_type
  
  # Web Tier 노드 그룹 설정
  web_desired_size = var.eks_web_desired_size
  web_min_size     = var.eks_web_min_size
  web_max_size     = var.eks_web_max_size
  
  # WAS Tier 노드 그룹 설정
  was_desired_size = var.eks_was_desired_size
  was_min_size     = var.eks_was_min_size
  was_max_size     = var.eks_was_max_size
  
  depends_on = [module.vpc]
}


# =================================================
# AWS RDS MySQL (Multi-AZ)
# =================================================


module "rds" {
  source = "./modules/rds"
  
  environment                = var.environment
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.rds_subnet_ids
  eks_security_group_id      = module.eks.cluster_security_group_id
  
  database_name              = var.db_name
  master_username            = var.db_username
  master_password            = "MyNewPassword123!"
  
  instance_class             = var.rds_instance_class
  allocated_storage          = var.rds_allocated_storage
  max_allocated_storage      = var.rds_max_allocated_storage
  
  multi_az                   = var.rds_multi_az
  skip_final_snapshot        = var.rds_skip_final_snapshot
  deletion_protection        = var.rds_deletion_protection
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

  lifecycle {
    create_before_destroy = true
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
  tunnel1_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel1_phase2_dh_group_numbers      = [2]
  tunnel1_phase2_encryption_algorithms = ["AES256"]
  tunnel1_phase2_integrity_algorithms  = ["SHA2-256"]
  
  tunnel2_ike_versions                 = ["ikev2"]
  tunnel2_phase1_dh_group_numbers      = [2]
  tunnel2_phase1_encryption_algorithms = ["AES256"]
  tunnel2_phase1_integrity_algorithms  = ["SHA2-256"]
  tunnel2_phase2_dh_group_numbers      = [2]
  tunnel2_phase2_encryption_algorithms = ["AES256"]
  tunnel2_phase2_integrity_algorithms  = ["SHA2-256"]
  
  tags = {
    Name = "vpn-to-azure-${var.environment}"
  }

  depends_on = [
    aws_customer_gateway.azure
  ]
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
