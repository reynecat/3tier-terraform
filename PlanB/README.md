# PlanB 재해 복구 시스템 사용자 가이드

**Multi-Cloud Disaster Recovery Solution**  
AWS (Primary) ↔ Azure (Secondary DR)

---

## 목차

1. [시스템 개요](#1-시스템-개요)
2. [사전 준비](#2-사전-준비)
3. [1단계: 평상시 대기 (1-always)](#3-1단계-평상시-대기-1-always)
4. [AWS Primary Site 구축](#4-aws-primary-site-구축)
5. [2단계: 긴급 대응 (2-emergency)](#5-2단계-긴급-대응-2-emergency)
6. [3단계: 완전 복구 (3-failover)](#6-3단계-완전-복구-3-failover)
7. [장애 시뮬레이션 테스트](#7-장애-시뮬레이션-테스트)
8. [Failback 절차](#8-failback-절차)
9. [트러블슈팅](#9-트러블슈팅)

---

## 1. 시스템 개요

### 1.1 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      Route53 DNS Failover                    │
│                 Primary (AWS) ↔ Secondary (Azure)            │
└─────────────────────────────────────────────────────────────┘
                         ↓                    ↓
        ┌────────────────────────┐   ┌──────────────────────┐
        │   AWS Primary Site     │   │  Azure DR Site       │
        │  ┌──────────────────┐  │   │  ┌────────────────┐  │
        │  │ EKS (Web+WAS)    │  │   │  │ AKS (3단계)    │  │
        │  │  - Nginx         │  │   │  │  - PetClinic   │  │
        │  │  - Spring Boot   │  │   │  └────────────────┘  │
        │  └──────────────────┘  │   │  ┌────────────────┐  │
        │  ┌──────────────────┐  │   │  │ App Gateway    │  │
        │  │ RDS MySQL        │──┼───┼─→│ (2단계)        │  │
        │  │  - Multi-AZ      │  │   │  └────────────────┘  │
        │  └──────────────────┘  │   │  ┌────────────────┐  │
        │  ┌──────────────────┐  │   │  │ MySQL Flexible │  │
        │  │ Backup EC2       │──┼───┼─→│ (2단계)        │  │
        │  │  - 5분/하루 1회  │  │   │  └────────────────┘  │
        │  └──────────────────┘  │   │  ┌────────────────┐  │
        │         ↓ Backup       │   │  │ Blob Storage   │  │
        │  ┌──────────────────┐  │   │  │  - Backup      │  │
        │  │ Azure Blob       │←─┼───┼──│  - 점검페이지  │  │
        │  └──────────────────┘  │   │  └────────────────┘  │
        └────────────────────────┘   └──────────────────────┘
```

### 1.2 재해 대응 시나리오

#### 1단계 (1-always): 평상시 대기
- **목적**: 최소 비용으로 DR 준비 상태 유지
- **배포 대상**: Azure Storage Account, VNet 예약
- **실행 상태**: AWS에서 정상 서비스, Azure는 백업만 수신

#### 2단계 (2-emergency): 긴급 대응 (T+0 ~ T+15분)
- **목적**: 사용자에게 점검 페이지 노출, DB 복구
- **배포 대상**: Application Gateway, MySQL Flexible Server
- **실행 상태**: 점검 페이지 표시, 데이터베이스 복구 완료

#### 3단계 (3-failover): 완전 복구 (T+15 ~ T+75분)
- **목적**: Azure에서 전체 서비스 복구
- **배포 대상**: AKS 클러스터, PetClinic 애플리케이션
- **실행 상태**: Azure에서 완전한 서비스 제공

### 1.3 핵심 기능

1. **자동 Failover**: Route53 Health Check 기반 DNS 자동 전환
2. **주기적 백업**: AWS RDS → Azure Blob Storage (설정 가능)
3. **단계적 복구**: 비용과 복구 시간의 균형
4. **완전한 격리**: AWS 장애 시 Azure만으로 독립 운영


### 1.4 고려되고 있는 추가 사항들
1. **네트워크 아키텍처 변경** Amazon CloudFront, VPC End Point, Azure Front Door 적용 유무
2. **CI/CD**
---

## 2. 사전 준비

### 2.1 필수 도구 설치

```bash
# Terraform 설치
wget https://releases.hashicorp.com/terraform/1.14.0/terraform_1.14.0_linux_amd64.zip
unzip terraform_1.14.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# eksctl 설치
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# AWS CLI 설치 (이미 설치되어 있으면 생략)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Azure CLI 설치
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# 버전 확인
terraform version
kubectl version --client
eksctl version
helm version
aws --version
az --version
```

### 2.2 AWS 설정

```bash
# AWS 자격증명 설정
aws configure
# AWS Access Key ID: <입력>
# AWS Secret Access Key: <입력>
# Default region name: ap-northeast-2
# Default output format: json

# 계정 확인
aws sts get-caller-identity
```

### 2.3 Azure 설정

```bash
# Azure 로그인
az login

# 구독 확인
az account show

# 구독 ID와 Tenant ID 저장
export AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Subscription ID: $AZURE_SUBSCRIPTION_ID"
echo "Tenant ID: $AZURE_TENANT_ID"
```

### 2.4 프로젝트 클론

```bash
# GitHub에서 프로젝트 클론
git clone https://github.com/reynecat/3tier-terraform.git
cd 3tier-terraform/PlanB
```

### 2.5 도메인 준비

- Route53에 Hosted Zone 생성
- ACM 인증서 발급 (us-east-1 리전)
- 도메인 등록 업체에서 네임서버 설정

---

## 3. 1단계: 평상시 대기 (1-always)

**목적**: 최소 비용으로 Azure에 백업 인프라 준비

### 3.1 설정 파일 작성

```bash
cd azure/1-always
cp terraform.tfvars.example terraform.tfvars
```

**terraform.tfvars 수정**:
```hcl
environment = "prod"
location    = "koreacentral"

# Storage Account (전역 고유 이름 필요)
storage_account_name      = "bloberry01"  # 소문자+숫자, 3-24자
backup_container_name     = "mysql-backups"
backup_retention_days     = 30
storage_replication_type  = "LRS"

# Network
vnet_cidr         = "172.16.0.0/16"
web_subnet_cidr   = "172.16.11.0/24"
was_subnet_cidr   = "172.16.21.0/24"
db_subnet_cidr    = "172.16.31.0/24"
aks_subnet_cidr   = "172.16.41.0/24"
appgw_subnet_cidr = "172.16.1.0/24"

# Azure 구독 정보
subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"
```

### 3.2 배포

```bash
# 초기화
terraform init

# 계획 확인
terraform plan

# 배포 (약 2-3분 소요)
terraform apply

# 출력 확인
terraform output
```

**배포되는 리소스**:
- Storage Account (백업용)
- Blob Container (mysql-backups)
- Static Website ($web - 점검 페이지)
- VNet + 5개 Subnet (예약만, 비용 없음)

### 3.3 점검 페이지 확인

```bash
# Static Website URL 확인
terraform output static_website_endpoint

# 브라우저 접속 또는 curl
curl https://$(terraform output -raw storage_account_name).z12.web.core.windows.net/
```


---

## 4. AWS Primary Site 구축

### 4.1 설정 파일 작성

```bash
cd ../../aws
cp terraform.tfvars.example terraform.tfvars
```

**terraform.tfvars 수정**:
```hcl
environment = "prod"
aws_region  = "ap-northeast-2"

# Azure 연동 (1-always에서 생성한 정보)
azure_storage_account_name  = "drbackupprod2024"
azure_storage_account_key   = "AZURE_STORAGE_KEY"  # Azure Portal에서 확인
azure_backup_container_name = "mysql-backups"
azure_tenant_id             = "TENANT_ID"
azure_subscription_id       = "SUBSCRIPTION_ID"

# 백업 설정
backup_schedule_cron = "0 3 * * *"  # 하루 1회 (실제 운영)
# backup_schedule_cron = "*/5 * * * *"  # 5분마다 (테스트)

# 백업 인스턴스 SSH 키
backup_instance_ssh_public_key = "ssh-rsa AAAA..."

# 데이터베이스
db_name     = "petclinic"
db_username = "admin"
db_password = "MySecurePassword123!"  # 8자 이상, 대소문자+숫자+특수문자

# VPC 설정
aws_vpc_cidr = "10.0.0.0/16"
aws_availability_zones = ["ap-northeast-2a", "ap-northeast-2c"]

# EKS 노드
eks_node_instance_type = "t3.small"
eks_web_desired_size   = 2
eks_web_min_size       = 1
eks_web_max_size       = 4
eks_was_desired_size   = 2
eks_was_min_size       = 1
eks_was_max_size       = 4

# RDS
rds_instance_class    = "db.t3.medium"
rds_multi_az          = true
rds_deletion_protection = false  # 테스트 시

# Route53 & 도메인
enable_custom_domain = true
domain_name          = "yourdomain.com"
```

### 4.2 인프라 배포

```bash
# 초기화
terraform init

# 계획 확인 (약 2분)
terraform plan

# 배포 (약 20-25분 소요)
terraform apply

# 주요 출력 저장
terraform output > outputs.txt
```

**배포되는 리소스**:
- VPC + Subnets (Public, Web, WAS, RDS)
- EKS 클러스터 + 노드 그룹 (Web/WAS 분리)
- RDS MySQL Multi-AZ
- Backup EC2 인스턴스
- Route53 Health Check (Primary)
- Secrets Manager

### 4.3 kubectl 설정

```bash
# EKS 클러스터 접속 설정
aws eks update-kubeconfig --region ap-northeast-2 --name $(terraform output -raw eks_cluster_name)

# 노드 확인
kubectl get nodes

# 출력 예시:
# NAME                                              STATUS   ROLES    AGE   VERSION
# ip-10-0-11-123.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.34.0
# ip-10-0-12-234.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.34.0
# ip-10-0-21-123.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.34.0
# ip-10-0-22-234.ap-northeast-2.compute.internal   Ready    <none>   5m    v1.34.0
```

### 4.4 AWS Load Balancer Controller 설치

```bash
cd k8s-manifests/scripts

# 스크립트 실행 권한 부여
chmod +x install-lb-controller.sh

# 설치 실행 (약 3-5분)
./install-lb-controller.sh

# 설치 확인
kubectl get deployment aws-load-balancer-controller -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# 출력 예시:
# NAME                                           READY   STATUS    RESTARTS   AGE
# aws-load-balancer-controller-xxx-xxx           1/1     Running   0          2m
# aws-load-balancer-controller-xxx-yyy           1/1     Running   0          2m
```

**문제 발생 시**: [트러블슈팅 섹션](#9-트러블슈팅) 참조

### 4.5 PetClinic 애플리케이션 배포

#### 4.5.1 Namespace 생성

```bash
cd ../
kubectl apply -f namespaces.yaml

# 확인
kubectl get namespaces | grep -E "web|was"
```

#### 4.5.2 Database Secret 생성

```bash
# RDS 정보 확인
cd ~/3tier-terraform/PlanB/aws
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)

echo "RDS Host: $RDS_HOST"

# Secret 생성 (비밀번호는 terraform.tfvars와 동일하게)
kubectl create secret generic db-credentials \
  --from-literal=url="jdbc:mysql://${RDS_HOST}:3306/petclinic" \
  --from-literal=username="admin" \
  --from-literal=password="MySecurePassword123!" \
  --namespace=was

# 확인
kubectl get secret db-credentials -n was
```

#### 4.5.3 WAS 배포

```bash
cd k8s-manifests

# WAS 배포
kubectl apply -f was/deployment.yaml
kubectl apply -f was/service.yaml

# Pod 상태 확인
kubectl get pods -n was -w
# Ctrl+C로 중단

# 정상 시작 확인
kubectl logs -n was -l app=was-spring --tail=50 | grep "Started"

# 출력 예시:
# ... Started PetClinicApplication in 16.159 seconds ...
```

#### 4.5.4 Web 배포

```bash
# Web 배포
kubectl apply -f web/deployment.yaml
kubectl apply -f web/service.yaml

# Pod 상태 확인
kubectl get pods -n web
```

#### 4.5.5 Ingress 배포

```bash
# Ingress YAML 수정 (ACM 인증서 ARN 입력)
vi ingress/ingress.yaml

# certificate-arn 부분 수정:
# alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:ap-northeast-2:ACCOUNT:certificate/CERT_ID

# Ingress 배포
kubectl apply -f ingress/ingress.yaml

# ALB 생성 대기 (2-3분)
kubectl get ingress web-ingress -n web -w
# Ctrl+C로 중단
```

#### 4.5.6 ALB DNS 확인 및 접속

```bash
# ALB DNS 확인
export ALB_DNS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "ALB DNS: $ALB_DNS"
echo "URL: http://$ALB_DNS"

# 브라우저 접속 또는 curl
curl -I http://$ALB_DNS
```

### 4.6 Route53 설정

### 4.6.1 Ingress 배포 후 Terraform 재실행
```bash
cd ~/3tier-terraform/PlanB/aws

# Ingress ALB 생성 확인 (2-3분 대기)
kubectl get ingress web-ingress -n web -w
# Ctrl+C로 중단

# ALB DNS 확인
kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo

# Terraform apply로 Route53 레코드 자동 생성
terraform apply

# 출력에서 ALB 정보 확인
terraform output route53_alb_info



```

#### 4.6.2 DNS 전파 확인

```bash
# DNS 조회 (1-2분 후)
dig yourdomain.com +short

# HTTPS 접속
curl -I https://yourdomain.com

# Route53 레코드 확인
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id) \
  --query "ResourceRecordSets[?Name=='yourdomain.com.']"

# 브라우저 접속
echo "https://yourdomain.com"
```

### 4.7 백업 시스템 확인

```bash
# 백업 인스턴스 ID 확인
terraform output backup_instance_id

# SSM Session Manager로 접속
aws ssm start-session --target $(terraform output -raw backup_instance_id)

# 접속 후 실행
sudo tail -f /var/log/mysql-backup-to-azure.log

# 백업 주기 확인
sudo crontab -l

# 출력 예시:
# 0 3 * * * /usr/local/bin/mysql-backup-to-azure.sh  (하루 1회)
# 또는
# */5 * * * * /usr/local/bin/mysql-backup-to-azure.sh  (5분마다 - 테스트)

# 빠져나오기: Ctrl+C 후 exit
exit
```

```bash
# Azure에서 백업 확인 (로컬 터미널)
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --output table

# 최신 백업 확인
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --query "sort_by([].{name:name, size:properties.contentLength, modified:properties.lastModified}, &modified)" \
  --output table
```

**AWS Primary Site 구축 완료!**

---

## 5. 2단계: 긴급 대응 (2-emergency)

**목적**: 재해 발생 후 15분 이내에 점검 페이지 노출 및 DB 복구

### 5.1 시나리오

- AWS ap-northeast-2 리전 완전 마비
- Route53 Primary Health Check 실패 감지
- 사용자에게 점검 페이지 표시 필요
- 데이터베이스 최신 백업으로 복구

### 5.2 설정 파일 작성

```bash
cd ~/3tier-terraform/PlanB/azure/2-emergency
cp terraform.tfvars.example terraform.tfvars
```

**terraform.tfvars 수정**:
```hcl
environment = "prod"

# Azure 구독 정보
subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"

# 1-always에서 생성된 리소스 참조
resource_group_name  = "rg-dr-prod"
vnet_name            = "vnet-dr-prod"
storage_account_name = "drbackupprod2024"

# MySQL 설정
db_name     = "petclinic"
db_username = "mysqladmin"
db_password = "MySecurePassword123!"  # 8자 이상

mysql_sku        = "B_Standard_B2s"
mysql_storage_gb = 20
```

### 5.3 배포 (T+0 ~ T+15분)

```bash
# 초기화
terraform init

# 배포 (10-15분 소요)
terraform apply

# 출력 확인
terraform output
```

**배포되는 리소스**:
- MySQL Flexible Server (B_Standard_B2s)
- Application Gateway (Standard_v2)
- Public IP (App Gateway용)

### 5.4 점검 페이지 확인

```bash
# App Gateway Public IP 확인
export APPGW_IP=$(terraform output -raw appgw_public_ip)

echo "점검 페이지 URL: http://$APPGW_IP"

# 브라우저 접속 또는 curl
curl http://$APPGW_IP

# 점검 페이지가 보이면 성공
```

### 5.5 MySQL 백업 복구

```bash
cd scripts
chmod +x restore-db.sh

# 복구 실행
./restore-db.sh

# 프롬프트에서 비밀번호 입력: byemyblue1!
```

**restore-db.sh 실행 과정**:
1. 최신 백업 파일 찾기
2. Azure Blob Storage에서 다운로드
3. 압축 해제
4. MySQL 복구

**예상 소요 시간**: 5-10분 (백업 크기에 따라)

### 5.6 Route53 Secondary 설정

```bash
# AWS 환경으로 돌아가기
cd ~/3tier-terraform/PlanB/aws

# Azure App Gateway IP를 terraform.tfvars에 추가
echo "azure_appgw_public_ip = \"$APPGW_IP\"" >> terraform.tfvars

# Terraform apply (Route53 Secondary 레코드 생성)
terraform apply

# Health Check 확인
aws route53 get-health-check \
  --health-check-id $(terraform output -json route53_health_check_ids | jq -r '.secondary')
```

**2단계 완료!**

**현재 상태**:
- 점검 페이지가 사용자에게 노출됨
- MySQL 복구 완료
- Route53 Secondary Health Check 활성화
- AWS 복구 시 자동으로 Primary로 복귀

---

## 6. 3단계: 완전 복구 (3-failover)

**목적**: Azure에서 전체 서비스 복구 (재해 장기화 시)

### 6.1 시나리오

- AWS 복구 불가능 또는 장기화
- Azure에서 완전한 서비스 제공 필요
- AKS 클러스터에 PetClinic 배포

### 6.2 설정 파일 작성

```bash
cd ~/3tier-terraform/PlanB/azure/3-failover
cp terraform.tfvars.example terraform.tfvars
```

**terraform.tfvars 수정**:
```hcl

# Azure 구독 정보 
subscription_id = "YOUR_SUBSCRIPTION_ID"
tenant_id       = "YOUR_TENANT_ID"


```

### 6.3 AKS 클러스터 배포 (T+15 ~ T+35분)

```bash
# 초기화
terraform init

# 배포 (15-20분 소요)
terraform apply

# kubectl 설정
az aks get-credentials \
  --resource-group rg-dr-prod \
  --name $(terraform output -raw aks_cluster_name) \
  --overwrite-existing

# 클러스터 확인
kubectl get nodes
kubectl cluster-info
```

### 6.4 PetClinic 배포 (T+35 ~ T+45분)

```bash
cd scripts
chmod +x deploy-petclinic.sh

# 배포 실행
./deploy-petclinic.sh

# 프롬프트에서 비밀번호 입력: MySecurePassword123!
```

**deploy-petclinic.sh 실행 과정**:
1. Namespace 생성 (petclinic)
2. MySQL Secret 생성
3. PetClinic Deployment 생성
4. Service 생성
5. Pod 시작 대기

### 6.5 Application Gateway 업데이트 (T+45 ~ T+50분)

```bash
chmod +x update-appgw.sh

# App Gateway를 점검 페이지에서 AKS로 전환
./update-appgw.sh
```

**update-appgw.sh 실행 과정**:
1. PetClinic Service IP 확인
2. Backend Pool 업데이트
3. HTTP Settings 업데이트
4. Health Probe 업데이트

### 6.6 서비스 확인

```bash
# App Gateway Public IP 확인
export APPGW_IP=$(az network public-ip show \
  --resource-group rg-dr-prod \
  --name pip-appgw-prod \
  --query ipAddress -o tsv)

echo "PetClinic URL: http://$APPGW_IP"

# 접속 테스트
curl -I http://$APPGW_IP

# 브라우저 접속
echo "브라우저에서 접속: http://$APPGW_IP"
```

**3단계 완료!**

**현재 상태**:
- Azure AKS에서 PetClinic 완전 복구
- Application Gateway → AKS 연결
- Route53 Secondary가 Azure를 가리킴
- 사용자는 정상 서비스 이용 가능

---

## 7. 장애 시뮬레이션 테스트

### 7.1 AWS Primary 장애 시뮬레이션

#### 방법 1: EKS 노드 그룹 스케일 다운

```bash
cd ~/3tier-terraform/PlanB/aws

# Web 노드 그룹 스케일 다운
aws eks update-nodegroup-config \
  --cluster-name $(terraform output -raw eks_cluster_name) \
  --nodegroup-name $(terraform output -raw eks_web_node_group_id | cut -d'/' -f2) \
  --scaling-config minSize=0,maxSize=0,desiredSize=0 \
  --region ap-northeast-2

# WAS 노드 그룹 스케일 다운
aws eks update-nodegroup-config \
  --cluster-name $(terraform output -raw eks_cluster_name) \
  --nodegroup-name $(terraform output -raw eks_was_node_group_id | cut -d'/' -f2) \
  --scaling-config minSize=0,maxSize=0,desiredSize=0 \
  --region ap-northeast-2

# 노드 확인 (모두 사라짐)
kubectl get nodes

# Pod 확인 (Pending 상태)
kubectl get pods -A
```

#### 방법 2: Ingress 삭제

```bash
# Ingress 삭제 (ALB 제거)
kubectl delete ingress web-ingress -n web

# ALB 삭제 확인
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(DNSName, 'k8s-web')].DNSName"
```

#### 방법 3: Security Group 규칙 차단

```bash
# ALB Security Group ID 확인
export ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=$(terraform output -raw eks_cluster_name)" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# HTTP/HTTPS 인바운드 규칙 삭제
aws ec2 revoke-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

aws ec2 revoke-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

### 7.2 Failover 확인

```bash
# Route53 Health Check 상태 확인
aws route53 get-health-check-status \
  --health-check-id $(cd ~/3tier-terraform/PlanB/aws && \
    terraform output -json route53_health_check_ids | jq -r '.primary')

# 출력 예시:
# "StatusReport": {
#   "Status": "Failure",  ← Primary 실패
#   "CheckedTime": "2024-12-21T12:00:00Z"
# }

# DNS 조회 (Secondary로 변경 확인)
dig yourdomain.com +short
# Azure App Gateway IP가 반환되어야 함

# 브라우저 접속
echo "https://yourdomain.com"
# Azure에서 서비스되는 PetClinic이 보여야 함
```

### 7.3 Failover 소요 시간 측정

```bash
# 장애 발생 시각 기록
echo "장애 시작: $(date)"

# Health Check 실패 감지: 약 1-2분
# (failure_threshold=3, request_interval=30초)

# DNS TTL 만료: 약 1분
# (Route53 TTL=60초)

# 총 Failover 시간: 약 2-3분
```

### 7.4 복구 (Failback 준비)

#### 방법 1 복구: 노드 그룹 스케일 업

```bash
# Web 노드 복구
aws eks update-nodegroup-config \
  --cluster-name $(terraform output -raw eks_cluster_name) \
  --nodegroup-name $(terraform output -raw eks_web_node_group_id | cut -d'/' -f2) \
  --scaling-config minSize=1,maxSize=4,desiredSize=2 \
  --region ap-northeast-2

# WAS 노드 복구
aws eks update-nodegroup-config \
  --cluster-name $(terraform output -raw eks_cluster_name) \
  --nodegroup-name $(terraform output -raw eks_was_node_group_id | cut -d'/' -f2) \
  --scaling-config minSize=1,maxSize=4,desiredSize=2 \
  --region ap-northeast-2

# 노드 확인
kubectl get nodes

# Pod 확인
kubectl get pods -A
```

#### 방법 2 복구: Ingress 재생성

```bash
cd ~/3tier-terraform/PlanB/aws/k8s-manifests

# Ingress 재생성
kubectl apply -f ingress/ingress.yaml

# ALB 생성 확인 (2-3분)
kubectl get ingress web-ingress -n web -w
```

#### 방법 3 복구: Security Group 규칙 복원

```bash
# HTTP 인바운드 규칙 추가
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# HTTPS 인바운드 규칙 추가
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0
```

### 7.5 Primary 복구 확인

```bash
# Health Check 상태 확인
aws route53 get-health-check-status \
  --health-check-id $(cd ~/3tier-terraform/PlanB/aws && \
    terraform output -json route53_health_check_ids | jq -r '.primary')

# 출력 예시:
# "StatusReport": {
#   "Status": "Success",  ← Primary 복구
#   "CheckedTime": "2024-12-21T12:10:00Z"
# }

# DNS 조회 (Primary로 복귀 확인)
dig yourdomain.com +short
# AWS ALB DNS가 반환되어야 함

# 브라우저 접속
echo "https://yourdomain.com"
# AWS에서 서비스되는 PetClinic이 보여야 함
```

---

## 8. Failback 절차 이건 팀프로젝트 논외

### 8.1 사전 확인

```bash
# AWS Primary 상태 확인
cd ~/3tier-terraform/PlanB/aws

# EKS 노드 상태
kubectl get nodes

# Pod 상태
kubectl get pods -n web
kubectl get pods -n was

# Ingress 및 ALB
kubectl get ingress web-ingress -n web

# RDS 상태
aws rds describe-db-instances \
  --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --query 'DBInstances[0].DBInstanceStatus'
```

### 8.2 데이터 동기화

**중요**: Failback 전에 Azure의 최신 데이터를 AWS로 동기화해야 함

```bash
# Azure MySQL에서 백업 생성
az mysql flexible-server backup create \
  --resource-group rg-dr-prod \
  --server-name mysql-dr-prod \
  --backup-name manual-failback-$(date +%Y%m%d)

# 또는 mysqldump로 백업
cd ~/3tier-terraform/PlanB/azure/2-emergency/scripts

# 수동 백업 스크립트 실행
MYSQL_HOST=$(cd .. && terraform output -raw mysql_fqdn)
mysqldump -h $MYSQL_HOST -u mysqladmin -p \
  --single-transaction \
  --databases petclinic \
  > /tmp/azure-failback-$(date +%Y%m%d).sql

# AWS RDS로 복원
cd ~/3tier-terraform/PlanB/aws
RDS_HOST=$(terraform output -raw rds_address)

mysql -h $RDS_HOST -u admin -p < /tmp/azure-failback-$(date +%Y%m%d).sql
```

### 8.3 Route53 Primary 복구 확인

```bash
# Primary Health Check 상태
aws route53 get-health-check-status \
  --health-check-id $(terraform output -json route53_health_check_ids | jq -r '.primary')

# DNS 레코드 확인
aws route53 list-resource-record-sets \
  --hosted-zone-id $(terraform output -raw route53_zone_id) \
  --query "ResourceRecordSets[?Name=='yourdomain.com.']"

# Primary 복구 확인 후 자동 Failback됨 (1-2분)
```

### 8.4 Failback 확인

```bash
# DNS 조회
dig yourdomain.com +short
# AWS ALB DNS가 반환되면 Failback 성공

# 접속 테스트
curl -I https://yourdomain.com

# Health Check 상태
echo "Primary: "
aws route53 get-health-check-status \
  --health-check-id $(terraform output -json route53_health_check_ids | jq -r '.primary') \
  --query 'HealthCheckObservations[0].StatusReport.Status'

echo "Secondary: "
aws route53 get-health-check-status \
  --health-check-id $(terraform output -json route53_health_check_ids | jq -r '.secondary') \
  --query 'HealthCheckObservations[0].StatusReport.Status'
```

### 8.5 Azure 리소스 정리 


```bash
# 3-failover 리소스 삭제 (AKS)
cd ~/3tier-terraform/PlanB/azure/3-failover
terraform destroy

# 2-emergency 리소스 삭제 (App Gateway, MySQL)
cd ../2-emergency
terraform destroy

# 1-always는 유지 (백업 수신)
```

**Failback 완료!**

---

## 9. 트러블슈팅

### 9.1 AWS Load Balancer Controller 설치 실패

#### 증상
```
aws-load-balancer-controller   0/2     0            0
```

#### 원인
- ServiceAccount가 없음
- IAM Role 설정 오류
- OIDC Provider 미설정

#### 해결
```bash
cd ~/3tier-terraform/PlanB/aws

# 1. 변수 확인
export CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Cluster: $CLUSTER_NAME"
echo "Account: $ACCOUNT_ID"

# 2. OIDC Provider 설정
eksctl utils associate-iam-oidc-provider \
  --region ap-northeast-2 \
  --cluster $CLUSTER_NAME \
  --approve

# 3. IAM Policy 확인/생성
if ! aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy &>/dev/null; then
    curl -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file:///tmp/iam-policy.json
fi

# 4. ServiceAccount 수동 생성
export OIDC_PROVIDER=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region ap-northeast-2 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed -e "s/^https:\/\///")

export ROLE_NAME="AWSLoadBalancerControllerRole-$(date +%s)"

cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
        "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
      }
    }
  }]
}
EOF

aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json

aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy

export ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF

# 5. Deployment 재시작
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

# 6. 확인
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### 9.2 WAS Pod CrashLoopBackOff

#### 증상
```
was-spring-xxx   0/1     CrashLoopBackOff
```

#### 원인
- DB 연결 실패 (비밀번호 불일치)
- RDS 보안 그룹 설정 오류

#### 해결
```bash
# 1. Pod 로그 확인
kubectl logs -n was -l app=was-spring --tail=100

# 2. Secret 확인
kubectl get secret db-credentials -n was -o jsonpath='{.data.password}' | base64 -d
echo

# 3. 비밀번호가 틀렸다면 Secret 재생성
kubectl delete secret db-credentials -n was

export RDS_HOST=$(cd ~/3tier-terraform/PlanB/aws && terraform output -raw rds_address)

kubectl create secret generic db-credentials \
  --from-literal=url="jdbc:mysql://${RDS_HOST}:3306/petclinic" \
  --from-literal=username="admin" \
  --from-literal=password="MySecurePassword123!" \
  --namespace=was

# 4. Deployment 재시작
kubectl rollout restart deployment was-spring -n was

# 5. 로그 확인
kubectl logs -f deployment/was-spring -n was
```

### 9.3 ALB 생성 안됨

#### 증상
```
web-ingress   alb     *                 80      10m
```
(ADDRESS 비어있음)

#### 원인
- Public Subnet 태그 누락
- HTTPS 설정 오류 (리스너 443 없음)

#### 해결
```bash
# 1. Ingress 로그 확인
kubectl describe ingress web-ingress -n web

kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100

# 2. Public Subnet 태그 추가
cd ~/3tier-terraform/PlanB/aws
export VPC_ID=$(terraform output -raw vpc_id)
export CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export PUBLIC_SUBNET_IDS=$(terraform output -json public_subnet_ids | jq -r '.[]')

for SUBNET_ID in $PUBLIC_SUBNET_IDS; do
  echo "Tagging subnet: $SUBNET_ID"
  aws ec2 create-tags \
    --resources $SUBNET_ID \
    --tags \
      Key=kubernetes.io/role/elb,Value=1 \
      Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared
done

# 3. HTTPS 설정 확인 (ingress.yaml)
# certificate-arn이 올바른지 확인
kubectl get ingress web-ingress -n web -o yaml | grep certificate-arn

# 4. Ingress 재생성
kubectl delete ingress web-ingress -n web
sleep 30
kubectl apply -f k8s-manifests/ingress/ingress.yaml

# 5. ALB 생성 확인
kubectl get ingress web-ingress -n web -w
```

### 9.4 Route53 DNS 전파 안됨

#### 증상
```bash
dig yourdomain.com
# ANSWER: 0
```

#### 원인
- 도메인 등록 업체 네임서버 미변경
- Hosted Zone ID 불일치

#### 해결
```bash
# 1. Route53 네임서버 확인
aws route53 get-hosted-zone \
  --id $(cd ~/3tier-terraform/PlanB/aws && terraform output -raw route53_zone_id) \
  --query 'DelegationSet.NameServers'

# 2. 도메인 등록 업체에서 네임서버 확인
whois yourdomain.com | grep -i "name server"

# 3. 일치하지 않으면 도메인 등록 업체 사이트에서 네임서버 변경

# 4. DNS 전파 대기
# 5. 임시로 /etc/hosts 사용
dig $(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}') +short
# ALB IP 확인 후
echo "ALB_IP yourdomain.com" | sudo tee -a /etc/hosts
```

### 9.5 Azure 백업 복구 실패

#### 증상
```
ERROR: Backup file not found
```

#### 원인
- Storage Account Key 불일치
- Container 이름 오류

#### 해결
```bash
# 1. Storage Account 확인
az storage account show \
  --name drbackupprod2024 \
  --query 'name'

# 2. Container 확인
az storage container show \
  --account-name drbackupprod2024 \
  --name mysql-backups

# 3. 백업 파일 확인
az storage blob list \
  --account-name drbackupprod2024 \
  --container-name mysql-backups \
  --output table

# 4. 수동 복구
LATEST_BACKUP=$(az storage blob list \
  --account-name drbackupprod2024 \
  --container-name mysql-backups \
  --query "sort_by([].name, &properties.lastModified)[-1]" \
  --output tsv)

az storage blob download \
  --account-name drbackupprod2024 \
  --container-name mysql-backups \
  --name "$LATEST_BACKUP" \
  --file /tmp/backup.sql.gz

gunzip /tmp/backup.sql.gz

mysql -h $(cd ~/3tier-terraform/PlanB/azure/2-emergency && terraform output -raw mysql_fqdn) \
  -u mysqladmin -p < /tmp/backup.sql
```


## 부록 A: 주요 명령어 모음

### AWS

```bash
# EKS 접속
aws eks update-kubeconfig --region ap-northeast-2 --name CLUSTER_NAME

# RDS 상태 확인
aws rds describe-db-instances --db-instance-identifier DB_ID

# Route53 Health Check
aws route53 get-health-check-status --health-check-id HC_ID

# ALB 목록
aws elbv2 describe-load-balancers

# Backup Instance 접속
aws ssm start-session --target INSTANCE_ID
```

### Azure

```bash
# AKS 접속
az aks get-credentials --resource-group RG_NAME --name AKS_NAME

# MySQL 상태
az mysql flexible-server show --resource-group RG_NAME --name SERVER_NAME

# Blob Storage 백업 목록
az storage blob list --account-name ACCOUNT_NAME --container-name CONTAINER_NAME

# App Gateway IP
az network public-ip show --resource-group RG_NAME --name PIP_NAME --query ipAddress
```

### Kubernetes

```bash
# Pod 확인
kubectl get pods -A

# 로그 확인
kubectl logs -f POD_NAME -n NAMESPACE

# Deployment 재시작
kubectl rollout restart deployment DEPLOYMENT_NAME -n NAMESPACE

# Ingress 확인
kubectl get ingress -A

# Secret 확인
kubectl get secret SECRET_NAME -n NAMESPACE -o yaml
```

---

## 부록 B: 체크리스트

### 배포 전 체크리스트

- [ ] AWS CLI 설정 완료
- [ ] Azure CLI 로그인 완료
- [ ] Terraform 설치 완료
- [ ] kubectl 설치 완료
- [ ] eksctl 설치 완료
- [ ] Helm 설치 완료
- [ ] 도메인 준비 (Route53 Hosted Zone)
- [ ] ACM 인증서 발급
- [ ] SSH 키 생성
- [ ] terraform.tfvars 작성 (AWS)
- [ ] terraform.tfvars 작성 (Azure 1-always)

### AWS 배포 후 체크리스트

- [ ] EKS 클러스터 정상 동작
- [ ] RDS MySQL 접속 가능
- [ ] Backup Instance 백업 정상 작동
- [ ] ALB 생성 완료
- [ ] PetClinic 정상 접속
- [ ] HTTPS 적용 완료
- [ ] Route53 Primary Health Check 정상
- [ ] Azure Blob에 백업 파일 확인

### Azure 2단계 배포 후 체크리스트

- [ ] MySQL Flexible Server 생성
- [ ] App Gateway 생성
- [ ] 점검 페이지 접속 가능
- [ ] MySQL 백업 복구 완료
- [ ] Route53 Secondary Health Check 정상

### Azure 3단계 배포 후 체크리스트

- [ ] AKS 클러스터 생성
- [ ] PetClinic Pod Running
- [ ] App Gateway → AKS 연결
- [ ] PetClinic 정상 접속
- [ ] Route53 Failover 테스트 완료

---

**문서 버전**: v1.0  
**최종 수정**: 2024-12-21  
**작성자**: I2ST-blue
