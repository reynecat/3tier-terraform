#!/bin/bash
# azure/scripts/restore-database.sh
# Azure MySQL 데이터베이스 복구 (Blob Storage 백업 사용)

set -e

LOG_FILE="/var/log/db-restore-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=========================================="
echo "데이터베이스 복구 시작"
echo "시작 시간: $(date)"
echo "=========================================="

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 변수
RESOURCE_GROUP="rg-dr-prod"
LOCATION="koreacentral"
STORAGE_ACCOUNT=$(az storage account list -g $RESOURCE_GROUP --query "[0].name" -o tsv)
CONTAINER_NAME="mysql-backups"
RESTORE_DIR="/tmp/mysql-restore"

mkdir -p $RESTORE_DIR

echo "Storage Account: $STORAGE_ACCOUNT"
echo "Container: $CONTAINER_NAME"
echo ""

# =================================================
# Phase 1: Azure MySQL 생성 (10분)
# =================================================

echo -e "${YELLOW}[Phase 1/4] Azure MySQL 서버 생성...${NC}"

# MySQL 서버 이름 (고유해야 함)
MYSQL_SERVER="mysql-dr-prod-$(date +%s | tail -c 5)"
DB_NAME="petclinic"
DB_USER="mysqladmin"

# 비밀번호 입력
echo -n "MySQL 관리자 비밀번호 입력: "
read -s DB_PASSWORD
echo ""

# VNet 설정
VNET_NAME="vnet-dr-prod"
SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name subnet-db \
    --query id \
    --output tsv)

# MySQL Flexible Server 생성
echo "[1.1] MySQL Flexible Server 생성 (약 10분 소요)..."
az mysql flexible-server create \
    --resource-group $RESOURCE_GROUP \
    --name $MYSQL_SERVER \
    --location $LOCATION \
    --admin-user $DB_USER \
    --admin-password "$DB_PASSWORD" \
    --sku-name Standard_B2s \
    --tier Burstable \
    --version 8.0.21 \
    --storage-size 20 \
    --subnet $SUBNET_ID \
    --private-dns-zone privatednsmysql.mysql.database.azure.com \
    --backup-retention 7 \
    --yes

MYSQL_HOST="$MYSQL_SERVER.mysql.database.azure.com"
echo "MySQL 서버 생성 완료: $MYSQL_HOST"

# 데이터베이스 생성
echo "[1.2] 데이터베이스 생성..."
az mysql flexible-server db create \
    --resource-group $RESOURCE_GROUP \
    --server-name $MYSQL_SERVER \
    --database-name $DB_NAME

# =================================================
# Phase 2: 최신 백업 다운로드 (5분)
# =================================================

echo -e "${YELLOW}[Phase 2/4] 최신 백업 파일 다운로드...${NC}"

# Storage Account Key 가져오기
STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT \
    --query '[0].value' \
    --output tsv)

# 최신 백업 파일 찾기
echo "[2.1] 최신 백업 파일 검색..."
LATEST_BACKUP=$(az storage blob list \
    --account-name $STORAGE_ACCOUNT \
    --account-key "$STORAGE_KEY" \
    --container-name $CONTAINER_NAME \
    --prefix "backups/" \
    --query "sort_by([?properties.contentLength>0], &properties.lastModified)[-1].name" \
    --output tsv)

if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${RED}백업 파일을 찾을 수 없습니다!${NC}"
    exit 1
fi

echo "최신 백업: $LATEST_BACKUP"

# 백업 다운로드
echo "[2.2] 백업 파일 다운로드..."
BACKUP_FILE="$RESTORE_DIR/$(basename $LATEST_BACKUP)"

az storage blob download \
    --account-name $STORAGE_ACCOUNT \
    --account-key "$STORAGE_KEY" \
    --container-name $CONTAINER_NAME \
    --name "$LATEST_BACKUP" \
    --file "$BACKUP_FILE"

echo "다운로드 완료: $BACKUP_FILE ($(du -h $BACKUP_FILE | cut -f1))"

# =================================================
# Phase 3: 백업 복구 (10-30분, 크기에 따라)
# =================================================

echo -e "${YELLOW}[Phase 3/4] 데이터베이스 복구 중...${NC}"

# 압축 해제
echo "[3.1] 백업 파일 압축 해제..."
gunzip -f "$BACKUP_FILE"
SQL_FILE="${BACKUP_FILE%.gz}"

echo "압축 해제 완료: $SQL_FILE ($(du -h $SQL_FILE | cut -f1))"

# MySQL 클라이언트 설치 (필요시)
if ! command -v mysql &> /dev/null; then
    echo "[3.2] MySQL 클라이언트 설치..."
    apt-get update
    apt-get install -y mysql-client
fi

# MySQL 복구
echo "[3.3] MySQL 복구 실행..."
mysql \
    -h $MYSQL_HOST \
    -u $DB_USER \
    -p"$DB_PASSWORD" \
    < $SQL_FILE

echo "데이터베이스 복구 완료 ✓"

# =================================================
# Phase 4: 데이터 검증 (1분)
# =================================================

echo -e "${YELLOW}[Phase 4/4] 데이터 무결성 검증...${NC}"

# 테이블 목록 및 레코드 수 확인
echo "[4.1] 테이블 검증..."
mysql \
    -h $MYSQL_HOST \
    -u $DB_USER \
    -p"$DB_PASSWORD" \
    -D $DB_NAME \
    -e "
SELECT 
    'vets' AS table_name, COUNT(*) AS record_count FROM vets
UNION ALL
SELECT 'owners', COUNT(*) FROM owners
UNION ALL
SELECT 'pets', COUNT(*) FROM pets
UNION ALL
SELECT 'visits', COUNT(*) FROM visits;
"

# 샘플 데이터 조회
echo "[4.2] 샘플 데이터 확인..."
mysql \
    -h $MYSQL_HOST \
    -u $DB_USER \
    -p"$DB_PASSWORD" \
    -D $DB_NAME \
    -e "SELECT * FROM owners LIMIT 3;"

# =================================================
# 정리
# =================================================

echo "[5] 임시 파일 정리..."
rm -rf $RESTORE_DIR
echo "정리 완료"

# =================================================
# 완료 및 정보 출력
# =================================================

echo ""
echo -e "${GREEN}=========================================="
echo "데이터베이스 복구 완료!"
echo "종료 시간: $(date)"
echo "==========================================${NC}"
echo ""
echo "MySQL 접속 정보:"
echo "  Host: $MYSQL_HOST"
echo "  Database: $DB_NAME"
echo "  Username: $DB_USER"
echo "  Password: [입력한 비밀번호]"
echo ""
echo "JDBC URL:"
echo "  jdbc:mysql://$MYSQL_HOST:3306/$DB_NAME?useSSL=true&serverTimezone=Asia/Seoul"
echo ""
echo "다음 단계:"
echo "  1. PetClinic 배포: ./deploy-petclinic.sh"
echo ""
echo "로그 파일: $LOG_FILE"
echo ""

# 접속 정보를 파일로 저장
cat > /tmp/mysql-connection-info.txt <<EOF
MYSQL_HOST=$MYSQL_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
EOF

chmod 600 /tmp/mysql-connection-info.txt
echo "접속 정보 저장: /tmp/mysql-connection-info.txt"
