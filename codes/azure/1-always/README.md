# PlanB Azure 1-always

평상시 항상 실행되는 리소스

## 포함 리소스

### 실행 중 (비용 발생):
- **Storage Account** (~$5/월)
  - Blob Container: 백업용
  - Static Website: 점검 페이지

### 예약만 (비용 없음):
- **VNet + Subnets**
  - Web Subnet
  - WAS Subnet
  - DB Subnet
  - AKS Subnet

### Route53 설정 (옵션):
- **CNAME 레코드**: 서브도메인을 Blob Static Website로 직접 연결
  - 예: maintenance.example.com → storage-account.z12.web.core.windows.net

## 배포

### 1. Azure 로그인
```bash
az login
az account show
```

### 2. terraform.tfvars 작성
```bash
cp terraform.tfvars.example terraform.tfvars
```

terraform.tfvars 내용:
```hcl
# Azure 인증
subscription_id      = "your-subscription-id"
tenant_id           = "your-tenant-id"

# Storage Account (전역 고유 이름)
storage_account_name = "bloberry01"

# Route53 설정 (옵션 - 도메인이 있는 경우만)
enable_route53       = true
aws_region          = "us-east-1"
domain_name         = "example.com"
subdomain_name      = "maintenance.example.com"
```

### 3. 배포 실행
```bash
terraform init
terraform plan
terraform apply
```

### 4. 점검 페이지 확인
```bash
# Output에서 URL 확인
terraform output static_website_endpoint

# 직접 접속 (Blob Storage)
curl https://<storage-account>.z12.web.core.windows.net/

# 서브도메인 접속 (Route53 설정한 경우)
curl https://maintenance.example.com/
```

## 백업 확인

```bash
# Storage Account Key 확인
terraform output -raw storage_account_key

# 백업 목록 확인
az storage blob list \
  --account-name <storage-account> \
  --container-name mysql-backups \
  --output table
```

## Route53 설정

### Route53을 사용하지 않는 경우
terraform.tfvars에서:
```hcl
enable_route53 = false
```

### Route53을 사용하는 경우
1. AWS 자격 증명 설정:
```bash
aws configure
# 또는
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

2. terraform.tfvars에서:
```hcl
enable_route53  = true
domain_name     = "example.com"
subdomain_name  = "maintenance.example.com"
```

3. 배포 후 확인:
```bash
# DNS 조회
dig maintenance.example.com

# CNAME 레코드 확인
dig maintenance.example.com CNAME
# 결과: storage-account.z12.web.core.windows.net
```

## 아키텍처

```
┌─────────────────────────────────────────┐
│ Route53 (Optional)                      │
│                                         │
│ maintenance.example.com (CNAME)         │
│         ↓                               │
│ storage.z12.web.core.windows.net        │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ Azure Storage Account (Static Website) │
│                                         │
│ - Blob: $web/index.html                 │
│ - 점검 페이지 (HTML)                    │
└─────────────────────────────────────────┘
```

**주요 변경사항:**
- Application Gateway 제거 (비용 절감)
- Route53 CNAME으로 Blob Container 직접 연결
- HTTPS는 Blob Storage 기본 제공 (*.z12.web.core.windows.net)

## 주의사항

1. **Storage Account 이름은 전역 고유**해야 함
   - 소문자 + 숫자만 가능
   - 3-24자
   - 예: `drbackupprod2024`

2. **Subscription ID와 Tenant ID 필수**
   ```bash
   az account show --query "{subscriptionId:id, tenantId:tenantId}"
   ```

3. **Blob Static Website는 HTTPS 지원**
   - Azure 기본 제공: https://storage-account.z12.web.core.windows.net
   - 커스텀 도메인 HTTPS는 Azure CDN 필요 (추가 비용)

4. **Route53 CNAME 제한사항**
   - HTTPS 사용 시 인증서 경고 발생 가능 (커스텀 도메인)
   - HTTP로 사용하거나, Azure CDN으로 HTTPS 설정 필요

## 다음 단계

재해 발생 시:
```bash
cd ../3-failover
terraform apply
```

## 비용

- Storage Account: ~$5/월
- VNet/Subnets: $0 (예약만)
- Route53 CNAME: $0 (기존 Hosted Zone 사용)
- **총: ~$5/월**
