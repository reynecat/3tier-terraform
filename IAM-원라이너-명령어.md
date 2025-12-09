# AWS IAM 권한 한방에 추가하기 ⚡

## 🎯 User에 직접 추가 (원라이너)

```bash
USER_NAME="terraform-user" && \
for policy in \
  AmazonVPCFullAccess \
  AmazonEKSClusterPolicy \
  AmazonEKSWorkerNodePolicy \
  AmazonEKS_CNI_Policy \
  AmazonEC2ContainerRegistryReadOnly \
  AmazonRDSFullAccess \
  AWSLambda_FullAccess \
  AmazonS3FullAccess \
  CloudWatchFullAccess \
  IAMFullAccess \
  AmazonRoute53FullAccess \
  ElasticLoadBalancingFullAccess \
  AmazonEventBridgeFullAccess \
  AmazonSNSFullAccess \
  AmazonEC2FullAccess; do
  echo "Adding $policy..."
  aws iam attach-user-policy \
    --user-name $USER_NAME \
    --policy-arn arn:aws:iam::aws:policy/$policy
done && echo "✓ 완료!"
```

---

## 🎯 Group에 추가 (원라이너)

```bash
GROUP_NAME="terraform-group" && \
for policy in \
  AmazonVPCFullAccess \
  AmazonEKSClusterPolicy \
  AmazonEKSWorkerNodePolicy \
  AmazonEKS_CNI_Policy \
  AmazonEC2ContainerRegistryReadOnly \
  AmazonRDSFullAccess \
  AWSLambda_FullAccess \
  AmazonS3FullAccess \
  CloudWatchFullAccess \
  IAMFullAccess \
  AmazonRoute53FullAccess \
  ElasticLoadBalancingFullAccess \
  AmazonEventBridgeFullAccess \
  AmazonSNSFullAccess \
  AmazonEC2FullAccess; do
  echo "Adding $policy..."
  aws iam attach-group-policy \
    --group-name $GROUP_NAME \
    --policy-arn arn:aws:iam::aws:policy/$policy
done && echo "✓ 완료!"
```

---

## 🚀 자동화 스크립트 사용 (추천)

```bash
# 실행 권한 부여
chmod +x scripts/setup-iam-permissions.sh

# 스크립트 실행
./scripts/setup-iam-permissions.sh
```

---

## 📝 사용 예시

### 1. 새로운 User 생성 후 권한 추가
```bash
# User 생성
aws iam create-user --user-name terraform-user

# Access Key 생성
aws iam create-access-key --user-name terraform-user

# 한방에 권한 추가
USER_NAME="terraform-user" && \
for policy in AmazonVPCFullAccess AmazonEKSClusterPolicy AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonRDSFullAccess AWSLambda_FullAccess AmazonS3FullAccess CloudWatchFullAccess IAMFullAccess AmazonRoute53FullAccess ElasticLoadBalancingFullAccess AmazonEventBridgeFullAccess AmazonSNSFullAccess AmazonEC2FullAccess; do
  aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/$policy
done
```

### 2. Group 생성 후 권한 추가 (권장)
```bash
# Group 생성
aws iam create-group --group-name terraform-admins

# 한방에 권한 추가
GROUP_NAME="terraform-admins" && \
for policy in AmazonVPCFullAccess AmazonEKSClusterPolicy AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly AmazonRDSFullAccess AWSLambda_FullAccess AmazonS3FullAccess CloudWatchFullAccess IAMFullAccess AmazonRoute53FullAccess ElasticLoadBalancingFullAccess AmazonEventBridgeFullAccess AmazonSNSFullAccess AmazonEC2FullAccess; do
  aws iam attach-group-policy --group-name $GROUP_NAME --policy-arn arn:aws:iam::aws:policy/$policy
done

# User를 Group에 추가
aws iam add-user-to-group --user-name terraform-user --group-name terraform-admins
```

---

## ✅ 권한 추가 확인

```bash
# User에 연결된 Policy 확인
aws iam list-attached-user-policies --user-name terraform-user

# Group에 연결된 Policy 확인
aws iam list-attached-group-policies --group-name terraform-admins

# 권한 테스트
aws ec2 describe-vpcs
aws eks list-clusters
aws rds describe-db-instances
```

---

## 🔧 권한 제거 (필요 시)

### User에서 모든 권한 제거
```bash
USER_NAME="terraform-user" && \
aws iam list-attached-user-policies --user-name $USER_NAME \
  --query 'AttachedPolicies[].PolicyArn' --output text | \
  xargs -I {} aws iam detach-user-policy --user-name $USER_NAME --policy-arn {}
```

### Group에서 모든 권한 제거
```bash
GROUP_NAME="terraform-admins" && \
aws iam list-attached-group-policies --group-name $GROUP_NAME \
  --query 'AttachedPolicies[].PolicyArn' --output text | \
  xargs -I {} aws iam detach-group-policy --group-name $GROUP_NAME --policy-arn {}
```

---

## 💡 추가 Policy 목록 (15개)

1. **AmazonVPCFullAccess** - VPC, Subnet, NAT Gateway
2. **AmazonEKSClusterPolicy** - EKS Cluster
3. **AmazonEKSWorkerNodePolicy** - EKS Node Groups
4. **AmazonEKS_CNI_Policy** - EKS 네트워킹
5. **AmazonEC2ContainerRegistryReadOnly** - ECR 이미지
6. **AmazonRDSFullAccess** - RDS 데이터베이스
7. **AWSLambda_FullAccess** - Lambda 함수
8. **AmazonS3FullAccess** - S3 버킷
9. **CloudWatchFullAccess** - 로그 및 모니터링
10. **IAMFullAccess** - IAM Role/Policy (IRSA용)
11. **AmazonRoute53FullAccess** - DNS 및 Health Check
12. **ElasticLoadBalancingFullAccess** - ALB/NLB
13. **AmazonEventBridgeFullAccess** - EventBridge 스케줄
14. **AmazonSNSFullAccess** - SNS 알람
15. **AmazonEC2FullAccess** - EC2, Security Group

---

**이제 한 줄 명령어로 모든 권한을 추가할 수 있습니다!** 🚀
