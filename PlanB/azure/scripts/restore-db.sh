#!/bin/bash
# azure/scripts/restore-db.sh
# 재해 시: 데이터베이스 복구 (60분)

set -e

echo "=========================================="
echo "데이터베이스 복구 (Plan B - Emergency)"
echo "시작 시간: $(date)"
echo "=========================================="

# 1. MySQL 서버 생성
echo "[1/4] MySQL Flexible Server 생성 (10분)..."
terraform apply \
    -target=azurerm_mysql_flexible_server.main \
    -target=azurerm_mysql_flexible_database.main \
    -auto-approve

MYSQL_HOST=$(terraform output -raw mysql_host)
DB_NAME=$(terraform output -raw db_name)
DB_USER=$(terraform output -raw db_username)
DB_PASSWORD=$(terraform output -raw db_password)

echo "MySQL 서버 생성 완료: $MYSQL_HOST"

# 2. 최신 백업 찾기
echo "[2/4] 최신 백업 찾기..."
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)
LATEST_BACKUP=$(az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --container-name mysql-backups \
    --prefix backups/ \
    --query "sort_by([], &properties.lastModified)[-1].name" \
    --output tsv)

echo "최신 백업: $LATEST_BACKUP"

# 3. 백업 다운로드
echo "[3/4] 백업 다운로드..."
az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --container-name mysql-backups \
    --name $LATEST_BACKUP \
    --file /tmp/latest-backup.sql.gz

gunzip /tmp/latest-backup.sql.gz

# 4. 데이터 복구
echo "[4/4] 데이터 복구..."
mysql -h $MYSQL_HOST -u $DB_USER -p"$DB_PASSWORD" < /tmp/latest-backup.sql

echo ""
echo "=========================================="
echo "데이터베이스 복구 완료!"
echo "=========================================="
echo ""
echo "MySQL Host: $MYSQL_HOST"
echo "Database: $DB_NAME"
echo ""
echo "다음 단계: ./deploy-app.sh"
echo ""
