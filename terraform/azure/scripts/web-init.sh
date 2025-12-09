#!/bin/bash
# scripts/web-init.sh
# Web VM 초기화 스크립트 (Nginx)

set -e

# 로그 파일
LOG_FILE="/var/log/web-init.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=== Web VM 초기화 시작 ==="
date

# 시스템 업데이트
echo "[1/5] 시스템 패키지 업데이트..."
apt-get update
apt-get upgrade -y

# Nginx 설치
echo "[2/5] Nginx 설치..."
apt-get install -y nginx

# WAS 주소 설정
WAS_IP="${was_ip}"

# Nginx 설정
echo "[3/5] Nginx 설정..."
cat > /etc/nginx/sites-available/default <<EOF
upstream backend {
    server $WAS_IP:8080;
}

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    server_name _;
    
    location / {
        proxy_pass http://backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Nginx 설정 테스트
echo "[4/5] Nginx 설정 테스트..."
nginx -t

# Nginx 재시작
echo "[5/5] Nginx 시작..."
systemctl enable nginx
systemctl restart nginx

echo "=== Web VM 초기화 완료 ==="
echo "WAS Backend: $WAS_IP:8080"
date
