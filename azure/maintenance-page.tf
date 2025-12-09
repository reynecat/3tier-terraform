# azure/maintenance-page.tf
# Azure 정적 유지보수 페이지 설정

# =================================================
# 유지보수 페이지 활성화 변수
# =================================================

variable "enable_maintenance_page" {
  description = "유지보수 페이지 표시 여부"
  type        = bool
  default     = false
}

# 랜덤 접미사 생성
resource "random_string" "suffix" {
  count   = var.enable_maintenance_page ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

# =================================================
# Storage Account (정적 웹사이트 호스팅용)
# =================================================

resource "azurerm_storage_account" "maintenance" {
  count = var.enable_maintenance_page ? 1 : 0
  
  name                     = "maintenance${random_string.suffix[0].result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # 정적 웹사이트 활성화
  static_website {
    index_document     = "index.html"
    error_404_document = "404.html"
  }
  
  tags = {
    Environment = var.environment
    Purpose     = "Maintenance Page"
  }
}

# =================================================
# 유지보수 페이지 HTML 업로드
# =================================================

resource "azurerm_storage_blob" "maintenance_html" {
  count = var.enable_maintenance_page ? 1 : 0
  
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.maintenance[0].name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  
  source_content = <<-HTML
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>서비스 점검 중 - PetClinic</title>
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
        
        .apology {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 20px;
            margin: 30px 0;
            text-align: left;
            border-radius: 5px;
        }
        
        .apology h2 {
            color: #856404;
            font-size: 20px;
            margin-bottom: 10px;
        }
        
        .apology p {
            color: #856404;
            line-height: 1.8;
            margin-bottom: 10px;
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
        
        .contact {
            margin-top: 30px;
            padding: 20px;
            background: #e7f3ff;
            border-radius: 10px;
        }
        
        .contact h3 {
            color: #0066cc;
            margin-bottom: 15px;
        }
        
        .contact p {
            color: #333;
            line-height: 1.6;
        }
        
        .social-links {
            margin-top: 20px;
            display: flex;
            gap: 15px;
            justify-content: center;
        }
        
        .social-links a {
            display: inline-block;
            width: 40px;
            height: 40px;
            background: #667eea;
            color: white;
            border-radius: 50%;
            line-height: 40px;
            text-decoration: none;
            transition: transform 0.3s;
        }
        
        .social-links a:hover {
            transform: scale(1.1);
        }
        
        .timer {
            font-size: 48px;
            font-weight: bold;
            color: #667eea;
            margin: 20px 0;
            font-family: 'Courier New', monospace;
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
        
        @media (max-width: 768px) {
            .container {
                padding: 40px 20px;
            }
            
            h1 {
                font-size: 24px;
            }
            
            .subtitle {
                font-size: 16px;
            }
            
            .icon {
                font-size: 60px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">🔧</div>
        <h1>서비스 점검 중입니다</h1>
        <p class="subtitle">
            더 나은 서비스를 제공하기 위해<br>
            시스템 점검 및 업그레이드를 진행하고 있습니다
        </p>
        
        <div class="progress-bar">
            <div class="progress-bar-fill"></div>
        </div>
        
        <div class="apology">
            <h2>⚠️ 불편을 드려 죄송합니다</h2>
            <p>
                예기치 않은 문제로 인해 일시적으로 서비스를 이용하실 수 없습니다.
                고객님께 불편을 드려 진심으로 사과드립니다.
            </p>
            <p>
                저희 기술팀은 최대한 빠른 시간 내에 서비스를 복구하기 위해
                최선을 다하고 있습니다. 잠시만 기다려 주시면 감사하겠습니다.
            </p>
        </div>
        
        <div class="info-box">
            <div class="info-item">
                <span class="info-label">📅 점검 시작</span>
                <span class="info-value" id="start-time">-</span>
            </div>
            <div class="info-item">
                <span class="info-label">⏰ 예상 완료</span>
                <span class="info-value">최대한 빠르게</span>
            </div>
            <div class="info-item">
                <span class="info-label">🔄 진행 상태</span>
                <span class="info-value">복구 작업 중</span>
            </div>
        </div>
        
        <div class="contact">
            <h3>📞 긴급 문의</h3>
            <p>
                <strong>이메일:</strong> support@petclinic.com<br>
                <strong>전화:</strong> 1588-1234<br>
                <strong>운영 시간:</strong> 24시간 365일
            </p>
        </div>
        
        <div class="social-links">
            <a href="#" title="Facebook">f</a>
            <a href="#" title="Twitter">t</a>
            <a href="#" title="Instagram">i</a>
        </div>
    </div>
    
    <script>
        // 현재 시간 표시
        function updateTime() {
            const now = new Date();
            const timeString = now.toLocaleString('ko-KR', {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            });
            document.getElementById('start-time').textContent = timeString;
        }
        
        updateTime();
        setInterval(updateTime, 60000); // 1분마다 업데이트
        
        // 자동 새로고침 (5분마다)
        setTimeout(() => {
            location.reload();
        }, 300000);
    </script>
</body>
</html>
HTML
}

# 404 페이지
resource "azurerm_storage_blob" "maintenance_404" {
  count = var.enable_maintenance_page ? 1 : 0
  
  name                   = "404.html"
  storage_account_name   = azurerm_storage_account.maintenance[0].name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  
  source_content = <<-HTML
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <title>404 - 페이지를 찾을 수 없습니다</title>
    <meta http-equiv="refresh" content="0;url=/">
</head>
<body>
    <p>메인 페이지로 이동 중...</p>
</body>
</html>
HTML
}

# =================================================
# Outputs
# =================================================

output "maintenance_page_url" {
  description = "유지보수 페이지 URL"
  value = var.enable_maintenance_page ? (
    "https://${azurerm_storage_account.maintenance[0].primary_web_host}"
  ) : "유지보수 페이지가 비활성화되어 있습니다"
}

output "maintenance_status" {
  description = "유지보수 모드 상태"
  value = var.enable_maintenance_page ? (
    "🔧 유지보수 모드 활성화됨 - 사용자는 사과 메시지를 볼 수 있습니다"
  ) : (
    "✅ 정상 운영 중"
  )
}

output "maintenance_instructions" {
  description = "유지보수 모드 사용 방법"
  value = <<-EOT
    
    ========================================
    유지보수 모드 전환 방법
    ========================================
    
    1. 유지보수 모드 활성화:
       terraform.tfvars에서:
       enable_maintenance_page = true
       
       terraform apply 실행
       
    2. Application Gateway에서 수동 전환:
       - Backend Pool을 maintenance-pool로 변경
       - 사용자는 사과 메시지 페이지를 보게 됩니다
       
    3. 정상 운영 복구:
       terraform.tfvars에서:
       enable_maintenance_page = false
       
       terraform apply 실행
    
    ========================================
    
  EOT
}
