 #!/bin/bash
# PlanB/azure/2-emergency/restore-db.sh
# MySQL 백업 복구 스크립트 (하드코딩 버전)

set -e

echo "=========================================="
echo "MySQL 백업 복구 (Plan B - Emergency)"
echo "시작 시간: $(date)"
echo "=========================================="

# ============================================
# 하드코딩 설정 (여기를 수정하세요)
# ============================================
MYSQL_HOST="mysql-dr-blue.mysql.database.azure.com"
RESOURCE_GROUP="rg-dr-blue"
STORAGE_ACCOUNT="bloberry01"
CONTAINER="mysql-backups"
DB_NAME="petclinic"
DB_USER="mysqladmin"
# ============================================

echo ""
echo "설정 정보:"
echo "  MySQL Host: $MYSQL_HOST"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo ""

# 비밀번호 입력
read -sp "MySQL Password: " DB_PASSWORD
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: 비밀번호가 입력되지 않았습니다."
    exit 1
fi

# MySQL 클라이언트 설치 확인
if ! command -v mysql &> /dev/null; then
    echo ""
    echo "MySQL 클라이언트가 설치되지 않았습니다."
    echo "설치 중..."
    sudo apt-get update
    sudo apt-get install -y mysql-client
fi

echo ""
echo "[1/4] 최신 백업 파일 찾기..."
LATEST_BACKUP=$(az storage blob list \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --prefix "backups/" \
    --query "sort_by([], &properties.lastModified)[-1].name" \
    --output tsv 2>/dev/null)

if [ -z "$LATEST_BACKUP" ]; then
    echo "ERROR: 백업 파일을 찾을 수 없습니다."
    exit 1
fi

echo "최신 백업: $LATEST_BACKUP"

echo ""
echo "[2/4] 백업 다운로드..."
RESTORE_DIR="/tmp/mysql-restore"
mkdir -p "$RESTORE_DIR"

az storage blob download \
    --account-name "$STORAGE_ACCOUNT" \
    --container-name "$CONTAINER" \
    --name "$LATEST_BACKUP" \
    --file "$RESTORE_DIR/backup.sql.gz" \
    --overwrite

echo ""
echo "[3/4] 압축 해제..."
gunzip -f "$RESTORE_DIR/backup.sql.gz"

echo ""
echo "[4/4] MySQL 복구..."
# Azure MySQL의 제약으로 stdin/pipe 리다이렉션 불가
# SQL을 파일에서 읽어 mysql에 전달
MYSQL_PWD="$DB_PASSWORD" mysql --batch \
      -h "$MYSQL_HOST" \
      -u "$DB_USER" \
      --ssl-mode=REQUIRED \
      2>/dev/null <<EOF
$(cat "$RESTORE_DIR/backup.sql")
EOF

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
echo "     mysql -h $MYSQL_HOST -u $DB_USER -p --ssl-mode=REQUIRED"
echo ""
echo "  2. 3단계 배포"
echo "     cd ../../3-failover && terraform apply"
echo ""

# 정리
rm -rf "$RESTORE_DIR"
