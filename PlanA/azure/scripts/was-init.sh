#!/bin/bash
# azure/scripts/was-init.sh
# WAS VM 초기화 스크립트 (유지보수 API 서버)

set -e

# 로그 파일 설정
LOG_FILE="/var/log/was-init.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=== WAS VM 초기화 시작 (유지보수 모드) ==="
date

# 시스템 업데이트
echo "[1/3] 시스템 패키지 업데이트..."
apt-get update
apt-get upgrade -y

# Python3 및 Flask 설치
echo "[2/3] Python3 및 Flask 설치..."
apt-get install -y python3 python3-pip
pip3 install flask

# 유지보수 API 서버 디렉토리 생성
echo "[3/3] 유지보수 API 서버 생성..."
mkdir -p /opt/maintenance
cd /opt/maintenance

# 간단한 Flask 애플리케이션 작성
cat > /opt/maintenance/app.py <<'PYEOF'
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def home():
    return jsonify({
        'status': 'maintenance',
        'message': 'System is under maintenance',
        'timestamp': datetime.utcnow().isoformat()
    })

@app.route('/health')
def health():
    return jsonify({
        'status': 'ok',
        'mode': 'maintenance'
    })

@app.route('/api/status')
def api_status():
    return jsonify({
        'service': 'maintenance-api',
        'version': '1.0.0',
        'environment': 'azure-dr',
        'mode': 'standby'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
PYEOF

# Systemd 서비스 파일 생성
cat > /etc/systemd/system/maintenance-api.service <<EOF
[Unit]
Description=Maintenance API Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/maintenance
ExecStart=/usr/bin/python3 /opt/maintenance/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
systemctl daemon-reload
systemctl enable maintenance-api
systemctl start maintenance-api

echo "=== WAS VM 초기화 완료 ==="
echo "Maintenance API URL: http://localhost:8080"
date

# 애플리케이션 시작 대기
echo "서비스 시작 대기 중 (10초)..."
sleep 10

# Health Check
if curl -s http://localhost:8080/health > /dev/null; then
    echo "✓ 유지보수 API 서버 정상 시작"
else
    echo "✗ 유지보수 API 서버 시작 실패"
    journalctl -u maintenance-api -n 50
fi