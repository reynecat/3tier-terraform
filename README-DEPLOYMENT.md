# 멀티클라우드 DR 아키텍처 배포 가이드

> AWS EKS + Azure VM 기반 고가용성 3-Tier 웹 서비스 및 재해복구 시스템

## 📋 목차

- [사전 준비 완료 확인](#사전-준비-완료-확인)
- [1단계: 프로젝트 구조 확인](#1단계-프로젝트-구조-확인)
- [2단계: AWS 인프라 배포](#2단계-aws-인프라-배포)
- [3단계: Azure 인프라 배포](#3단계-azure-인프라-배포)
- [4단계: VPN 연결 구성](#4단계-vpn-연결-구성)
- [5단계: EKS 애플리케이션 배포](#5단계-eks-애플리케이션-배포)
- [6단계: 데이터 동기화 확인](#6단계-데이터-동기화-확인)
- [7단계: DNS Failover 설정](#7단계-dns-failover-설정)
- [8단계: 모니터링 구성](#8단계-모니터링-구성)
- [트러블슈팅](#트러블슈팅)
- [정리 및 삭제](#정리-및-삭제)

---

## 사전 준비 완료 확인

다음 항목들이 설치되고 로그인되어 있어야 합니다:

### ✅ 필수 도구 설치 확인
```bash
# Terraform 버전 확인 (1.5 이상)
terraform version

# AWS CLI 확인 및 로그인 상태
aws sts get-caller-identity

# Azure CLI 확인 및 로그인 상태
az account show

# kubectl 확인 (1.28 이상)
kubectl version --client

# Helm 확인 (3.0 이상)
helm version
```

**모든 명령어가 정상적으로 실행되면 다음 단계로 진행하세요.**

---

## 1단계: 프로젝트 구조 확인

### 프로젝트 디렉토리 구조
```bash
cd terraform-multi-cloud-dr
tree -L 2

# 예상 구조:
# .
# ├── main.tf                    # AWS 메인 Terraform 파일
# ├── variables.tf               # AWS 변수 정의
# ├── outputs.tf                 # AWS 출력 정의
# ├── terraform.tfvars.example   # 변수 예제 파일
# ├── modules/
# │   ├── vpc/                   # VPC 모듈
# │   ├── alb/                   # ALB 모듈
# │   ├── rds/                   # RDS 모듈
# │   └── eks/                   # EKS 모듈
# ├── k8s-manifests/
# │   └── application.yaml       # Kubernetes 배포 매니페스트
# ├── scripts/
# │   ├── lambda-db-sync/        # Lambda 함수
# │   └── deploy-eks-app.sh      # EKS 배포 스크립트
# └── terraform/
#     └── azure/                 # Azure Terraform 코드
#         ├── main.tf
#         ├── variables.tf
#         ├── outputs.tf
#         └── scripts/
```

### 핵심 파일 설명
- **AWS 인프라**: 루트 디렉토리의 Terraform 파일
- **Azure 인프라**: `terraform/azure/` 디렉토리
- **Kubernetes 배포**: `k8s-manifests/application.yaml`
- **데이터 동기화**: `scripts/lambda-db-sync/`

---

## 2단계: AWS 인프라 배포

### 2.1 환경 변수 설정

```bash
# 현재 AWS 계정 정보 확인
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION="ap-northeast-2"

echo "AWS Account ID: $AWS_ACCOUNT_ID"
echo "AWS Region: $AWS_REGION"
```

### 2.2 Terraform 변수 파일 생성

```bash
# terraform.tfvars.example을 복사
cp terraform.tfvars.example terraform.tfvars

# 변수 파일 편집
nano terraform.tfvars
```

**terraform.tfvars 필수 수정 항목:**
```hcl
# ==================== 기본 설정 ====================
environment    = "prod"
aws_region     = "ap-northeast-2"

# ==================== 도메인 설정 ====================
domain_name    = "example.com"           # 본인 도메인으로 변경 ⚠️
alarm_email    = "admin@example.com"     # 알람 수신 이메일 변경 ⚠️

# ==================== DB 설정 ====================
db_name        = "petclinic"
db_username    = "admin"
# db_password는 자동 생성됨

# ==================== EKS 설정 ====================
eks_node_instance_type = "t3.medium"

# Web Tier Node Group
eks_web_desired_size   = 2
eks_web_min_size       = 1
eks_web_max_size       = 4

# WAS Tier Node Group
eks_was_desired_size   = 2
eks_was_min_size       = 1
eks_was_max_size       = 4

# ==================== RDS 설정 ====================
db_instance_class      = "db.t3.micro"   # 개발: db.t3.micro, 운영: db.t3.small
multi_az               = true            # Multi-AZ 활성화
```

### 2.3 Lambda 함수 패키징

```bash
# Lambda 함수 디렉토리로 이동
cd scripts/lambda-db-sync

# 패키징 스크립트 실행 권한 부여
chmod +x package.sh

# 패키징 실행
./package.sh

# 결과 확인
ls -lh lambda-package.zip

# 프로젝트 루트로 복귀
cd ../..
```

**출력 예시:**
```
Installing dependencies...
Creating deployment package...
✓ Lambda package created: lambda-package.zip (2.5 MB)
```

### 2.4 Terraform 초기화

```bash
# Terraform 초기화
terraform init

# 실행 계획 확인
terraform plan
```

**plan 출력 확인 사항:**
- 생성될 리소스 수: 약 50-60개
- VPC, Subnets, EKS Cluster, RDS, Lambda 등

### 2.5 AWS 인프라 배포

```bash
# 배포 실행 (약 20-30분 소요)
terraform apply

# 확인 후 "yes" 입력
```

**배포 진행 상황:**
```
1. VPC 및 네트워크 생성 (2-3분)
2. RDS MySQL 생성 (10-15분) ⏰
3. EKS Cluster 생성 (10-15분) ⏰
4. EKS Node Groups 생성 (5분)
5. Lambda, S3, CloudWatch 생성 (2-3분)
```

### 2.6 배포 결과 확인

```bash
# Terraform outputs 확인
terraform output

# 주요 출력 항목:
# - aws_eks_cluster_name
# - aws_rds_endpoint
# - aws_alb_dns_name
# - aws_vpc_id
# - db_credentials (sensitive)
```

**outputs 저장:**
```bash
# 나중에 사용할 정보 저장
terraform output -json > aws-outputs.json

# DB 비밀번호 확인 (안전한 곳에 저장)
terraform output -json db_credentials | jq -r '.password'
```

---

## 3단계: Azure 인프라 배포

### 3.1 Azure 디렉토리로 이동

```bash
cd terraform/azure
```

### 3.2 SSH 키 생성 (Azure VM 접속용)

```bash
# SSH 키 생성
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_dr_key -N ""

# 공개 키 확인
cat ~/.ssh/azure_dr_key.pub
```

### 3.3 Azure 변수 파일 생성

```bash
# 현재 공인 IP 확인
export MY_PUBLIC_IP=$(curl -s ifconfig.me)
echo "Your Public IP: $MY_PUBLIC_IP"

# terraform.tfvars 파일 생성
cat > terraform.tfvars <<EOF
# ==================== 기본 설정 ====================
environment     = "prod"
location        = "koreacentral"

# ==================== 관리자 설정 ====================
admin_username  = "azureuser"
admin_ip        = "$MY_PUBLIC_IP/32"
ssh_public_key  = "$(cat ~/.ssh/azure_dr_key.pub)"

# ==================== VM 크기 설정 ====================
web_vm_size     = "Standard_B2s"   # 2 vCPU, 4GB RAM
was_vm_size     = "Standard_B2ms"  # 2 vCPU, 8GB RAM

# ==================== Application Gateway ====================
appgw_capacity  = 1

# ==================== MySQL 설정 ====================
mysql_sku       = "B_Standard_B2s"
db_name         = "petclinic"
db_username     = "dbadmin"
db_password     = "$(openssl rand -base64 32 | tr -d /=+ | cut -c -20)P@ssw0rd!"

EOF

# 생성된 파일 확인
cat terraform.tfvars
```

### 3.4 Azure 인프라 배포

```bash
# Terraform 초기화
terraform init

# 실행 계획 확인
terraform plan

# 배포 실행 (약 15-20분 소요)
terraform apply
```

**배포 진행 상황:**
```
1. Resource Group, VNet 생성 (1-2분)
2. Application Gateway 생성 (5-7분) ⏰
3. VM 생성 (Web, WAS) (3-5분)
4. Azure MySQL 생성 (5-10분) ⏰
5. VPN Gateway 생성 (15-20분) ⏰ ⚠️ 가장 오래 걸림
```

### 3.5 Azure 배포 결과 확인

```bash
# Terraform outputs 확인
terraform output

# 주요 출력:
# - application_gateway_public_ip
# - web_vm_public_ip
# - mysql_fqdn
# - vpn_gateway_public_ip
```

**outputs 저장:**
```bash
terraform output -json > azure-outputs.json

# 프로젝트 루트로 복귀
cd ../..
```

---

## 4단계: VPN 연결 구성

### 4.1 VPN 정보 수집

```bash
# AWS VPN Gateway Public IP (Terraform으로 자동 생성된 경우)
export AWS_VPN_IP=$(terraform output -raw aws_vpn_gateway_ip 2>/dev/null || echo "MANUAL")

# Azure VPN Gateway Public IP
export AZURE_VPN_IP=$(cd terraform/azure && terraform output -raw vpn_gateway_public_ip)

echo "AWS VPN Gateway IP: $AWS_VPN_IP"
echo "Azure VPN Gateway IP: $AZURE_VPN_IP"
```

### 4.2 VPN Connection 생성 (수동)

**만약 Terraform에서 VPN이 자동 설정되지 않은 경우:**

#### AWS 측 설정
```bash
# AWS Customer Gateway 생성
aws ec2 create-customer-gateway \
  --type ipsec.1 \
  --public-ip $AZURE_VPN_IP \
  --bgp-asn 65000 \
  --tag-specifications "ResourceType=customer-gateway,Tags=[{Key=Name,Value=azure-cgw}]"

# VPN Connection 생성
aws ec2 create-vpn-connection \
  --type ipsec.1 \
  --customer-gateway-id <customer-gateway-id> \
  --vpn-gateway-id <vpn-gateway-id> \
  --options TunnelOptions=[{PreSharedKey=YourStrongPreSharedKey123!}]
```

#### Azure 측 설정
```bash
# Azure Local Network Gateway 생성
az network local-gateway create \
  --resource-group rg-dr-prod \
  --name lng-aws \
  --gateway-ip-address $AWS_VPN_IP \
  --local-address-prefixes 10.0.0.0/16

# VPN Connection 생성
az network vpn-connection create \
  --resource-group rg-dr-prod \
  --name vpn-aws-azure \
  --vnet-gateway1 vgw-prod \
  --local-gateway2 lng-aws \
  --shared-key YourStrongPreSharedKey123!
```

### 4.3 VPN 연결 확인

```bash
# AWS VPN 상태 확인
aws ec2 describe-vpn-connections

# Azure VPN 상태 확인
az network vpn-connection show \
  --resource-group rg-dr-prod \
  --name vpn-aws-azure \
  --query "connectionStatus"
```

**연결 성공 시: "Connected"**

---

## 5단계: EKS 애플리케이션 배포

### 5.1 kubectl 설정

```bash
# EKS 클러스터 이름 확인
export EKS_CLUSTER_NAME=$(terraform output -raw aws_eks_cluster_name)

# kubectl 설정
aws eks update-kubeconfig \
  --name $EKS_CLUSTER_NAME \
  --region ap-northeast-2

# 연결 확인
kubectl get nodes
```

**예상 출력:**
```
NAME                                            STATUS   ROLES    AGE   VERSION
ip-10-0-11-xxx.ap-northeast-2.compute.internal  Ready    <none>   5m    v1.28.x
ip-10-0-12-xxx.ap-northeast-2.compute.internal  Ready    <none>   5m    v1.28.x
ip-10-0-21-xxx.ap-northeast-2.compute.internal  Ready    <none>   5m    v1.28.x
ip-10-0-22-xxx.ap-northeast-2.compute.internal  Ready    <none>   5m    v1.28.x
```

**노드 레이블 확인:**
```bash
kubectl get nodes --show-labels | grep tier
```

### 5.2 AWS Load Balancer Controller 설치

```bash
# Helm 저장소 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Load Balancer Controller IAM Role ARN 확인
export LBC_ROLE_ARN=$(terraform output -raw load_balancer_controller_role_arn)

# AWS Load Balancer Controller 설치
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$LBC_ROLE_ARN

# 설치 확인
kubectl get deployment -n kube-system aws-load-balancer-controller
```

### 5.3 애플리케이션 배포 (자동 스크립트)

```bash
# 배포 스크립트 실행 권한 부여
chmod +x scripts/deploy-eks-app.sh

# 자동 배포 실행
./scripts/deploy-eks-app.sh
```

**스크립트가 자동으로 수행하는 작업:**
1. Terraform outputs에서 RDS 정보 추출
2. Kubernetes namespace 생성
3. ConfigMap 생성 (DB 연결 정보)
4. Secret 생성 (DB 비밀번호)
5. 애플리케이션 배포 (Web + WAS)
6. Load Balancer 주소 확인

### 5.4 수동 배포 (선택사항)

자동 스크립트 대신 수동으로 배포하려면:

```bash
# 1. RDS 정보 추출
export RDS_ENDPOINT=$(terraform output -raw aws_rds_endpoint)
export DB_USERNAME=$(terraform output -json db_credentials | jq -r '.username')
export DB_PASSWORD=$(terraform output -json db_credentials | jq -r '.password')

# 2. Namespace 생성
kubectl create namespace petclinic

# 3. ConfigMap 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: petclinic-config
  namespace: petclinic
data:
  SPRING_PROFILES_ACTIVE: "mysql"
  SPRING_DATASOURCE_URL: "jdbc:mysql://$RDS_ENDPOINT/petclinic"
EOF

# 4. Secret 생성
kubectl create secret generic petclinic-secret \
  --from-literal=SPRING_DATASOURCE_USERNAME=$DB_USERNAME \
  --from-literal=SPRING_DATASOURCE_PASSWORD=$DB_PASSWORD \
  --namespace=petclinic

# 5. 애플리케이션 배포
kubectl apply -f k8s-manifests/application.yaml
```

### 5.5 배포 확인

```bash
# Pod 상태 확인
kubectl get pods -n petclinic

# 예상 출력:
# NAME                             READY   STATUS    RESTARTS   AGE
# petclinic-web-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# petclinic-web-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# petclinic-was-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# petclinic-was-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# Service 확인
kubectl get svc -n petclinic

# Load Balancer 주소 확인 (최대 3분 소요)
kubectl get svc petclinic-web-service -n petclinic -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### 5.6 애플리케이션 접속 테스트

```bash
# Load Balancer DNS 추출
export LB_DNS=$(kubectl get svc petclinic-web-service -n petclinic -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Application URL: http://$LB_DNS"

# Health Check
curl -I http://$LB_DNS/actuator/health

# 웹 브라우저로 접속
# http://$LB_DNS
```

---

## 6단계: 데이터 동기화 확인

### 6.1 Lambda 함수 확인

```bash
# Lambda 함수 목록
aws lambda list-functions --query 'Functions[?contains(FunctionName, `db-sync`)].FunctionName'

# Lambda 로그 확인 (최근 10분)
aws logs tail /aws/lambda/petclinic-db-sync-prod --follow --since 10m
```

### 6.2 EventBridge 스케줄 확인

```bash
# EventBridge 규칙 확인
aws events list-rules --name-prefix "db-sync"

# 규칙 상태 확인 (ENABLED 확인)
aws events describe-rule --name db-sync-schedule-prod
```

### 6.3 S3 백업 확인

```bash
# S3 버킷 이름 확인
export S3_BUCKET=$(terraform output -raw s3_backup_bucket)

# 백업 파일 확인 (5분 후 생성됨)
aws s3 ls s3://$S3_BUCKET/backups/ --recursive

# 최신 백업 다운로드 (테스트)
aws s3 cp s3://$S3_BUCKET/backups/owners-$(date +%Y%m%d).csv ./test-backup.csv

# 파일 내용 확인
head -5 test-backup.csv
```

### 6.4 수동 Lambda 실행 (테스트)

```bash
# Lambda 함수 수동 실행
aws lambda invoke \
  --function-name petclinic-db-sync-prod \
  --invocation-type RequestResponse \
  --log-type Tail \
  response.json

# 실행 결과 확인
cat response.json | jq .

# 로그 확인
aws logs tail /aws/lambda/petclinic-db-sync-prod --since 5m
```

---

## 7단계: DNS Failover 설정

### 7.1 Route 53 Hosted Zone 확인

```bash
# Hosted Zone ID 확인
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
  --query "HostedZones[?Name=='example.com.'].Id" \
  --output text | cut -d'/' -f3)

echo "Hosted Zone ID: $HOSTED_ZONE_ID"
```

### 7.2 Health Check 생성

```bash
# EKS Load Balancer IP 확인 (Health Check용)
export PRIMARY_LB=$(kubectl get svc petclinic-web-service -n petclinic -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Health Check 생성
aws route53 create-health-check \
  --caller-reference "$(date +%s)" \
  --health-check-config \
    Type=HTTPS,\
ResourcePath=/actuator/health,\
FullyQualifiedDomainName=$PRIMARY_LB,\
Port=80,\
RequestInterval=30,\
FailureThreshold=3 \
  --query 'HealthCheck.Id' \
  --output text
```

### 7.3 DNS 레코드 생성

```bash
# Azure Application Gateway IP 확인
export AZURE_APP_GW_IP=$(cd terraform/azure && terraform output -raw application_gateway_public_ip)

# Primary (AWS) 레코드
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.example.com",
        "Type": "A",
        "SetIdentifier": "Primary-AWS",
        "Failover": "PRIMARY",
        "TTL": 60,
        "ResourceRecords": [{"Value": "'$PRIMARY_LB'"}],
        "HealthCheckId": "<health-check-id>"
      }
    }]
  }'

# Secondary (Azure) 레코드
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "app.example.com",
        "Type": "A",
        "SetIdentifier": "Secondary-Azure",
        "Failover": "SECONDARY",
        "TTL": 60,
        "ResourceRecords": [{"Value": "'$AZURE_APP_GW_IP'"}]
      }
    }]
  }'
```

### 7.4 DNS Failover 테스트

```bash
# DNS 조회
dig app.example.com

# Health Check 상태 확인
aws route53 get-health-check-status --health-check-id <health-check-id>

# Failover 테스트 (Primary 중단 시뮬레이션)
# 1. EKS 애플리케이션 중지
kubectl scale deployment petclinic-web --replicas=0 -n petclinic

# 2. DNS 재조회 (90초 후 Azure로 전환)
watch -n 10 'dig app.example.com +short'

# 3. 복구
kubectl scale deployment petclinic-web --replicas=2 -n petclinic
```

---

## 8단계: 모니터링 구성

### 8.1 CloudWatch Dashboard 확인

```bash
# CloudWatch Dashboard 목록
aws cloudwatch list-dashboards

# 브라우저에서 접속
echo "https://console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:"
```

**주요 메트릭:**
- EKS Cluster CPU/Memory
- RDS CPU/Connections
- Lambda Invocations
- ALB Request Count/Response Time

### 8.2 알람 확인

```bash
# CloudWatch 알람 목록
aws cloudwatch describe-alarms

# 알람 상태 확인
aws cloudwatch describe-alarms \
  --alarm-name-prefix "petclinic" \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

### 8.3 SNS 구독 확인

```bash
# SNS 토픽 확인
aws sns list-topics

# 이메일 구독 확인 (inbox에서 확인 메일 클릭)
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_topic_arn)
```

---

## 트러블슈팅

### 문제 1: EKS 노드가 Ready 상태가 안 됨

**증상:**
```bash
kubectl get nodes
# STATUS: NotReady
```

**해결:**
```bash
# 노드 상세 확인
kubectl describe node <node-name>

# VPC CNI 로그 확인
kubectl logs -n kube-system -l k8s-app=aws-node

# VPC CNI 재시작
kubectl rollout restart daemonset aws-node -n kube-system
```

### 문제 2: Pod가 Pending 상태

**증상:**
```bash
kubectl get pods -n petclinic
# STATUS: Pending
```

**해결:**
```bash
# Pod 이벤트 확인
kubectl describe pod <pod-name> -n petclinic

# 일반적인 원인:
# 1. nodeSelector 불일치
kubectl get nodes --show-labels | grep tier

# 2. 리소스 부족
kubectl top nodes

# 3. Node Group 스케일 업
aws eks update-nodegroup-config \
  --cluster-name $EKS_CLUSTER_NAME \
  --nodegroup-name eks-web-nodes-prod \
  --scaling-config desiredSize=3
```

### 문제 3: RDS 연결 실패

**증상:**
```bash
kubectl logs <was-pod-name> -n petclinic
# Error: Connection refused
```

**해결:**
```bash
# Security Group 확인
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=rds-sg-prod"

# WAS에서 RDS로 연결 테스트
kubectl exec -it <was-pod-name> -n petclinic -- \
  nc -zv <rds-endpoint> 3306

# Security Group 수정 (필요 시)
aws ec2 authorize-security-group-ingress \
  --group-id <rds-sg-id> \
  --protocol tcp \
  --port 3306 \
  --source-group <was-sg-id>
```

### 문제 4: Lambda 함수 실행 실패

**증상:**
```bash
aws lambda invoke --function-name petclinic-db-sync-prod response.json
# Error
```

**해결:**
```bash
# Lambda 로그 확인
aws logs tail /aws/lambda/petclinic-db-sync-prod --since 10m

# 일반적인 원인:
# 1. RDS 연결 실패 → Security Group 확인
# 2. S3 권한 부족 → IAM Role 확인
# 3. VPC 설정 오류 → Lambda VPC 설정 확인

# Lambda 환경 변수 확인
aws lambda get-function-configuration \
  --function-name petclinic-db-sync-prod \
  --query 'Environment.Variables'
```

### 문제 5: Azure VM 접속 불가

**증상:**
```bash
ssh -i ~/.ssh/azure_dr_key azureuser@<vm-ip>
# Connection refused
```

**해결:**
```bash
# NSG 규칙 확인
az network nsg show \
  --resource-group rg-dr-prod \
  --name nsg-web-prod

# Public IP 확인
az vm list-ip-addresses \
  --resource-group rg-dr-prod \
  --name vm-web-prod

# VM 상태 확인
az vm get-instance-view \
  --resource-group rg-dr-prod \
  --name vm-web-prod \
  --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus"
```

---

## 정리 및 삭제

### ⚠️ 주의사항
리소스 삭제 시 **비용이 더 이상 발생하지 않으나 데이터도 영구 삭제**됩니다.

### Azure 리소스 삭제

```bash
cd terraform/azure

# 삭제 전 확인
terraform plan -destroy

# Azure 리소스 삭제 (약 15분 소요)
terraform destroy

# 확인 후 "yes" 입력

cd ../..
```

### AWS 리소스 삭제

```bash
# Kubernetes 리소스 먼저 삭제 (LoadBalancer 정리)
kubectl delete -f k8s-manifests/application.yaml
kubectl delete namespace petclinic

# AWS Load Balancer Controller 삭제
helm uninstall aws-load-balancer-controller -n kube-system

# 3분 대기 (LoadBalancer 완전 삭제 대기)
sleep 180

# Terraform으로 AWS 리소스 삭제 (약 20분 소요)
terraform destroy

# 확인 후 "yes" 입력
```

### 수동 정리 (필요 시)

```bash
# CloudWatch Log Groups (자동 삭제 안 되는 경우)
aws logs delete-log-group --log-group-name /aws/eks/eks-prod/cluster
aws logs delete-log-group --log-group-name /aws/lambda/petclinic-db-sync-prod

# S3 버킷 (내용물이 있는 경우)
aws s3 rm s3://$S3_BUCKET --recursive
aws s3 rb s3://$S3_BUCKET

# VPC 삭제 확인
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=vpc-prod"
```

---

## 📚 추가 문서

- **[QUICKSTART.md](./QUICKSTART.md)** - 빠른 시작 가이드
- **[Web-WAS서브넷분리완료.md](./Web-WAS서브넷분리완료.md)** - 서브넷 분리 설명
- **[Azure-VM기반변경완료.md](./Azure-VM기반변경완료.md)** - Azure VM 아키텍처
- **[EKS수정완료.md](./EKS수정완료.md)** - EKS 아키텍처 설명
- **[아키텍처다이어그램가이드.md](./아키텍처다이어그램가이드.md)** - Mermaid 다이어그램

---

## 🎯 다음 단계

1. **SSL/TLS 인증서 적용**
   ```bash
   # ACM 인증서 요청
   aws acm request-certificate \
     --domain-name "*.example.com" \
     --validation-method DNS
   
   # ALB에 HTTPS 리스너 추가
   ```

2. **CI/CD 파이프라인 구축**
   - GitHub Actions 또는 Jenkins
   - 컨테이너 이미지 자동 빌드/배포

3. **추가 모니터링**
   - Prometheus + Grafana
   - ELK Stack

4. **보안 강화**
   - AWS WAF 설정
   - GuardDuty 활성화
   - Secrets Manager 사용

---

## 💬 지원

- **이슈**: GitHub Issues
- **문서**: README.md 및 관련 문서
- **AWS 문서**: https://docs.aws.amazon.com/
- **Azure 문서**: https://learn.microsoft.com/azure/

---

**배포 완료를 축하합니다! 🎉**

이제 AWS-Azure 멀티클라우드 DR 아키텍처가 완전히 구축되었습니다.
