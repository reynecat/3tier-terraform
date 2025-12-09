#!/bin/bash
# scripts/was-init.sh
# WAS VM 초기화 스크립트 (Spring Boot)

set -e

# 로그 파일
LOG_FILE="/var/log/was-init.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=== WAS VM 초기화 시작 ==="
date

# DB 연결 정보
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"

# 시스템 업데이트
echo "[1/6] 시스템 패키지 업데이트..."
apt-get update
apt-get upgrade -y

# Java 설치
echo "[2/6] OpenJDK 17 설치..."
apt-get install -y openjdk-17-jdk

# MySQL Client 설치
echo "[3/6] MySQL Client 설치..."
apt-get install -y mysql-client

# 애플리케이션 디렉토리 생성
echo "[4/6] 애플리케이션 디렉토리 생성..."
mkdir -p /opt/petclinic
cd /opt/petclinic

# Spring PetClinic 다운로드
echo "[5/6] Spring PetClinic 다운로드..."
wget -O petclinic.jar https://github.com/spring-projects/spring-petclinic/releases/download/v3.1.0/spring-petclinic-3.1.0.jar

# 환경 변수 파일 생성
cat > /opt/petclinic/.env <<EOF
SPRING_PROFILES_ACTIVE=mysql
SPRING_DATASOURCE_URL=jdbc:mysql://$DB_HOST:3306/$DB_NAME
SPRING_DATASOURCE_USERNAME=$DB_USERNAME
SPRING_DATASOURCE_PASSWORD=$DB_PASSWORD
SPRING_JPA_HIBERNATE_DDL_AUTO=update
SERVER_PORT=8080
EOF

# Systemd 서비스 생성
echo "[6/6] Systemd 서비스 생성..."
cat > /etc/systemd/system/petclinic.service <<EOF
[Unit]
Description=Spring PetClinic Application
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/petclinic
EnvironmentFile=/opt/petclinic/.env
ExecStart=/usr/bin/java -jar /opt/petclinic/petclinic.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 서비스 시작
systemctl daemon-reload
systemctl enable petclinic
systemctl start petclinic

echo "=== WAS VM 초기화 완료 ==="
echo "DB Host: $DB_HOST"
echo "Application: http://localhost:8080"
date

# 애플리케이션 시작 대기
echo "애플리케이션 시작 대기 중..."
sleep 30

# Health Check
if curl -s http://localhost:8080/actuator/health > /dev/null; then
    echo "✓ 애플리케이션 정상 시작"
else
    echo "✗ 애플리케이션 시작 실패 - 로그 확인 필요"
    journalctl -u petclinic -n 50
fi
