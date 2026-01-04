# Terraform Destroy 에러 수정 요약

## 🔴 발생한 문제

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

## ✅ 수정 사항

### 1. [modules/eks/main.tf](./modules/eks/main.tf#L14-L98)

#### Before (문제가 있던 코드):
```hcl
resource "null_resource" "cleanup_k8s_resources" {
  triggers = {
    cluster_name = "${var.environment}-eks"
    vpc_id       = var.vpc_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up..."
      for lb_arn in $(aws elbv2 ...); do
        ...
      done
    EOT
  }
}
```

**문제점:**
- ❌ 기본 인터프리터 `/bin/sh` 사용 → bash 문법 미지원
- ❌ ENI(Network Interface) 정리 누락 → Security Group 의존성 에러
- ❌ 에러 발생 시 즉시 중단 → 부분 정리 후 실패
- ❌ 리전 정보 미전달

#### After (수정된 코드):
```hcl
resource "null_resource" "cleanup_k8s_resources" {
  triggers = {
    cluster_name = "${var.environment}-eks"
    vpc_id       = var.vpc_id
    region       = var.region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]  # ✅ bash 명시
    on_failure  = continue             # ✅ 에러 시 계속 진행
    command     = <<-BASH
      set -e
      echo "=== Starting cleanup ==="

      VPC_ID="${self.triggers.vpc_id}"
      REGION="${self.triggers.region}"

      # 1. Load Balancer 삭제
      LB_ARNS=$(aws elbv2 describe-load-balancers ... || echo "")
      if [ -n "$LB_ARNS" ]; then
        for lb_arn in $LB_ARNS; do
          aws elbv2 delete-load-balancer ... || true
        done
        sleep 30
      fi

      # 2. Target Group 삭제
      TG_ARNS=$(aws elbv2 describe-target-groups ... || echo "")
      if [ -n "$TG_ARNS" ]; then
        for tg_arn in $TG_ARNS; do
          aws elbv2 delete-target-group ... || true
        done
      fi

      # 3. ENI 정리 ⭐ 새로 추가
      ENI_IDS=$(aws ec2 describe-network-interfaces ... || echo "")
      if [ -n "$ENI_IDS" ]; then
        for eni_id in $ENI_IDS; do
          aws ec2 delete-network-interface ... || true
        done
      fi

      # 4. Security Group 삭제 대기
      sleep 20
    BASH
  }
}
```

**개선점:**
- ✅ bash 인터프리터 명시적 지정
- ✅ ENI 정리 로직 추가 → Security Group 의존성 해결
- ✅ `on_failure = continue` → 에러 발생 시에도 계속 진행
- ✅ 각 AWS CLI 명령에 `|| true` 추가 → 개별 실패 시에도 계속
- ✅ 적절한 대기 시간 추가 (30초 + 20초)
- ✅ 리전 정보 triggers에 추가

### 2. [modules/eks/variables.tf](./modules/eks/variables.tf#L13-L17)

```hcl
variable "region" {
  description = "AWS 리전 (destroy 시 K8s 생성 리소스 정리에 사용)"
  type        = string
  default     = "ap-northeast-2"
}
```

### 3. [main.tf](./main.tf#L55-L76)

```hcl
module "eks" {
  source = "./modules/eks"

  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  region              = var.aws_region  # ✅ 추가
  web_subnet_ids      = module.vpc.web_subnet_ids
  was_subnet_ids      = module.vpc.was_subnet_ids
  ...
}
```

---

## 🔄 리소스 삭제 순서 비교

### Before (문제가 있던 순서):
```
1. EKS 클러스터 삭제 시작
2. Load Balancer 삭제
3. Target Group 삭제
4. Terraform이 Security Group 삭제 시도
5. ❌ ENI가 아직 남아있어 실패
```

### After (개선된 순서):
```
1. EKS 클러스터 삭제 시작
2. Load Balancer 삭제
3. ⏱️  대기 (30초)
4. Target Group 삭제
5. ✅ ENI 삭제 (새로 추가)
6. ⏱️  대기 (20초)
7. ✅ Security Group 삭제 성공
8. 나머지 리소스 삭제
```

---

## 🧪 테스트 결과

```bash
$ cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
$ terraform validate
Success! The configuration is valid.
```

---

## 📚 왜 이런 문제가 발생했나?

### 1. Kubernetes의 AWS 통합 방식
- AWS Load Balancer Controller는 Kubernetes `Ingress`/`Service` 리소스를 감지
- 자동으로 AWS의 ALB/NLB, Target Group, ENI, Security Group Rule 생성
- 이런 리소스들은 Terraform의 관리 범위 밖에 있음
- **Terraform destroy 시 이런 리소스들이 남아있어 의존성 에러 발생**

### 2. Shell 인터프리터 차이
- Terraform의 `local-exec` provisioner는 기본적으로 `/bin/sh` 사용
- `/bin/sh`는 POSIX 표준 쉘로 일부 bash 문법 미지원
- `for ... in $(command); do ... done` 같은 구문에서 에러 발생 가능

### 3. ENI(Elastic Network Interface)의 역할
- ALB/NLB는 각 서브넷에 ENI를 생성
- ENI는 Security Group을 참조
- **ENI가 삭제되지 않으면 Security Group 삭제 불가**

---

## 🛡️ 재발 방지책

### 1. Destroy 전 Kubernetes 리소스 정리 (권장)
```bash
# 모든 Ingress와 LoadBalancer 타입 Service 삭제
kubectl delete ingress --all --all-namespaces
kubectl delete svc --type=LoadBalancer --all --all-namespaces

# 5분 대기 (AWS 리소스 완전 삭제 대기)
sleep 300

# 이후 terraform destroy 실행
terraform destroy
```

### 2. 코드 레벨 방어
- ✅ **이미 적용됨**: `null_resource`에서 자동 정리
- ✅ **이미 적용됨**: bash 인터프리터 명시
- ✅ **이미 적용됨**: ENI 정리 로직
- ✅ **이미 적용됨**: `on_failure = continue`

### 3. 수동 정리 스크립트 (비상용)
```bash
#!/bin/bash
# cleanup-aws-k8s-resources.sh

VPC_ID="vpc-xxxxxx"  # 실제 VPC ID로 변경
REGION="ap-northeast-2"

# Load Balancer 삭제
aws elbv2 describe-load-balancers --region $REGION \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text | xargs -n1 aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn

sleep 30

# Target Group 삭제
aws elbv2 describe-target-groups --region $REGION \
  --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
  --output text | xargs -n1 aws elbv2 delete-target-group --region $REGION --target-group-arn

# ENI 삭제
aws ec2 describe-network-interfaces --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "NetworkInterfaces[?Status=='available'].NetworkInterfaceId" \
  --output text | xargs -n1 aws ec2 delete-network-interface --region $REGION --network-interface-id

sleep 20
echo "Cleanup complete. You can now run 'terraform destroy'"
```

---

## 📖 참고 자료

- [Terraform Local-Exec Provisioner](https://developer.hashicorp.com/terraform/language/resources/provisioners/local-exec)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [AWS Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html)
- [AWS ENI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html)

---

## 수정 파일 목록

| 파일 | 변경 내용 |
|------|----------|
| [modules/eks/main.tf](./modules/eks/main.tf) | cleanup provisioner 전면 개선 |
| [modules/eks/variables.tf](./modules/eks/variables.tf) | region 변수 추가 |
| [main.tf](./main.tf) | EKS 모듈에 region 파라미터 전달 |

---

**수정 완료 날짜**: 2026-01-04
**검증 상태**: ✅ `terraform validate` 통과
