# AWS IAM 권한 설정 가이드

> Terraform으로 멀티클라우드 DR 아키텍처를 배포하기 위한 IAM 권한 설정

## 📋 목차

- [권한 설정 방법](#권한-설정-방법)
- [필수 AWS Managed Policies](#필수-aws-managed-policies)
- [커스텀 Policy (최소 권한 원칙)](#커스텀-policy-최소-권한-원칙)
- [콘솔에서 설정하기](#콘솔에서-설정하기)
- [CLI로 설정하기](#cli로-설정하기)
- [권한 검증](#권한-검증)

---

## 권한 설정 방법

두 가지 방법 중 선택:

### 방법 1: AWS Managed Policies (권장 - 간단함)
- AWS에서 제공하는 정책 사용
- 빠르고 간단하게 설정 가능
- **단점**: 필요 이상의 권한 부여 가능

### 방법 2: 커스텀 Policy (보안 강화)
- 최소 권한 원칙 적용
- 프로젝트에 필요한 권한만 부여
- **단점**: 설정이 복잡함

---

## 필수 AWS Managed Policies

### 🎯 방법 1 사용 시 (빠른 시작 - 개발/테스트 환경)

다음 AWS Managed Policies를 User 또는 Group에 연결하세요:

| Policy 이름 | 목적 | 필수 여부 |
|------------|------|----------|
| **AmazonVPCFullAccess** | VPC, Subnet, Route Table, NAT Gateway 관리 | ✅ 필수 |
| **AmazonEKSClusterPolicy** | EKS Cluster 생성 및 관리 | ✅ 필수 |
| **AmazonEKSWorkerNodePolicy** | EKS Node Group 관리 | ✅ 필수 |
| **AmazonEKS_CNI_Policy** | EKS Pod 네트워킹 | ✅ 필수 |
| **AmazonEC2ContainerRegistryReadOnly** | ECR 이미지 Pull | ✅ 필수 |
| **AmazonRDSFullAccess** | RDS 인스턴스 생성 및 관리 | ✅ 필수 |
| **AWSLambda_FullAccess** | Lambda 함수 생성 및 관리 | ✅ 필수 |
| **AmazonS3FullAccess** | S3 버킷 생성 및 관리 | ✅ 필수 |
| **CloudWatchFullAccess** | CloudWatch 로그, 메트릭, 알람 | ✅ 필수 |
| **IAMFullAccess** | IAM Role, Policy 생성 (EKS IRSA용) | ✅ 필수 |
| **AmazonRoute53FullAccess** | Route 53 DNS 및 Health Check | ✅ 필수 |
| **ElasticLoadBalancingFullAccess** | ALB 생성 및 관리 | ✅ 필수 |
| **AmazonEventBridgeFullAccess** | EventBridge 규칙 생성 | ✅ 필수 |
| **AmazonSNSFullAccess** | SNS 토픽 및 구독 관리 | ✅ 필수 |
| **AmazonEC2FullAccess** | Security Group, VPN Gateway 등 | ✅ 필수 |

**총 15개 Policies**

---

## 커스텀 Policy (최소 권한 원칙)

### 🔒 방법 2 사용 시 (운영 환경 권장)

다음 커스텀 Policy를 생성하고 User/Group에 연결하세요.

### Policy 1: VPC 및 네트워크 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VPCManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:DescribeVpcs",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:DescribeSubnets",
        "ec2:ModifySubnetAttribute",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:DescribeRouteTables",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecurityGroups",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "VPNGateway",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateVpnGateway",
        "ec2:DeleteVpnGateway",
        "ec2:AttachVpnGateway",
        "ec2:DetachVpnGateway",
        "ec2:DescribeVpnGateways",
        "ec2:CreateCustomerGateway",
        "ec2:DeleteCustomerGateway",
        "ec2:DescribeCustomerGateways",
        "ec2:CreateVpnConnection",
        "ec2:DeleteVpnConnection",
        "ec2:DescribeVpnConnections"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 2: EKS 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSClusterManagement",
      "Effect": "Allow",
      "Action": [
        "eks:CreateCluster",
        "eks:DeleteCluster",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:UpdateClusterConfig",
        "eks:UpdateClusterVersion",
        "eks:CreateNodegroup",
        "eks:DeleteNodegroup",
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "eks:UpdateNodegroupConfig",
        "eks:UpdateNodegroupVersion",
        "eks:CreateAddon",
        "eks:DeleteAddon",
        "eks:DescribeAddon",
        "eks:ListAddons",
        "eks:UpdateAddon",
        "eks:TagResource",
        "eks:UntagResource",
        "eks:ListTagsForResource",
        "eks:DescribeUpdate",
        "eks:ListUpdates"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EKSServiceLinkedRole",
      "Effect": "Allow",
      "Action": [
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "arn:aws:iam::*:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS*",
      "Condition": {
        "StringLike": {
          "iam:AWSServiceName": "eks.amazonaws.com"
        }
      }
    },
    {
      "Sid": "EC2ForEKS",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeImages",
        "ec2:DescribeVolumes",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:RunInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScalingForEKS",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 3: RDS 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSManagement",
      "Effect": "Allow",
      "Action": [
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:DescribeDBInstances",
        "rds:ModifyDBInstance",
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:DescribeDBSubnetGroups",
        "rds:CreateDBParameterGroup",
        "rds:DeleteDBParameterGroup",
        "rds:DescribeDBParameterGroups",
        "rds:ModifyDBParameterGroup",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource",
        "rds:ListTagsForResource",
        "rds:CreateDBSnapshot",
        "rds:DeleteDBSnapshot",
        "rds:DescribeDBSnapshots"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 4: Lambda 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LambdaManagement",
      "Effect": "Allow",
      "Action": [
        "lambda:CreateFunction",
        "lambda:DeleteFunction",
        "lambda:GetFunction",
        "lambda:ListFunctions",
        "lambda:UpdateFunctionCode",
        "lambda:UpdateFunctionConfiguration",
        "lambda:InvokeFunction",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:GetPolicy",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:ListTags",
        "lambda:PublishVersion",
        "lambda:CreateAlias",
        "lambda:DeleteAlias",
        "lambda:UpdateAlias"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 5: S3 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3Management",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:GetBucketAcl",
        "s3:PutBucketAcl",
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListAllMyBuckets",
        "s3:PutBucketTagging",
        "s3:GetBucketTagging",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetBucketPublicAccessBlock"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 6: IAM 권한 (IRSA용)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "IAMForEKSIRSA",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicies",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagPolicy",
        "iam:UntagPolicy",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 7: Load Balancer 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LoadBalancerManagement",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DescribeLoadBalancers",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags",
        "elasticloadbalancing:DescribeTags"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 8: CloudWatch & EventBridge 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchManagement",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EventBridgeManagement",
      "Effect": "Allow",
      "Action": [
        "events:PutRule",
        "events:DeleteRule",
        "events:DescribeRule",
        "events:ListRules",
        "events:PutTargets",
        "events:RemoveTargets",
        "events:ListTargetsByRule",
        "events:TagResource",
        "events:UntagResource"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 9: Route 53 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Route53Management",
      "Effect": "Allow",
      "Action": [
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetChange",
        "route53:CreateHealthCheck",
        "route53:DeleteHealthCheck",
        "route53:GetHealthCheck",
        "route53:ListHealthChecks",
        "route53:UpdateHealthCheck",
        "route53:GetHealthCheckStatus",
        "route53:ChangeTagsForResource",
        "route53:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

### Policy 10: SNS 권한

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SNSManagement",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:ListTopics",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:ListSubscriptions",
        "sns:ListSubscriptionsByTopic",
        "sns:Publish",
        "sns:TagResource",
        "sns:UntagResource",
        "sns:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 콘솔에서 설정하기

### 방법 1: AWS Managed Policies 연결

#### Step 1: IAM 콘솔 접속
1. AWS Console → IAM 서비스
2. 좌측 메뉴에서 **"Users"** 또는 **"User groups"** 선택

#### Step 2: User/Group 선택
- **User에 직접 연결**: Users → 사용자 선택
- **Group에 연결 (권장)**: User groups → 그룹 선택 (또는 "Create group")

#### Step 3: Permissions 탭 → Add permissions

1. **"Add permissions"** 버튼 클릭
2. **"Attach policies directly"** 선택
3. 검색창에서 아래 정책들을 하나씩 검색하여 체크:

```
✅ AmazonVPCFullAccess
✅ AmazonEKSClusterPolicy
✅ AmazonEKSWorkerNodePolicy
✅ AmazonEKS_CNI_Policy
✅ AmazonEC2ContainerRegistryReadOnly
✅ AmazonRDSFullAccess
✅ AWSLambda_FullAccess
✅ AmazonS3FullAccess
✅ CloudWatchFullAccess
✅ IAMFullAccess
✅ AmazonRoute53FullAccess
✅ ElasticLoadBalancingFullAccess
✅ AmazonEventBridgeFullAccess
✅ AmazonSNSFullAccess
✅ AmazonEC2FullAccess
```

4. **"Next"** → **"Add permissions"** 클릭

---

### 방법 2: 커스텀 Policy 연결

#### Step 1: Policy 생성

1. IAM 콘솔 → 좌측 메뉴 **"Policies"**
2. **"Create policy"** 버튼 클릭
3. **"JSON"** 탭 선택
4. 위의 Policy 1~10 중 하나를 복사하여 붙여넣기
5. **"Next"** 클릭
6. Policy 이름 입력 (예: `TerraformDR-VPC-Policy`)
7. **"Create policy"** 클릭
8. **Policy 2~10도 반복**

#### Step 2: Policy를 User/Group에 연결

1. Users 또는 User groups → 사용자/그룹 선택
2. **"Add permissions"** 버튼
3. **"Attach policies directly"** 선택
4. 생성한 커스텀 Policy 10개 모두 체크
5. **"Add permissions"** 클릭

---

## CLI로 설정하기

### 방법 1: AWS Managed Policies (CLI)

```bash
# User에 직접 연결
USER_NAME="terraform-user"

aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AWSLambdaFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
aws iam attach-user-policy --user-name $USER_NAME --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

**또는 Group에 연결:**
```bash
GROUP_NAME="terraform-group"

aws iam attach-group-policy --group-name $GROUP_NAME --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
# ... (위와 동일하게 반복)
```

---

### 방법 2: 커스텀 Policy (CLI)

```bash
# Policy 파일들을 저장할 디렉토리 생성
mkdir -p iam-policies

# Policy 1: VPC 생성
cat > iam-policies/vpc-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [...]
}
EOF

# Policy 생성
aws iam create-policy \
  --policy-name TerraformDR-VPC-Policy \
  --policy-document file://iam-policies/vpc-policy.json

# 생성된 Policy ARN 확인
export POLICY_ARN=$(aws iam list-policies \
  --scope Local \
  --query 'Policies[?PolicyName==`TerraformDR-VPC-Policy`].Arn' \
  --output text)

# User/Group에 연결
aws iam attach-user-policy \
  --user-name terraform-user \
  --policy-arn $POLICY_ARN

# Policy 2-10도 동일하게 반복
```

---

## 권한 검증

### 연결된 Policy 확인

```bash
# User에 연결된 Policy 목록
aws iam list-attached-user-policies --user-name terraform-user

# Group에 연결된 Policy 목록
aws iam list-attached-group-policies --group-name terraform-group

# User가 속한 Group 확인
aws iam list-groups-for-user --user-name terraform-user
```

### 권한 테스트

```bash
# VPC 권한 테스트
aws ec2 describe-vpcs

# EKS 권한 테스트
aws eks list-clusters

# RDS 권한 테스트
aws rds describe-db-instances

# S3 권한 테스트
aws s3 ls

# Lambda 권한 테스트
aws lambda list-functions

# IAM 권한 테스트
aws iam list-roles --max-items 1
```

**모든 명령어가 오류 없이 실행되면 권한 설정 완료!**

---

## 추천 설정 방법

### 🎯 개발/테스트 환경
**→ 방법 1 사용 (AWS Managed Policies)**
- 빠르고 간단
- 15개 Policy 연결만으로 완료

### 🔒 운영 환경
**→ 방법 2 사용 (커스텀 Policy)**
- 최소 권한 원칙
- 보안 강화
- 10개 커스텀 Policy 생성 및 연결

---

## 보안 Best Practices

### 1. User Group 사용 권장
```bash
# Group 생성
aws iam create-group --group-name terraform-admins

# User를 Group에 추가
aws iam add-user-to-group \
  --user-name terraform-user \
  --group-name terraform-admins

# Group에 Policy 연결 (User에 개별 연결보다 관리 용이)
aws iam attach-group-policy \
  --group-name terraform-admins \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
```

### 2. MFA 활성화
```bash
# MFA 디바이스 연결 (콘솔에서 설정 권장)
# IAM → Users → Security credentials → MFA
```

### 3. Access Key 관리
```bash
# Access Key 로테이션 (90일마다)
aws iam create-access-key --user-name terraform-user

# 기존 Key 비활성화
aws iam update-access-key \
  --access-key-id OLD_KEY_ID \
  --status Inactive \
  --user-name terraform-user
```

### 4. CloudTrail 로깅 활성화
```bash
# 모든 API 호출 기록
aws cloudtrail create-trail \
  --name terraform-audit-trail \
  --s3-bucket-name my-cloudtrail-bucket
```

---

## 트러블슈팅

### 문제 1: "AccessDenied" 오류

```bash
# 현재 사용자 확인
aws sts get-caller-identity

# 연결된 Policy 확인
aws iam list-attached-user-policies --user-name $(aws sts get-caller-identity --query Arn --output text | cut -d'/' -f2)

# 특정 Action 권한 확인
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names ec2:CreateVpc
```

### 문제 2: Policy가 너무 많아 보임

**해결**: Inline Policy 대신 Managed Policy 사용
```bash
# User의 Inline Policy 제거
aws iam delete-user-policy \
  --user-name terraform-user \
  --policy-name old-inline-policy
```

### 문제 3: Terraform에서 특정 리소스 생성 실패

```bash
# Terraform 로그 확인
export TF_LOG=DEBUG
terraform apply

# 필요한 권한 확인 후 추가
aws iam attach-user-policy \
  --user-name terraform-user \
  --policy-arn <missing-policy-arn>
```

---

## 요약 체크리스트

### ✅ 빠른 시작 (개발/테스트)

```bash
□ AWS Console → IAM → User groups → Create group
□ Group name: "terraform-admins"
□ Add permissions → 15개 AWS Managed Policies 연결
□ Add user to group
□ 권한 테스트 완료
```

### ✅ 보안 강화 (운영 환경)

```bash
□ 10개 커스텀 Policy JSON 파일 생성
□ IAM → Policies → Create policy (10회 반복)
□ User group 생성
□ 커스텀 Policy 10개 연결
□ User를 Group에 추가
□ MFA 활성화
□ CloudTrail 활성화
□ 권한 테스트 완료
```

---

## 참고 자료

- **AWS IAM 문서**: https://docs.aws.amazon.com/IAM/
- **Terraform AWS Provider**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **AWS Policy Simulator**: https://policysim.aws.amazon.com/

---

**이제 IAM 권한 설정이 완료되었습니다!**

다음 단계: [README-DEPLOYMENT.md](./README-DEPLOYMENT.md)를 참고하여 인프라를 배포하세요.
