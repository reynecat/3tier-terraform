#!/bin/bash
# azure/scripts/web-init.sh
# Web VM 초기화 스크립트 (유지보수 페이지)

set -e

# 로그 파일 설정
LOG_FILE="/var/log/web-init.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=== Web VM 초기화 시작 (유지보수 모드) ==="
date

# WAS 주소 설정
WAS_IP="${was_ip}"

# 시스템 업데이트
echo "[1/4] 시스템 패키지 업데이트..."
apt-get update
apt-get upgrade -y

# Nginx 설치
echo "[2/4] Nginx 설치..."
apt-get install -y nginx

# 유지보수 페이지 HTML 생성
echo "[3/4] 유지보수 페이지 생성..."
cat > /var/www/html/index.html <<'HTML'
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
        <h1>서비스 점검 중입니다</h1>
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
                <span class="info-value">Warm Standby</span>
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

# Nginx 설정 파일 작성
echo "[4/4] Nginx 설정..."
cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    root /var/www/html;
    index index.html;
    
    # 유지보수 페이지 제공
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    # Health Check 엔드포인트
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # API 프록시 (필요시)
    location /api/ {
        proxy_pass http://$WAS_IP:8080/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Nginx 설정 테스트
nginx -t

# Nginx 시작
systemctl enable nginx
systemctl restart nginx

echo "=== Web VM 초기화 완료 ==="
echo "Maintenance Page: http://localhost/"
echo "Nginx Status: $(systemctl is-active nginx)"
date
