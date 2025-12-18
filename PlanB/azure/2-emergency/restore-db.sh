#!/bin/bash
# PlanB/azure/2-emergency/scripts/restore-db.sh
# MySQL 백업 복구 스크립트

set -e

echo "=========================================="
echo "MySQL 백업 복구 (Plan B - Emergency)"
echo "시작 시간: $(date)"
echo "=========================================="

# Terraform outputs에서 정보 가져오기
cd ..
MYSQL_HOST=$(terraform output -raw mysql_fqdn)
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-dr-prod")

cd scripts

# Storage Account 정보 (1-always에서)
STORAGE_ACCOUNT="drbackupprod2024"  # terraform.tfvars에서 확인
CONTAINER="mysql-backups"

# MySQL 정보
DB_NAME="petclinic"
DB_USER="mysqladmin"

# 비밀번호 입력
echo ""
read -sp "MySQL Password: " DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo "비밀번호가 입력되지 않았습니다."
    exit 1
fi

echo ""
echo "[1/4] 최신 백업 파일 찾기..."
LATEST_BACKUP=$(az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER \
    --prefix "backups/" \
    --query "sort_by([], &properties.lastModified)[-1].name" \
    --output tsv)

if [ -z "$LATEST_BACKUP" ]; then
    echo "백업 파일을 찾을 수 없습니다."
    exit 1
fi

echo "최신 백업: $LATEST_BACKUP"

echo ""
echo "[2/4] 백업 다운로드..."
mkdir -p /tmp/mysql-restore
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --container-name $CONTAINER \
    --name "$LATEST_BACKUP" \
    --file /tmp/mysql-restore/backup.sql.gz

echo ""
echo "[3/4] 압축 해제..."
gunzip -f /tmp/mysql-restore/backup.sql.gz

echo ""
echo "[4/4] MySQL 복구..."
mysql -h $MYSQL_HOST \
      -u $DB_USER \
      -p"$DB_PASSWORD" \
      < /tmp/mysql-restore/backup.sql

echo ""
echo "=========================================="
echo "MySQL 백업 복구 완료!"
echo "=========================================="
echo ""
echo "MySQL Host: $MYSQL_HOST"
echo "Database: $DB_NAME"
echo ""
echo "다음 단계:"
echo "  1. MySQL 연결 테스트"
echo "  2. cd ../../3-failover && terraform apply"
echo ""

# 정리
rm -rf /tmp/mysql-restore
