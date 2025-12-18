#!/bin/bash
# aws/scripts/backup-init.sh
# Plan B (Pilot Light): RDS → Azure Blob Storage 직접 백업
# S3 미사용 (AWS 리전 마비 시 접근 불가)

set -e

LOG_FILE="/var/log/backup-instance-init.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=========================================="
echo "백업 인스턴스 초기화 (Plan B - Pilot Light)"
echo "시작 시간: $(date)"
echo "=========================================="

# Terraform 변수
REGION="${region}"
RDS_ENDPOINT="${rds_endpoint}"
RDS_ADDRESS="${rds_address}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
AZURE_STORAGE_ACCOUNT="${azure_storage_account}"
AZURE_CONTAINER="${azure_container}"
SECRET_ARN="${secret_arn}"

echo "RDS Endpoint: $RDS_ENDPOINT"
echo "RDS Address: $RDS_ADDRESS"
echo "Database: $DB_NAME"
echo "Azure Storage: $AZURE_STORAGE_ACCOUNT"
echo "Azure Container: $AZURE_CONTAINER"
echo ""

# =================================================
# Phase 1: 시스템 업데이트 및 패키지 설치 (5분)
# =================================================

echo "[Phase 1/5] 시스템 업데이트 및 패키지 설치..."

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

apt-get install -y \
    mysql-client \
    awscli \
    jq \
    curl \
    gzip

echo "패키지 설치 완료"

# =================================================
# Phase 2: Azure CLI 설치 (3분)
# =================================================

echo "[Phase 2/5] Azure CLI 설치..."

curl -sL https://aka.ms/InstallAzureCLIDeb | bash

az --version

echo "Azure CLI 설치 완료"

# =================================================
# Phase 3: Secrets Manager에서 자격증명 로드 (1분)
# =================================================

echo "[Phase 3/5] Secrets Manager에서 자격증명 로드..."

SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id $SECRET_ARN \
    --region $REGION \
    --query SecretString \
    --output text)

export RDS_PASSWORD=$(echo $SECRET_JSON | jq -r '.rds_password')
export AZURE_STORAGE_KEY=$(echo $SECRET_JSON | jq -r '.azure_storage_key')
export AZURE_TENANT_ID=$(echo $SECRET_JSON | jq -r '.azure_tenant_id')
export AZURE_SUBSCRIPTION_ID=$(echo $SECRET_JSON | jq -r '.azure_subscription_id')

echo "자격증명 로드 완료"

# =================================================
# Phase 4: RDS 연결 테스트 (2분)
# =================================================

echo "[Phase 4/5] RDS 연결 테스트..."

RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
if [ -z "$RDS_HOST" ]; then
    RDS_HOST=$RDS_ADDRESS
fi

echo "RDS Host: $RDS_HOST"

MAX_RETRIES=5
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if mysql -h $RDS_HOST -u $DB_USERNAME -p"$RDS_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
        echo "RDS 연결 성공 ✓"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "RDS 연결 실패 (시도 $RETRY_COUNT/$MAX_RETRIES), 30초 후 재시도..."
        sleep 30
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "RDS 연결 실패 - 최대 재시도 횟수 초과"
    exit 1
fi

mysql -h $RDS_HOST -u $DB_USERNAME -p"$RDS_PASSWORD" -e "USE $DB_NAME;" || {
    echo "데이터베이스 '$DB_NAME' 생성..."
    mysql -h $RDS_HOST -u $DB_USERNAME -p"$RDS_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
}

# =================================================
# Phase 5: 백업 스크립트 생성 (2분)
# =================================================

echo "[Phase 5/5] 백업 스크립트 생성..."

mkdir -p /opt/mysql-backup
cd /opt/mysql-backup

cat > /usr/local/bin/mysql-backup-to-azure.sh <<'BACKUP_SCRIPT'
#!/bin/bash
# MySQL → Azure Blob Storage 백업 스크립트 (Plan B)
# S3 미사용 - Azure만 사용

set -e

LOG_FILE="/var/log/mysql-backup-to-azure.log"
exec >> $LOG_FILE 2>&1

echo "=========================================="
echo "백업 시작: $(date)"
echo "=========================================="

# 환경 변수
RDS_HOST=__RDS_HOST__
DB_NAME=__DB_NAME__
DB_USERNAME=__DB_USERNAME__
RDS_PASSWORD=__RDS_PASSWORD__
AZURE_STORAGE_ACCOUNT=__AZURE_STORAGE_ACCOUNT__
AZURE_STORAGE_KEY=__AZURE_STORAGE_KEY__
AZURE_CONTAINER=__AZURE_CONTAINER__

# 백업 파일명
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/opt/mysql-backup"
BACKUP_FILE="$BACKUP_DIR/backup-$TIMESTAMP.sql"
COMPRESSED_FILE="$BACKUP_FILE.gz"

# 1. MySQL Dump
echo "[1/3] MySQL Dump 실행..."
mysqldump \
    -h $RDS_HOST \
    -u $DB_USERNAME \
    -p"$RDS_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --databases $DB_NAME \
    > $BACKUP_FILE

BACKUP_SIZE=$(du -h $BACKUP_FILE | cut -f1)
echo "Dump 완료: $BACKUP_FILE ($BACKUP_SIZE)"

# 2. 압축
echo "[2/3] 파일 압축..."
gzip -f $BACKUP_FILE
COMPRESSED_SIZE=$(du -h $COMPRESSED_FILE | cut -f1)
echo "압축 완료: $COMPRESSED_FILE ($COMPRESSED_SIZE)"

# 3. Azure Blob Storage 업로드
echo "[3/3] Azure Blob Storage 업로드..."
az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --account-key "$AZURE_STORAGE_KEY" \
    --container-name $AZURE_CONTAINER \
    --name "backups/backup-$TIMESTAMP.sql.gz" \
    --file $COMPRESSED_FILE \
    --overwrite

echo "Azure 업로드 완료: backups/backup-$TIMESTAMP.sql.gz"
echo "[Note] S3 백업 생략 (Plan B - AWS 리전 독립)"

# 4. 로컬 정리 (24시간 이상된 파일)
echo "[4/4] 로컬 파일 정리..."
find $BACKUP_DIR -name "backup-*.sql.gz" -mtime +1 -delete
echo "로컬 정리 완료"

echo "백업 완료: $(date)"
echo "=========================================="
echo ""

BACKUP_SCRIPT

# 변수 치환
sed -i "s|__RDS_HOST__|$RDS_HOST|g" /usr/local/bin/mysql-backup-to-azure.sh
sed -i "s|__DB_NAME__|$DB_NAME|g" /usr/local/bin/mysql-backup-to-azure.sh
sed -i "s|__DB_USERNAME__|$DB_USERNAME|g" /usr/local/bin/mysql-backup-to-azure.sh
sed -i "s|__RDS_PASSWORD__|$RDS_PASSWORD|g" /usr/local/bin/mysql-backup-to-azure.sh
sed -i "s|__AZURE_STORAGE_ACCOUNT__|$AZURE_STORAGE_ACCOUNT|g" /usr/local/bin/mysql-backup-to-azure.sh
sed -i "s|__AZURE_STORAGE_KEY__|$AZURE_STORAGE_KEY|g" /usr/local/bin/mysql-backup-to-azure.sh
sed -i "s|__AZURE_CONTAINER__|$AZURE_CONTAINER|g" /usr/local/bin/mysql-backup-to-azure.sh

chmod +x /usr/local/bin/mysql-backup-to-azure.sh

echo "백업 스크립트 생성 완료"

# =================================================
# Cron 설정 (5분마다 백업)
# =================================================

echo "Cron 작업 등록..."

(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/mysql-backup-to-azure.sh") | crontab -

echo "Cron 설정 완료 (5분마다 실행)"

# =================================================
# 첫 백업 테스트
# =================================================

echo "첫 백업 테스트 실행..."
/usr/local/bin/mysql-backup-to-azure.sh

echo ""
echo "Azure Blob Storage 백업 확인:"
az storage blob list \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --account-key "$AZURE_STORAGE_KEY" \
    --container-name $AZURE_CONTAINER \
    --prefix "backups/" \
    --output table

echo ""
echo "=========================================="
echo "백업 인스턴스 초기화 완료!"
echo "종료 시간: $(date)"
echo "=========================================="
echo ""
echo "백업 설정:"
echo "  - 주기: 5분마다"
echo "  - 대상: $RDS_HOST ($DB_NAME)"
echo "  - 저장소: Azure Blob Storage ($AZURE_STORAGE_ACCOUNT/$AZURE_CONTAINER)"
echo "  - S3: 미사용 (Plan B)"
echo ""
echo "로그 확인:"
echo "  tail -f /var/log/mysql-backup-to-azure.log"
echo ""
