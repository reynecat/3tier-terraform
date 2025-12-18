# Plan B - Pilot Light DR Strategy

## 개요

**DR 전략:** Pilot Light (최소 대기)  
**비용:** $217/월 (Plan A 대비 64% 절감)  
**RTO:** 2-4시간 | **RPO:** 5분

## 아키텍처

```
평상시:
AWS (Primary) ────5분 백업───→ Azure (Storage만)
├── EKS + RDS                   └── Blob Storage
└── Backup Instance                 └── mysql-backups/

재해 시:
1. deploy-maintenance.sh (15분) → 점검 페이지
2. restore-db.sh (60분)         → MySQL 복구
3. deploy-app.sh (90분)         → PetClinic 배포
```

## 디렉토리 구조

```
reynecat-planB/
├── README.md              # 이 파일
├── aws/                   # AWS 백업 인프라
│   ├── backup-instance.tf
│   ├── variables.tf
│   ├── terraform.tfvars.example
│   └── scripts/
│       └── backup-init.sh
│
└── azure/                 # Azure DR 인프라
    ├── minimal-infra.tf
    ├── variables.tf
    ├── terraform.tfvars.example
    └── scripts/
        ├── deploy-maintenance.sh
        ├── restore-db.sh
        └── deploy-app.sh
```

## 빠른 시작


### 1단계: Azure Storage 배포

```bash
cd azure
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # 설정 입력

terraform init
terraform apply
```

필수 입력 항목:
- `subscription_id` - Azure 구독 ID
- `tenant_id` - Azure 테넌트 ID
- `storage_account_name` - 전역 고유 이름 (예: drbackuppetclinic2024)
- `ssh_public_key` - SSH 공개 키
- `db_password` - MySQL 비밀번호

### 2단계: Storage Key 확인

```bash
az storage account keys list \
  --account-name drbackuppetclinic2024 \
  --query "[0].value" -o tsv
```

### 3단계: AWS 백업 인스턴스 배포

```bash
cd ../aws
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Azure Storage 정보 입력

terraform init
terraform apply
```

필수 입력 항목:
- `azure_storage_account_name` - Azure Storage 이름
- `azure_storage_account_key` - Storage Key (3단계)
- `azure_tenant_id` - Azure 테넌트 ID
- `azure_subscription_id` - Azure 구독 ID
- `backup_instance_ssh_public_key` - SSH 공개 키

### 4단계: 백업 확인

```bash
# 백업 인스턴스 접속
aws ssm start-session --target $(terraform output -raw backup_instance_id)

# 백업 로그 확인
sudo tail -f /var/log/mysql-backup-to-azure.log

# Azure에서 백업 확인
az storage blob list \
  --account-name drbackuppetclinic2024 \
  --container-name mysql-backups \
  --output table
```

## 재해 대응 절차

### Phase 1: 점검 페이지 (T+0 ~ T+15분)

```bash
cd azure/scripts
./deploy-maintenance.sh
```

### Phase 2: DB 복구 (T+15 ~ T+75분)

```bash
./restore-db.sh
```

### Phase 3: 앱 배포 (T+75 ~ T+165분)

```bash
./deploy-app.sh
```

## 주요 명령어

```bash
# Azure Storage Key 확인
az storage account keys list --account-name <name> --query "[0].value" -o tsv

# 백업 인스턴스 접속
aws ssm start-session --target <instance-id>

# 백업 로그 실시간 확인
sudo tail -f /var/log/mysql-backup-to-azure.log

# 수동 백업 실행
sudo /usr/local/bin/mysql-backup-to-azure.sh

# Azure 백업 목록 확인
az storage blob list \
  --account-name <name> \
  --container-name mysql-backups \
  --output table
