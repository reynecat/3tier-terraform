# 사용자 가이드

Multi-Cloud DR 시스템을 처음부터 끝까지 배포하는 방법을 단계별로 설명합니다.

---

## 📋 목차

1. [시작하기 전에](#1-시작하기-전에)
2. [준비 작업](#2-준비-작업)
3. [Azure 대기 리소스 배포](#3-azure-대기-리소스-배포)
4. [AWS Primary 사이트 구축](#4-aws-primary-사이트-구축)
5. [재해 복구 테스트](#5-재해-복구-테스트)
6. [리소스 정리](#6-리소스-정리)

---

## 1. 시작하기 전에

### 1.1 필요한 것

#### 계정
- ✅ AWS 계정 (학생: AWS Educate $100 크레딧)
- ✅ Azure 계정 (학생: Azure for Students $100 크레딧)
- ✅ 도메인 (선택사항, Route53 도메인 $12/년)

#### 기본 지식
- ☑️ Linux 명령어 기초 (cd, ls, mkdir)
- ☑️ Git 기본 사용법 (clone, commit)
- ☑️ 클라우드 개념 (가상 머신, 네트워크 정도만)

**모르셔도 됩니다!** 가이드를 따라하면서 배울 수 있습니다.

### 1.2 예상 소요 시간

| 단계 | 소요 시간 | 비고 |
|------|-----------|------|
| 준비 작업 | 30분 | 도구 설치, 계정 설정 |
| Azure 대기 배포 | 10분 | Storage, VNet 생성 |
| AWS Primary 배포 | 60분 | EKS, RDS 등 생성 |
| 애플리케이션 배포 | 30분 | PocketBank 배포 |
| **총 소요 시간** | **약 2시간 30분** | - |

### 1.3 예상 비용

**⚠️ 중요: 테스트 후 반드시 리소스를 삭제하세요!**

| 항목 | 시간당 | 하루 | 한 달 |
|------|--------|------|-------|
| AWS (EKS + RDS) | ~$0.30 | ~$7.20 | ~$248 |
| Azure (대기만) | ~$0.01 | ~$0.24 | ~$10 |
| **합계** | **~$0.31** | **~$7.44** | **~$258** |

**💡 팁**: 테스트 완료 후 즉시 삭제하면 **~$15 이하**로 가능합니다!

---

## 2. 준비 작업

### 2.1 작업 환경 선택

#### 방법 1: 로컬 컴퓨터 (Ubuntu/macOS)
```bash
# 홈 디렉토리로 이동
cd ~
```

#### 방법 2: AWS Cloud9 (추천 - 무료)
```bash
# Cloud9 터미널에서 시작
# 별도 설정 불필요
```

#### 방법 3: Windows (WSL2)
```bash
# WSL2 Ubuntu 터미널에서 시작
wsl
cd ~
```

### 2.2 필수 도구 설치

**한 번에 설치하는 스크립트:**

```bash
# 설치 스크립트 다운로드
curl -o setup.sh https://raw.githubusercontent.com/yourusername/3tier-terraform/main/scripts/setup.sh

# 실행 권한 부여
chmod +x setup.sh

# 설치 시작
./setup.sh
```

**또는 하나씩 설치:**

```bash
# 1. Terraform 설치
wget https://releases.hashicorp.com/terraform/1.14.0/terraform_1.14.0_linux_amd64.zip
unzip terraform_1.14.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version  # 확인

# 2. AWS CLI 설치
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version  # 확인

# 3. Azure CLI 설치
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az --version  # 확인

# 4. kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client  # 확인

# 5. eksctl 설치
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version  # 확인
```

### 2.3 프로젝트 다운로드

```bash
# GitHub에서 클론
git clone https://github.com/reynecat/3tier-terraform.git
cd 3tier-terraform

# 디렉토리 구조 확인
tree -L 2
```

### 2.4 AWS 계정 설정

```bash
# AWS 자격증명 설정
aws configure

# 입력 내용:
# AWS Access Key ID: AKIAXXXXXXXXXXXXXXXX (AWS 콘솔에서 생성)
# AWS Secret Access Key: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# Default region name: ap-northeast-2 (서울 리전)
# Default output format: json

# 확인
aws sts get-caller-identity
# 출력 예시:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/yourname"
# }
```

**💡 AWS Access Key 생성 방법:**
1. AWS 콘솔 → IAM → Users → 본인 선택
2. Security credentials 탭
3. "Create access key" 클릭
4. 키 다운로드 및 안전하게 보관

### 2.5 Azure 계정 설정

```bash
# Azure 로그인 (브라우저가 열립니다)
az login

# 구독 ID와 Tenant ID 확인
az account show

# 출력 예시:
# {
#   "id": "12345678-1234-1234-1234-123456789012",  ← Subscription ID
#   "tenantId": "87654321-4321-4321-4321-210987654321",  ← Tenant ID
#   "name": "Azure for Students"
# }

# 환경변수로 저장
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Subscription ID: $AZURE_SUBSCRIPTION_ID"
echo "Tenant ID: $AZURE_TENANT_ID"
```

---

## 3. Azure 대기 리소스 배포

### 3.1 설정 파일 작성

```bash
cd codes/azure/1-always

# 예제 파일 복사
cp terraform.tfvars.example terraform.tfvars

# 편집기로 열기 (nano 또는 vi)
nano terraform.tfvars
```

**terraform.tfvars 내용:**

```hcl
# 환경 이름 (본인 이름 또는 프로젝트명)
environment = "blue"

# Azure 리전
location = "koreacentral"

# Storage Account 이름 (전 세계에서 유일해야 함!)
# 규칙: 소문자 + 숫자만, 3-24자
storage_account_name = "bloberry01"  # ← 본인만의 이름으로 변경!

# 백업 컨테이너 이름
backup_container_name = "mysql-backups"

# 백업 보관 기간 (일)
backup_retention_days = 30

# Storage 복제 타입 (비용 절감)
storage_replication_type = "LRS"

# 네트워크 CIDR (기본값 사용 권장)
vnet_cidr         = "172.16.0.0/16"
web_subnet_cidr   = "172.16.11.0/24"
was_subnet_cidr   = "172.16.21.0/24"
db_subnet_cidr    = "172.16.31.0/24"
aks_subnet_cidr   = "172.16.41.0/24"
appgw_subnet_cidr = "172.16.1.0/24"

# Azure 구독 정보 (위에서 확인한 값)
subscription_id = "12345678-1234-1234-1234-123456789012"  # ← 본인 ID
tenant_id       = "87654321-4321-4321-4321-210987654321"  # ← 본인 ID

# 태그 (선택사항)
tags = {
  Environment = "blue"
  Team        = "I2ST"
  Purpose     = "DR-Testing"
}
```

**Ctrl + O (저장), Ctrl + X (종료)**

### 3.2 배포 실행

```bash
# Terraform 초기화 (플러그인 다운로드)
terraform init

# 실행 계획 확인
terraform plan

# 출력 예시:
# Plan: 7 to add, 0 to change, 0 to destroy.
#
# 생성될 리소스:
# - azurerm_resource_group.main
# - azurerm_storage_account.backups
# - azurerm_storage_container.backups
# - azurerm_virtual_network.main
# - azurerm_subnet.web
# - azurerm_subnet.was
# - azurerm_subnet.db
# (+ 더 많은 subnet들)

# 배포 시작
terraform apply

# "yes" 입력하여 확인
```

**⏱️ 소요 시간: 약 2-3분**

### 3.3 배포 확인

```bash
# 생성된 리소스 확인
terraform output

# 출력 예시:
# resource_group_name = "rg-dr-blue"
# storage_account_name = "bloberry01"
# vnet_name = "vnet-dr-blue"
# static_website_endpoint = "https://bloberry01.z12.web.core.windows.net/"

# 웹사이트 접속 (점검 페이지가 보여야 함)
curl https://bloberry01.z12.web.core.windows.net/
```

**✅ 성공!** Azure 대기 리소스 배포 완료!

---

## 4. AWS Primary 사이트 구축

### 4.1 Service 인프라 배포

```bash
cd ~/3tier-terraform/codes/aws/service

# 설정 파일 복사
cp terraform.tfvars.example terraform.tfvars

# 편집
nano terraform.tfvars
```

**terraform.tfvars 핵심 설정:**

```hcl
environment = "prod"
aws_region  = "ap-northeast-2"

# Azure 연동 (위에서 배포한 정보)
azure_storage_account_name  = "bloberry01"  # ← 본인 Storage Account 이름
azure_storage_account_key   = "AZURE_KEY"   # ← Azure Portal에서 확인 필요
azure_backup_container_name = "mysql-backups"
azure_tenant_id             = "YOUR_TENANT_ID"
azure_subscription_id       = "YOUR_SUBSCRIPTION_ID"

# 데이터베이스 설정
db_name     = "pocketbank"
db_username = "admin"
db_password = "MySecurePassword123!"  # ← 보안 강화 필요 (대소문자+숫자+특수문자)

# 백업 스케줄
backup_schedule_cron = "0 3 * * *"  # 매일 03:00 UTC

# 도메인 (선택사항)
enable_custom_domain = false  # 도메인 없으면 false
# domain_name = "yourdomain.com"  # 있으면 활성화
```

**💡 Azure Storage Key 확인 방법:**

```bash
# Azure Portal에서:
# Storage accounts → bloberry01 → Access keys → key1 복사

# 또는 CLI로:
az storage account keys list \
  --account-name bloberry01 \
  --resource-group rg-dr-blue \
  --query "[0].value" \
  --output tsv
```

**배포 시작:**

```bash
terraform init
terraform plan
terraform apply
# yes 입력
```

**⏱️ 소요 시간: 약 20-25분 (EKS 클러스터 생성에 시간 소요)**

### 4.2 kubectl 설정

```bash
# EKS 클러스터 접속 설정
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name $(terraform output -raw eks_cluster_name)

# 노드 확인
kubectl get nodes

# 출력 예시:
# NAME                                              STATUS   ROLES    AGE   VERSION
# ip-10-0-11-123.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.34.0
# ip-10-0-12-234.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.34.0
```

### 4.3 AWS Load Balancer Controller 설치

```bash
cd ~/3tier-terraform/codes/aws/service/scripts

# 스크립트 실행 권한
chmod +x install-lb-controller.sh

# 설치
./install-lb-controller.sh

# 확인 (2개 Pod가 Running이어야 함)
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**문제가 발생하면:** [트러블슈팅 가이드](troubleshooting.md#11-aws-load-balancer-controller-설치-실패) 참조

### 4.4 PocketBank 애플리케이션 배포

#### 1) Namespace 생성

```bash
cd ~/3tier-terraform/codes/aws/service
kubectl apply -f k8s-manifests/namespaces.yaml

# 확인
kubectl get namespaces
```

#### 2) Database Secret 생성

```bash
# RDS 주소 확인
export RDS_HOST=$(terraform output -raw rds_address)
echo "RDS Host: $RDS_HOST"

# Secret 생성 (terraform.tfvars의 비밀번호와 동일하게!)
kubectl create secret generic db-credentials \
  --from-literal=url="jdbc:mysql://${RDS_HOST}:3306/pocketbank" \
  --from-literal=username="admin" \
  --from-literal=password="MySecurePassword123!" \
  --namespace=was

# 확인
kubectl get secret db-credentials -n was
```

#### 3) WAS 배포

```bash
cd k8s-manifests

# Deployment 배포
kubectl apply -f was/deployment.yaml

# Service 배포
kubectl apply -f was/service.yaml

# Pod 상태 확인 (Running이 될 때까지 대기)
kubectl get pods -n was -w
# Ctrl+C로 중단

# 로그 확인 (PocketBank 시작 확인)
kubectl logs -n was -l app=was-spring --tail=20 | grep "Started"
```

#### 4) Web 배포

```bash
kubectl apply -f web/deployment.yaml
kubectl apply -f web/service.yaml

# 확인
kubectl get pods -n web
```

#### 5) Ingress 배포 (ALB 생성)

**ACM 인증서 ARN 확인 (도메인 있는 경우):**

```bash
# ACM 인증서 조회
aws acm list-certificates \
  --region ap-northeast-2 \
  --query "CertificateSummaryList[*].{Domain:DomainName,ARN:CertificateArn}" \
  --output table

# ARN 복사
export CERT_ARN="arn:aws:acm:ap-northeast-2:123456789012:certificate/xxx"
```

**Ingress YAML 수정:**

```bash
nano ingress/ingress.yaml

# certificate-arn 부분 수정
# alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-northeast-2:xxx:certificate/xxx
```

**배포:**

```bash
kubectl apply -f ingress/ingress.yaml

# ALB 생성 대기 (2-3분)
kubectl get ingress web-ingress -n web -w
```

**ALB DNS 확인:**

```bash
export ALB_DNS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB URL: http://$ALB_DNS"

# 브라우저 접속 또는 curl
curl -I http://$ALB_DNS
```

**✅ 성공!** PocketBank이 보이면 성공!

---

## 5. 재해 복구 테스트

### 5.1 Azure DR 사이트 배포

```bash
cd ~/3tier-terraform/codes/azure/2-emergency

# 설정 파일
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**terraform.tfvars:**

```hcl
environment = "blue"

subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"

# 1-always에서 생성된 리소스 참조
resource_group_name  = "rg-dr-blue"
vnet_name            = "vnet-dr-blue"
storage_account_name = "bloberry01"

# MySQL 설정 (AWS와 동일하게)
db_name     = "pocketbank"
db_username = "mysqladmin"
db_password = "MySecurePassword123!"

mysql_sku        = "B_Standard_B2s"
mysql_storage_gb = 20
```

**배포:**

```bash
terraform init
terraform apply
# yes 입력
```

**⏱️ 소요 시간: 15-20분**

### 5.2 AKS 접속

```bash
# kubeconfig 설정
az aks get-credentials \
  --resource-group rg-dr-blue \
  --name $(terraform output -raw aks_cluster_name) \
  --overwrite-existing

# 노드 확인
kubectl get nodes
```

### 5.3 MySQL 백업 복구

```bash
# 최신 백업 파일 찾기
LATEST_BACKUP=$(az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --query "sort_by([].name, &properties.lastModified)[-1]" \
  --output tsv)

echo "최신 백업: $LATEST_BACKUP"

# 백업 다운로드
az storage blob download \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --name "$LATEST_BACKUP" \
  --file /tmp/backup.sql.gz

# 압축 해제
gunzip /tmp/backup.sql.gz

# MySQL 복구
export MYSQL_HOST=$(cd ~/3tier-terraform/codes/azure/2-emergency && terraform output -raw mysql_fqdn)

mysql -h $MYSQL_HOST -u mysqladmin -p < /tmp/backup.sql
# 비밀번호 입력: MySecurePassword123!
```

### 5.4 PocketBank 배포 (AKS)

```bash
# Namespace 생성
kubectl create namespace pocketbank

# Secret 생성
kubectl create secret generic db-credentials \
  --from-literal=url="jdbc:mysql://${MYSQL_HOST}:3306/pocketbank" \
  --from-literal=username="mysqladmin" \
  --from-literal=password="MySecurePassword123!" \
  --namespace=pocketbank

# Deployment + Service 생성 (한 번에)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: pocketbank-config
  namespace: pocketbank
data:
  SPRING_PROFILES_ACTIVE: mysql
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pocketbank
  namespace: pocketbank
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pocketbank
  template:
    metadata:
      labels:
        app: pocketbank
    spec:
      containers:
      - name: pocketbank
        image: springcommunity/spring-pocketbank:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        - name: SPRING_PROFILES_ACTIVE
          valueFrom:
            configMapKeyRef:
              name: pocketbank-config
              key: SPRING_PROFILES_ACTIVE
---
apiVersion: v1
kind: Service
metadata:
  name: pocketbank
  namespace: pocketbank
spec:
  type: LoadBalancer
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: pocketbank
EOF

# Pod 시작 확인
kubectl get pods -n pocketbank -w
```

**Pod가 CrashLoopBackOff면:** [트러블슈팅](troubleshooting.md#85-aks-pocketbank-pod-crashloopbackoff-mysql-연결-실패) 참조

### 5.5 Application Gateway 주소 확인

```bash
# App Gateway IP 확인
az network public-ip show \
  -g rg-dr-blue \
  -n pip-appgw-blue \
  --query ipAddress \
  -o tsv

# 브라우저 접속 또는 curl
curl -I http://<APP_GATEWAY_IP>/
```

**✅ 성공!** Azure에서 PocketBank이 정상 작동하면 DR 테스트 완료!

---

## 6. 리소스 정리

**⚠️ 중요: 비용 발생을 막기 위해 반드시 삭제하세요!**

### 6.1 삭제 순서 (역순)

```bash
# 1. Azure DR 리소스 삭제
cd ~/3tier-terraform/codes/azure/2-emergency
terraform destroy
# yes 입력

# 2. AWS Primary 삭제
cd ~/3tier-terraform/codes/aws/service
terraform destroy
# yes 입력

# 3. Azure 대기 리소스 삭제
cd ~/3tier-terraform/codes/azure/1-always
terraform destroy
# yes 입력
```

**⏱️ 소요 시간: 각 10-15분, 총 30-45분**

### 6.2 완전 정리 확인

```bash
# AWS 리소스 확인
aws ec2 describe-instances --query "Reservations[*].Instances[*].{ID:InstanceId,State:State.Name}"
aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier"

# Azure 리소스 확인
az group list --query "[?starts_with(name, 'rg-dr')].name"

# 남아있는 리소스가 있으면 수동 삭제
```

---

## 💡 다음 단계

축하합니다! Multi-Cloud DR 시스템을 성공적으로 구축하고 테스트했습니다!

### 더 공부하고 싶다면

1. **[트러블슈팅 가이드](troubleshooting.md)** 읽어보기
2. **CloudFront 수동 Failover** 직접 해보기
3. **모니터링 대시보드** 구축해보기
4. **CI/CD 파이프라인** 추가해보기

### 도움이 필요하면

- GitHub Issues: [이슈 등록](https://github.com/reynecat/3tier-terraform/issues)
- Discord/Slack: 커뮤니티 참여

---

**문서 버전**: v1.0
**최종 수정**: 2025-12-23
**작성자**: I2ST-blue

**즐거운 학습 되세요!** 🚀
