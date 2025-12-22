# Failover 테스트 가이드 (업데이트)

## 아키텍처 개요

### Primary (AWS)
- EKS Cluster
- RDS MySQL
- ALB Ingress
- Route53: example.com → AWS ALB

### Secondary (Azure)
**평상시 (1-always):**
- Storage Account (점검 페이지)
- VNet (예약)
- Route53: maintenance.example.com → Blob Storage (CNAME)

**재해 시 (3-failover):**
- MySQL Flexible Server
- AKS Cluster
- LoadBalancer
- Route53: example.com → AKS LoadBalancer IP (수동 업데이트)

## 📋 사전 준비

### 1. 현재 상태 확인
```bash
# DNS 확인
dig example.com +short
# 예상 결과: AWS ALB IP

# 점검 페이지 확인 (평상시)
dig maintenance.example.com CNAME
# 예상 결과: storage-account.z12.web.core.windows.net

curl https://maintenance.example.com/
# 예상 결과: 점검 페이지 HTML

# AWS EKS Pod 상태
kubectl config use-context arn:aws:eks:ap-northeast-2:xxx:cluster/blue-eks
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: web-nginx 2개, was-spring 2개 Running
```

## 🔥 Failover 시나리오

### Step 1: AWS Primary 장애 발생 (시뮬레이션)

```bash
# AWS EKS 컨텍스트로 전환
kubectl config use-context arn:aws:eks:ap-northeast-2:xxx:cluster/blue-eks

# Web과 WAS Pod를 0으로 스케일 다운 (장애 시뮬레이션)
kubectl scale deployment web-nginx -n web --replicas=0
kubectl scale deployment was-spring -n was --replicas=0

# 확인
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: No resources found
```

**장애 확인:**
```bash
# 웹사이트 접속 시도
curl -I https://example.com
# 예상 결과: HTTP 503 Service Unavailable
```

### Step 2: Route53 Failover 발동 (점검 페이지)

**자동 Failover (Route53 Health Check):**
- Primary 장애 감지 (약 60초)
- Route53이 Secondary로 자동 전환

**확인:**
```bash
# DNS 변경 확인 (약 60초 대기)
dig maintenance.example.com +short
# 예상 결과: storage-account.z12.web.core.windows.net

# 점검 페이지 접속
curl https://maintenance.example.com/
# 예상 결과: HTTP 200 OK, 점검 페이지 HTML

curl -s https://maintenance.example.com/ | grep title
# 예상 결과: <title>서비스 점검 중</title>
```

**이 단계에서 사용자는:**
- maintenance.example.com 으로 점검 페이지 확인
- 메인 도메인(example.com)은 여전히 장애 상태

### Step 3: Azure 3-failover 배포 (MySQL + AKS)

```bash
cd codes/azure/3-failover

# 배포
terraform apply
# 배포 시간: 약 15-20분
```

**MySQL 백업 복구:**
```bash
./restore-db.sh
# MySQL 백업 자동 복구
```

**AKS 설정:**
```bash
# kubeconfig 설정
az aks get-credentials --resource-group rg-dr-prod --name aks-dr-prod

# PetClinic 배포
cd scripts
./deploy-petclinic.sh

# LoadBalancer IP 확인
kubectl get svc web-nginx -n web
# EXTERNAL-IP 획득까지 약 2-3분 소요
```

### Step 4: 메인 도메인 Route53 업데이트

```bash
# LoadBalancer IP 확인
LB_IP=$(kubectl get svc web-nginx -n web -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Azure LoadBalancer IP: $LB_IP"

# Route53 레코드 수동 업데이트
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

# DNS 전파 대기 (약 60초)
sleep 60

# DNS 변경 확인
dig example.com +short
# 예상 결과: Azure LoadBalancer IP
```

### Step 5: Failover 성공 확인

```bash
# 메인 도메인 접속
curl -I https://example.com
# 예상 결과: HTTP 200 OK

# PetClinic 페이지 확인
curl -s https://example.com | grep title
# 예상 결과: <title>PetClinic :: a Spring Framework demonstration</title>

# Azure AKS Pod 상태
kubectl config use-context <azure-aks-context>
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: web-nginx 2/2, was-spring 2/2 Running
```

**이 단계에서:**
- example.com → Azure AKS (정상 서비스)
- maintenance.example.com → Blob Storage (점검 페이지, 더 이상 필요 없음)

## 🔄 Failback: AWS Primary로 복구

### Step 1: AWS Pod 복구

```bash
# AWS EKS 컨텍스트
kubectl config use-context arn:aws:eks:ap-northeast-2:xxx:cluster/blue-eks

# Pod 복구
kubectl scale deployment web-nginx -n web --replicas=2
kubectl scale deployment was-spring -n was --replicas=2

# Pod 시작 확인 (약 60초 대기)
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: web-nginx 2/2 Running, was-spring 2/2 Running
```

### Step 2: AWS 서비스 확인

```bash
# AWS ALB IP 확인
ALB_DNS=$(kubectl get ingress -n web web-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "AWS ALB: $ALB_DNS"

# ALB 접속 테스트
curl -I http://$ALB_DNS
# 예상 결과: HTTP 200 OK
```

### Step 3: Route53을 AWS로 복구

```bash
# Route53 레코드를 AWS ALB로 업데이트
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "example.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z1234567890ABC",
          "DNSName": "'$ALB_DNS'",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'

# DNS 전파 대기 (약 60초)
sleep 60

# DNS 복구 확인
dig example.com +short
# 예상 결과: AWS ALB IP
```

### Step 4: 복구 확인

```bash
# 웹사이트 접속
curl -I https://example.com
# 예상 결과: HTTP 200 OK

# PetClinic 페이지 확인
curl -s https://example.com | grep title
# 예상 결과: <title>PetClinic :: a Spring Framework demonstration</title>
```

### Step 5: Azure 리소스 삭제 (비용 절감)

```bash
cd codes/azure/3-failover

# MySQL + AKS 삭제
terraform destroy
# 확인: yes

# 주의: 1-always는 삭제하지 않음!
# Storage Account와 점검 페이지는 평상시에도 유지
```

**Failback 완료:**
- example.com → AWS ALB (Primary 복구)
- maintenance.example.com → Blob Storage (평상시 대기)
- Azure 3-failover 리소스 삭제 완료

## 📊 Failover 타임라인

### 자동 Failover (점검 페이지)
1. AWS 장애 발생: 0분
2. Route53 Health Check 감지: ~1분
3. maintenance.example.com 전환: ~2분
4. **사용자는 점검 페이지 확인 가능**

### 수동 Failover (전체 서비스)
1. 3-failover 배포 시작: 장애 발생 후 즉시
2. MySQL + AKS 배포 완료: ~20분
3. MySQL 백업 복구: ~5분
4. PetClinic 배포: ~5분
5. Route53 업데이트: ~2분
6. **총 소요 시간: 약 30-35분**

### Failback (AWS 복구)
1. AWS Pod 복구: ~2분
2. Route53 업데이트: ~2분
3. Azure 리소스 삭제: ~10분
4. **총 소요 시간: 약 15분**

## 🔍 주요 변경사항

### 이전 아키텍처 (2-emergency)
- Application Gateway 사용 (비용: ~$150/월)
- AG가 Blob Storage 프록시
- MySQL만 별도 배포

### 새 아키텍처 (1-always + 3-failover)
- **평상시:** Storage Account만 실행 (~$5/월)
- **점검 페이지:** Route53 CNAME → Blob Storage (Application Gateway 불필요)
- **재해 시:** MySQL + AKS 한 번에 배포 (~$165/월)
- **비용 절감:** Application Gateway 제거로 월 ~$150 절감

## 💡 권장사항

1. **정기적인 훈련**
   - 월 1회 Failover 테스트
   - 자동화 스크립트 검증

2. **백업 관리**
   - AWS RDS 자동 백업
   - Azure Blob Storage 30일 보관

3. **모니터링**
   - Route53 Health Check 알림
   - AWS CloudWatch + Azure Monitor

4. **비용 최적화**
   - 재해 복구 후 즉시 Azure 리소스 삭제
   - 1-always만 평상시 유지

5. **문서화**
   - Failover 절차 문서 업데이트
   - 담당자 연락처 관리
