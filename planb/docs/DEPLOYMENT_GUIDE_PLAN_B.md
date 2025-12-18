# Plan B (Pilot Light) 배포 가이드

## 📋 목차

1. [사전 준비](#사전-준비)
2. [Azure 배포](#azure-배포)
3. [AWS 배포](#aws-배포)
4. [백업 검증](#백업-검증)
5. [재해 대응 훈련](#재해-대응-훈련)
6. [문제 해결](#문제-해결)

---

## 🎯 Plan B 개요

**전략:** Pilot Light (최소 리소스)
**목표:** 비용 최소화 + AWS 리전 독립
**RTO:** 2-4시간
**RPO:** 5분

### 평상시 구조
```
AWS:
├─ EKS (Primary)
├─ RDS (Primary)
└─ Backup EC2 Instance
    └─ mysqldump → Azure Blob (5분마다)

Azure:
└─ Blob Storage (백업만 저장)
```

### 재해 시 구조
```
Azure:
├─ Blob Storage (백업)
├─ MySQL (복구)
├─ WAS VM (Spring Boot)
├─ Web VM (Nginx)
└─ Application Gateway
```

---

## 사전 준비

### 1. 필수 도구 설치

#### Terraform
```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# 확인
terraform version
```

#### Azure CLI
```bash
# macOS
brew install azure-cli

# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 확인
az version
```

#### AWS CLI
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 확인
aws --version
```

### 2. 인증 설정

#### Azure 로그인
```bash
# Azure 로그인
az login

# 구독 확인
az account show

# 구독 ID와 Tenant ID 저장
az account show --query "{subscriptionId:id, tenantId:tenantId}" -o json
```

#### AWS 설정
```bash
# AWS 자격증명 설정
aws configure

# 입력:
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region name: ap-northeast-2
# Default output format: json
```

### 3. SSH 키 생성
```bash
# SSH 키 생성
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_dr_key -C "azure-dr-key"

# 공개 키 확인
cat ~/.ssh/azure_dr_key.pub
```

---

## Azure 배포

### 1단계: Storage Account 이름 결정

Storage Account 이름은 **전역에서 고유**해야 합니다.

```bash
# 규칙:
# - 소문자와 숫자만
# - 3-24자
# - 전역 고유

# 예시:
# drbackuppetclinic2024
# drbackup조직명202412
# drbackup본인이름2024
```

### 2단계: terraform.tfvars 작성

```bash
cd azure

# 예시 파일 복사
cp terraform-planb.tfvars.example terraform.tfvars

# 수정
nano terraform.tfvars
```

**수정 항목:**
```hcl
# 1. Storage Account 이름 (전역 고유)
storage_account_name = "drbackuppetclinic2024"

# 2. Azure 구독 정보
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
tenant_id       = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# 3. SSH 공개 키
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E... your-email@example.com"

# 4. DB 비밀번호
db_password = "MySecurePassword123!"
```

### 3단계: Azure 배포

```bash
# Terraform 초기화
terraform init

# Plan 확인 (Storage Account만 생성되는지 확인)
terraform plan

# 배포
terraform apply

# 확인
terraform output
```

**예상 출력:**
```
storage_account_name = "drbackuppetclinic2024"
storage_account_key = "xyz123abc..."
blob_container_url = "https://drbackuppetclinic2024.blob.core.windows.net/mysql-backups"
estimated_monthly_cost = "$12"
```

### 4단계: Storage 정보 저장

```bash
# Storage Account Key 저장
az storage account keys list \
  --account-name drbackuppetclinic2024 \
  --query "[0].value" -o tsv > storage_key.txt

# 안전하게 보관
chmod 600 storage_key.txt
```

---

## AWS 배포

### 1단계: terraform.tfvars 작성

```bash
cd aws

# 예시 파일 복사
cp terraform-planb.tfvars.example terraform.tfvars

# 수정
nano terraform.tfvars
```

**수정 항목:**
```hcl
# 1. Azure Storage 정보 (위에서 확인한 값)
azure_storage_account_name = "drbackuppetclinic2024"
azure_storage_account_key  = "xyz123abc..."  # storage_key.txt 내용
azure_backup_container_name = "mysql-backups"

# 2. Azure 구독 정보
azure_tenant_id       = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
azure_subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# 3. 백업 인스턴스 SSH 키
backup_instance_ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..."

# 4. 백업 활성화
enable_backup_instance = true
```

### 2단계: AWS 배포

```bash
# Terraform 초기화
terraform init

# Plan 확인
terraform plan -var-file=terraform.tfvars

# 배포 (백업 인스턴스만)
terraform apply -var-file=terraform.tfvars

# 확인
terraform output
```

**예상 출력:**
```
backup_instance_id = "i-0123456789abcdef"
backup_instance_private_ip = "10.0.21.45"
backup_status_command = "aws ssm start-session --target i-0123456789abcdef"
estimated_additional_cost = "$15/월"
```

---

## 백업 검증

### 1단계: 백업 인스턴스 접속

```bash
# SSM Session Manager로 접속
INSTANCE_ID=$(terraform output -raw backup_instance_id)
aws ssm start-session --target $INSTANCE_ID
```

### 2단계: 백업 로그 확인

```bash
# 로그 실시간 확인
sudo tail -f /var/log/mysql-backup-to-azure.log

# 최근 백업 확인
sudo tail -50 /var/log/mysql-backup-to-azure.log
```

**정상 출력 예시:**
```
[2024-12-17 10:00:01] Starting MySQL backup...
[2024-12-17 10:00:15] Dumping database: petclinic
[2024-12-17 10:01:30] Compressing backup...
[2024-12-17 10:02:00] Uploading to Azure Blob Storage...
[2024-12-17 10:03:45] Backup completed: petclinic-20241217-100001.sql.gz
[2024-12-17 10:03:46] Size: 45.2 MB
[2024-12-17 10:03:46] Next backup in 5 minutes
```

### 3단계: Azure Blob Storage 확인

```bash
# Azure CLI로 백업 파일 목록 확인
az storage blob list \
  --account-name drbackuppetclinic2024 \
  --container-name mysql-backups \
  --output table

# 최신 백업 확인
az storage blob list \
  --account-name drbackuppetclinic2024 \
  --container-name mysql-backups \
  --query "[?contains(name,'petclinic')] | sort_by(@, &properties.lastModified) | [-1]" \
  --output json
```

**정상 출력 예시:**
```
Name                                    Size    Content-Type    Last Modified
--------------------------------------  ------  --------------  --------------------------
petclinic-20241217-100001.sql.gz        47MB    application/gz  2024-12-17T10:03:45+00:00
petclinic-20241217-100501.sql.gz        47MB    application/gz  2024-12-17T10:08:45+00:00
petclinic-20241217-101001.sql.gz        47MB    application/gz  2024-12-17T10:13:45+00:00
```

### 4단계: Cron 작동 확인

```bash
# Cron 설정 확인
sudo crontab -l | grep mysql-backup

# 예상 출력:
# */5 * * * * /usr/local/bin/mysql-backup-to-azure.sh >> /var/log/mysql-backup-to-azure.log 2>&1
```

### 5단계: CloudWatch Alarm 확인

```bash
# CloudWatch Alarm 상태 확인
aws cloudwatch describe-alarms \
  --alarm-names "backup-instance-failures-prod" \
  --region ap-northeast-2

# Alarm이 정상(OK) 상태여야 함
```

---

## 재해 대응 훈련

### 시나리오: AWS 리전 전체 마비

#### Phase 1: 점검 페이지 배포 (15분)

```bash
cd azure/scripts

# 점검 페이지 배포
./deploy-maintenance.sh

# 진행 상황:
# [1/6] Public IP 생성... ✓
# [2/6] NSG 생성... ✓
# [3/6] NIC 생성... ✓
# [4/6] VM 생성... ✓
# [5/6] 점검 페이지 배포... ✓
# [6/6] Route53 Failover 설정... ✓
#
# 점검 페이지 URL: http://xxx.xxx.xxx.xxx
# 소요 시간: 약 15분
```

**검증:**
```bash
# 점검 페이지 접속 테스트
MAINTENANCE_IP=$(terraform output -raw maintenance_page_ip)
curl -I http://$MAINTENANCE_IP

# HTTP 200 OK 응답 확인
```

#### Phase 2: 데이터베이스 복구 (60분)

```bash
# DB 복구 스크립트 실행
./restore-database.sh

# 진행 상황:
# [1/7] Azure MySQL 생성... ✓ (15분)
# [2/7] 최신 백업 다운로드... ✓ (5분)
# [3/7] 압축 해제... ✓ (2분)
# [4/7] MySQL 복구... ✓ (30분)
# [5/7] 인덱스 재생성... ✓ (5분)
# [6/7] 무결성 검증... ✓ (3분)
# [7/7] 연결 테스트... ✓
#
# MySQL Endpoint: xxx.mysql.database.azure.com
# 소요 시간: 약 60분
```

**검증:**
```bash
# MySQL 접속 테스트
MYSQL_ENDPOINT=$(terraform output -raw mysql_endpoint)
mysql -h $MYSQL_ENDPOINT -u mysqladmin -p petclinic -e "SHOW TABLES;"

# 테이블 개수 확인
mysql -h $MYSQL_ENDPOINT -u mysqladmin -p petclinic -e "SELECT COUNT(*) FROM owners;"
```

#### Phase 3: 애플리케이션 배포 (90분)

```bash
# 앱 배포 스크립트 실행
./deploy-petclinic.sh

# 진행 상황:
# [1/8] WAS VM 생성... ✓ (10분)
# [2/8] Java 21 설치... ✓ (5분)
# [3/8] Spring Boot 다운로드... ✓ (5분)
# [4/8] DB 연결 설정... ✓
# [5/8] 앱 시작... ✓ (30분)
# [6/8] Web VM 생성... ✓ (10분)
# [7/8] Nginx 설정... ✓ (5분)
# [8/8] Health Check... ✓
#
# Application URL: http://xxx.xxx.xxx.xxx
# 소요 시간: 약 90분
```

**검증:**
```bash
# 앱 Health Check
APP_URL=$(terraform output -raw application_url)
curl -s http://$APP_URL/actuator/health | jq .

# 예상 출력:
# {
#   "status": "UP",
#   "components": {
#     "db": { "status": "UP" },
#     "diskSpace": { "status": "UP" }
#   }
# }

# 브라우저에서 접속 테스트
echo "접속: http://$APP_URL"
```

#### Phase 4: Route53 전환 (10분)

```bash
# Route53 Failover 설정
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch file://failover-to-azure.json

# DNS 전파 확인 (1-5분)
dig petclinic.example.com

# Azure IP로 응답하는지 확인
```

**전체 소요 시간:**
- Phase 1: 15분 (점검 페이지)
- Phase 2: 60분 (DB 복구)
- Phase 3: 90분 (앱 배포)
- Phase 4: 10분 (DNS 전환)
- **총 RTO: ~3시간**

---

## 문제 해결

### 백업 실패

**증상:**
```
[ERROR] Failed to connect to Azure Blob Storage
```

**해결:**
```bash
# 1. Azure 자격증명 확인
aws secretsmanager get-secret-value \
  --secret-id azure-backup-credentials \
  --region ap-northeast-2

# 2. 네트워크 연결 확인
curl -I https://drbackuppetclinic2024.blob.core.windows.net

# 3. Storage Account Key 재생성
az storage account keys renew \
  --account-name drbackuppetclinic2024 \
  --key primary

# 4. Secrets Manager 업데이트
aws secretsmanager update-secret \
  --secret-id azure-backup-credentials \
  --secret-string "{\"storage_key\":\"NEW_KEY\"}"

# 5. 백업 인스턴스 재시작
aws ec2 reboot-instances --instance-ids $INSTANCE_ID
```

### Storage Account 이름 중복

**증상:**
```
Error: Storage account name 'drbackuppetclinic2024' is already taken
```

**해결:**
```bash
# 다른 이름으로 변경
# terraform.tfvars 수정:
storage_account_name = "drbackuppetclinic20241217"  # 날짜 추가

# 또는
storage_account_name = "drbackup본인이름2024"  # 본인 이름 추가
```

### MySQL 복구 실패

**증상:**
```
[ERROR] Cannot import backup: Invalid data format
```

**해결:**
```bash
# 1. 백업 파일 무결성 확인
az storage blob download \
  --account-name drbackuppetclinic2024 \
  --container-name mysql-backups \
  --name petclinic-latest.sql.gz \
  --file test-backup.sql.gz

# 2. 압축 해제 테스트
gunzip -t test-backup.sql.gz

# 3. MySQL 버전 확인
mysql --version  # Azure MySQL과 동일한지 확인

# 4. 다른 백업 파일로 재시도
az storage blob list \
  --account-name drbackuppetclinic2024 \
  --container-name mysql-backups \
  --output table
```

---

## 비용 분석

### 평상시 비용

**AWS ($205/월):**
- EKS Control Plane: $73
- EKS Nodes: $60
- RDS Multi-AZ: $85
- NAT Gateway: $32
- Backup Instance: $15
- 네트워크: $20

**Azure ($12/월):**
- Blob Storage (100GB): $2
- 네트워크 Ingress: $0 (무료)
- 트랜잭션: $10

**총: $217/월**

### 재해 발생 시 추가 비용

**Azure 추가 ($5/시간):**
- VM 2대: $3/시간
- MySQL: $1/시간
- 네트워크: $1/시간

**4시간 재해 대응:**
- 추가 비용: $20

**월 1회 DR 훈련:**
- 훈련 비용: $20/월

**실제 연간 비용:**
- 평상시: $217 × 12 = $2,604
- DR 훈련: $20 × 12 = $240
- **총: $2,844/년**

---

## 다음 단계

1. **정기 백업 모니터링**
   - 매일 Azure Blob 확인
   - CloudWatch Alarm 설정
   - 백업 크기 추이 관찰

2. **월 1회 DR 훈련**
   - 점검 페이지 배포 테스트
   - DB 복구 테스트
   - 전체 시나리오 실행

3. **Runbook 업데이트**
   - 절차 개선사항 문서화
   - 소요 시간 기록
   - 문제 해결 방법 추가

4. **비용 최적화**
   - Storage Lifecycle Policy 확인
   - 불필요한 백업 삭제
   - 복제 타입 검토 (LRS vs GRS)

---

## 참고 문서

- [PLAN_A_VS_B_COMPARISON.md](../PLAN_A_VS_B_COMPARISON.md) - Plan A/B 비교
- [S3_REMOVAL_SUMMARY.md](../S3_REMOVAL_SUMMARY.md) - S3 제거 요약
- [runbooks/emergency-response.md](../runbooks/emergency-response.md) - 긴급 대응 절차
- [DR_PLAN_B_README.md](../DR_PLAN_B_README.md) - Plan B 개요

---

## 결론

Plan B (Pilot Light)는:
- ✓ 매우 저렴 ($217/월, 64% 절감)
- ✓ AWS 완전 독립
- ✓ 간단한 구조
- ✓ 교육용으로 최적

**배포를 시작하세요! 🚀**
