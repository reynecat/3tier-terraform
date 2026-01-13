# 3-Tier 인프라 트러블슈팅 완전 가이드

> 프로젝트 전반에 걸쳐 발생했던 모든 문제와 해결 과정을 상세히 기록한 문서입니다.

## 목차

1. [Terraform Destroy 관련 문제](#1-terraform-destroy-관련-문제)
2. [Security Group 의존성 문제](#2-security-group-의존성-문제)
3. [AWS 인프라 배포 문제](#3-aws-인프라-배포-문제)
4. [Kubernetes 배포 문제](#4-kubernetes-배포-문제)
5. [백업 시스템 문제](#5-백업-시스템-문제)
6. [네트워크 및 DNS 문제](#6-네트워크-및-dns-문제)

---

## 1. Terraform Destroy 관련 문제

### 1.1 Security Group 의존성 에러

#### 문제 상황
```
Error: deleting Security Group (sg-067530e0bb78b53ec): DependencyViolation
resource sg-067530e0bb78b53ec has a dependent object
```

`terraform destroy` 실행 시 Security Group을 삭제하려 할 때 의존성 에러가 지속적으로 발생했습니다.

#### 근본 원인
1. **Kubernetes가 생성한 AWS 리소스**: AWS Load Balancer Controller가 Ingress로부터 ALB/NLB를 자동 생성하고, 이 로드밸런서들이 ENI(Elastic Network Interface)를 생성합니다.
2. **삭제 순서 문제**: Terraform이 Security Group을 삭제하려 할 때, ALB/NLB의 ENI가 아직 해당 Security Group을 참조하고 있어 삭제가 불가능합니다.
3. **리소스 정리 누락**: 기존 코드에는 destroy provisioner가 있었지만 ENI 정리 로직이 없었습니다.

#### 해결 과정

**1단계: 문제 진단**
```bash
# 문제가 되는 Security Group 확인
SG_ID="sg-067530e0bb78b53ec"
aws ec2 describe-security-groups --group-ids "$SG_ID"

# 무엇이 이 SG를 사용 중인지 확인
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=$SG_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
  --output table
```

결과: ALB/NLB의 ENI가 Security Group을 참조하고 있었습니다.

**2단계: 자동 정리 로직 추가**

[codes/aws/2. service/modules/eks/main.tf](../codes/aws/2.%20service/modules/eks/main.tf) 수정:

```hcl
resource "null_resource" "cleanup_k8s_resources" {
  triggers = {
    cluster_name = "${var.environment}-eks"
    vpc_id       = var.vpc_id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]  # bash 명시
    on_failure  = continue
    command     = <<-BASH
      set -e

      VPC_ID="${self.triggers.vpc_id}"
      AWS_REGION=$${AWS_DEFAULT_REGION:-ap-northeast-2}

      echo "=== 1. Load Balancer 삭제 ==="
      LB_ARNS=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

      if [ -n "$LB_ARNS" ]; then
        for lb_arn in $LB_ARNS; do
          echo "Deleting ALB/NLB: $lb_arn"
          aws elbv2 delete-load-balancer \
            --region "$AWS_REGION" \
            --load-balancer-arn "$lb_arn" 2>/dev/null || true
        done
      fi

      sleep 30

      echo "=== 2. Target Group 삭제 ==="
      TG_ARNS=$(aws elbv2 describe-target-groups \
        --region "$AWS_REGION" \
        --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
        --output text 2>/dev/null || echo "")

      if [ -n "$TG_ARNS" ]; then
        for tg_arn in $TG_ARNS; do
          echo "Deleting Target Group: $tg_arn"
          aws elbv2 delete-target-group \
            --region "$AWS_REGION" \
            --target-group-arn "$tg_arn" 2>/dev/null || true
        done
      fi

      echo "=== 3. ENI 삭제 (핵심) ==="
      ENI_IDS=$(aws ec2 describe-network-interfaces \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" \
        --output text 2>/dev/null || echo "")

      if [ -n "$ENI_IDS" ]; then
        for eni_id in $ENI_IDS; do
          echo "Deleting ENI: $eni_id"
          aws ec2 delete-network-interface \
            --region "$AWS_REGION" \
            --network-interface-id "$eni_id" 2>/dev/null || true
        done
      fi

      sleep 20

      echo "=== 정리 완료 ==="
    BASH
  }
}
```

**3단계: Bash 인터프리터 문제 해결**

초기에 `/bin/sh`를 사용했을 때 구문 에러가 발생했습니다:
```
/bin/sh: 4: Syntax error: word unexpected (expecting "do")
```

해결: `interpreter = ["/bin/bash", "-c"]`로 명시적으로 bash를 지정했습니다.

**4단계: Region 설정 문제 해결**

처음에는 `var.region`을 triggers에 추가하려 했으나 기존 state와 호환성 문제가 발생:
```
Error: Missing map element
on modules/eks/main.tf line 30
This map does not have an element with the key "region".
```

해결: 환경 변수에서 region을 가져오는 방식으로 변경:
```bash
AWS_REGION=$${AWS_DEFAULT_REGION:-ap-northeast-2}
```

#### 최종 해결 결과

리소스 삭제 순서:
```
1. Load Balancer 조회 및 삭제
   ↓
2. 대기 (30초) - ALB/NLB 완전 삭제
   ↓
3. Target Group 삭제
   ↓
4. ENI (Network Interface) 삭제 ⭐
   ↓
5. 대기 (20초) - 의존성 완전 해제
   ↓
6. Security Group 삭제 (Terraform)
   ↓
7. 성공!
```

#### 예방 조치
1. `on_failure = continue` 추가로 부분 실패 시에도 계속 진행
2. 적절한 대기 시간 추가 (30초 + 20초)
3. 모든 AWS CLI 명령에 에러 처리 추가 (`|| true`)

#### 관련 문서
- [FIX_SUMMARY_FINAL.md](./FIX_SUMMARY_FINAL.md)
- [TERRAFORM_DESTROY_FIX.md](./TERRAFORM_DESTROY_FIX.md)

---

### 1.2 백업 인스턴스 Security Group 삭제 불가

#### 문제 상황
```
Error: deleting Security Group (sg-067530e0bb78b53ec): DependencyViolation
resource sg-067530e0bb78b53ec has a dependent object
```

Security Group 이름: `backup-instance-sg-*`
설명: Security group for backup instance

#### 특이 사항
- Terraform state에서 이미 제거됨
- 모든 확인 가능한 리소스(ENI, EC2, RDS)가 이미 삭제됨
- AWS Console 및 CLI에서도 의존성이 확인되지 않음

#### 근본 원인
AWS의 **숨겨진 의존성(Hidden Dependency)**:
- Security Group이 과거에 연결되었던 리소스의 메타데이터가 AWS 내부에 남아있음
- 삭제된 ENI나 인스턴스의 레퍼런스가 완전히 정리되지 않은 상태
- AWS의 eventual consistency로 인한 지연

#### 해결 방법

**방법 1: Terraform state에서 제거 (적용됨)**
```bash
terraform state rm 'aws_security_group.backup_instance'
```

이후 Terraform destroy는 해당 Security Group을 무시하고 진행됩니다.

**방법 2: 시간 경과 후 수동 삭제**
```bash
# 30분 ~ 1시간 대기 후
aws ec2 delete-security-group --group-id sg-067530e0bb78b53ec
```

**방법 3: AWS Console에서 수동 삭제**
- AWS Console이 CLI보다 더 상세한 의존성 정보를 제공하는 경우가 있음
- EC2 Console → Security Groups → 해당 SG 선택 → Delete

**방법 4: VPC 전체 삭제**
VPC를 삭제하면 연관된 모든 Security Group도 함께 삭제됩니다.

#### 향후 방지책

**코드 개선**:
```hcl
resource "aws_security_group" "backup_instance" {
  # ... 기존 설정 ...

  lifecycle {
    create_before_destroy = false
  }

  depends_on = [
    aws_instance.backup  # 인스턴스가 먼저 삭제되도록
  ]
}
```

#### 관련 문서
- [SG_DEPENDENCY_FINAL_FIX.md](./SG_DEPENDENCY_FINAL_FIX.md)

---

## 2. Security Group 의존성 문제

### 2.1 ENI가 Security Group을 참조

#### 문제 진단 절차

**1단계: Security Group 정보 확인**
```bash
SG_ID="sg-067530e0bb78b53ec"

aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].[GroupId,GroupName,Description,VpcId]' \
  --output table
```

**2단계: 사용 중인 리소스 확인**
```bash
# ENI 확인
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=$SG_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description,Attachment.InstanceId]' \
  --output table

# 인스턴스 확인
aws ec2 describe-instances \
  --filters "Name=instance.group-id,Values=$SG_ID" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Load Balancer 확인
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?SecurityGroups && contains(SecurityGroups, '$SG_ID')].[LoadBalancerArn,LoadBalancerName]" \
  --output table
```

**3단계: VPC 내 모든 ENI 확인**
```bash
VPC_ID="vpc-06e4fdfb8ec4950d1"

aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
  --output table
```

#### 강제 정리 프로세스

**자동화 스크립트**:
```bash
#!/bin/bash
# manual-cleanup.sh

set -e

VPC_ID="vpc-06e4fdfb8ec4950d1"
AWS_REGION="ap-northeast-2"

echo "=== 1. Kubernetes 리소스 정리 ==="
kubectl delete svc,ingress --all --all-namespaces || true
sleep 60

echo "=== 2. Load Balancer 정리 ==="
for lb_arn in $(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text 2>/dev/null); do
  aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn" || true
done
sleep 30

echo "=== 3. Target Group 정리 ==="
for tg_arn in $(aws elbv2 describe-target-groups \
  --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
  --output text 2>/dev/null); do
  aws elbv2 delete-target-group --target-group-arn "$tg_arn" || true
done

echo "=== 4. ENI 정리 (3회 시도) ==="
for i in {1..3}; do
  echo "  시도 $i/3..."
  for eni_id in $(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
    --output text 2>/dev/null); do
    aws ec2 delete-network-interface --network-interface-id "$eni_id" || true
  done
  sleep 10
done

echo "=== 5. 최종 대기 ==="
sleep 30

echo "=== 6. Terraform Destroy 재시도 ==="
terraform destroy
```

#### 관련 문서
- [EMERGENCY_FIX.md](./EMERGENCY_FIX.md)

---

## 3. AWS 인프라 배포 문제

### 3.1 AWS Secrets Manager 리소스 충돌

#### 문제 상황
```
Error: creating Secrets Manager Secret (backup-credentials-blue):
operation error Secrets Manager: CreateSecret, api error
InvalidRequestException: You can't create this secret because a secret
with this name is already scheduled for deletion.
```

#### 원인
이전에 삭제된 Secret이 복구 대기 기간(기본 7일, 최대 30일) 중이었습니다. AWS Secrets Manager는 삭제된 Secret을 즉시 제거하지 않고 복구 가능 상태로 유지합니다.

#### 해결 방법

**방법 1: 강제 삭제 후 재생성 (권장)**
```bash
# 복구 불가능하게 강제 삭제
aws secretsmanager delete-secret \
  --secret-id backup-credentials-blue \
  --force-delete-without-recovery \
  --region ap-northeast-2

# Terraform 재실행
terraform apply
```

**방법 2: 리소스 이름 변경**
```hcl
# backup-instance.tf
resource "aws_secretsmanager_secret" "backup_credentials" {
  name = "backup-credentials-${var.environment}-v2"  # -v2 추가
  # ...
}
```

**방법 3: 기존 Secret 복구 후 Import**
```bash
# Secret 복구
aws secretsmanager restore-secret \
  --secret-id backup-credentials-blue \
  --region ap-northeast-2

# Secret 값 업데이트
aws secretsmanager put-secret-value \
  --secret-id backup-credentials-blue \
  --secret-string '{
    "rds_host": "...",
    "db_username": "admin",
    "db_password": "byemyblue",
    "azure_storage_account": "bloberry01",
    "azure_storage_key": "..."
  }' \
  --region ap-northeast-2

# Terraform state로 import
terraform import aws_secretsmanager_secret.backup_credentials backup-credentials-blue
```

---

### 3.2 IAM Role 이미 존재 오류

#### 문제 상황
```
Error: creating IAM Role (AmazonEKSClusterRole-blue):
EntityAlreadyExists: Role with name AmazonEKSClusterRole-blue already exists.
```

#### 원인
이전 배포에서 생성된 IAM 역할이 남아있고, Terraform state와 실제 AWS 리소스가 불일치합니다.

#### 해결 방법

**방법 1: 기존 역할 삭제**
```bash
# 연결된 정책 확인
aws iam list-attached-role-policies --role-name AmazonEKSClusterRole-blue

# 정책 분리
aws iam detach-role-policy \
  --role-name AmazonEKSClusterRole-blue \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# 역할 삭제
aws iam delete-role --role-name AmazonEKSClusterRole-blue

# Terraform 재실행
terraform apply
```

**방법 2: Import 후 재사용**
```bash
terraform import aws_iam_role.eks_cluster AmazonEKSClusterRole-blue
terraform import aws_iam_role.eks_node AmazonEKSNodeRole-blue
```

---

### 3.3 NAT Gateway EIP 연결 충돌

#### 문제 상황
```
Error: creating EC2 NAT Gateway: operation error EC2: CreateNatGateway,
InvalidElasticIpID.InUse: The Elastic IP address 'eipalloc-xxx' is
already associated.
```

#### 해결 방법
```bash
# EIP 연결 상태 확인
aws ec2 describe-addresses --allocation-ids eipalloc-xxx

# NAT Gateway 삭제
NAT_GW_ID=$(aws ec2 describe-addresses \
  --allocation-ids eipalloc-xxx \
  --query 'Addresses[0].AssociationId' \
  --output text)

aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_ID

# 5분 대기 (NAT Gateway 삭제 완료)
sleep 300

# EIP 해제 및 삭제
aws ec2 release-address --allocation-id eipalloc-xxx

# Terraform 재실행
terraform apply
```

---

### 3.4 백업 인스턴스와 RDS AZ 정렬

#### 개선 사항
백업 인스턴스를 RDS와 동일한 Availability Zone에 배치하여 성능과 비용을 최적화했습니다.

#### 구현 방법

**1단계: RDS AZ 정보 노출**
```hcl
# modules/rds/outputs.tf
output "db_availability_zone" {
  description = "RDS 인스턴스 가용영역"
  value       = aws_db_instance.main.availability_zone
}
```

**2단계: VPC 서브넷 매핑**
```hcl
# modules/vpc/outputs.tf
output "was_subnets_by_az" {
  description = "WAS 서브넷 ID를 AZ별로 매핑"
  value = zipmap(
    aws_subnet.was[*].availability_zone,
    aws_subnet.was[*].id
  )
}
```

**3단계: 백업 인스턴스 배치**
```hcl
# backup-instance.tf
resource "aws_instance" "backup_instance" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  # RDS와 동일한 AZ의 WAS 서브넷에 배치
  subnet_id                   = module.vpc.was_subnets_by_az[module.rds.db_availability_zone]
  availability_zone           = module.rds.db_availability_zone

  # ...
}
```

#### 장점
- 네트워크 지연 최소화 (같은 AZ 내 데이터 전송)
- 데이터 전송 비용 절감 (AZ 간 전송 비용 없음)
- 백업 성능 향상

#### 고려사항
- AZ 장애 시 RDS와 백업 인스턴스가 동시에 영향받을 수 있음
- 완화: Azure Blob Storage 백업이 리전 단위 DR 역할 수행
- Multi-AZ RDS 사용 시: Primary AZ만 추적

#### 관련 문서
- [BACKUP_INSTANCE_AZ_ALIGNMENT.md](./BACKUP_INSTANCE_AZ_ALIGNMENT.md)

---

## 4. Kubernetes 배포 문제

### 4.1 AWS Load Balancer Controller 설치 실패

#### 문제 상황
```
aws-load-balancer-controller   0/2     0            0
```

#### 원인
- ServiceAccount가 없거나 IAM Role이 연결되지 않음
- OIDC Provider 미설정

#### 해결 절차

**1단계: OIDC Provider 설정**
```bash
export CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl utils associate-iam-oidc-provider \
  --region ap-northeast-2 \
  --cluster $CLUSTER_NAME \
  --approve
```

**2단계: IAM Policy 생성**
```bash
curl -o /tmp/iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/iam-policy.json
```

**3단계: ServiceAccount 생성**
```bash
export OIDC_PROVIDER=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --region ap-northeast-2 \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed -e "s/^https:\/\///")

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

export ROLE_NAME="AWSLoadBalancerControllerRole-$(date +%s)"

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
```

**4단계: Deployment 재시작**
```bash
kubectl rollout restart deployment aws-load-balancer-controller -n kube-system

# 확인
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

---

### 4.2 WAS Pod CrashLoopBackOff

#### 문제 상황
```
was-spring-xxx   0/1     CrashLoopBackOff   5   10m
```

#### 원인
1. DB 비밀번호 불일치
2. RDS 보안 그룹 설정 오류
3. RDS 엔드포인트 잘못 설정

#### 해결 절차

**1단계: Pod 로그 확인**
```bash
kubectl logs -n was -l app=was-spring --tail=100

# 에러 패턴 확인
# "Access denied for user 'admin'@'xxx'" -> 비밀번호 문제
# "Communications link failure" -> 네트워크 문제
# "Unknown database 'pocketbank'" -> 데이터베이스 없음
```

**2단계: Secret 확인 및 재생성**
```bash
# 현재 비밀번호 확인
kubectl get secret db-credentials -n was -o jsonpath='{.data.password}' | base64 -d
echo

# Secret 삭제
kubectl delete secret db-credentials -n was

# RDS 정보 확인
export RDS_HOST=$(cd ~/3tier-terraform/codes/aws/2.\ service && terraform output -raw rds_address)

# Secret 재생성
kubectl create secret generic db-credentials \
  --from-literal=url="jdbc:mysql://${RDS_HOST}:3306/petclinic" \
  --from-literal=username="admin" \
  --from-literal=password="byemyblue" \
  --namespace=was

# Deployment 재시작
kubectl rollout restart deployment was-spring -n was

# 로그 모니터링
kubectl logs -f deployment/was-spring -n was
```

**3단계: RDS 보안 그룹 확인**
```bash
# RDS 보안 그룹 ID 확인
RDS_SG_ID=$(aws rds describe-db-instances \
  --db-instance-identifier blue-rds \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# 인바운드 규칙 확인
aws ec2 describe-security-groups \
  --group-ids $RDS_SG_ID \
  --query 'SecurityGroups[0].IpPermissions'

# WAS 서브넷 CIDR 확인
WAS_SUBNET_CIDR="10.0.11.0/24"

# 규칙이 없다면 추가
aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --cidr $WAS_SUBNET_CIDR
```

---

### 4.3 ALB 생성 안됨

#### 문제 상황
```bash
kubectl get ingress -n web
# NAME          CLASS   HOSTS   ADDRESS   PORTS   AGE
# web-ingress   alb     *                 80      10m
```
ADDRESS 필드가 비어있음

#### 원인
- Public Subnet 태그 누락
- Load Balancer Controller 로그에 에러 존재

#### 해결 방법

**1단계: Controller 로그 확인**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=100
```

**2단계: Public Subnet 태그 추가**
```bash
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
```

**3단계: Ingress 재생성**
```bash
kubectl delete ingress web-ingress -n web
sleep 30
kubectl apply -f k8s-manifests/ingress/ingress.yaml

# ALB 생성 확인 (2-3분 소요)
kubectl get ingress -n web -w
```

---

### 4.4 ServiceAccount DNS 해석 실패

#### 문제 상황
```
Error: unable to recognize "sa.yaml": Get
"https://FEACDB00987EE9F39E4D7139AF69127D.gr7.ap-northeast-2.eks.amazonaws.com/...":
dial tcp: lookup FEACDB00987EE9F39E4D7139AF69127D.gr7.ap-northeast-2.eks.amazonaws.com:
no such host
```

#### 원인
EKS 클러스터 엔드포인트가 DNS에 전파되지 않음 (클러스터 생성 직후 1-2분 소요)

#### 해결 방법

**방법 1: kubeconfig 재생성**
```bash
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name $(terraform output -raw eks_cluster_name)

kubectl cluster-info

# 재시도
kubectl apply -f sa.yaml
```

**방법 2: DNS 캐시 초기화**
```bash
# Ubuntu/Debian
sudo systemctl restart systemd-resolved
sudo resolvectl flush-caches

# DNS 조회 테스트
nslookup FEACDB00987EE9F39E4D7139AF69127D.gr7.ap-northeast-2.eks.amazonaws.com
```

**방법 3: 대기 후 재시도**
```bash
# 2분 대기
sleep 120

kubectl apply -f sa.yaml
```

---

## 5. 백업 시스템 문제

### 5.1 MySQL 백업 연결 문제

#### 문제 상황
백업 인스턴스에서 RDS로 MySQL 연결 시 실패

#### 원인
`-p` 옵션 사용법 오류 또는 환경변수 미설정

#### 해결 절차

**1단계: 백업 인스턴스 접속**
```bash
# SSM으로 접속
BACKUP_INSTANCE_ID=$(terraform output -raw backup_instance_id)
aws ssm start-session --target $BACKUP_INSTANCE_ID
```

**2단계: 환경변수 설정**
```bash
# RDS 정보 수동 설정
export RDS_HOST="blue-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com"
export DB_USERNAME="admin"
export DB_PASSWORD="byemyblue"

echo "RDS Host: $RDS_HOST"
echo "DB Username: $DB_USERNAME"
```

**3단계: MySQL 연결 테스트 (여러 방법)**
```bash
# 방법 1: 비밀번호를 직접 붙여서 입력
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;"

# 방법 2: 비밀번호 프롬프트 사용
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p
# Enter password: byemyblue

# 방법 3: 설정 파일 사용 (권장)
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

**4단계: 데이터베이스 확인**
```bash
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "SHOW DATABASES;"
mysql -h "$RDS_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" -e "USE petclinic; SHOW TABLES;"
```

---

### 5.2 mysqldump 권한 오류 (RDS)

#### 문제 상황
```
mysqldump: Couldn't execute 'FLUSH TABLES WITH READ LOCK':
Access denied; you need (at least one of) the RELOAD privilege(s)
for this operation (1227)
```

#### 원인
RDS MySQL은 보안상 FLUSH TABLES WITH READ LOCK 권한을 제공하지 않습니다.

#### 해결 방법

`--set-gtid-purged=OFF` 옵션 추가:

```bash
# backup-init.sh (이미 수정됨)
mysqldump \
    -h $RDS_HOST \
    -u $DB_USERNAME \
    -p"$DB_PASSWORD" \
    --single-transaction \
    --skip-lock-tables \
    --routines \
    --triggers \
    --events \
    --set-gtid-purged=OFF \  # 이 옵션이 핵심
    --databases $DB_NAME \
    > $BACKUP_FILE
```

기존 백업 인스턴스 수정:
```bash
# SSM 접속
aws ssm start-session --target i-0066dc51da5528f0f

# 스크립트 수정
sudo sed -i 's/--single-transaction/--single-transaction --set-gtid-purged=OFF/g' \
  /usr/local/bin/mysql-backup-to-azure.sh

# 백업 테스트
sudo /usr/local/bin/mysql-backup-to-azure.sh

# 로그 확인
sudo tail -f /var/log/mysql-backup-to-azure.log
```

---

### 5.3 Azure Blob Storage 백업 실패

#### 문제 상황
```
ERROR: Backup file not found in Azure Blob Storage
```

#### 원인
- Storage Account Key 불일치
- Container 이름 오류
- 네트워크 연결 문제

#### 해결 절차

**1단계: Storage Account 확인**
```bash
az storage account show \
  --name bloberry01 \
  --query 'name'
```

**2단계: Container 확인**
```bash
az storage container show \
  --account-name bloberry01 \
  --name mysql-backups
```

**3단계: 백업 파일 목록 확인**
```bash
az storage blob list \
  --account-name bloberry01 \
  --container-name mysql-backups \
  --output table
```

**4단계: Storage Key 업데이트**
```bash
# 최신 Storage Key 가져오기
NEW_KEY=$(az storage account keys list \
  --account-name bloberry01 \
  --resource-group rg-dr-blue \
  --query "[0].value" -o tsv)

# 백업 인스턴스에서 업데이트
aws ssm start-session --target i-0066dc51da5528f0f

# 스크립트에서 Storage Key 업데이트
sudo sed -i "s/AZURE_STORAGE_KEY=.*/AZURE_STORAGE_KEY=\"$NEW_KEY\"/g" \
  /usr/local/bin/mysql-backup-to-azure.sh

# 백업 테스트
sudo /usr/local/bin/mysql-backup-to-azure.sh
```

---

## 6. 네트워크 및 DNS 문제

### 6.1 Route53 DNS 전파 안됨

#### 문제 상황
```bash
dig blueisthenewblack.store
# ANSWER: 0
```

#### 원인
도메인 등록 업체의 네임서버가 Route53 네임서버로 변경되지 않음

#### 해결 절차

**1단계: Route53 네임서버 확인**
```bash
aws route53 get-hosted-zone \
  --id $(terraform output -raw route53_zone_id) \
  --query 'DelegationSet.NameServers'

# 출력 예시:
# [
#     "ns-1234.awsdns-12.org",
#     "ns-5678.awsdns-34.co.uk",
#     "ns-91.awsdns-11.com",
#     "ns-1234.awsdns-56.net"
# ]
```

**2단계: 도메인 등록 업체 네임서버 확인**
```bash
whois blueisthenewblack.store | grep -i "name server"
```

**3단계: 네임서버 변경**
- 도메인 등록 업체 웹사이트 접속
- DNS 설정 메뉴
- 네임서버를 Route53의 네임서버로 변경
- 저장 및 전파 대기 (최대 48시간, 보통 1-2시간)

**4단계: 전파 확인**
```bash
# 특정 네임서버에 직접 질의
dig @ns-1234.awsdns-12.org blueisthenewblack.store

# 전파 상태 확인 (여러 DNS 서버)
for ns in 8.8.8.8 1.1.1.1 208.67.222.222; do
  echo "=== DNS: $ns ==="
  dig @$ns blueisthenewblack.store +short
  echo
done
```

**5단계: 임시 /etc/hosts 사용**
```bash
# ALB IP 확인
ALB_DNS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
ALB_IP=$(dig $ALB_DNS +short | head -1)

# /etc/hosts 추가
echo "$ALB_IP blueisthenewblack.store" | sudo tee -a /etc/hosts

# 테스트
curl http://blueisthenewblack.store/
```

---

### 6.2 Subnet 태그 누락으로 ALB 생성 실패

#### 문제 상황
AWS Load Balancer Controller가 ALB를 생성하지 못함

#### 원인
Public Subnet에 필요한 태그가 누락됨

#### 필수 태그
```
kubernetes.io/role/elb = 1
kubernetes.io/cluster/<CLUSTER_NAME> = shared
```

#### 해결 방법

Terraform 코드에 태그 추가 (이미 수정됨):
```hcl
# modules/vpc/main.tf
resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.environment}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}
```

수동으로 태그 추가:
```bash
export CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
export PUBLIC_SUBNET_IDS=$(terraform output -json public_subnet_ids | jq -r '.[]')

for SUBNET_ID in $PUBLIC_SUBNET_IDS; do
  aws ec2 create-tags \
    --resources $SUBNET_ID \
    --tags \
      Key=kubernetes.io/role/elb,Value=1 \
      Key=kubernetes.io/cluster/${CLUSTER_NAME},Value=shared
done
```

---

## 요약 및 핵심 교훈

### 1. Terraform Destroy 문제
**핵심 교훈**: Kubernetes가 생성하는 AWS 리소스(ALB, ENI)는 Terraform이 직접 관리하지 않으므로, destroy provisioner에서 명시적으로 정리해야 합니다.

**해결 키워드**: ENI 삭제, cleanup provisioner, bash 인터프리터

### 2. Security Group 의존성
**핵심 교훈**: AWS의 eventual consistency와 숨겨진 의존성을 고려해야 하며, 적절한 대기 시간과 에러 처리가 필요합니다.

**해결 키워드**: 대기 시간, state 제거, AWS Console 사용

### 3. AWS 리소스 충돌
**핵심 교훈**: AWS 리소스 삭제 시 복구 대기 기간을 고려하고, 강제 삭제 옵션을 활용합니다.

**해결 키워드**: force-delete-without-recovery, resource import

### 4. Kubernetes 통합
**핵심 교훈**: EKS와 AWS 서비스 통합 시 IAM Role, OIDC Provider, Subnet 태그 등이 올바르게 설정되어야 합니다.

**해결 키워드**: ServiceAccount, IAM Role, Subnet 태그

### 5. 백업 시스템
**핵심 교훈**: RDS의 제한된 권한과 Azure 통합을 고려한 백업 스크립트 작성이 필요합니다.

**해결 키워드**: set-gtid-purged, Storage Key, mysql 연결 방법

### 6. 네트워크 및 DNS
**핵심 교훈**: 도메인 네임서버 변경과 DNS 전파 시간을 고려한 배포 계획이 필요합니다.

**해결 키워드**: Route53 네임서버, DNS 전파, /etc/hosts

---

## 관련 문서

- [FIX_SUMMARY_FINAL.md](./FIX_SUMMARY_FINAL.md) - Terraform Destroy 완전 해결
- [TERRAFORM_DESTROY_FIX.md](./TERRAFORM_DESTROY_FIX.md) - Destroy 에러 수정 가이드
- [EMERGENCY_FIX.md](./EMERGENCY_FIX.md) - Security Group 긴급 해결
- [SG_DEPENDENCY_FINAL_FIX.md](./SG_DEPENDENCY_FINAL_FIX.md) - SG 삭제 불가 문제
- [BACKUP_INSTANCE_AZ_ALIGNMENT.md](./BACKUP_INSTANCE_AZ_ALIGNMENT.md) - 백업 인스턴스 AZ 정렬
- [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) - Terraform Destroy 가이드
- [deployment-guide.md](./deployment-guide.md) - 배포 가이드

---

**작성일**: 2026-01-07
**버전**: 1.0
**상태**: 완료
