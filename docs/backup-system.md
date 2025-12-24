# 백업 시스템 아키텍처 (Plan B - Pilot Light)

## 목차
- [개요](#개요)
- [아키텍처 다이어그램](#아키텍처-다이어그램)
- [백업 프로세스](#백업-프로세스)
- [보안 및 인증](#보안-및-인증)
- [Azure Blob Storage 설정](#azure-blob-storage-설정)
- [백업 스케줄 관리](#백업-스케줄-관리)
- [모니터링 및 로그](#모니터링-및-로그)
- [복구 절차](#복구-절차)
- [트러블슈팅](#트러블슈팅)

---

## 개요

### 목적
AWS RDS 데이터를 Azure Blob Storage로 직접 백업하여 AWS 리전 장애 시에도 데이터 복구가 가능하도록 합니다.

### 핵심 특징
- **리전 독립성**: AWS S3를 사용하지 않고 Azure Blob Storage로 직접 백업
- **자동화**: Cron 스케줄에 따라 자동 백업 실행
- **보안**: AWS Secrets Manager를 통한 자격증명 관리
- **비용 효율**: EC2 t3.small 인스턴스만 사용 (~$15/월)
- **라이프사이클 관리**: 30일 후 자동 삭제

### 구성 요소
1. **백업 인스턴스** (EC2 t3.small)
2. **AWS Secrets Manager** (자격증명 저장)
3. **Azure Blob Storage** (백업 저장소)
4. **CloudWatch Alarms** (상태 모니터링)

---

## 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS 환경                                 │
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │  RDS MySQL       │      │ Secrets Manager  │                 │
│  │  (Primary DB)    │      │                  │                 │
│  │                  │      │  - RDS Password  │                 │
│  │  Port: 3306      │      │  - Azure Keys    │                 │
│  └────────┬─────────┘      └────────┬─────────┘                 │
│           │                         │                            │
│           │ mysqldump               │ IAM Role                   │
│           │                         │                            │
│  ┌────────▼─────────────────────────▼─────────┐                 │
│  │   백업 인스턴스 (EC2 t3.small)              │                 │
│  │                                             │                 │
│  │  1. Secrets Manager에서 자격증명 로드        │                 │
│  │  2. mysqldump로 RDS 덤프                   │                 │
│  │  3. gzip 압축                              │                 │
│  │  4. az storage blob upload                 │                 │
│  │                                             │                 │
│  │  Cron: */5 * * * * (테스트)                │                 │
│  │        0 3 * * *   (운영)                  │                 │
│  └────────────────────┬────────────────────────┘                 │
│                       │                                          │
└───────────────────────┼──────────────────────────────────────────┘
                        │
                        │ HTTPS (Azure REST API)
                        │ + Storage Account Key 인증
                        │
┌───────────────────────▼──────────────────────────────────────────┐
│                        Azure 환경                                 │
│                                                                   │
│  ┌──────────────────────────────────────────────────────┐        │
│  │  Storage Account (bloberry01)                        │        │
│  │                                                       │        │
│  │  ┌────────────────────────────────────────────┐      │        │
│  │  │ Container: mysql-backups (private)         │      │        │
│  │  │                                             │      │        │
│  │  │  backups/                                   │      │        │
│  │  │  ├── backup-20251224-030000.sql.gz         │      │        │
│  │  │  ├── backup-20251224-030500.sql.gz         │      │        │
│  │  │  └── backup-20251224-031000.sql.gz         │      │        │
│  │  │                                             │      │        │
│  │  │  접근 제어: Private (Storage Key 필요)      │      │        │
│  │  └────────────────────────────────────────────┘      │        │
│  │                                                       │        │
│  │  Lifecycle Policy: 30일 후 자동 삭제                  │        │
│  └──────────────────────────────────────────────────────┘        │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## 백업 프로세스

### 1. 초기화 단계 (EC2 인스턴스 시작 시)

**파일**: `codes/aws/service/scripts/backup-init.sh`

```bash
# Phase 1: 패키지 설치
apt-get install -y mysql-client awscli jq curl gzip

# Phase 2: Azure CLI 설치
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Phase 3: Secrets Manager에서 자격증명 로드
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id $SECRET_ARN \
    --region $REGION \
    --query SecretString \
    --output text)

export RDS_PASSWORD=$(echo $SECRET_JSON | jq -r '.rds_password')
export AZURE_STORAGE_KEY=$(echo $SECRET_JSON | jq -r '.azure_storage_key')

# Phase 4: RDS 연결 테스트
mysql -h $RDS_HOST -u $DB_USERNAME -p"$RDS_PASSWORD" -e "SELECT 1;"

# Phase 5: 백업 스크립트 생성 및 Cron 등록
cat > /usr/local/bin/mysql-backup-to-azure.sh <<'SCRIPT'
  [백업 로직]
SCRIPT

crontab -e
```

### 2. 백업 실행 단계 (Cron 스케줄)

**파일**: `codes/aws/service/scripts/backup-init.sh` (131-204줄)

```bash
#!/bin/bash
# /usr/local/bin/mysql-backup-to-azure.sh

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Step 1: MySQL Dump
mysqldump \
    -h $RDS_HOST \
    -u $DB_USERNAME \
    -p"$RDS_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --databases $DB_NAME \
    > /opt/mysql-backup/backup-$TIMESTAMP.sql

# Step 2: 압축
gzip -f /opt/mysql-backup/backup-$TIMESTAMP.sql

# Step 3: Azure Blob Storage 업로드
az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --account-key "$AZURE_STORAGE_KEY" \
    --container-name $AZURE_CONTAINER \
    --name "backups/backup-$TIMESTAMP.sql.gz" \
    --file /opt/mysql-backup/backup-$TIMESTAMP.sql.gz \
    --overwrite

# Step 4: 로컬 정리 (24시간 이상된 파일 삭제)
find /opt/mysql-backup -name "backup-*.sql.gz" -mtime +1 -delete
```

### 3. 백업 파일 위치 지정

Azure CLI는 **4가지 파라미터**로 정확한 Blob Storage 위치를 특정합니다:

```bash
az storage blob upload \
    --account-name bloberry01 \              # 1. 스토리지 계정 이름
    --account-key "xxxxxxxxxxxx" \           # 2. Access Key (인증)
    --container-name mysql-backups \         # 3. 컨테이너 이름
    --name "backups/backup-20251224.sql.gz"  # 4. Blob 경로 + 파일명
```

**계층 구조**:
```
Azure Storage Account (bloberry01)
└── Container (mysql-backups) [private]
    └── Blob Path (backups/)
        ├── backup-20251224-030000.sql.gz
        ├── backup-20251224-030500.sql.gz
        └── backup-20251224-031000.sql.gz
```

---

## 보안 및 인증

### AWS Secrets Manager 구조

**파일**: `codes/aws/service/backup-instance.tf` (223-250줄)

```hcl
resource "aws_secretsmanager_secret" "backup_credentials" {
  name        = "backup-credentials-${var.environment}"
  description = "Credentials for RDS and Azure Blob Storage backup"
}

resource "aws_secretsmanager_secret_version" "backup_credentials" {
  secret_id = aws_secretsmanager_secret.backup_credentials.id

  secret_string = jsonencode({
    rds_password          = var.db_password
    azure_storage_account = var.azure_storage_account_name
    azure_storage_key     = var.azure_storage_account_key
    azure_tenant_id       = var.azure_tenant_id
    azure_subscription_id = var.azure_subscription_id
  })
}
```

### 저장된 자격증명 항목

| 키 이름 | 용도 | 사용 위치 |
|---------|------|-----------|
| `rds_password` | RDS MySQL 접속 비밀번호 | mysqldump 실행 시 |
| `azure_storage_account` | Azure Storage Account 이름 | az storage blob upload |
| `azure_storage_key` | Azure Storage Access Key | az storage blob upload (인증) |
| `azure_tenant_id` | Azure Tenant ID | (향후 확장용) |
| `azure_subscription_id` | Azure Subscription ID | (향후 확장용) |

### IAM 권한 구조

**파일**: `codes/aws/service/backup-instance.tf` (51-76줄)

```hcl
resource "aws_iam_role_policy" "backup_instance" {
  name = "backup-instance-policy"
  role = aws_iam_role.backup_instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets",
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### 자격증명 로드 프로세스

```bash
# 1. EC2 인스턴스의 IAM Role로 Secrets Manager 접근
aws secretsmanager get-secret-value \
    --secret-id backup-credentials-prod \
    --region ap-northeast-2

# 2. JSON 파싱
RDS_PASSWORD=$(echo $SECRET_JSON | jq -r '.rds_password')
AZURE_STORAGE_KEY=$(echo $SECRET_JSON | jq -r '.azure_storage_key')

# 3. 환경 변수로 백업 스크립트에 주입
# (스크립트 파일에 직접 저장되므로 보안 주의 필요)
```

**보안 주의사항**:
- 백업 스크립트 파일(`/usr/local/bin/mysql-backup-to-azure.sh`)에 비밀번호가 평문으로 저장됨
- 파일 권한: `chmod 700` (root만 읽기/실행 가능)
- 프로덕션 환경에서는 더 안전한 방법 권장 (예: 매번 Secrets Manager 호출)

---

## Azure Blob Storage 설정

### Storage Account 구성

**파일**: `codes/azure/1-always/main.tf` (93-112줄)

```hcl
resource "azurerm_storage_account" "backups" {
  name                     = var.storage_account_name  # 예: bloberry01
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type  # LRS, GRS 등

  https_traffic_only_enabled = false

  # Static Website 기능 (점검 페이지용)
  static_website {
    index_document = "index.html"
  }

  blob_properties {
    versioning_enabled = true  # 버전 관리
  }

  tags = var.tags
}
```

### 백업 컨테이너 (Private)

**파일**: `codes/azure/1-always/main.tf` (115-119줄)

```hcl
resource "azurerm_storage_container" "mysql_backups" {
  name                  = var.backup_container_name  # 예: mysql-backups
  storage_account_name  = azurerm_storage_account.backups.name
  container_access_type = "private"  # 🔒 비공개 설정
}
```

### 접근 제어 방식

| 컨테이너 | Access Type | 접근 방법 | 용도 |
|----------|-------------|-----------|------|
| `mysql-backups` | `private` | Storage Account Key 필요 | MySQL 백업 파일 저장 |
| `$web` | `public` (Static Website) | 인터넷에서 직접 접근 가능 | DR 점검 페이지 |

**중요**: 백업 컨테이너는 **완전히 비공개**이므로 Storage Account Key 없이는 접근 불가능합니다.

### Lifecycle Management (자동 삭제)

**파일**: `codes/azure/1-always/main.tf` (128-146줄)

```hcl
resource "azurerm_storage_management_policy" "backup_lifecycle" {
  storage_account_id = azurerm_storage_account.backups.id

  rule {
    name    = "deleteOldBackups"
    enabled = true

    filters {
      prefix_match = ["mysql-backups/backups/"]  # 백업 경로만 적용
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30  # 30일 후 삭제
      }
    }
  }
}
```

**효과**: 30일이 지난 백업 파일은 자동으로 삭제되어 스토리지 비용 절감

---

## 백업 스케줄 관리

### Cron 스케줄 설정

**파일**: `codes/aws/service/backup-instance.tf` (8-18줄)

```hcl
variable "backup_schedule_cron" {
  description = "백업 주기 (Cron 형식)"
  type        = string
  default     = "*/5 * * * *"  # 테스트용: 5분마다

  # 사용 예시:
  # - 하루 1회 (실제 운영): "0 3 * * *"     # UTC 오전 3시
  # - 5분마다 (테스트):     "*/5 * * * *"
  # - 1시간마다:            "0 * * * *"
  # - 6시간마다:            "0 */6 * * *"
}
```

### Cron 스케줄 변경 방법

#### 1. terraform.tfvars 수정

```hcl
# codes/aws/service/terraform.tfvars
backup_schedule_cron = "0 3 * * *"  # 하루 1회 (UTC 오전 3시)
```

#### 2. Terraform 적용

```bash
cd codes/aws/service
terraform plan
terraform apply
```

**주의**: `user_data` 변경 시 EC2 인스턴스가 재시작됩니다.

#### 3. 수동으로 Cron 변경 (즉시 적용)

```bash
# SSM Session Manager로 접속
aws ssm start-session --target <instance-id>

# Cron 편집
sudo crontab -e

# 예: 하루 1회로 변경
0 3 * * * /usr/local/bin/mysql-backup-to-azure.sh

# 확인
sudo crontab -l
```

### 백업 시간대 권장사항

| 환경 | Cron 스케줄 | 설명 |
|------|------------|------|
| 테스트 | `*/5 * * * *` | 5분마다 (빠른 검증) |
| 개발 | `0 */6 * * *` | 6시간마다 |
| 운영 | `0 3 * * *` | 하루 1회 (UTC 오전 3시) |
| 운영 (한국시간 기준) | `0 18 * * *` | 하루 1회 (UTC 오후 6시 = KST 오전 3시) |

---

## 모니터링 및 로그

### CloudWatch Alarms

**파일**: `codes/aws/service/backup-instance.tf` (256-276줄)

```hcl
resource "aws_cloudwatch_metric_alarm" "backup_instance_status" {
  alarm_name          = "backup-instance-status-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "백업 인스턴스 상태 체크 실패"

  dimensions = {
    InstanceId = aws_instance.backup_instance.id
  }
}
```

### 로그 파일 위치

| 로그 파일 | 용도 | 위치 |
|-----------|------|------|
| `/var/log/backup-instance-init.log` | 초기화 로그 | EC2 인스턴스 |
| `/var/log/mysql-backup-to-azure.log` | 백업 실행 로그 | EC2 인스턴스 |

### 로그 확인 방법

```bash
# SSM Session Manager로 접속
aws ssm start-session --target <instance-id>

# 실시간 백업 로그 모니터링
sudo tail -f /var/log/mysql-backup-to-azure.log

# 초기화 로그 확인
sudo cat /var/log/backup-instance-init.log

# Cron 작업 확인
sudo crontab -l
```

### 백업 로그 예시

```
==========================================
백업 시작: Tue Dec 24 03:00:00 UTC 2024
==========================================
[1/3] MySQL Dump 실행...
Dump 완료: /opt/mysql-backup/backup-20241224-030000.sql (2.5M)
[2/3] 파일 압축...
압축 완료: /opt/mysql-backup/backup-20241224-030000.sql.gz (512K)
[3/3] Azure Blob Storage 업로드...
Azure 업로드 완료: backups/backup-20241224-030000.sql.gz
[Note] S3 백업 생략 (Plan B - AWS 리전 독립)
[4/4] 로컬 파일 정리...
로컬 정리 완료
백업 완료: Tue Dec 24 03:00:15 UTC 2024
==========================================
```

### Azure Blob Storage 백업 확인

```bash
# Azure CLI로 백업 목록 확인
az storage blob list \
  --account-name bloberry01 \
  --account-key "xxxxxxxxxxxx" \
  --container-name mysql-backups \
  --prefix "backups/" \
  --output table

# 특정 백업 파일 다운로드
az storage blob download \
  --account-name bloberry01 \
  --account-key "xxxxxxxxxxxx" \
  --container-name mysql-backups \
  --name "backups/backup-20241224-030000.sql.gz" \
  --file ./backup-20241224-030000.sql.gz
```

---

## 복구 절차

### 1. Azure에서 백업 파일 다운로드

```bash
# 최신 백업 파일 확인
az storage blob list \
  --account-name bloberry01 \
  --account-key "xxxxxxxxxxxx" \
  --container-name mysql-backups \
  --prefix "backups/" \
  --output table \
  --query "sort_by([].{Name:name, LastModified:properties.lastModified}, &LastModified)" \
  | tail -5

# 최신 백업 다운로드
az storage blob download \
  --account-name bloberry01 \
  --account-key "xxxxxxxxxxxx" \
  --container-name mysql-backups \
  --name "backups/backup-20241224-030000.sql.gz" \
  --file ./backup.sql.gz
```

### 2. 백업 파일 압축 해제

```bash
gunzip backup.sql.gz
```

### 3. MySQL에 복구

```bash
# Azure MySQL Flexible Server에 복구
mysql -h <azure-mysql-host> \
      -u <username> \
      -p<password> \
      < backup.sql
```

### 4. 자동 복구 스크립트

**파일**: `codes/azure/2-failover/restore-db.sh`

```bash
#!/bin/bash
# Azure DR 사이트에서 백업 복구

MYSQL_HOST="your-mysql-server.mysql.database.azure.com"
MYSQL_USER="mysqladmin"
MYSQL_PASS="your-password"
STORAGE_ACCOUNT="bloberry01"
CONTAINER="mysql-backups"

# 최신 백업 다운로드
LATEST_BACKUP=$(az storage blob list \
  --account-name $STORAGE_ACCOUNT \
  --container-name $CONTAINER \
  --prefix "backups/" \
  --output tsv \
  --query "sort_by([].name, &lastModified)[-1]")

az storage blob download \
  --account-name $STORAGE_ACCOUNT \
  --container-name $CONTAINER \
  --name "$LATEST_BACKUP" \
  --file backup.sql.gz

# 복구
gunzip backup.sql.gz
mysql -h $MYSQL_HOST -u $MYSQL_USER -p$MYSQL_PASS < backup.sql
```

---

## 트러블슈팅

### 1. 백업이 실행되지 않음

**증상**: Cron 작업이 실행되지 않음

**확인 사항**:
```bash
# Cron 작업 확인
sudo crontab -l

# Cron 서비스 상태
sudo systemctl status cron

# 수동 실행 테스트
sudo /usr/local/bin/mysql-backup-to-azure.sh
```

**해결 방법**:
```bash
# Cron 재시작
sudo systemctl restart cron

# 스크립트 실행 권한 확인
sudo chmod +x /usr/local/bin/mysql-backup-to-azure.sh
```

### 2. RDS 연결 실패

**증상**: `ERROR 2003 (HY000): Can't connect to MySQL server`

**확인 사항**:
```bash
# Security Group 확인
aws ec2 describe-security-groups \
  --group-ids <backup-instance-sg-id>

# RDS Security Group Inbound 규칙 확인
aws ec2 describe-security-groups \
  --group-ids <rds-sg-id>

# 네트워크 연결 테스트
telnet <rds-endpoint> 3306
```

**해결 방법**:
- RDS Security Group에 백업 인스턴스 Security Group 허용 추가
- VPC 서브넷 라우팅 확인

### 3. Azure 업로드 실패

**증상**: `AuthenticationFailed: Server failed to authenticate the request`

**확인 사항**:
```bash
# Azure Storage Key 확인
az storage account keys list \
  --account-name bloberry01 \
  --resource-group rg-dr-prod

# Secrets Manager에 저장된 키 확인
aws secretsmanager get-secret-value \
  --secret-id backup-credentials-prod \
  --query SecretString \
  --output text | jq -r '.azure_storage_key'
```

**해결 방법**:
```bash
# Secrets Manager 업데이트
aws secretsmanager put-secret-value \
  --secret-id backup-credentials-prod \
  --secret-string '{"azure_storage_key":"new-key-value",...}'

# EC2 인스턴스 재시작 (user_data 재실행)
aws ec2 reboot-instances --instance-ids <instance-id>
```

### 4. 디스크 용량 부족

**증상**: `No space left on device`

**확인 사항**:
```bash
# 디스크 사용량 확인
df -h

# 백업 디렉토리 크기
du -sh /opt/mysql-backup/*
```

**해결 방법**:
```bash
# 오래된 백업 파일 수동 삭제
sudo find /opt/mysql-backup -name "backup-*.sql.gz" -mtime +1 -delete

# EBS 볼륨 확장 (Terraform)
# codes/aws/service/backup-instance.tf
root_block_device {
  volume_size = 50  # 30GB -> 50GB
}
```

### 5. Secrets Manager 권한 오류

**증상**: `AccessDeniedException: User is not authorized to perform: secretsmanager:GetSecretValue`

**확인 사항**:
```bash
# IAM Role 확인
aws iam get-role --role-name backup-instance-role-prod

# IAM Policy 확인
aws iam list-role-policies --role-name backup-instance-role-prod
```

**해결 방법**:
- IAM Role에 Secrets Manager 권한 추가 (Terraform에서 자동 설정됨)
- EC2 인스턴스에 올바른 IAM Instance Profile이 연결되었는지 확인

---

## 참고 문서

- [DR Failover 절차](dr-failover-procedure.md)
- [아키텍처 문서](architecture.md)
- [모니터링 가이드](MONITORING.md)
- [트러블슈팅](troubleshooting.md)
