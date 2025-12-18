# Plan B (Pilot Light) 

## 빠른 시작

### 1. Azure Storage 배포
```bash
cd azure
cp terraform-planb.tfvars.example terraform.tfvars
nano terraform.tfvars  # subscription_id, tenant_id, storage_account_name 입력

terraform init
terraform apply
```

### 2. Storage 정보 확인
```bash
az storage account keys list \
  --account-name <storage-name> \
  --query "[0].value" -o tsv
```

### 3. AWS 백업 인스턴스 배포
```bash
cd ../aws
cp terraform-planb.tfvars.example terraform.tfvars
nano terraform.tfvars  # Azure Storage 정보 입력

terraform init
terraform apply -var-file=terraform.tfvars
```

### 4. 백업 확인
```bash
aws ssm start-session --target <instance-id>
sudo tail -f /var/log/mysql-backup-to-azure.log
```

## 디렉토리 구조

```
plan-b-deployment/
├── aws/                           # AWS 백업 인스턴스
│   ├── backup-instance-planb.tf
│   ├── variables-planb.tf
│   ├── terraform-planb.tfvars.example
│   └── scripts/
│       └── backup-instance-init-planb.sh
│
├── azure/                         # Azure 최소 인프라
│   ├── minimal-infrastructure.tf
│   ├── variables-planb.tf
│   ├── terraform-planb.tfvars.example
│   └── scripts/
│       ├── deploy-maintenance.sh
│       ├── maintenance-cloud-init.yaml
│       ├── restore-database.sh
│       └── deploy-petclinic.sh
│
├── runbooks/                      # 운영 문서
│   └── emergency-response.md
│
└── docs/                          # 가이드
    ├── DR_PLAN_B_README.md
    ├── PLAN_A_VS_B_COMPARISON.md
    ├── S3_REMOVAL_SUMMARY.md
    └── DEPLOYMENT_GUIDE_PLAN_B.md
```

## 비용

- **평상시:** $217/월
- **재해 시:** +$5/시간
- **Plan A 대비:** 64% 절감

## 주요 특징

- ✅ S3 없음 (Azure Blob만)
- ✅ VPN/DMS 없음
- ✅ AWS 완전 독립
- ✅ RTO: 2-4시간
- ✅ RPO: 5분

## 상세 가이드

`docs/DEPLOYMENT_GUIDE_PLAN_B.md` 참고
