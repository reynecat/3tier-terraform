# PlanB DR 아키텍처 배포 가이드

## 목차
1. [사전 준비](#1-사전-준비)
2. [Azure Storage 배포 (1-always)](#2-azure-storage-배포-1-always)
3. [AWS 인프라 배포](#3-aws-인프라-배포)
4. [백업 시스템 검증](#4-백업-시스템-검증)
5. [재해 대응 시나리오](#5-재해-대응-시나리오)
6. [문제 해결](#6-문제-해결)

---

## 1. 사전 준비

### 1.1 필수 도구 설치

```bash
# AWS CLI 설치 확인
aws --version

# Azure CLI 설치 확인
az --version

# Terraform 설치 확인 (>= 1.14.0)
terraform --version

# kubectl 설치 확인
kubectl version --client
```

### 1.2 자격증명 설정

**AWS 설정:**
```bash
# AWS 프로파일 설정
aws configure

# 설정 확인
aws sts get-caller-identity
```

**Azure 설정:**
```bash
# Azure 로그인
az login

# 구독 확인
az account show

# 구독 ID와 테넌트 ID 저장
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Subscription ID: $AZURE_SUBSCRIPTION_ID"
echo "Tenant ID: $AZURE_TENANT_ID"
```

### 1.3 SSH 키 생성

```bash
# SSH 키페어 생성 (없는 경우)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/planb_key -C "planb-backup-instance"

# 공개 키 내용 확인 및 복사
cat ~/.ssh/planb_key.pub
```

---

## 2. Azure Storage 배포 (1-always)

### 2.1 디렉토리 이동 및 설정

```bash
cd PlanB/azure/1-always

# 예제 설정 파일 복사
cp terraform.tfvars.example terraform.tfvars
```

### 2.2 terraform.tfvars 편집

```bash
nano terraform.tfvars
```

다음 내용을 입력:

```hcl
environment = "prod"
location    = "koreacentral"

# Storage Account 이름 (전역 고유, 소문자+숫자, 3-24자)
storage_account_name      = "bloberry01"  # 본인의 고유한 이름으로 변경
backup_container_name     = "mysql-backups"
backup_retention_days     = 30
storage_replication_type  = "LRS"

# Network CIDR
vnet_cidr       = "172.16.0.0/16"
web_subnet_cidr = "172.16.11.0/24"
was_subnet_cidr = "172.16.21.0/24"
db_subnet_cidr  = "172.16.31.0/24"
aks_subnet_cidr = "172.16.41.0/24"
appgw_subnet_cidr = "172.16.1.0/24"

# Azure 구독 정보
subscription_id = "YOUR_SUBSCRIPTION_ID"  # 위에서 확인한 값 입력
tenant_id       = "YOUR_TENANT_ID"        # 위에서 확인한 값 입력

tags = {
  Environment = "Production"
  DRPlan      = "Plan-B-Pilot-Light"
  ManagedBy   = "Terraform"
  Purpose     = "Disaster-Recovery"
  Team        = "AWS2-Team"
}
```

### 2.3 Terraform 배포

```bash
# 초기화
terraform init

# 계획 확인
terraform plan

# 배포 실행
terraform apply
# 'yes' 입력하여 확인
```

### 2.4 배포 결과 확인

```bash
# Storage Account 정보 확인
terraform output storage_account_name
terraform output static_website_url

# 점검 페이지 접속 테스트
STORAGE_NAME=$(terraform output -raw storage_account_name)
curl "https://${STORAGE_NAME}.z12.web.core.windows.net/"
```

### 2.5 Storage Account Key 저장

```bash
# Storage Key 확인 및 저장 (다음 단계에서 사용)
az storage account keys list \
  --account-name $(terraform output -raw storage_account_name) \
  --query "[0].value" -o tsv

# 환경 변수로 저장
export AZURE_STORAGE_KEY=$(az storage account keys list \
  --account-name $(terraform output -raw storage_account_name) \
  --query "[0].value" -o tsv)

echo "Storage Key: $AZURE_STORAGE_KEY"
```

---

## 3. AWS 인프라 배포

### 3.1 디렉토리 이동 및 설정

```bash
cd ../../aws

# 예제 설정 파일 복사
cp terraform.tfvars.example terraform.tfvars
```

### 3.2 terraform.tfvars 편집

```bash
nano terraform.tfvars
```

다음 내용을 입력:

```hcl
# 기본 설정
environment = "prod"
aws_region  = "ap-northeast-2"

# Azure 연동 정보 (2단계에서 획득한 값 입력)
azure_storage_account_name  = "bloberry01"  # 본인의 Storage Account 이름
azure_storage_account_key   = "YOUR_AZURE_STORAGE_KEY"  # 위에서 확인한 값
azure_backup_container_name = "mysql-backups"
azure_tenant_id             = "YOUR_AZURE_TENANT_ID"
azure_subscription_id       = "YOUR_AZURE_SUBSCRIPTION_ID"

# 백업 인스턴스 설정
enable_backup_instance = true
backup_instance_ssh_public_key = "ssh-rsa AAAAB3..."  # ~/.ssh/planb_key.pub 내용

# 데이터베이스 설정
db_name     = "petclinic"
db_username = "admin"
db_password = "MyNewPassword123!"  # 강력한 비밀번호로 변경

# VPC 설정
aws_vpc_cidr = "10.0.0.0/16"
aws_availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]

public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
web_subnet_cidrs    = ["10.0.11.0/24", "10.0.12.0/24"]
was_subnet_cidrs    = ["10.0.21.0/24", "10.0.22.0/24"]
rds_subnet_cidrs    = ["10.0.31.0/24", "10.0.32.0/24"]

# EKS 노드 설정
eks_node_instance_type = "t3.small"
eks_web_desired_size   = 2
eks_web_min_size       = 1
eks_web_max_size       = 4
eks_was_desired_size   = 2
eks_was_min_size       = 1
eks_was_max_size       = 4

# RDS 설정
rds_instance_class        = "db.t3.medium"
rds_allocated_storage     = 100
rds_max_allocated_storage = 200
rds_multi_az              = true
rds_skip_final_snapshot   = true  # 개발 환경에서만 true
rds_deletion_protection   = false # 개발 환경에서만 false

# Route53 설정 (도메인 없으면 false)
enable_custom_domain = false
domain_name          = ""
create_hosted_zone   = false
```

### 3.3 Terraform 배포

```bash
# 초기화
terraform init

# 계획 확인 (약 5분 소요)
terraform plan

# 배포 실행 (약 20-30분 소요)
terraform apply
# 'yes' 입력하여 확인
```

### 3.4 배포 진행 상황 모니터링

다른 터미널에서 실시간으로 진행 상황을 확인할 수 있다:

```bash
# VPC 생성 확인
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=prod" --query "Vpcs[0].State"

# EKS 클러스터 상태 확인
aws eks describe-cluster --name prod-eks --query "cluster.status"

# RDS 인스턴스 상태 확인
aws rds describe-db-instances --db-instance-identifier prod-rds --query "DBInstances[0].DBInstanceStatus"
```

### 3.5 배포 결과 확인

```bash
# 주요 리소스 정보 출력
terraform output

# EKS 클러스터 정보
terraform output -raw eks_cluster_name
terraform output -raw eks_cluster_endpoint

# RDS 엔드포인트
terraform output -raw rds_endpoint

# 백업 인스턴스 정보
terraform output backup_instance_id
terraform output backup_instance_private_ip
```

### 3.6 EKS 클러스터 접근 설정

```bash
# kubectl 설정
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name $(terraform output -raw eks_cluster_name)

# 클러스터 접근 확인
kubectl cluster-info
kubectl get nodes
```

---

## 4. 백업 시스템 검증

### 4.1 백업 인스턴스 접속

```bash
# SSM Session Manager로 접속 (권장)
INSTANCE_ID=$(terraform output -raw backup_instance_id)
aws ssm start-session --target $INSTANCE_ID
```

### 4.2 백업 로그 확인

백업 인스턴스에 접속한 후:

```bash
# 초기화 로그 확인
sudo tail -100 /var/log/backup-instance-init.log

# 백업 실행 로그 실시간 확인
sudo tail -f /var/log/mysql-backup-to-azure.log
```

### 4.3 백업 스크립트 수동 실행

```bash
# 수동으로 백업 실행 테스트
sudo /usr/local/bin/mysql-backup-to-azure.sh

# 결과 확인
echo $?  # 0이면 성공
```

### 4.4 Azure에서 백업 확인

로컬 터미널에서:

```bash
# 백업 파일 목록 확인
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --prefix "backups/" \
  --output table

# 최신 백업 파일 확인
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --prefix "backups/" \
  --query "sort_by([], &properties.lastModified)[-1].[name, properties.lastModified, properties.contentLength]" \
  --output table
```

### 4.5 Cron 작업 확인

백업 인스턴스에서:

```bash
# Cron 작업 목록 확인
sudo crontab -l

# 5분마다 실행되는지 확인
# */5 * * * * /usr/local/bin/mysql-backup-to-azure.sh
```

---

## 5. 재해 대응 시나리오

### 5.1 Phase 1: 점검 페이지 배포 (T+0 ~ T+15분)

```bash
cd PlanB/azure/2-emergency

# 설정 파일 준비
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

terraform.tfvars 내용:

```hcl
environment = "prod"

subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"

resource_group_name  = "rg-dr-prod"
vnet_name            = "vnet-dr-prod"
storage_account_name = "bloberry01"

db_name     = "petclinic"
db_username = "mysqladmin"
db_password = "MySecurePassword123!"  # 8자 이상, 대소문자+숫자+특수문자

mysql_sku        = "B_Standard_B2s"
mysql_storage_gb = 20

tags = {
  Environment = "Production"
  DRPlan      = "Plan-B-Pilot-Light"
  Phase       = "Emergency"
  ManagedBy   = "Terraform"
}
```

배포 실행:

```bash
terraform init
terraform plan
terraform apply
# 약 10-15분 소요
```

점검 페이지 확인:

```bash
# Application Gateway IP 확인
terraform output maintenance_page_url

# 브라우저 또는 curl로 접속 테스트
curl $(terraform output -raw maintenance_page_url)
```

### 5.2 Phase 2: MySQL 백업 복구 (T+15 ~ T+75분)

```bash
cd scripts

# 복구 스크립트 실행
./restore-db.sh

# 프롬프트에서 MySQL 비밀번호 입력
# Password: MySecurePassword123!
```

복구 과정:

1. 최신 백업 파일 검색
2. Azure Blob Storage에서 다운로드
3. 압축 해제
4. MySQL에 복구

복구 완료 후 확인:

```bash
# MySQL 접속 테스트
MYSQL_HOST=$(cd .. && terraform output -raw mysql_fqdn)
mysql -h $MYSQL_HOST -u mysqladmin -p

# MySQL 프롬프트에서
USE petclinic;
SHOW TABLES;
SELECT COUNT(*) FROM owners;
EXIT;
```

### 5.3 Phase 3: AKS 배포 (재해 장기화 시)

```bash
cd ../../3-failover

# 설정 파일 준비
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

terraform.tfvars 내용:

```hcl
environment = "prod"

subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"

resource_group_name  = "rg-dr-prod"
vnet_name            = "vnet-dr-prod"
mysql_server_name    = "mysql-dr-prod"
appgw_public_ip_name = "pip-appgw-prod"

kubernetes_version = "1.28"
node_count         = 2
node_min_count     = 2
node_max_count     = 5
node_vm_size       = "Standard_D2s_v3"

tags = {
  Environment = "Production"
  DRPlan      = "Plan-B-Pilot-Light"
  Phase       = "Full-Failover"
  ManagedBy   = "Terraform"
}
```

AKS 배포:

```bash
terraform init
terraform plan
terraform apply
# 약 15-20분 소요
```

kubectl 설정:

```bash
az aks get-credentials \
  --resource-group rg-dr-prod \
  --name $(terraform output -raw aks_cluster_name)

kubectl cluster-info
kubectl get nodes
```

PetClinic 배포:

```bash
cd scripts
./deploy-petclinic.sh

# MySQL 비밀번호 입력 프롬프트
# Password: MySecurePassword123!
```

Application Gateway 업데이트:

```bash
./update-appgw.sh
```

서비스 확인:

```bash
# Pod 상태 확인
kubectl get pods -n petclinic

# Service 확인
kubectl get svc -n petclinic

# Application Gateway IP로 접속
APPGW_IP=$(cd .. && terraform output -raw appgw_public_ip)
echo "PetClinic URL: http://$APPGW_IP"
curl http://$APPGW_IP
```

---

## 6. 문제 해결

### 6.1 백업 인스턴스 문제

**증상: 백업이 실행되지 않음**

```bash
# SSM으로 접속
aws ssm start-session --target <instance-id>

# 로그 확인
sudo tail -100 /var/log/backup-instance-init.log
sudo tail -100 /var/log/mysql-backup-to-azure.log

# RDS 연결 테스트
mysql -h <rds-endpoint> -u admin -p

# Azure CLI 설치 확인
az --version

# Azure 인증 테스트
az storage account show --name bloberry01
```

**해결 방법:**

- RDS 보안 그룹 확인: 백업 인스턴스 SG가 허용되어 있는지 확인
- Secrets Manager 권한 확인: IAM 역할에 권한이 있는지 확인
- Azure Storage Key 확인: 올바른 키가 Secrets Manager에 저장되어 있는지 확인

### 6.2 EKS Pod 시작 실패

**증상: Pod가 Pending 상태**

```bash
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>
```

**일반적인 원인:**

- 노드 리소스 부족: 노드 그룹 스케일링 확인
- 이미지 풀링 실패: 이미지 이름 확인
- PVC 바인딩 실패: 스토리지 클래스 확인

### 6.3 MySQL 연결 실패

**증상: Pod에서 MySQL 연결 불가**

```bash
# Secret 확인
kubectl get secret db-credentials -n petclinic -o yaml

# MySQL 엔드포인트 확인
kubectl get secret db-credentials -n petclinic -o jsonpath='{.data.url}' | base64 -d

# Pod에서 직접 테스트
kubectl exec -it <pod-name> -n petclinic -- sh
mysql -h <mysql-host> -u mysqladmin -p
```

**해결 방법:**

- Azure MySQL 방화벽 규칙 확인
- VNet 통합 확인
- Secret 값이 올바른지 확인

### 6.4 Terraform State 잠금 문제

**증상: State 파일이 잠겨있음**

```bash
# 강제 잠금 해제 (주의: 다른 작업이 진행 중이 아닌지 확인)
terraform force-unlock <lock-id>
```

### 6.5 백업 복구 실패

**증상: restore-db.sh 실행 중 오류**

```bash
# 백업 파일 존재 확인
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --prefix "backups/"

# 수동 다운로드 및 복구
az storage blob download \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --name "backups/backup-20241219-120000.sql.gz" \
  --file backup.sql.gz

gunzip backup.sql.gz
mysql -h <mysql-host> -u mysqladmin -p < backup.sql
```






### 공식 문서

- AWS EKS: https://docs.aws.amazon.com/eks/
- Azure AKS: https://docs.microsoft.com/azure/aks/
- Terraform AWS: https://registry.terraform.io/providers/hashicorp/aws/
- Terraform Azure: https://registry.terraform.io/providers/hashicorp/azurerm/

### 프로젝트 구조

```
PlanB/
├── aws/                      # AWS 인프라
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── modules/
│   │   ├── vpc/
│   │   ├── eks/
│   │   ├── rds/
│   │   └── alb/
│   ├── scripts/
│   │   └── backup-init.sh
│   └── k8s-manifests/
│
└── azure/                    # Azure DR 사이트
    ├── 1-always/            # 평상시 실행
    │   ├── main.tf
    │   ├── variables.tf
    │   └── terraform.tfvars
    ├── 2-emergency/         # 재해 시 배포
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── terraform.tfvars
    │   └── scripts/
    │       └── restore-db.sh
    └── 3-failover/          # 전체 Failover
        ├── main.tf
        ├── variables.tf
        ├── terraform.tfvars
        └── scripts/
            ├── deploy-petclinic.sh
            └── update-appgw.sh
```


---

마지막 업데이트: 2024-12-19