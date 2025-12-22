# PlanB Azure 2-emergency

재해 시 배포하는 리소스

## 포함 리소스

- **MySQL Flexible Server** - 백업 복구용
- **Application Gateway** - 점검 페이지 프록시
- **Public IP** - 인터넷 접속용

## 배포 시나리오

### Phase 1: 점검 페이지 (T+0 ~ T+15분)

```bash
# 1. 배포
terraform init
terraform apply

# 2. 점검 페이지 확인
terraform output maintenance_page_url
# http://<app-gateway-ip>

# 3. 브라우저 접속 확인
curl http://<app-gateway-ip>
```

### Phase 2: MySQL 백업 복구 (T+15 ~ T+75분)

```bash
cd scripts
./restore-db.sh
```

## 배포 전 준비

1. **1-always 먼저 배포**
   ```bash
   cd ../1-always
   terraform apply
   ```

2. **terraform.tfvars 수정**
   - `storage_account_name`: 1-always와 동일
   - `db_password`: MySQL 비밀번호

## 주요 기능

### 1. 점검 페이지 프록시
- Blob Storage의 Static Website를 App Gateway로 프록시
- HTTP로 접속 가능
- 도메인 없이도 Public IP로 접속

### 2. MySQL 복구
- Blob Storage 백업에서 복구
- 복구 스크립트: `scripts/restore-db.sh`

## 비용

- MySQL B_Standard_B2s: ~$25/월
- Application Gateway Standard_v2: ~$25/월
- Public IP: ~$3/월
- **총: ~$53/월** (실행 중일 때만)

## 주의사항

1. **1-always 먼저 배포 필수**
2. **MySQL 비밀번호 8자 이상** (대소문자+숫자+특수문자)
3. **배포 시간 10-15분 소요** (App Gateway 생성)

## 다음 단계

재해 장기화 시 AKS 배포:
```bash
cd ../3-failover
terraform apply
```

## 삭제

```bash
terraform destroy
```

점검 완료 후 비용 절감을 위해 삭제 권장.
