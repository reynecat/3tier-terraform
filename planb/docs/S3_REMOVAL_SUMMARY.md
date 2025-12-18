# S3 제거 완료 - Plan A & Plan B 최종 정리

## 변경 사유

### S3가 불필요한 이유

1. **AWS 리전 종속성**
   - S3는 AWS 리전별 서비스
   - AWS 리전 전체 마비 시 S3도 접근 불가
   - DR 목적과 상충

2. **Plan A: DMS 실시간 복제**
   - RDS → Azure MySQL 직접 복제
   - Azure에 항상 최신 복제본 유지
   - S3 백업 불필요

3. **Plan B: Azure Blob Storage**
   - AWS 독립적인 백업 저장소
   - Azure 리전에 저장
   - AWS 마비 시에도 접근 가능

## 변경 사항

### Plan A (Warm Standby)

#### 제거된 리소스

```terraform
# aws/main.tf에서 제거
resource "aws_s3_bucket" "backup" { ... }                              # 제거
resource "aws_s3_bucket_versioning" "backup" { ... }                   # 제거
resource "aws_s3_bucket_server_side_encryption_configuration" { ... } # 제거
```

#### 새로운 아키텍처

```
AWS RDS (Primary)
    │
    │ DMS (실시간 복제)
    │ VPN Tunnel
    │ RPO: ~1분
    ▼
Azure MySQL (Replica)
    ├─ 항상 최신 상태
    ├─ 즉시 Failover 가능
    └─ S3 불필요
```

#### 수정된 파일

- ✓ `aws/main-planA.tf` - S3 버킷 제거
- ✓ `aws/dms-planA.tf` - S3 로깅 제거
- ✓ `aws/outputs-planA.tf` - S3 출력 제거, 백업 전략 명시

#### 비용 변화

```
기존: $421/월 (AWS) + $200/월 (Azure) = $621/월
변경: $401/월 (AWS) + $196/월 (Azure) = $597/월
절감: $24/월 (S3 + 관련 전송 비용)
```

### Plan B (Pilot Light)

#### 제거된 리소스

```terraform
# aws/backup-instance.tf에서 제거
policy {
  "s3:PutObject",      # 제거
  "s3:GetObject",      # 제거
  "s3:ListBucket"      # 제거
}

user_data {
  s3_bucket = ...      # 제거
}
```

#### 새로운 아키텍처

```
AWS RDS
    │
    │ mysqldump (5분마다)
    ▼
Backup EC2 Instance
    │
    │ HTTPS (Azure CLI)
    │ Public Internet
    │ RPO: 5분
    ▼
Azure Blob Storage (유일한 백업)
    ├─ AWS 독립적
    ├─ 30일 보관
    └─ Lifecycle Policy
```

#### 수정된 파일

- ✓ `aws/backup-instance-planb.tf` - S3 IAM 권한 제거
- ✓ `aws/scripts/backup-instance-init-planb.sh` - S3 업로드 제거
- ✓ `aws/variables-planb.tf` - S3 변수 제거
- ✓ `aws/terraform-planb.tfvars.example` - S3 설정 제거

#### 비용 변화

```
기존: $232/월 (S3 포함)
변경: $217/월 (Blob만)
절감: $15/월 (S3 제거)
```

## 최종 비교

| 항목 | Plan A (수정 후) | Plan B (수정 후) | 차이 |
|------|------------------|------------------|------|
| **전략** | Warm Standby | Pilot Light | - |
| **백업** | DMS 실시간 복제 | Azure Blob (5분) | - |
| **S3** | 미사용 | 미사용 | 동일 |
| **VPN** | 필수 ($72/월) | 없음 | -$72 |
| **DMS** | 필수 ($100/월) | 없음 | -$100 |
| **Azure VM** | 항상 가동 | 재해 시만 | -$60 |
| **Azure DB** | 항상 가동 | 재해 시만 | -$50 |
| **월 비용** | $597 | $217 | **-$380** |
| **연 비용** | $7,164 | $2,604 | **-$4,560 (64%)** |
| **RTO** | 5분 | 2-4시간 | +2-4시간 |
| **RPO** | 1분 | 5분 | +4분 |

## 파일 구조

### Plan A 파일들

```
aws/
├── main-planA.tf                    ✓ S3 제거
├── dms-planA.tf                     ✓ S3 제거
├── outputs-planA.tf                 ✓ S3 제거
└── terraform-planA.tfvars           ✓ S3 제거

azure/
├── main.tf                          (기존 유지)
├── scripts/
│   ├── web-init.sh
│   └── was-init.sh
└── terraform.tfvars
```

### Plan B 파일들

```
aws/
├── backup-instance-planb.tf         ✓ S3 제거
├── scripts/
│   └── backup-instance-init-planb.sh ✓ S3 제거
├── variables-planb.tf               ✓ S3 제거
└── terraform-planb.tfvars.example   ✓ S3 제거

azure/
├── minimal-infrastructure.tf
└── scripts/
    ├── deploy-maintenance.sh
    ├── restore-database.sh
    └── deploy-petclinic.sh
```

## 배포 가이드

### Plan A 배포

```bash
# 1. Azure VPN Gateway 먼저 생성
cd azure
terraform apply -target=azurerm_public_ip.vpn
terraform apply -target=azurerm_virtual_network_gateway.main

# 2. Azure VPN Gateway IP를 AWS에 입력
cd ../aws
# terraform.tfvars 수정:
# azure_vpn_gateway_ip = "<Azure VPN Gateway Public IP>"

# 3. AWS 인프라 배포 (VPN, DMS 포함)
terraform init
terraform plan -out=planA.tfplan
terraform apply planA.tfplan

# 4. AWS VPN Tunnel IP를 Azure에 입력
terraform output vpn_connection_tunnel1_address
# Azure terraform.tfvars에 입력

# 5. Azure 나머지 리소스 배포
cd ../azure
terraform apply

# 6. DMS 복제 확인
cd ../aws
aws dms describe-replication-tasks \
  --region ap-northeast-2 \
  --query 'ReplicationTasks[0].Status'
```

### Plan B 배포

```bash
# 1. Azure Storage Account 먼저 생성
cd azure
terraform apply -target=azurerm_storage_account.backups
terraform apply -target=azurerm_storage_container.mysql_backups

# 2. Storage Account 정보를 AWS에 입력
cd ../aws
# terraform-planb.tfvars 수정:
# azure_storage_account_name = "<Azure Storage Account Name>"
# azure_storage_account_key = "<Azure Storage Account Key>"

# 3. AWS 백업 인스턴스 배포
terraform init
terraform plan -var-file=terraform-planb.tfvars -out=planB.tfplan
terraform apply planB.tfplan

# 4. 백업 확인
aws ssm start-session --target <backup-instance-id>
sudo tail -f /var/log/mysql-backup-to-azure.log

# 5. Azure에서 백업 확인
az storage blob list \
  --account-name <storage-account-name> \
  --container-name mysql-backups \
  --output table
```

## 중요 참고사항

### Plan A

✓ **장점**
- RTO 5분 (빠른 복구)
- RPO 1분 (거의 실시간)
- 자동 Failover
- Azure에 항상 최신 데이터

✗ **단점**
- 높은 비용 ($597/월)
- VPN+DMS 복잡도
- AWS 마비 시 VPN도 중단

### Plan B

✓ **장점**
- 저렴한 비용 ($217/월, 64% 절감)
- 간단한 구조
- AWS 완전 독립
- Azure Blob만으로 충분

✗ **단점**
- 긴 RTO (2-4시간)
- 수동 복구 필요
- 약간 긴 RPO (5분)

## 권장사항

### 우리 프로젝트: Plan B 강력 추천

**이유:**
1. **비용 효율**: 64% 절감 ($4,560/년)
2. **교육 목적**: DR 절차 직접 학습
3. **충분한 RTO/RPO**: 교육용으로 2-4시간 허용
4. **AWS 독립성**: 리전 마비에도 복구 가능
5. **간단한 구조**: 유지보수 용이

### Git 전략

```bash
# Main branch: 기존 프로젝트 유지
main
├── 기존 EKS + RDS 구조
└── Document 참고용

# Plan A branch: Warm Standby (참고)
plan-a-warm-standby
├── VPN + DMS
├── Azure 항상 가동
└── 높은 비용

# Plan B branch: Pilot Light (실제 사용 권장)
plan-b-pilot-light
├── Azure Blob만
├── 재해 시 배포
└── 저렴한 비용
```

## 다음 단계

1. **Branch 생성**
```bash
git checkout -b plan-b-pilot-light
git add aws/backup-instance-planb.tf
git add aws/scripts/backup-instance-init-planb.sh
git add azure/minimal-infrastructure.tf
git commit -m "Plan B: S3 removed, Azure Blob only"
git push origin plan-b-pilot-light
```

2. **Azure Storage 배포**
```bash
cd azure
terraform init
terraform apply
```

3. **AWS 백업 배포**
```bash
cd aws
terraform init
terraform apply -var-file=terraform-planb.tfvars
```

4. **DR 훈련**
```bash
cd azure/scripts
./deploy-maintenance.sh  # 점검 페이지 (15분)
./restore-database.sh    # DB 복구 (60분)
./deploy-petclinic.sh    # 앱 배포 (90분)
```

## 결론

✓ **Plan A & Plan B 모두에서 S3 제거 완료**
✓ **Plan A: DMS로 실시간 복제 (S3 불필요)**
✓ **Plan B: Azure Blob만 사용 (AWS 독립)**
✓ **비용 절감: Plan A $24/월, Plan B $15/월**
✓ **더 간단하고 명확한 구조**

**최종 권장: Plan B (Pilot Light) 사용** 🎯
