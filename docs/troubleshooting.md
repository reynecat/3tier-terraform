# 트러블슈팅 가이드

## 목차
- [1. AWS 관련 문제](#1-aws-관련-문제)
  - [1.1 AWS Load Balancer Controller 설치 실패](#11-aws-load-balancer-controller-설치-실패)
  - [1.2 WAS Pod CrashLoopBackOff](#12-was-pod-crashloopbackoff)
  - [1.3 ALB 생성 안됨](#13-alb-생성-안됨)
  - [1.4 Route53 DNS 전파 안됨](#14-route53-dns-전파-안됨)
- [2. Azure 관련 문제](#2-azure-관련-문제)
  - [2.1 Azure 백업 복구 실패](#21-azure-백업-복구-실패)
- [3. 백업 관련 문제](#3-백업-관련-문제)
  - [3.1 MySQL 백업 연결 문제](#31-mysql-백업-연결-문제)

---

## 1. AWS 관련 문제

### 1.1 AWS Load Balancer Controller 설치 실패

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
cd ~/3tier-terraform/codes/aws/service

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

### 1.2 WAS Pod CrashLoopBackOff

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

export RDS_HOST=$(cd ~/3tier-terraform/codes/aws/service && terraform output -raw rds_address)

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

### 1.3 ALB 생성 안됨

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
cd ~/3tier-terraform/codes/aws/service
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

### 1.4 Route53 DNS 전파 안됨

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
  --id $(cd ~/3tier-terraform/codes/aws/route53 && terraform output -raw route53_zone_id) \
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

---

## 2. Azure 관련 문제

### 2.1 Azure 백업 복구 실패

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

mysql -h $(cd ~/3tier-terraform/codes/azure/2-failover && terraform output -raw mysql_fqdn) \
  -u mysqladmin -p < /tmp/backup.sql
```

---

## 3. 백업 관련 문제

### 3.1 MySQL 백업 연결 문제

#### 문제 원인

`-p` 옵션 뒤에 바로 비밀번호를 붙여야 하는데, 공백이 있거나 환경변수가 제대로 설정되지 않았을 수 있음

#### 해결 방법

##### 1단계: 환경변수 재설정

```bash
# RDS 엔드포인트 확인 (로컬 터미널에서)
cd ~/3tier-terraform/PlanB/aws
terraform output rds_address
```

**백업 인스턴스에 접속해서:**

```bash
# SSM으로 접속
aws ssm start-session --target i-0155f8568e2ed335d
```

**백업 인스턴스 내부에서:**

```bash
# RDS 정보 수동 설정
export RDS_HOST="blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com"
export DB_USERNAME="admin"
export DB_PASSWORD="byemyblue"

echo "RDS Host: $RDS_HOST"
echo "DB Username: $DB_USERNAME"
```

##### 2단계: MySQL 연결 테스트 (여러 방법)

**방법 1: 비밀번호를 직접 붙여서 입력**
```bash
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;"
```

**방법 2: 비밀번호 프롬프트 사용**
```bash
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p
# Enter password: byemyblue
```

**방법 3: 변수 없이 직접 입력**
```bash
mysql -h blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com -u admin -pbyemyblue -e "SELECT 1;"
```

**방법 4: 설정 파일 사용**
```bash
# MySQL 설정 파일 생성
cat > ~/.my.cnf <<EOF
[client]
host=blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com
user=admin
password=byemyblue
EOF

chmod 600 ~/.my.cnf

# 간단하게 연결
mysql -e "SELECT 1;"
```

##### 3단계: 연결 성공 후 데이터베이스 확인

```bash
# 데이터베이스 목록
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SHOW DATABASES;"

# petclinic 데이터베이스 확인
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "USE petclinic; SHOW TABLES;"
```

##### 4단계: 백업 스크립트 생성 (연결 성공 후)

```bash
# Secrets Manager에서 Azure 자격증명 가져오기
export REGION="ap-northeast-2"

# Secret ARN 찾기
export SECRET_ARN=$(aws secretsmanager list-secrets \
    --region $REGION \
    --query "SecretList[?contains(Name, 'backup-credentials-blue')].ARN | [0]" \
    --output text)

echo "Secret ARN: $SECRET_ARN"

# Secret 내용 가져오기
SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --region $REGION \
    --query SecretString \
    --output text)

# Azure 자격증명 추출
export AZURE_STORAGE_ACCOUNT=$(echo $SECRET_JSON | jq -r '.azure_storage_account')
export AZURE_STORAGE_KEY=$(echo $SECRET_JSON | jq -r '.azure_storage_key')
export AZURE_CONTAINER="mysql-backups"

echo "Azure Storage Account: $AZURE_STORAGE_ACCOUNT"
```

##### 5단계: 백업 스크립트 생성

```bash
# 디렉토리 생성
sudo mkdir -p /opt/mysql-backup

# 백업 스크립트 생성
sudo tee /usr/local/bin/mysql-backup-to-azure.sh > /dev/null <<'SCRIPT_EOF'
#!/bin/bash
# MySQL → Azure Blob Storage 백업 스크립트

set -e

LOG_FILE="/var/log/mysql-backup-to-azure.log"
exec >> $LOG_FILE 2>&1

echo "=========================================="
echo "백업 시작: $(date)"
echo "=========================================="

# 환경 변수
RDS_HOST="blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com"
DB_NAME="petclinic"
DB_USERNAME="admin"
DB_PASSWORD="byemyblue"
AZURE_STORAGE_ACCOUNT="bloberry01"
AZURE_STORAGE_KEY="AZURE_KEY_HERE"
AZURE_CONTAINER="mysql-backups"

# 백업 파일명
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="/opt/mysql-backup"
BACKUP_FILE="$BACKUP_DIR/backup-$TIMESTAMP.sql"
COMPRESSED_FILE="$BACKUP_FILE.gz"

# 1. MySQL Dump
echo "[1/3] MySQL Dump 실행..."
mysqldump \
    -h $RDS_HOST \
    -u $DB_USERNAME \
    -p"$DB_PASSWORD" \
    --single-transaction \
    --skip-lock-tables \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \
    --databases $DB_NAME \
    > $BACKUP_FILE

BACKUP_SIZE=$(du -h $BACKUP_FILE | cut -f1)
echo "Dump 완료: $BACKUP_FILE ($BACKUP_SIZE)"

# 2. 압축
echo "[2/3] 파일 압축..."
gzip -f $BACKUP_FILE
COMPRESSED_SIZE=$(du -h $COMPRESSED_FILE | cut -f1)
echo "압축 완료: $COMPRESSED_FILE ($COMPRESSED_SIZE)"

# 3. Azure Blob Storage 업로드
echo "[3/3] Azure Blob Storage 업로드..."
az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --account-key "$AZURE_STORAGE_KEY" \
    --container-name $AZURE_CONTAINER \
    --name "backups/backup-$TIMESTAMP.sql.gz" \
    --file $COMPRESSED_FILE \
    --overwrite

echo "Azure 업로드 완료: backups/backup-$TIMESTAMP.sql.gz"

# 4. 로컬 정리
echo "[4/4] 로컬 파일 정리..."
find $BACKUP_DIR -name "backup-*.sql.gz" -mtime +1 -delete
echo "로컬 정리 완료"

echo "백업 완료: $(date)"
echo "=========================================="
echo ""
SCRIPT_EOF

# Azure Storage Key를 실제 값으로 치환
sudo sed -i "s|YOUR_AZURE_STORAGE_KEY|$AZURE_STORAGE_KEY|g" /usr/local/bin/mysql-backup-to-azure.sh

# 실행 권한 부여
sudo chmod +x /usr/local/bin/mysql-backup-to-azure.sh
```

##### 6단계: 첫 백업 테스트

```bash
# 백업 스크립트 실행
sudo /usr/local/bin/mysql-backup-to-azure.sh

# 로그 확인
sudo tail -f /var/log/mysql-backup-to-azure.log

# 출력 예시:
# ==========================================
# 백업 시작: Sun Dec 21 21:03:14 UTC 2025
# ==========================================
# [1/3] MySQL Dump 실행...
# Dump 완료: /opt/mysql-backup/backup-20251221-210314.sql (45M)
# [2/3] 파일 압축...
# 압축 완료: /opt/mysql-backup/backup-20251221-210314.sql.gz (12M)
# [3/3] Azure Blob Storage 업로드...
# Azure 업로드 완료: backups/backup-20251221-210314.sql.gz
# [4/4] 로컬 파일 정리...
# 로컬 정리 완료
# 백업 완료: Sun Dec 21 21:03:18 UTC 2025
```

##### 7단계: Cron 설정

```bash
# 5분마다 백업 (테스트)
echo "*/5 * * * * /usr/local/bin/mysql-backup-to-azure.sh" | sudo crontab -

# Cron 확인
sudo crontab -l
```

##### 8단계: Azure Blob Storage 백업 확인

**로컬 터미널에서:**

```bash
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --output table
```

##### 추가 트러블슈팅

만약 계속 연결이 안된다면:

```bash
# 포트 연결 테스트
nc -zv $RDS_HOST 3306

# DNS 조회
nslookup $RDS_HOST

# 보안 그룹 재확인 (로컬 터미널)
aws ec2 describe-security-groups \
  --group-ids sg-xxxxx \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`3306`]'
```

---

**문서 버전**: v1.3
**최종 수정**: 2024-12-23
**작성자**: I2ST-blue
