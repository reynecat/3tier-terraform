# Terraform Destroy 에러 수정 가이드

## 문제 개요

Terraform destroy 실행 시 발생한 두 가지 주요 에러:

### 1. Security Group 의존성 에러
```
Error: deleting Security Group (sg-067530e0bb78b53ec): DependencyViolation
resource sg-067530e0bb78b53ec has a dependent object
```

### 2. Bash 스크립트 구문 에러
```
/bin/sh: 4: Syntax error: word unexpected (expecting "do")
```

---

## 근본 원인 분석

### 1. Security Group 의존성 에러

**원인:**
- Kubernetes의 AWS Load Balancer Controller가 생성한 ALB/NLB가 ENI(Elastic Network Interface)를 생성
- 이 ENI들이 Security Group을 참조하고 있음
- Terraform이 Security Group을 삭제하려 할 때, ENI가 아직 삭제되지 않아 의존성 에러 발생

**리소스 삭제 순서 문제:**
```
1. EKS 클러스터 삭제 시작
2. Terraform이 Security Group 삭제 시도
3. BUT: ALB/NLB의 ENI가 아직 존재하여 실패
4. 결과: DependencyViolation 에러
```

### 2. Bash 스크립트 구문 에러

**원인:**
- `provisioner "local-exec"`의 기본 인터프리터는 `/bin/sh`
- `/bin/sh`는 일부 bash 문법을 지원하지 않음
- Heredoc 내부의 줄바꿈 문자나 특수 문자 처리 실패

**문제가 된 코드:**
```hcl
provisioner "local-exec" {
  when = destroy
  command = <<-EOT
    for lb_arn in $(aws elbv2 ...); do
      ...
    done
  EOT
}
```

---

## 해결 방법

### 수정된 코드 주요 변경사항

#### 1. 명시적 Bash 인터프리터 지정
```hcl
provisioner "local-exec" {
  when        = destroy
  interpreter = ["/bin/bash", "-c"]  # ✅ bash 명시
  on_failure  = continue             # ✅ 에러 발생 시 계속 진행
  command     = <<-BASH
    ...
  BASH
}
```

#### 2. ENI(Network Interface) 정리 추가
```bash
# 3. VPC 내 모든 ENI (Elastic Network Interface) 정리
echo "Step 3: Cleaning up Network Interfaces in VPC $VPC_ID..."
ENI_IDS=$(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" \
  --output text 2>/dev/null || echo "")

if [ -n "$ENI_IDS" ]; then
  for eni_id in $ENI_IDS; do
    echo "  - Deleting ENI: $eni_id"
    aws ec2 delete-network-interface \
      --region "$REGION" \
      --network-interface-id "$eni_id" 2>/dev/null || true
  done
fi
```

#### 3. 적절한 대기 시간 추가
```bash
# ALB/NLB 삭제 후 대기
sleep 30

# 모든 정리 작업 후 Security Group 삭제 전 대기
sleep 20
```

#### 4. 에러 처리 강화
```bash
set -e  # 에러 발생 시 즉시 중단

# 각 AWS CLI 명령에 fallback 추가
LB_ARNS=$(aws elbv2 describe-load-balancers ... || echo "")

# 삭제 실패 시 계속 진행
aws elbv2 delete-load-balancer ... || true
```

---

## 리소스 삭제 순서 (개선 후)

```
1. Load Balancer 조회 및 삭제
   ↓
2. 대기 (30초) - ALB/NLB 완전 삭제
   ↓
3. Target Group 삭제
   ↓
4. ENI (Network Interface) 삭제  ⭐ 새로 추가
   ↓
5. 대기 (20초) - 의존성 완전 해제
   ↓
6. Security Group 삭제 (Terraform)
   ↓
7. 나머지 리소스 삭제
```

---

## 재발 방지 체크리스트

### ✅ 코드 수정 완료 항목

1. **[modules/eks/main.tf](./modules/eks/main.tf#L14-L98)**
   - `interpreter = ["/bin/bash", "-c"]` 추가
   - `on_failure = continue` 추가
   - ENI 정리 로직 추가
   - 적절한 대기 시간 추가

2. **[modules/eks/variables.tf](./modules/eks/variables.tf#L13-L17)**
   - `region` 변수 추가

3. **[main.tf](./main.tf#L55-L76)**
   - EKS 모듈에 `region` 파라미터 전달

### 🔍 향후 주의사항

1. **Kubernetes가 생성하는 AWS 리소스 파악**
   - ALB/NLB (Load Balancer)
   - Target Groups
   - ENI (Elastic Network Interfaces)
   - Security Group Rules

2. **Destroy 전 수동 정리 옵션**
   ```bash
   # EKS에 배포된 모든 서비스 삭제
   kubectl delete ingress --all -n web
   kubectl delete svc --all -n web
   kubectl delete svc --all -n was

   # 5분 대기 후 terraform destroy 실행
   sleep 300
   terraform destroy
   ```

3. **Terraform State 확인**
   ```bash
   terraform state list | grep security_group
   terraform state show <security_group_resource>
   ```

---

## 테스트 방법

### 1. 코드 검증
```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
terraform init
terraform validate
terraform plan -destroy
```

### 2. 실제 삭제 테스트 (주의!)
```bash
# 먼저 Kubernetes 리소스 정리
kubectl delete ingress --all --all-namespaces
kubectl delete svc --type=LoadBalancer --all --all-namespaces

# 3분 대기
sleep 180

# Terraform destroy 실행
terraform destroy -auto-approve
```

### 3. 에러 발생 시 수동 정리
```bash
# VPC ID 확인
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "vpc-xxxxxx")

# 모든 Load Balancer 삭제
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text | xargs -n1 aws elbv2 delete-load-balancer --load-balancer-arn

# 모든 Target Group 삭제
aws elbv2 describe-target-groups \
  --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
  --output text | xargs -n1 aws elbv2 delete-target-group --target-group-arn

# 모든 ENI 삭제
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" \
  --output text | xargs -n1 aws ec2 delete-network-interface --network-interface-id

# 다시 terraform destroy 실행
terraform destroy -auto-approve
```

---

## 관련 파일

- [modules/eks/main.tf](./modules/eks/main.tf) - 메인 수정 파일
- [modules/eks/variables.tf](./modules/eks/variables.tf) - region 변수 추가
- [main.tf](./main.tf) - region 파라미터 전달

---

## 참고 문서

- [Terraform Provisioners](https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [AWS ENI Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html)
