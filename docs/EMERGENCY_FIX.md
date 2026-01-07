# 🚨 Security Group 에러 긴급 해결 가이드

> **현재 상황**: Terraform destroy 중 Security Group 의존성 에러 발생

```
Error: deleting Security Group (sg-067530e0bb78b53ec): DependencyViolation
resource sg-067530e0bb78b53ec has a dependent object
```

---

## 🎯 즉시 해결 방법

### Option 1: 자동 정리 스크립트 사용 (권장)

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service

# VPC ID 확인
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)
echo "VPC ID: $VPC_ID"

# 자동 정리 스크립트 실행
./manual-cleanup.sh "$VPC_ID"

# 정리 완료 후 다시 destroy
terraform destroy
```

### Option 2: 수동 명령어 실행

```bash
# 환경 설정
export AWS_REGION=ap-northeast-2
export VPC_ID="vpc-06e4fdfb8ec4950d1"  # 실제 VPC ID로 변경

# 1. Load Balancer 삭제
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text | \
xargs -n1 -I {} aws elbv2 delete-load-balancer --load-balancer-arn {}

sleep 30

# 2. Target Group 삭제
aws elbv2 describe-target-groups \
  --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
  --output text | \
xargs -n1 -I {} aws elbv2 delete-target-group --target-group-arn {}

# 3. ENI 삭제
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" \
  --output text | \
xargs -n1 -I {} aws ec2 delete-network-interface --network-interface-id {}

sleep 30

# 4. 다시 destroy 시도
terraform destroy
```

---

## 🔍 문제 원인 진단

### 해당 Security Group이 뭔지 확인

```bash
SG_ID="sg-067530e0bb78b53ec"  # 에러 메시지의 SG ID

aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].[GroupId,GroupName,Description,VpcId]' \
  --output table
```

### 무엇이 이 SG를 사용 중인지 확인

```bash
# ENI (Network Interface) 확인
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

---

## 🛠️ 단계별 강제 정리

### 1단계: Kubernetes 리소스 완전 삭제

```bash
# EKS 클러스터에 연결
aws eks update-kubeconfig --name blue-eks --region ap-northeast-2

# 모든 LoadBalancer 타입 서비스 삭제
kubectl delete svc --all --all-namespaces --field-selector spec.type=LoadBalancer

# 모든 Ingress 삭제
kubectl delete ingress --all --all-namespaces

# 5분 대기
sleep 300
```

### 2단계: AWS Load Balancer 강제 삭제

```bash
# VPC 내 모든 LB 찾기
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].[LoadBalancerArn,LoadBalancerName,Type]" \
  --output table

# 하나씩 삭제
for lb_arn in $(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text); do
  echo "Deleting: $lb_arn"
  aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn"
done
```

### 3단계: ENI 강제 해제 및 삭제

```bash
# VPC 내 모든 ENI 찾기
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
  --output table

# ENI 해제 및 삭제
for eni_id in $(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' \
  --output text); do

  echo "Processing ENI: $eni_id"

  # Attachment 확인
  attachment_id=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$eni_id" \
    --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
    --output text)

  # Detach if attached
  if [ "$attachment_id" != "None" ] && [ -n "$attachment_id" ]; then
    echo "  Detaching: $attachment_id"
    aws ec2 detach-network-interface \
      --attachment-id "$attachment_id" \
      --force || true
    sleep 5
  fi

  # Delete ENI
  echo "  Deleting: $eni_id"
  aws ec2 delete-network-interface \
    --network-interface-id "$eni_id" || true
done
```

### 4단계: Security Group 재확인

```bash
# 아직 남아있는 SG 확인
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[?GroupName!='default'].[GroupId,GroupName]" \
  --output table

# 특정 SG 사용 중인 리소스 재확인
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=$SG_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status]' \
  --output table
```

---

## 💡 Terraform State 재동기화

만약 리소스는 삭제되었는데 Terraform state에 남아있다면:

```bash
# State 확인
terraform state list | grep security_group

# 특정 리소스를 state에서 제거 (신중하게!)
# terraform state rm 'module.vpc.aws_security_group.xxxxx'

# 또는 전체 refresh
terraform refresh
```

---

## 🔄 최종 해결 프로세스

```bash
#!/bin/bash
# 완전 자동화 스크립트

set -e

VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)
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

---

## 🆘 그래도 안 되면?

### AWS Console에서 수동 삭제

1. **EC2 Console** → **Network Interfaces** → VPC 필터
   - 모든 ENI 수동 삭제

2. **EC2 Console** → **Load Balancers**
   - VPC 내 모든 ALB/NLB 수동 삭제

3. **EC2 Console** → **Security Groups**
   - VPC 내 Security Group 확인
   - 사용 중인 리소스 확인

4. **다시 Terraform Destroy**

---

## 📋 체크리스트

수동 정리 전 확인:

- [ ] VPC ID 확인 완료
- [ ] AWS Region 확인 완료
- [ ] kubectl 접근 가능 (EKS 있는 경우)
- [ ] AWS CLI 권한 확인 완료
- [ ] 중요 데이터 백업 완료

수동 정리 후 확인:

- [ ] Load Balancer 0개
- [ ] Target Group 0개
- [ ] Available ENI 0개
- [ ] Security Group 의존성 없음

---

## 🔗 관련 문서

- [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) - 정상적인 destroy 가이드
- [FIX_SUMMARY_FINAL.md](./FIX_SUMMARY_FINAL.md) - 코드 수정 내역
- [manual-cleanup.sh](./manual-cleanup.sh) - 자동화 스크립트

---

**작성일**: 2026-01-04
**상황**: Security Group DependencyViolation 에러 해결
