# PlanB/azure/1-always/main.tf
# 평상시 항상 실행: Storage Account (백업용 + 점검 페이지) + Route53 CNAME

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

provider "aws" {
  region = var.aws_region
}

# =================================================
# Resource Group
# =================================================

resource "azurerm_resource_group" "main" {
  name     = "rg-dr-${var.environment}"
  location = var.location

  tags = var.tags
}

# =================================================
# Virtual Network (예약만, 비용 없음)
# =================================================

resource "azurerm_virtual_network" "main" {
  name                = "vnet-dr-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = [var.vnet_cidr]

  tags = var.tags
}

# =================================================
# Subnet 1: Application Gateway 전용 서브넷
# =================================================
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.appgw_subnet_cidr]
}

# =================================================
# Subnet 2: Web Pod 서브넷 (AKS Web 노드풀용)
# =================================================
resource "azurerm_subnet" "web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.web_subnet_cidr]
}

# =================================================
# Subnet 3: WAS Pod 서브넷 (AKS WAS 노드풀용)
# =================================================
resource "azurerm_subnet" "was" {
  name                 = "snet-was"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.was_subnet_cidr]
}

# =================================================
# Subnet 4: DB 서브넷 (MySQL Flexible Server용)
# =================================================
resource "azurerm_subnet" "db" {
  name                 = "snet-db"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.db_subnet_cidr]

  delegation {
    name = "mysql-delegation"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# =================================================
# Storage Account (백업용 + 점검 페이지 - 항상 실행)
# =================================================

resource "azurerm_storage_account" "backups" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type

  https_traffic_only_enabled = false

  # Static Website 기능 활성화
  static_website {
    index_document = "index.html"
  }

  blob_properties {
    versioning_enabled = true
  }

  tags = var.tags
}

# Blob Container - 백업용
resource "azurerm_storage_container" "mysql_backups" {
  name                  = var.backup_container_name
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"
}

# Blob Container - 점검 페이지용 ($web)
# Static Website 활성화하면 자동 생성됨

# =================================================
# Lifecycle Management - 30일 후 자동 삭제
# =================================================

resource "azurerm_storage_management_policy" "backup_lifecycle" {
  storage_account_id = azurerm_storage_account.backups.id

  rule {
    name    = "deleteOldBackups"
    enabled = true

    filters {
      prefix_match = ["${var.backup_container_name}/backups/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = var.backup_retention_days
      }
    }
  }
}

# =================================================
# 점검 페이지 HTML 업로드
# =================================================

resource "azurerm_storage_blob" "maintenance_page" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.backups.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"

  source_content = <<HTML
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>서비스 점검 중</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }

        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            max-width: 600px;
            width: 100%;
            padding: 60px 40px;
            text-align: center;
            animation: fadeIn 0.5s ease-in;
        }

        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(-20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .icon {
            font-size: 80px;
            margin-bottom: 30px;
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0%, 100% {
                transform: scale(1);
            }
            50% {
                transform: scale(1.1);
            }
        }

        h1 {
            color: #333;
            font-size: 32px;
            margin-bottom: 20px;
            font-weight: 600;
        }

        .subtitle {
            color: #666;
            font-size: 18px;
            margin-bottom: 30px;
            line-height: 1.6;
        }

        .info-box {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            margin-top: 30px;
        }

        .info-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px 0;
            border-bottom: 1px solid #dee2e6;
        }

        .info-item:last-child {
            border-bottom: none;
        }

        .info-label {
            color: #6c757d;
            font-weight: 600;
        }

        .info-value {
            color: #333;
            font-weight: 500;
        }

        .status-badge {
            display: inline-block;
            padding: 8px 16px;
            background: #ffc107;
            color: #856404;
            border-radius: 20px;
            font-weight: 600;
            margin: 20px 0;
        }

        .progress-bar {
            width: 100%;
            height: 6px;
            background: #e0e0e0;
            border-radius: 3px;
            overflow: hidden;
            margin-top: 20px;
        }

        .progress-bar-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            animation: progress 3s ease-in-out infinite;
        }

        @keyframes progress {
            0% {
                width: 0%;
            }
            50% {
                width: 70%;
            }
            100% {
                width: 100%;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">🔧</div>
        <h1>시스템 점검 중입니다</h1>
        <p class="subtitle">
            더 나은 서비스를 제공하기 위해<br>
            시스템 점검을 진행하고 있습니다
        </p>

        <div class="status-badge">DR 사이트 대기 중</div>

        <div class="progress-bar">
            <div class="progress-bar-fill"></div>
        </div>

        <div class="info-box">
            <div class="info-item">
                <span class="info-label">환경</span>
                <span class="info-value">Azure DR Site</span>
            </div>
            <div class="info-item">
                <span class="info-label">모드</span>
                <span class="info-value">Pilot Light</span>
            </div>
            <div class="info-item">
                <span class="info-label">상태</span>
                <span class="info-value">정상 대기</span>
            </div>
        </div>
    </div>

    <script>
        // 자동 새로고침 (5분마다)
        setTimeout(() => {
            location.reload();
        }, 300000);
    </script>
</body>
</html>
HTML

  depends_on = [azurerm_storage_account.backups]
}

# =================================================
# Route53 - Subdomain CNAME to Blob Container
# =================================================

# Data Source - Route53 Hosted Zone
data "aws_route53_zone" "main" {
  count = var.enable_route53 ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

# CNAME Record - 서브도메인을 Blob Static Website로 직접 연결
resource "aws_route53_record" "azure_maintenance" {
  count = var.enable_route53 ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.subdomain_name
  type    = "CNAME"
  ttl     = 300

  records = ["${var.storage_account_name}.z12.web.core.windows.net"]
}
