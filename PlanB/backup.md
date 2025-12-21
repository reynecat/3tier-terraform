명령어 구문에 문제가 있어. MySQL 클라이언트가 호스트 이름을 잘못 인식하고 있어.

## 문제 원인

`-p` 옵션 뒤에 바로 비밀번호를 붙여야 하는데, 공백이 있거나 환경변수가 제대로 설정되지 않았을 수 있어.

## 해결 방법

### 1단계: 환경변수 재설정

```bash
# RDS 엔드포인트 확인 (로컬 터미널에서)
cd ~/3tier-terraform/PlanB/aws
terraform output rds_address
```

**백업 인스턴스에 접속해서:**

```bash
# SSM으로 접속
aws ssm start-session --target i-0155f8568e2ed335d
```

**백업 인스턴스 내부에서:**

```bash
# RDS 정보 수동 설정
export RDS_HOST="blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com"
export DB_USERNAME="admin"
export DB_PASSWORD="byemyblue"

echo "RDS Host: $RDS_HOST"
echo "DB Username: $DB_USERNAME"
```

### 2단계: MySQL 연결 테스트 (여러 방법)

**방법 1: 비밀번호를 직접 붙여서 입력**
```bash
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;"
```

**방법 2: 비밀번호 프롬프트 사용**
```bash
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p
# Enter password: byemyblue
```

**방법 3: 변수 없이 직접 입력**
```bash
mysql -h blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com -u admin -pbyemyblue -e "SELECT 1;"
```

**방법 4: 설정 파일 사용**
```bash
# MySQL 설정 파일 생성
cat > ~/.my.cnf <<EOF
[client]
host=blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com
user=admin
password=byemyblue
EOF

chmod 600 ~/.my.cnf

# 간단하게 연결
mysql -e "SELECT 1;"
```

### 3단계: 연결 성공 후 데이터베이스 확인

```bash
# 데이터베이스 목록
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SHOW DATABASES;"

# petclinic 데이터베이스 확인
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "USE petclinic; SHOW TABLES;"
```

### 4단계: 백업 스크립트 생성 (연결 성공 후)

```bash
# Secrets Manager에서 Azure 자격증명 가져오기
export REGION="ap-northeast-2"

# Secret ARN 찾기
export SECRET_ARN=$(aws secretsmanager list-secrets \
    --region $REGION \
    --query "SecretList[?contains(Name, 'backup-credentials-blue')].ARN | [0]" \
    --output text)

echo "Secret ARN: $SECRET_ARN"

# Secret 내용 가져오기
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --region $REGION \
    --query SecretString \
    --output text)

# Azure 자격증명 추출
export AZURE_STORAGE_ACCOUNT=$(echo $SECRET_JSON | jq -r '.azure_storage_account')
export AZURE_STORAGE_KEY=$(echo $SECRET_JSON | jq -r '.azure_storage_key')
export AZURE_CONTAINER="mysql-backups"

echo "Azure Storage Account: $AZURE_STORAGE_ACCOUNT"
```

### 5단계: 백업 스크립트 생성

```bash
# 디렉토리 생성
sudo mkdir -p /opt/mysql-backup

# 백업 스크립트 생성
sudo tee /usr/local/bin/mysql-backup-to-azure.sh > /dev/null <<'SCRIPT_EOF'
#!/bin/bash
# MySQL → Azure Blob Storage 백업 스크립트

set -e

LOG_FILE="/var/log/mysql-backup-to-azure.log"
exec >> $LOG_FILE 2>&1

echo "=========================================="
echo "백업 시작: $(date)"
echo "=========================================="

# 환경 변수
RDS_HOST="blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com"
DB_NAME="petclinic"
DB_USERNAME="admin"
DB_PASSWORD="byemyblue"
AZURE_STORAGE_ACCOUNT="bloberry01"
AZURE_STORAGE_KEY="AZURE_KEY_HERE"
AZURE_CONTAINER="mysql-backups"

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
    -p"$DB_PASSWORD" \
    --single-transaction \
    --skip-lock-tables \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \
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

# 4. 로컬 정리
echo "[4/4] 로컬 파일 정리..."
find $BACKUP_DIR -name "backup-*.sql.gz" -mtime +1 -delete
echo "로컬 정리 완료"

echo "백업 완료: $(date)"
echo "=========================================="
echo ""
SCRIPT_EOF

# Azure Storage Key를 실제 값으로 치환
sudo sed -i "s|YOUR_AZURE_STORAGE_KEY|$AZURE_STORAGE_KEY|g" /usr/local/bin/mysql-backup-to-azure.sh

# 실행 권한 부여
sudo chmod +x /usr/local/bin/mysql-backup-to-azure.sh
```

### 6단계: 첫 백업 테스트

```bash
# 백업 스크립트 실행
sudo /usr/local/bin/mysql-backup-to-azure.sh

# 로그 확인
sudo tail -f /var/log/mysql-backup-to-azure.log

udo tail -f /var/log/mysql-backup-to-azure.log
  "request_server_encrypted": true,
  "version": "2022-11-02",
  "version_id": "2025-12-21T21:03:17.5406732Z"
}
Azure 업로드 완료: backups/backup-20251221-210314.sql.gz
[4/4] 로컬 파일 정리...
로컬 정리 완료
백업 완료: Sun Dec 21 21:03:18 UTC 2025
```

### 7단계: Cron 설정

```bash
# 5분마다 백업 (테스트)
echo "*/5 * * * * /usr/local/bin/mysql-backup-to-azure.sh" | sudo crontab -

# Cron 확인
sudo crontab -l
```

### 8단계: Azure Blob Storage 백업 확인

**로컬 터미널에서:**

```bash
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --output table
```

## 트러블슈팅

만약 계속 연결이 안된다면:

```bash
# 포트 연결 테스트
nc -zv $RDS_HOST 3306

# DNS 조회
nslookup $RDS_HOST

# 보안 그룹 재확인 (로컬 터미널)
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`3306`]'
```
