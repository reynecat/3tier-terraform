# Monitoring Module Upgrade Guide

## 개요

이 가이드는 monitoring 모듈을 destroy 후 재배포할 수 있도록 개선한 내용을 설명합니다.

## 주요 변경사항

### 1. Lambda 함수 배포 방식 개선

**변경 전:**
- 사전에 생성된 `lambda/auto_recovery.zip` 파일 필요
- zip 파일이 없으면 배포 실패

**변경 후:**
- `lambda/index.py`에서 자동으로 zip 파일 생성
- `data.archive_file.lambda_zip` 사용
- `source_code_hash`로 코드 변경 자동 감지

### 2. 파일 구조

```
codes/aws/3. monitoring/
├── .gitignore                        # 생성된 파일 제외
├── CHANGELOG.md                      # 변경 이력
├── README.md                         # 상세 가이드
├── UPGRADE_GUIDE.md                  # 업그레이드 가이드 (이 파일)
├── deploy.sh                         # 배포 스크립트
├── lambda/
│   ├── index.py                      # Lambda 소스 (버전 관리)
│   ├── auto_recovery.zip             # 기존 zip (유지)
│   └── auto_recovery_generated.zip   # 자동 생성 (git 제외)
├── main.tf
├── outputs.tf
├── variables.tf
├── terraform.tfvars                  # 실제 설정 값
└── terraform.tfvars.example          # 설정 템플릿
```

### 3. Terraform Provider 추가

`main.tf`에 archive provider 추가:

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 6.0"
  }
  archive = {
    source  = "hashicorp/archive"
    version = "~> 2.4"
  }
}
```

## 업그레이드 절차

### Step 1: 현재 상태 확인

```bash
cd "codes/aws/3. monitoring"

# 현재 리소스 확인
terraform state list

# 출력값 저장
terraform output > outputs_backup.txt
```

### Step 2: 변경사항 적용

```bash
# Terraform 재초기화 (archive provider 설치)
terraform init -upgrade

# 변경사항 확인
terraform plan

# 변경사항 적용
terraform apply
```

### Step 3: 검증

```bash
# Lambda 함수 확인
aws lambda get-function --function-name blue-eks-auto-recovery --region ap-northeast-2

# 대시보드 확인
aws cloudwatch list-dashboards --region ap-northeast-2

# 알람 확인
aws cloudwatch describe-alarms --region ap-northeast-2 | grep blue-eks
```

## Destroy & Redeploy 테스트

### Destroy

```bash
# 현재 설정 백업 (이미 git에 커밋되어 있음)
cp terraform.tfvars terraform.tfvars.backup

# Destroy
terraform destroy
```

### Redeploy

```bash
# Terraform 초기화
terraform init

# 배포 계획 확인
terraform plan

# 배포
terraform apply

# 검증
terraform output
```

## 예상 결과

Destroy 후 재배포 시:

✅ **유지되는 것:**
- `terraform.tfvars` 설정 파일
- `lambda/index.py` 소스 코드
- 대시보드 정의 (main.tf 내)
- 알람 정의

✅ **자동 생성되는 것:**
- Lambda zip 파일 (`auto_recovery_generated.zip`)
- CloudWatch 대시보드
- CloudWatch 알람
- SNS Topic
- Lambda 함수

✅ **동일하게 복구되는 것:**
- 모든 메트릭 및 알람 설정
- 대시보드 레이아웃 및 위젯
- Route53 헬스체크 모니터링
- Auto Recovery 로직

## 문제 해결

### Lambda 함수 생성 실패

```bash
# index.py 파일 확인
ls -la lambda/index.py

# 권한 확인
chmod 644 lambda/index.py

# Terraform 재초기화
terraform init -upgrade
terraform apply
```

### Archive Provider 오류

```bash
# Provider 캐시 삭제
rm -rf .terraform
rm .terraform.lock.hcl

# 재초기화
terraform init
```

### 설정 파일 누락

```bash
# 템플릿에서 복사
cp terraform.tfvars.example terraform.tfvars

# 편집
vi terraform.tfvars
```

## 배포 스크립트 사용

새로운 배포 스크립트를 사용하면 더 쉽게 관리할 수 있습니다:

```bash
# 배포 계획
./deploy.sh plan

# 배포
./deploy.sh apply

# 삭제
./deploy.sh destroy

# 출력 확인
./deploy.sh output
```

## 롤백 절차

문제가 발생한 경우:

```bash
# 상태 파일 복구
cp terraform.tfstate.backup terraform.tfstate

# 또는 이전 커밋으로 롤백
git checkout <previous-commit> .
terraform init
terraform apply
```

## 참고사항

1. **terraform.tfvars는 git에 커밋되어 있음**
   - 민감한 정보가 없으므로 안전
   - 재배포 시 동일한 설정 보장

2. **Lambda 코드 변경 시**
   - `lambda/index.py` 수정
   - `terraform apply`만 실행
   - `source_code_hash`가 자동으로 변경 감지

3. **대시보드 수정 시**
   - `main.tf`의 dashboard_body 수정
   - `terraform apply` 실행

4. **알람 임계값 변경 시**
   - `terraform.tfvars` 수정
   - `terraform apply` 실행

## 추가 개선사항

향후 개선 가능한 사항:

- [ ] 대시보드 JSON을 별도 파일로 분리
- [ ] Slack 워크스페이스 자동 연동
- [ ] 알람 템플릿 모듈화
- [ ] 멀티 리전 대시보드 통합
- [ ] Cost Explorer 통합

## 지원

문제가 발생하면:
1. README.md의 문제 해결 섹션 참조
2. Terraform 로그 확인: `TF_LOG=DEBUG terraform apply`
3. AWS 콘솔에서 리소스 상태 확인
