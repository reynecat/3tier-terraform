# AWS EKS PetClinic 배포 가이드

## 목차
1. [사전 확인](#1-사전-확인)
2. [AWS Load Balancer Controller 설치](#2-aws-load-balancer-controller-설치)
3. [데이터베이스 Secret 생성](#3-데이터베이스-secret-생성)
4. [PetClinic 애플리케이션 배포](#4-petclinic-애플리케이션-배포)
5. [Ingress 배포 및 확인](#5-ingress-배포-및-확인)
6. [접속 테스트](#6-접속-테스트)
7. [모니터링 및 관리](#7-모니터링-및-관리)
8. [문제 해결](#8-문제-해결)

---

## 1. 사전 확인

### 1.1 Terraform 배포 완료 확인

```bash
cd PlanB/aws

# Terraform 출력 확인
terraform output

# 주요 정보 확인
export CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
export AWS_REGION=$(terraform output -raw aws_region)

echo "Cluster: $CLUSTER_NAME"
echo "RDS: $RDS_ENDPOINT"
echo "Region: $AWS_REGION"
```

### 1.2 kubectl 설정

```bash
# EKS 클러스터 인증 정보 가져오기
aws eks update-kubeconfig \
  --region $AWS_REGION \
  --name $CLUSTER_NAME

# 연결 확인
kubectl cluster-info
kubectl get nodes

# 노드 상태 확인 (모두 Ready여야 함)
kubectl get nodes -o wide
```

예상 출력:
```
NAME                                            STATUS   ROLES    AGE   VERSION
ip-10-0-11-xxx.ap-northeast-2.compute.internal  Ready    <none>   10m   v1.34.x
ip-10-0-12-xxx.ap-northeast-2.compute.internal  Ready    <none>   10m   v1.34.x
ip-10-0-21-xxx.ap-northeast-2.compute.internal  Ready    <none>   10m   v1.34.x
ip-10-0-22-xxx.ap-northeast-2.compute.internal  Ready    <none>   10m   v1.34.x
```

### 1.3 RDS 연결 정보 확인

```bash
# RDS 엔드포인트에서 호스트명 추출
export RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
export RDS_PORT=3306
export DB_NAME="petclinic"
export DB_USERNAME="admin"

echo "RDS Host: $RDS_HOST"
echo "Database: $DB_NAME"
```

---

## 2. AWS Load Balancer Controller 설치

### 2.1 IAM Policy 생성

```bash
# IAM Policy JSON 다운로드
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# IAM Policy 생성
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json

# Policy ARN 저장
export LBC_POLICY_ARN=$(aws iam list-policies \
  --query 'Policies[?PolicyName==`AWSLoadBalancerControllerIAMPolicy`].Arn' \
  --output text)

echo "Policy ARN: $LBC_POLICY_ARN"
```

### 2.2 IAM ServiceAccount 생성

```bash
# OIDC Provider 생성 (아직 없는 경우)
eksctl utils associate-iam-oidc-provider \
  --region $AWS_REGION \
  --cluster $CLUSTER_NAME \
  --approve

# ServiceAccount 생성
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=$LBC_POLICY_ARN \
  --override-existing-serviceaccounts \
  --region $AWS_REGION \
  --approve
```

### 2.3 Helm으로 Controller 설치

```bash
# Helm repo 추가
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# AWS Load Balancer Controller 설치
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$AWS_REGION \
  --set vpcId=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)

# 설치 확인
kubectl get deployment -n kube-system aws-load-balancer-controller

# Pod 상태 확인
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

예상 출력:
```
NAME                                            READY   STATUS    RESTARTS   AGE
aws-load-balancer-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
aws-load-balancer-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          30s
```

---

## 3. 데이터베이스 Secret 생성

### 3.1 Namespace 생성

```bash
cd k8s-manifests

# Namespace 생성
kubectl apply -f namespaces.yaml

# 확인
kubectl get namespaces
```

### 3.2 DB Secret 생성 (수동 방법)

```bash
# RDS 비밀번호 입력받기
read -sp "RDS Password: " DB_PASSWORD
echo

# JDBC URL 생성
JDBC_URL="jdbc:mysql://${RDS_HOST}:${RDS_PORT}/${DB_NAME}"

echo "JDBC URL: $JDBC_URL"

# WAS Namespace에 Secret 생성
kubectl create secret generic db-credentials \
  --from-literal=url="$JDBC_URL" \
  --from-literal=username="$DB_USERNAME" \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=was \
  --dry-run=client -o yaml | kubectl apply -f -

# Secret 생성 확인
kubectl get secret db-credentials -n was

# Secret 내용 확인 (base64 인코딩됨)
kubectl describe secret db-credentials -n was
```

### 3.3 DB Secret 생성 (스크립트 방법)

```bash
# 배포 스크립트 생성
cat > create-db-secret.sh << 'EOF'
#!/bin/bash
set -e

# RDS 정보 가져오기
RDS_ENDPOINT=$(cd .. && terraform output -raw rds_endpoint)
RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
DB_NAME="petclinic"
DB_USERNAME="admin"

# 비밀번호 입력
read -sp "RDS Password: " DB_PASSWORD
echo

# JDBC URL
JDBC_URL="jdbc:mysql://${RDS_HOST}:3306/${DB_NAME}"

echo "Creating Secret with:"
echo "  URL: $JDBC_URL"
echo "  Username: $DB_USERNAME"

# Secret 생성
kubectl create secret generic db-credentials \
  --from-literal=url="$JDBC_URL" \
  --from-literal=username="$DB_USERNAME" \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=was \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret created successfully!"
EOF

chmod +x create-db-secret.sh

# 실행
./create-db-secret.sh
```

---

## 4. PetClinic 애플리케이션 배포

### 4.1 WAS Tier 배포

```bash
# WAS Deployment 및 Service 배포
kubectl apply -f was/deployment.yaml
kubectl apply -f was/service.yaml

# Pod 생성 대기 (최대 2분)
kubectl wait --for=condition=ready pod \
  -l app=was-spring \
  -n was \
  --timeout=120s

# Pod 상태 확인
kubectl get pods -n was -o wide

# Pod 로그 확인 (Spring Boot 시작 확인)
kubectl logs -f deployment/was-spring -n was --tail=50
```

예상 로그:
```
  .   ____          _            __ _ _
 /\\ / ___'_ __ _ _(_)_ __  __ _ \ \ \ \
( ( )\___ | '_ | '_| | '_ \/ _` | \ \ \ \
 \\/  ___)| |_)| | | | | || (_| |  ) ) ) )
  '  |____| .__|_| |_|_| |_\__, | / / / /
 =========|_|==============|___/=/_/_/_/
 :: Spring Boot ::                (v3.x.x)

... Started PetClinicApplication in X.XXX seconds ...
```

### 4.2 Web Tier 배포

```bash
# Web Deployment 및 Service 배포
kubectl apply -f web/deployment.yaml
kubectl apply -f web/service.yaml

# Pod 생성 대기
kubectl wait --for=condition=ready pod \
  -l app=web-nginx \
  -n web \
  --timeout=60s

# Pod 상태 확인
kubectl get pods -n web -o wide

# Nginx 설정 확인
kubectl logs deployment/web-nginx -n web --tail=20
```

### 4.3 배포 상태 전체 확인

```bash
# 모든 네임스페이스의 리소스 확인
kubectl get all -n web
kubectl get all -n was

# Pod 상세 정보
kubectl describe pods -n was
kubectl describe pods -n web

# Service 엔드포인트 확인
kubectl get endpoints -n was
kubectl get endpoints -n web
```

---

## 5. Ingress 배포 및 확인

### 5.1 Ingress 배포

```bash
# Ingress 리소스 생성
kubectl apply -f ingress/ingress.yaml

# Ingress 상태 확인
kubectl get ingress -n web

# 상세 정보 확인
kubectl describe ingress web-ingress -n web
```

### 5.2 ALB 생성 대기 및 확인

```bash
# ALB 생성 대기 (약 2-3분 소요)
echo "Waiting for ALB to be created..."

# ADDRESS 필드에 DNS가 나타날 때까지 대기
while true; do
  ALB_DNS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  if [ ! -z "$ALB_DNS" ]; then
    echo "ALB DNS: $ALB_DNS"
    break
  fi
  echo "Waiting for ALB... (checking again in 10s)"
  sleep 10
done

# ALB 정보 저장
export ALB_DNS=$ALB_DNS
echo "export ALB_DNS=$ALB_DNS" >> ~/.bashrc
```

### 5.3 AWS Console에서 ALB 확인

```bash
# ALB ARN 확인
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(DNSName, '$(echo $ALB_DNS | cut -d'-' -f1)')].LoadBalancerArn" \
  --output text

# Target Group 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names k8s-web-webservi-* \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)
```

---

## 6. 접속 테스트

### 6.1 기본 연결 테스트

```bash
# ALB DNS 확인
echo "ALB URL: http://$ALB_DNS"

# Health Check 엔드포인트 테스트
curl -I http://$ALB_DNS/health

# 예상 응답: HTTP/1.1 200 OK
```

### 6.2 PetClinic 애플리케이션 테스트

```bash
# 홈페이지 접속 테스트
curl -s http://$ALB_DNS/ | grep -o "<title>.*</title>"

# 예상 출력: <title>PetClinic :: a Spring Framework demonstration</title>

# API 엔드포인트 테스트
curl -s http://$ALB_DNS/vets.html | head -20

# 전체 응답 확인
curl -v http://$ALB_DNS/
```

### 6.3 브라우저 접속

```bash
# URL 출력
echo "=========================================="
echo "PetClinic Application"
echo "=========================================="
echo ""
echo "URL: http://$ALB_DNS"
echo ""
echo "브라우저에서 위 URL로 접속하세요."
echo "=========================================="
```

브라우저에서 확인할 내용:
- PetClinic 홈페이지 정상 로드
- "Find Owners" 메뉴 동작
- "Veterinarians" 목록 표시
- MySQL 데이터 정상 조회

### 6.4 데이터베이스 연동 확인

```bash
# WAS Pod에서 MySQL 연결 테스트
WAS_POD=$(kubectl get pods -n was -l app=was-spring -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $WAS_POD -n was -- sh -c "
  apt-get update -qq && apt-get install -y -qq mysql-client > /dev/null 2>&1
  mysql -h $RDS_HOST -u $DB_USERNAME -p$DB_PASSWORD -e 'USE petclinic; SHOW TABLES;'
"
```

---

## 7. 모니터링 및 관리

### 7.1 실시간 모니터링

```bash
# 전체 Pod 상태 모니터링
watch -n 2 'kubectl get pods -A'

# 특정 네임스페이스 모니터링
kubectl get pods -n web -w
kubectl get pods -n was -w

# 로그 실시간 확인
kubectl logs -f deployment/was-spring -n was
kubectl logs -f deployment/web-nginx -n web
```

### 7.2 리소스 사용량 확인

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods -n web
kubectl top pods -n was

# 전체 리소스 사용량
kubectl top pods -A
```

### 7.3 이벤트 확인

```bash
# 최근 이벤트 확인
kubectl get events -n web --sort-by='.lastTimestamp'
kubectl get events -n was --sort-by='.lastTimestamp'

# 경고/에러만 필터링
kubectl get events -n web --field-selector type=Warning
kubectl get events -n was --field-selector type=Warning
```

### 7.4 스케일링

```bash
# WAS Pod 스케일 아웃
kubectl scale deployment was-spring -n was --replicas=3

# Web Pod 스케일 아웃
kubectl scale deployment web-nginx -n web --replicas=3

# 상태 확인
kubectl get pods -n was
kubectl get pods -n web

# 원복
kubectl scale deployment was-spring -n was --replicas=2
kubectl scale deployment web-nginx -n web --replicas=2
```

---

## 8. 문제 해결

### 8.1 Pod가 시작되지 않는 경우

**증상: Pending 상태**

```bash
kubectl get pods -n was
kubectl describe pod <pod-name> -n was
```

일반적인 원인:
- 노드 리소스 부족
- 이미지 Pull 실패
- nodeAffinity 조건 불일치

해결 방법:

```bash
# 노드 리소스 확인
kubectl describe nodes | grep -A 5 "Allocated resources"

# 이미지 확인
kubectl describe pod <pod-name> -n was | grep -A 10 "Events"

# 노드 레이블 확인
kubectl get nodes --show-labels | grep tier
```

### 8.2 Database 연결 실패

**증상: CrashLoopBackOff, Connection refused**

```bash
# WAS Pod 로그 확인
kubectl logs deployment/was-spring -n was --tail=100 | grep -i error

# Secret 확인
kubectl get secret db-credentials -n was -o yaml
kubectl get secret db-credentials -n was -o jsonpath='{.data.url}' | base64 -d

# RDS 보안 그룹 확인
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*rds*" \
  --query "SecurityGroups[].IpPermissions[]"
```

해결 방법:

```bash
# Secret 재생성
kubectl delete secret db-credentials -n was
./create-db-secret.sh

# Pod 재시작
kubectl rollout restart deployment/was-spring -n was
```

### 8.3 ALB가 생성되지 않는 경우

**증상: Ingress ADDRESS 필드 비어있음**

```bash
# AWS Load Balancer Controller 로그 확인
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Ingress 이벤트 확인
kubectl describe ingress web-ingress -n web
```

해결 방법:

```bash
# Controller 재시작
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system

# Ingress 재생성
kubectl delete ingress web-ingress -n web
kubectl apply -f ingress/ingress.yaml
```

### 8.4 503 Service Unavailable

**증상: ALB는 생성되었으나 503 에러**

```bash
# Target Group 상태 확인
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --query "TargetGroups[?contains(TargetGroupName, 'k8s-web')].TargetGroupArn" \
    --output text)

# Pod 상태 확인
kubectl get pods -n web
kubectl describe pods -n web

# Service 엔드포인트 확인
kubectl get endpoints -n web
```

해결 방법:

```bash
# Pod가 Ready 상태인지 확인
kubectl get pods -n web -o wide

# Health Check 경로 확인
curl http://<pod-ip>/health

# Pod 재시작
kubectl rollout restart deployment/web-nginx -n web
```

### 8.5 Nginx에서 WAS 연결 실패

**증상: 502 Bad Gateway**

```bash
# Nginx 로그 확인
kubectl logs deployment/web-nginx -n web

# WAS Service 확인
kubectl get svc was-service -n was
kubectl get endpoints was-service -n was

# DNS 확인
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
nslookup was-service.was.svc.cluster.local
```

해결 방법:

```bash
# WAS Pod 상태 확인
kubectl get pods -n was

# WAS 재시작
kubectl rollout restart deployment/was-spring -n was

# Nginx 재시작
kubectl rollout restart deployment/web-nginx -n web
```

---

## 9. 배포 스크립트 (자동화)

전체 배포를 자동화하는 스크립트:

```bash
cat > scripts/deploy-app.sh << 'EOF'
#!/bin/bash
# PetClinic 전체 배포 자동화 스크립트

set -e

echo "=========================================="
echo "PetClinic Application Deployment"
echo "=========================================="
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# RDS 정보 가져오기
cd ..
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
DB_NAME="petclinic"
DB_USERNAME="admin"
cd k8s-manifests

echo -e "${YELLOW}[1/7] RDS 정보 확인...${NC}"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo "  Database: $DB_NAME"
echo ""

# 비밀번호 입력
read -sp "RDS Password: " DB_PASSWORD
echo ""
echo ""

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}비밀번호가 입력되지 않았습니다.${NC}"
    exit 1
fi

# Namespace 생성
echo -e "${YELLOW}[2/7] Namespace 생성...${NC}"
kubectl apply -f namespaces.yaml
echo ""

# Secret 생성
echo -e "${YELLOW}[3/7] Database Secret 생성...${NC}"
JDBC_URL="jdbc:mysql://${RDS_HOST}:3306/${DB_NAME}"
kubectl create secret generic db-credentials \
  --from-literal=url="$JDBC_URL" \
  --from-literal=username="$DB_USERNAME" \
  --from-literal=password="$DB_PASSWORD" \
  --namespace=was \
  --dry-run=client -o yaml | kubectl apply -f -
echo -e "${GREEN}Secret 생성 완료${NC}"
echo ""

# WAS 배포
echo -e "${YELLOW}[4/7] WAS Tier 배포...${NC}"
kubectl apply -f was/deployment.yaml
kubectl apply -f was/service.yaml
echo "WAS Pod 시작 대기 (최대 120초)..."
kubectl wait --for=condition=ready pod \
  -l app=was-spring \
  -n was \
  --timeout=120s || {
    echo -e "${RED}WAS Pod 시작 실패${NC}"
    kubectl get pods -n was
    kubectl logs deployment/was-spring -n was --tail=50
    exit 1
}
echo -e "${GREEN}WAS 배포 완료${NC}"
echo ""

# Web 배포
echo -e "${YELLOW}[5/7] Web Tier 배포...${NC}"
kubectl apply -f web/deployment.yaml
kubectl apply -f web/service.yaml
echo "Web Pod 시작 대기 (최대 60초)..."
kubectl wait --for=condition=ready pod \
  -l app=web-nginx \
  -n web \
  --timeout=60s || {
    echo -e "${RED}Web Pod 시작 실패${NC}"
    kubectl get pods -n web
    exit 1
}
echo -e "${GREEN}Web 배포 완료${NC}"
echo ""

# Ingress 배포
echo -e "${YELLOW}[6/7] Ingress 배포...${NC}"
kubectl apply -f ingress/ingress.yaml
echo ""

# ALB 생성 대기
echo -e "${YELLOW}[7/7] ALB 생성 대기...${NC}"
echo "ALB가 생성되는 동안 대기합니다 (약 2-3분)..."
RETRY_COUNT=0
MAX_RETRIES=30

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  ALB_DNS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  
  if [ ! -z "$ALB_DNS" ]; then
    echo -e "${GREEN}ALB 생성 완료!${NC}"
    echo ""
    break
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "대기 중... ($RETRY_COUNT/$MAX_RETRIES)"
  sleep 10
done

if [ -z "$ALB_DNS" ]; then
    echo -e "${RED}ALB 생성 시간 초과${NC}"
    echo "Ingress 상태 확인:"
    kubectl describe ingress web-ingress -n web
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}배포 완료!${NC}"
echo "=========================================="
echo ""
echo "리소스 상태:"
kubectl get pods -n web
kubectl get pods -n was
echo ""
echo "접속 정보:"
echo "  ALB URL: http://$ALB_DNS"
echo ""
echo "브라우저에서 위 URL로 접속하세요."
echo ""
echo "로그 확인:"
echo "  kubectl logs -f deployment/was-spring -n was"
echo "  kubectl logs -f deployment/web-nginx -n web"
echo ""

EOF

chmod +x scripts/deploy-app.sh
```

스크립트 실행:

```bash
cd k8s-manifests
./scripts/deploy-app.sh
```

---

## 10. 정리 및 삭제

애플리케이션만 삭제 (인프라는 유지):

```bash
# Ingress 삭제 (ALB 자동 삭제)
kubectl delete -f ingress/ingress.yaml

# 애플리케이션 삭제
kubectl delete -f web/
kubectl delete -f was/

# Namespace 삭제
kubectl delete -f namespaces.yaml

# 확인
kubectl get all -A | grep -E 'web|was'
```

전체 인프라 삭제:

```bash
cd PlanB/aws
terraform destroy
```

---

마지막 업데이트: 2024-12-19