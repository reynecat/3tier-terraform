# PlanB Azure 3-failover

재해 시 배포: MySQL + AKS 클러스터 + PocketBank

## 포함 리소스

### MySQL Flexible Server
- SKU: B_Standard_B2s (Burstable)
- Storage: 20GB
- Backup: 7일 보관
- 백업 복구 후 사용

### AKS Cluster
- Kubernetes Version: 1.28
- Node Pool: 2-5 노드 (Auto Scaling)
- VM Size: Standard_D2s_v3
- Network: Azure CNI

### 예상 비용
- MySQL: ~$15/월
- AKS: ~$150/월 (2 노드)
- **총: ~$165/월** (재해 시에만 배포)

## 배포 전 준비

### 1. 1-always가 배포되어 있어야 함
```bash
cd ../1-always
terraform output
# Resource Group, VNet, Subnet 확인
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

# 1-always에서 생성된 리소스
resource_group_name  = "rg-dr-prod"
vnet_name           = "vnet-dr-prod"
storage_account_name = "drbackupprod2024"

# MySQL 설정
db_password         = "your-secure-password"
```

## 배포 순서

### Step 1: Terraform 배포 (MySQL + AKS)
```bash
terraform init
terraform plan
terraform apply
```

배포 시간: 약 15-20분

### Step 2: MySQL 백업 복구
```bash
# 복구 스크립트 실행
./restore-db.sh

# 또는 수동 복구
# 1. 최신 백업 파일 다운로드
az storage blob download \
  --account-name drbackupprod2024 \
  --container-name mysql-backups \
  --name backups/backup-2024-12-22.sql.gz \
  --file backup.sql.gz

# 2. 압축 해제
gunzip backup.sql.gz

# 3. MySQL 복구
mysql -h mysql-dr-prod.mysql.database.azure.com \
      -u mysqladmin \
      -p < backup.sql
```

### Step 3: AKS 설정
```bash
# kubeconfig 설정
az aks get-credentials \
  --resource-group rg-dr-prod \
  --name aks-dr-prod

# 클러스터 확인
kubectl get nodes
kubectl get namespaces
```

### Step 4: PocketBank 배포
```bash
cd scripts
./deploy-pocketbank.sh

# 또는 수동 배포
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

### Step 5: LoadBalancer IP 확인
```bash
# Service 확인
kubectl get svc -n web

# LoadBalancer IP 획득 (약 2-3분 소요)
kubectl get svc web-nginx -n web -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Step 6: Route53 업데이트 (도메인이 있는 경우)
```bash
# LoadBalancer IP 확인
LB_IP=$(kubectl get svc web-nginx -n web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Route53 레코드 업데이트
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "example.com",
        "Type": "A",
        "TTL": 60,
        "ResourceRecords": [{"Value": "'$LB_IP'"}]
      }
    }]
  }'
```

## 배포 확인

### MySQL 확인
```bash
# MySQL 접속
mysql -h mysql-dr-prod.mysql.database.azure.com \
      -u mysqladmin \
      -p

# 데이터베이스 확인
SHOW DATABASES;
USE pocketbank;
SHOW TABLES;
```

### AKS 확인
```bash
# Pod 상태
kubectl get pods -A

# Service 확인
kubectl get svc -A

# Log 확인
kubectl logs -n web deployment/web-nginx
kubectl logs -n was deployment/was-spring
```

### 웹사이트 접근
```bash
# LoadBalancer IP로 직접 접속
curl http://<LoadBalancer-IP>

# 도메인 접속 (Route53 업데이트 후)
curl https://example.com
```

## 아키텍처

```
┌─────────────────────────────────────────┐
│ Route53 (도메인 업데이트)               │
│                                         │
│ example.com → AKS LoadBalancer IP       │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ AKS Cluster                             │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ Web Tier (Nginx)                    │ │
│ │ - Replicas: 2                       │ │
│ │ - Service: LoadBalancer             │ │
│ └─────────────────────────────────────┘ │
│               ↓                         │
│ ┌─────────────────────────────────────┐ │
│ │ WAS Tier (Spring PocketBank)         │ │
│ │ - Replicas: 2                       │ │
│ │ - Service: ClusterIP                │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
                  ↓
┌─────────────────────────────────────────┐
│ MySQL Flexible Server                   │
│                                         │
│ - FQDN: mysql-dr-prod.mysql...          │
│ - Database: pocketbank                   │
└─────────────────────────────────────────┘
```

## 트러블슈팅

### MySQL 접속 실패
```bash
# 방화벽 규칙 확인
az mysql flexible-server firewall-rule list \
  --resource-group rg-dr-prod \
  --name mysql-dr-prod

# 내 IP 추가
MY_IP=$(curl -s ifconfig.me)
az mysql flexible-server firewall-rule create \
  --resource-group rg-dr-prod \
  --name mysql-dr-prod \
  --rule-name AllowMyIP \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP
```

### LoadBalancer IP가 할당되지 않음
```bash
# Service 이벤트 확인
kubectl describe svc web-nginx -n web

# AKS Role Assignment 확인
az role assignment list \
  --assignee $(az aks show -g rg-dr-prod -n aks-dr-prod --query identity.principalId -o tsv) \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-dr-prod
```

### Pod가 시작되지 않음
```bash
# Pod 상세 정보
kubectl describe pod <pod-name> -n <namespace>

# Log 확인
kubectl logs <pod-name> -n <namespace>

# 이벤트 확인
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## 복구 (Failback)

AWS Primary가 복구되면:

### 1. AWS EKS로 트래픽 전환
```bash
# Route53을 AWS ALB로 업데이트
aws route53 change-resource-record-sets ...
```

### 2. Azure 리소스 삭제 (비용 절감)
```bash
terraform destroy
```

단, **1-always는 유지** (Storage Account, VNet)

## 비용 관리

### 평상시 (1-always만 실행)
- Storage Account: ~$5/월

### 재해 시 (3-failover 추가 배포)
- Storage Account: ~$5/월
- MySQL: ~$15/월
- AKS: ~$150/월
- **총: ~$170/월**

### 권장사항
- 재해 복구 후 가능한 빨리 AWS Primary로 Failback
- Azure 리소스는 즉시 `terraform destroy`로 삭제
- 1-always만 유지하여 비용 최소화
