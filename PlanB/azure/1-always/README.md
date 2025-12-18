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
  - App Gateway Subnet

## 배포

### 1. Azure 로그인
```bash
az login
az account show
```

### 2. terraform.tfvars 수정
```bash
# subscription_id, tenant_id 입력
# storage_account_name 전역 고유 이름으로 변경
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

# 브라우저에서 접속
https://<storage-account>.z12.web.core.windows.net/
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

## 주의사항

1. **Storage Account 이름은 전역 고유**해야 함
   - 소문자 + 숫자만 가능
   - 3-24자
   - 예: `drbackupprod2024`

2. **Subscription ID와 Tenant ID 필수**
   ```bash
   az account show --query "{subscriptionId:id, tenantId:tenantId}"
   ```

3. **점검 페이지는 HTTP만 지원**
   - HTTPS 필요 시 Azure CDN 추가 필요
   - 또는 2-emergency에서 Application Gateway 사용

## 다음 단계

재해 발생 시:
```bash
cd ../2-emergency
terraform apply
```

## 비용

- Storage Account: ~$5/월
- VNet/Subnets: $0 (예약만)
- **총: ~$5/월**
