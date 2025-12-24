# DR Failover 테스트 가이드

## 개요

이 문서는 실제 DR 시나리오를 테스트하는 절차를 상세히 설명합니다. 3단계로 구성됩니다:

1. **Phase 1**: AWS Web Pod를 0으로 스케일링 → Blob Storage 정적 페이지로 자동 failover
2. **Phase 2**: 장애 장기화 가정 → Azure 2-failover 배포 → Application Gateway로 트래픽 전환
3. **Phase 3**: AWS 복구 → Azure 인프라 정리 → Blob Storage secondary origin 원복

---

## 사전 준비사항

### 필수 확인사항

```bash
# 1. AWS 자격증명 확인
aws sts get-caller-identity

# 2. Azure 자격증명 확인
az account show

# 3. kubectl 컨텍스트 확인
kubectl config current-context

# 4. 현재 서비스 상태 확인
curl -I https://blueisthenewblack.store
```

### 필요한 정보 수집

```bash
# AWS EKS 클러스터 정보
cd /home/ubuntu/3tier-terraform/codes/aws/service
export AWS_CLUSTER_NAME=$(terraform output -raw cluster_name)
export AWS_REGION="ap-northeast-2"

# Route53 CloudFront 정보
cd /home/ubuntu/3tier-terraform/codes/aws/route53
export CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id)

# Azure Blob Storage 정보
export BLOB_ENDPOINT="bloberry01.z12.web.core.windows.net"
```

---

## Phase 1: 단기 장애 시뮬레이션 (Blob Storage Failover)

### 목표
AWS Web Pod를 의도적으로 중단시켜 CloudFront가 자동으로 Azure Blob Storage의 정적 유지보수 페이지로 failover되는지 확인

### 1.1 현재 상태 확인

```bash
# AWS EKS 자격증명 설정
cd /home/ubuntu/3tier-terraform/codes/aws/service
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name $(terraform output -raw cluster_name)

# 현재 Web 노드 그룹 상태 확인
export WEB_NODEGROUP=$(aws eks list-nodegroups \
  --cluster-name $(terraform output -raw cluster_name) \
  --region ap-northeast-2 \
  --query "nodegroups[?contains(@, 'web')]" \
  --output text)

aws eks describe-nodegroup \
  --cluster-name $(terraform output -raw cluster_name) \
  --nodegroup-name $WEB_NODEGROUP \
  --region ap-northeast-2 \
  --query 'nodegroup.scalingConfig'

# 출력 예시:
# {
#     "minSize": 2,
#     "maxSize": 4,
#     "desiredSize": 2
# }
```

### 1.2 Web Pod Desired 개수를 0으로 스케일링

```bash
# Web 노드 그룹 스케일 다운 (desired=0)
aws eks update-nodegroup-config \
  --cluster-name $(terraform output -raw cluster_name) \
  --nodegroup-name $WEB_NODEGROUP \
  --scaling-config minSize=0,maxSize=4,desiredSize=0 \
  --region ap-northeast-2

# 노드 스케일링 상태 모니터링
echo "Waiting for nodes to scale down to 0..."
watch -n 5 "kubectl get nodes -l role=web"
```

**예상 결과:**
- 2-3분 후 Web 노드가 모두 사라짐
- `No resources found` 메시지 출력

### 1.3 ALB Health Check 실패 확인

```bash
# ALB 상태 확인
cd /home/ubuntu/3tier-terraform/codes/aws/service
export ALB_ARN=$(terraform output -raw alb_arn)
export TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn $ALB_ARN \
  --region ap-northeast-2 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Target Health 확인 (약 2-3분 후 모두 unhealthy로 변경됨)
watch -n 5 "aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region ap-northeast-2 \
  --query 'TargetHealthDescriptions[*].[Target.Id, TargetHealth.State]' \
  --output table"
```

**예상 결과:**
```
--------------------------------
|  DescribeTargetHealth        |
+----------------+-------------+
|  None          |  unused     |
+----------------+-------------+
```

### 1.4 CloudFront Failover 확인

```bash
# CloudFront가 Secondary Origin(Blob Storage)으로 failover 되었는지 확인
# 약 3-5분 소요 (CloudFront Health Check Interval)

# 1. 도메인 접속 테스트
curl -I https://blueisthenewblack.store

# 예상 응답:
# HTTP/2 503 (또는 200 with maintenance page)
# x-cache: Error from cloudfront (Primary failed)
# 또는
# x-cache: Hit from cloudfront (Secondary origin served)

# 2. 실제 HTML 내용 확인
curl -s https://blueisthenewblack.store | grep -i "maintenance\|unavailable"

# 예상 결과: Blob Storage의 정적 유지보수 페이지 내용 표시
```

### 1.5 Blob Storage 정적 페이지 확인

```bash
# Azure Blob Storage 직접 접속 테스트
curl -I https://bloberry01.z12.web.core.windows.net/

# 예상 결과:
# HTTP/1.1 200 OK
# Content-Type: text/html
```

**브라우저에서 확인:**
1. `https://blueisthenewblack.store` 접속
2. 정적 유지보수 페이지 표시 확인 (PetClinic이 아닌 정적 HTML)

---

## Phase 2: 장기 장애 대응 (Azure Application Gateway로 전환)

### 목표
장애가 장기화되었다고 가정하고, Azure 2-failover 인프라를 배포하여 완전한 PetClinic 서비스를 Azure에서 제공

### 2.1 Azure 2-failover 인프라 배포

```bash
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover

# Terraform 초기화 (처음 한 번만)
terraform init

# 배포 계획 확인
terraform plan

# 배포 실행 (약 15-20분 소요)
terraform apply -auto-approve

# 배포 완료 후 출력값 확인
terraform output
```

**배포되는 리소스:**
- Azure MySQL Flexible Server (PetClinic DB)
- Azure AKS Cluster (Kubernetes)
- Application Gateway (External Load Balancer)
- Public IP (Application Gateway용)

### 2.2 Azure MySQL 데이터 복구

#### 옵션 A: Azure Blob Storage 백업 사용 (권장)

```bash
# 1. 최신 백업 파일 확인
LATEST_BACKUP=$(az storage blob list \
  --account-name bloberry01 \
  --container-name backups \
  --prefix petclinic- \
  --query "sort_by([].{name:name, lastModified:properties.lastModified}, &lastModified)[-1].name" \
  --output tsv)

echo "Latest backup: $LATEST_BACKUP"

# 2. 백업 파일 다운로드
az storage blob download \
  --account-name bloberry01 \
  --container-name backups \
  --name "$LATEST_BACKUP" \
  --file /tmp/petclinic-backup.sql

# 3. Azure MySQL 접속 정보 확인
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover
AZURE_MYSQL_HOST=$(terraform output -raw mysql_fqdn)
AZURE_MYSQL_USER=$(terraform output -raw mysql_admin_username)
AZURE_MYSQL_DB=$(terraform output -raw mysql_database_name)

# 4. 현재 IP에서 MySQL 접근 허용
MY_IP=$(curl -s ifconfig.me)
az mysql flexible-server firewall-rule create \
  --resource-group rg-blue \
  --name mysql-dr-blue \
  --rule-name allow-my-ip \
  --start-ip-address $MY_IP \
  --end-ip-address $MY_IP

# 5. 데이터 복구 (비밀번호 입력 필요)
mysql -h $AZURE_MYSQL_HOST \
  -u $AZURE_MYSQL_USER \
  -p \
  $AZURE_MYSQL_DB < /tmp/petclinic-backup.sql

# 복구 확인
mysql -h $AZURE_MYSQL_HOST -u $AZURE_MYSQL_USER -p -e "USE $AZURE_MYSQL_DB; SHOW TABLES;"
```

### 2.3 Azure AKS에 PetClinic 배포

```bash
# 1. AKS 자격증명 구성
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover

az aks get-credentials \
  --resource-group rg-blue \
  --name $(terraform output -raw aks_cluster_name) \
  --overwrite-merge

# 컨텍스트 확인
kubectl config current-context

# 노드 확인
kubectl get nodes

# 2. Namespace 생성
kubectl create namespace petclinic

# 3. ConfigMap 및 Secret 생성
AZURE_MYSQL_HOST=$(terraform output -raw mysql_fqdn)
AZURE_MYSQL_DB=$(terraform output -raw mysql_database_name)
AZURE_MYSQL_USER=$(terraform output -raw mysql_admin_username)

kubectl create configmap petclinic-config -n petclinic \
  --from-literal=MYSQL_HOST=$AZURE_MYSQL_HOST \
  --from-literal=MYSQL_PORT=3306 \
  --from-literal=MYSQL_DATABASE=$AZURE_MYSQL_DB

# DB 비밀번호 입력 필요
read -sp "Enter MySQL password: " MYSQL_PASSWORD
echo

kubectl create secret generic petclinic-secret -n petclinic \
  --from-literal=MYSQL_USER=$AZURE_MYSQL_USER \
  --from-literal=MYSQL_PASSWORD=$MYSQL_PASSWORD

# 4. PetClinic Deployment 배포
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic
  namespace: petclinic
spec:
  replicas: 2
  selector:
    matchLabels:
      app: petclinic
  template:
    metadata:
      labels:
        app: petclinic
    spec:
      containers:
      - name: petclinic
        image: springcommunity/spring-petclinic:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: mysql
        - name: MYSQL_HOST
          valueFrom:
            configMapKeyRef:
              name: petclinic-config
              key: MYSQL_HOST
        - name: MYSQL_PORT
          valueFrom:
            configMapKeyRef:
              name: petclinic-config
              key: MYSQL_PORT
        - name: MYSQL_DATABASE
          valueFrom:
            configMapKeyRef:
              name: petclinic-config
              key: MYSQL_DATABASE
        - name: SPRING_DATASOURCE_URL
          value: jdbc:mysql://$(MYSQL_HOST):$(MYSQL_PORT)/$(MYSQL_DATABASE)
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: petclinic-secret
              key: MYSQL_USER
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: petclinic-secret
              key: MYSQL_PASSWORD
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 90
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 5
EOF

# 5. Service 생성
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: petclinic
  namespace: petclinic
spec:
  type: ClusterIP
  selector:
    app: petclinic
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
EOF

# 6. 배포 상태 모니터링
kubectl rollout status deployment/petclinic -n petclinic -w

# Pod 상태 확인
kubectl get pods -n petclinic -o wide
```

**예상 결과:**
```
NAME                         READY   STATUS    RESTARTS   AGE
petclinic-xxxxxxxxx-xxxxx    1/1     Running   0          2m
petclinic-xxxxxxxxx-xxxxx    1/1     Running   0          2m
```

### 2.4 Application Gateway Backend Pool 업데이트

```bash
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover

# 1. PetClinic Service의 ClusterIP 확인
PETCLINIC_IP=$(kubectl get svc petclinic -n petclinic -o jsonpath='{.spec.clusterIP}')
echo "PetClinic Service ClusterIP: $PETCLINIC_IP"

# 2. Application Gateway 정보 확인
APPGW_NAME=$(terraform output -raw appgw_name)
APPGW_RG="rg-blue"

# 3. Backend Pool을 Blob Storage에서 AKS Service로 변경
az network application-gateway address-pool update \
  --resource-group $APPGW_RG \
  --gateway-name $APPGW_NAME \
  --name blob-backend-pool \
  --servers $PETCLINIC_IP

# 4. HTTP Settings를 HTTPS에서 HTTP로 변경
az network application-gateway http-settings update \
  --resource-group $APPGW_RG \
  --gateway-name $APPGW_NAME \
  --name blob-http-settings \
  --port 80 \
  --protocol Http \
  --probe health-probe

# 5. Health Probe 업데이트
az network application-gateway probe update \
  --resource-group $APPGW_RG \
  --gateway-name $APPGW_NAME \
  --name health-probe \
  --protocol Http \
  --path / \
  --host-name-from-http-settings false \
  --host $PETCLINIC_IP
```

### 2.5 Application Gateway 테스트

```bash
# Application Gateway Public IP 확인
APPGW_PUBLIC_IP=$(terraform output -raw appgw_public_ip)
echo "Application Gateway Public IP: $APPGW_PUBLIC_IP"

# HTTP 테스트
curl -I http://$APPGW_PUBLIC_IP

# 예상 결과: HTTP/1.1 200 OK

# PetClinic 응답 확인
curl -s http://$APPGW_PUBLIC_IP | grep -i "petclinic"

# 예상 결과: <title>PetClinic :: a Spring Framework demonstration</title>
```

### 2.6 CloudFront Secondary Origin을 Application Gateway로 전환

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/route53
CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id)

# 1. 현재 설정 백업
aws cloudfront get-distribution-config \
  --id $CLOUDFRONT_ID \
  --query 'DistributionConfig' > /tmp/cloudfront-config-backup.json

# 2. Application Gateway IP 가져오기
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover
APPGW_IP=$(terraform output -raw appgw_public_ip)
echo "App Gateway IP: $APPGW_IP"

# 3. CloudFront 설정 업데이트 (Secondary Origin 변경)
cd /home/ubuntu/3tier-terraform/codes/aws/route53

aws cloudfront get-distribution-config --id $CLOUDFRONT_ID --query 'DistributionConfig' | \
python3 <<EOF > /tmp/cloudfront-config-appgw.json
import json
import sys

config = json.load(sys.stdin)

# Secondary Origin의 DomainName을 App Gateway IP로 변경
for origin in config['Origins']['Items']:
    if origin['Id'] == 'secondary-azure':
        origin['DomainName'] = '$APPGW_IP'
        origin['CustomOriginConfig']['OriginProtocolPolicy'] = 'http-only'
        origin['CustomOriginConfig']['HTTPPort'] = 80
        print(f"Updated secondary origin to {origin['DomainName']}", file=sys.stderr)

json.dump(config, sys.stdout, indent=2)
EOF

# 4. ETag 가져오기
ETAG=$(aws cloudfront get-distribution-config --id $CLOUDFRONT_ID --query 'ETag' --output text)

# 5. CloudFront 업데이트 실행
aws cloudfront update-distribution \
  --id $CLOUDFRONT_ID \
  --distribution-config file:///tmp/cloudfront-config-appgw.json \
  --if-match "$ETAG"

# 6. CloudFront 배포 완료 대기 (약 5-10분 소요)
echo "Waiting for CloudFront deployment..."
while true; do
  STATUS=$(aws cloudfront get-distribution --id $CLOUDFRONT_ID --query 'Distribution.Status' --output text)
  echo "$(date '+%Y-%m-%d %H:%M:%S') - CloudFront Status: $STATUS"
  if [ "$STATUS" = "Deployed" ]; then
    echo "CloudFront update completed!"
    break
  fi
  sleep 20
done
```

### 2.7 서비스 전환 확인

```bash
# 1. CloudFront 캐시 무효화 (즉시 반영)
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_ID \
  --paths "/*"

# 2. 도메인 접속 테스트
curl -I https://blueisthenewblack.store

# 예상 응답:
# HTTP/2 200 OK
# x-cache: Miss from cloudfront (새로 가져옴)

# 3. PetClinic 응답 확인
curl -s https://blueisthenewblack.store | grep -i "petclinic"

# 예상 결과: PetClinic HTML 내용 표시
```

**브라우저 테스트:**
1. `https://blueisthenewblack.store` 접속
2. PetClinic 홈페이지 정상 표시 확인
3. "Find Owners" 메뉴 → 데이터 조회 확인 (Azure MySQL 연결 확인)
4. "Veterinarians" 메뉴 확인

**결과:** 이제 Azure에서 완전한 PetClinic 서비스가 제공됩니다!

---

## Phase 3: AWS 복구 및 정상화

### 목표
AWS 인프라를 복구하고, 트래픽을 AWS로 전환한 후, Azure 임시 인프라를 정리하고 secondary origin을 다시 Blob Storage로 원복

### 3.1 AWS Web 노드 그룹 복구

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/service

# 1. Web 노드 그룹 이름 확인
export WEB_NODEGROUP=$(aws eks list-nodegroups \
  --cluster-name $(terraform output -raw cluster_name) \
  --region ap-northeast-2 \
  --query "nodegroups[?contains(@, 'web')]" \
  --output text)

echo "Web NodeGroup: $WEB_NODEGROUP"

# 2. Web 노드 그룹 스케일업 (desired=2로 복구)
aws eks update-nodegroup-config \
  --cluster-name $(terraform output -raw cluster_name) \
  --nodegroup-name $WEB_NODEGROUP \
  --scaling-config minSize=2,maxSize=4,desiredSize=2 \
  --region ap-northeast-2

# 3. 노드 복구 대기 (약 3-5분 소요)
echo "Waiting for nodes to scale up..."
watch -n 5 "kubectl get nodes -l role=web"
```

**예상 결과:**
```
NAME                                          STATUS   ROLES    AGE   VERSION
ip-10-0-1-xxx.ap-northeast-2.compute.internal Ready    <none>   2m    v1.28.x
ip-10-0-1-yyy.ap-northeast-2.compute.internal Ready    <none>   2m    v1.28.x
```

### 3.2 AWS EKS PetClinic Pod 상태 확인

```bash
# AWS EKS 컨텍스트로 전환
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name $(terraform output -raw cluster_name)

# Pod 상태 확인
kubectl get pods -n petclinic -o wide

# 예상 결과: Running 상태의 Pod들
```

### 3.3 AWS ALB Health Check 확인

```bash
# Target Group Health 확인
export ALB_ARN=$(terraform output -raw alb_arn)
export TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn $ALB_ARN \
  --region ap-northeast-2 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

# Target Health 상태 확인 (약 2-3분 후 healthy로 변경됨)
watch -n 5 "aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region ap-northeast-2 \
  --query 'TargetHealthDescriptions[*].[Target.Id, TargetHealth.State]' \
  --output table"
```

**예상 결과:**
```
-----------------------------------
|  DescribeTargetHealth           |
+-----------------------+---------+
|  i-0123456789abcdef0  | healthy |
|  i-0fedcba9876543210  | healthy |
+-----------------------+---------+
```

### 3.4 AWS ALB 직접 접속 테스트

```bash
# ALB DNS 이름 확인
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "ALB DNS: $ALB_DNS"

# HTTP 테스트
curl -I http://$ALB_DNS

# 예상 결과: HTTP/1.1 200 OK

# PetClinic 응답 확인
curl -s http://$ALB_DNS | grep -i "petclinic"
```

### 3.5 CloudFront가 AWS Primary Origin을 사용하도록 대기

```bash
# CloudFront는 자동으로 Primary Origin(AWS ALB)이 healthy 상태가 되면 다시 사용합니다.
# Health Check Interval: 30초
# Failure Threshold: 3회
# 따라서 약 1-2분 후 자동 복구됩니다.

# 도메인 접속 테스트 (Primary Origin 사용 확인)
curl -I https://blueisthenewblack.store

# 예상 응답:
# x-cache: Miss from cloudfront (Primary origin에서 새로 가져옴)
# x-amz-cf-pop: ICN54-P1 (AWS CloudFront Edge in Korea)

# 여러 번 요청하여 Primary Origin 사용 확인
for i in {1..5}; do
  echo "Request $i:"
  curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" https://blueisthenewblack.store
  sleep 2
done
```

**예상 결과:** 모두 200 OK 응답

### 3.6 CloudFront Secondary Origin을 Blob Storage로 원복

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/route53
CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id)

# 1. Secondary Origin을 Blob Storage로 변경
aws cloudfront get-distribution-config --id $CLOUDFRONT_ID --query 'DistributionConfig' | \
python3 <<EOF > /tmp/cloudfront-config-rollback.json
import json
import sys

config = json.load(sys.stdin)

# Secondary Origin을 다시 Blob Storage로 변경
for origin in config['Origins']['Items']:
    if origin['Id'] == 'secondary-azure':
        origin['DomainName'] = 'bloberry01.z12.web.core.windows.net'
        origin['CustomOriginConfig']['OriginProtocolPolicy'] = 'https-only'
        origin['CustomOriginConfig']['HTTPSPort'] = 443
        origin['CustomOriginConfig']['HTTPPort'] = 80
        print(f"Restored secondary origin to {origin['DomainName']}", file=sys.stderr)

json.dump(config, sys.stdout, indent=2)
EOF

# 2. ETag 가져오기
ETAG=$(aws cloudfront get-distribution-config --id $CLOUDFRONT_ID --query 'ETag' --output text)

# 3. CloudFront 업데이트
aws cloudfront update-distribution \
  --id $CLOUDFRONT_ID \
  --distribution-config file:///tmp/cloudfront-config-rollback.json \
  --if-match "$ETAG"

# 4. 배포 완료 대기
echo "Waiting for CloudFront rollback deployment..."
while true; do
  STATUS=$(aws cloudfront get-distribution --id $CLOUDFRONT_ID --query 'Distribution.Status' --output text)
  echo "$(date '+%Y-%m-%d %H:%M:%S') - CloudFront Status: $STATUS"
  if [ "$STATUS" = "Deployed" ]; then
    echo "CloudFront rollback completed!"
    break
  fi
  sleep 20
done
```

### 3.7 Azure 2-failover 인프라 삭제

```bash
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover

# 1. AKS PetClinic 리소스 삭제 (선택사항)
kubectl delete namespace petclinic --force --grace-period=0

# 2. Terraform으로 Azure 인프라 삭제
terraform destroy -auto-approve

# 삭제되는 리소스:
# - Azure AKS Cluster
# - Azure MySQL Flexible Server
# - Application Gateway
# - Public IP
# - 관련 네트워크 인터페이스 및 보안 그룹
```

**주의:** `rg-blue` 리소스 그룹과 `vnet-blue`, `bloberry01` 스토리지는 1-always 인프라이므로 삭제되지 않습니다.

### 3.8 최종 상태 확인

```bash
# 1. 도메인 접속 테스트
curl -I https://blueisthenewblack.store

# 예상 응답:
# HTTP/2 200 OK
# x-cache: Hit from cloudfront (Primary origin - AWS ALB)

# 2. PetClinic 정상 동작 확인
curl -s https://blueisthenewblack.store | grep -i "petclinic"

# 3. CloudFront Origin 설정 확인
aws cloudfront get-distribution-config \
  --id $CLOUDFRONT_ID \
  --query 'DistributionConfig.Origins.Items[*].[Id, DomainName]' \
  --output table

# 예상 결과:
# -----------------------------------------------------------
# |                 GetDistributionConfig                   |
# +------------------+--------------------------------------+
# |  primary-aws     |  blue-alb-xxxxxxx.ap-northeast-2... |
# |  secondary-azure |  bloberry01.z12.web.core.windows...|
# +------------------+--------------------------------------+
```

---

## 테스트 시나리오 요약

| Phase | 상태 | Primary Origin | Secondary Origin | 서비스 |
|-------|------|----------------|------------------|--------|
| **시작** | 정상 운영 | AWS ALB (Healthy) | Blob Storage | PetClinic (AWS) |
| **Phase 1** | 단기 장애 | AWS ALB (Unhealthy) | Blob Storage | 정적 유지보수 페이지 |
| **Phase 2** | 장기 DR | AWS ALB (Unhealthy) | App Gateway → AKS | PetClinic (Azure) |
| **Phase 3** | 복구 완료 | AWS ALB (Healthy) | Blob Storage | PetClinic (AWS) |

---

## 체크리스트

### Phase 1: 단기 장애 (Blob Storage Failover)
- [ ] AWS Web 노드 그룹 desired=0 설정 완료
- [ ] Web 노드 모두 종료 확인
- [ ] ALB Target Group unhealthy 확인
- [ ] CloudFront가 Secondary Origin(Blob Storage) 사용 확인
- [ ] 브라우저에서 정적 유지보수 페이지 표시 확인

### Phase 2: 장기 DR (Azure Application Gateway)
- [ ] Azure 2-failover Terraform 배포 완료
- [ ] Azure MySQL 데이터 복구 완료
- [ ] Azure AKS PetClinic 배포 완료
- [ ] Application Gateway Backend Pool을 AKS Service로 변경
- [ ] Application Gateway HTTP 테스트 성공
- [ ] CloudFront Secondary Origin을 App Gateway로 변경
- [ ] CloudFront 배포 완료 (Status: Deployed)
- [ ] 도메인에서 PetClinic (Azure) 정상 동작 확인

### Phase 3: AWS 복구 및 정상화
- [ ] AWS Web 노드 그룹 desired=2로 복구
- [ ] AWS Web 노드 모두 Running 확인
- [ ] ALB Target Group healthy 확인
- [ ] AWS ALB 직접 접속 테스트 성공
- [ ] CloudFront가 Primary Origin(AWS ALB) 자동 복구 확인
- [ ] CloudFront Secondary Origin을 Blob Storage로 원복
- [ ] Azure 2-failover 인프라 삭제 완료
- [ ] 도메인에서 PetClinic (AWS) 정상 동작 확인

---

## 트러블슈팅

### 문제 1: CloudFront가 Secondary Origin으로 failover 되지 않음

**원인:** Health Check Interval이 아직 충분히 경과하지 않음

**해결:**
```bash
# CloudFront Origin Failover 설정 확인
aws cloudfront get-distribution-config \
  --id $CLOUDFRONT_ID \
  --query 'DistributionConfig.OriginGroups' \
  --output json

# 최소 3-5분 대기 후 재확인
```

### 문제 2: Application Gateway에서 502 Bad Gateway 에러

**원인:** Backend Pool이 AKS Service에 연결되지 않음

**해결:**
```bash
# 1. PetClinic Service ClusterIP 재확인
kubectl get svc petclinic -n petclinic -o jsonpath='{.spec.clusterIP}'

# 2. Application Gateway Backend Health 확인
az network application-gateway show-backend-health \
  --resource-group rg-blue \
  --name appgw-blue

# 3. Backend Pool 재설정
PETCLINIC_IP=$(kubectl get svc petclinic -n petclinic -o jsonpath='{.spec.clusterIP}')
az network application-gateway address-pool update \
  --resource-group rg-blue \
  --gateway-name appgw-blue \
  --name blob-backend-pool \
  --servers $PETCLINIC_IP
```

### 문제 3: Azure MySQL 연결 실패

**원인:** 방화벽 규칙이 AKS Subnet을 허용하지 않음

**해결:**
```bash
# AKS Subnet CIDR 확인
AKS_SUBNET_CIDR=$(az network vnet subnet show \
  --resource-group rg-blue \
  --vnet-name vnet-blue \
  --name snet-aks \
  --query addressPrefix -o tsv)

# 방화벽 규칙 추가
az mysql flexible-server firewall-rule create \
  --resource-group rg-blue \
  --name mysql-dr-blue \
  --rule-name allow-aks-subnet \
  --start-ip-address $(echo $AKS_SUBNET_CIDR | cut -d'/' -f1) \
  --end-ip-address $(echo $AKS_SUBNET_CIDR | cut -d'/' -f1 | awk -F'.' '{print $1"."$2"."$3".255"}')
```

### 문제 4: AWS 복구 후에도 CloudFront가 Secondary Origin 사용

**원인:** CloudFront 캐시에 여전히 Secondary Origin 응답이 저장됨

**해결:**
```bash
# CloudFront 캐시 전체 무효화
aws cloudfront create-invalidation \
  --distribution-id $CLOUDFRONT_ID \
  --paths "/*"

# 무효화 완료 대기
aws cloudfront wait invalidation-completed \
  --distribution-id $CLOUDFRONT_ID \
  --id <INVALIDATION_ID>
```

---

## 참고 정보

### CloudFront Origin Failover 동작 원리

1. **Primary Origin Health Check**
   - Interval: 30초
   - Timeout: 10초
   - Failure Threshold: 3회 (약 90초)

2. **Failover 조건**
   - Primary Origin이 3회 연속 실패 시 Secondary Origin으로 전환
   - HTTP 상태 코드 500, 502, 503, 504 발생 시

3. **Failback 조건**
   - Primary Origin이 다시 healthy 상태가 되면 자동으로 Primary로 복귀

### Azure 리소스 비용 절감 팁

2-failover 인프라는 장애 시에만 사용하므로 평소에는 destroy 상태로 유지하여 비용 절감 가능:

```bash
# 필요 시 배포
terraform apply -auto-approve

# 사용 완료 후 즉시 삭제
terraform destroy -auto-approve
```

---

## 다음 단계

이 테스트를 완료한 후:

1. **정기 DR Drill 수행**: 분기별로 이 테스트를 반복하여 절차 숙달
2. **자동화 스크립트 작성**: 반복 작업을 스크립트로 자동화
3. **모니터링 대시보드 구축**: CloudWatch + Azure Monitor 통합 모니터링
4. **알림 설정**: AWS Health Check 실패 시 자동 알림 구성

---

**문서 작성일**: 2025-12-24
**테스트 환경**: AWS ap-northeast-2 + Azure Korea Central
**예상 소요 시간**: 약 60-90분
