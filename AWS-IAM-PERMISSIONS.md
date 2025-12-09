# AWS IAM 권한 설정 가이드

> 멀티클라우드 DR 프로젝트 배포에 필요한 AWS IAM 권한 목록

## 📋 목차

- [권한 설정 방법](#권한-설정-방법)
- [필수 AWS 관리형 정책](#필수-aws-관리형-정책)
- [커스텀 정책 (최소 권한)](#커스텀-정책-최소-권한)
- [IAM 사용자 생성 및 권한 부여](#iam-사용자-생성-및-권한-부여)
- [권한 확인](#권한-확인)
- [보안 권장사항](#보안-권장사항)

---

## 권한 설정 방법

### 방법 1: AWS 관리형 정책 사용 (권장 - 빠르고 간단)

**장점**: 빠른 설정, AWS가 자동 업데이트
**단점**: 필요 이상의 권한 포함 가능

### 방법 2: 커스텀 정책 사용 (최소 권한 원칙)

**장점**: 필요한 권한만 부여
**단점**: 설정 복잡, 권한 누락 가능

---

## 필수 AWS 관리형 정책

### 🚀 빠른 시작 (프로덕션 권장하지 않음)

개발/테스트 환경에서 빠르게 시작하려면:

```bash
# IAM 사용자에 관리자 권한 부여 (전체 권한)
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

**⚠️ 주의**: AdministratorAccess는 모든 AWS 리소스에 대한 전체 권한입니다.

---

### ✅ 프로덕션 권장 - 서비스별 관리형 정책

다음 AWS 관리형 정책들을 조합하여 사용:

#### 1. VPC 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
```

**제공 권한**:
- VPC, Subnet, Route Table 생성/수정/삭제
- Internet Gateway, NAT Gateway 관리
- Security Group, Network ACL 관리
- VPC Endpoints, Flow Logs 관리

#### 2. EKS 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController
```

**제공 권한**:
- EKS Cluster 생성/관리
- Node Group 생성/관리
- Fargate Profile 관리
- VPC CNI 플러그인 사용

#### 3. EC2 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
```

**제공 권한**:
- EC2 인스턴스 관리 (EKS Node용)
- EBS 볼륨 관리
- AMI 관리
- Key Pair 관리

#### 4. RDS 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess
```

**제공 권한**:
- RDS 인스턴스 생성/수정/삭제
- Parameter Group, Option Group 관리
- Subnet Group 관리
- Snapshot 관리

#### 5. S3 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

**제공 권한**:
- S3 버킷 생성/삭제
- 객체 업로드/다운로드
- 버킷 정책 관리
- 수명 주기 정책 관리

#### 6. Lambda 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
```

**제공 권한**:
- Lambda 함수 생성/수정/삭제
- Lambda Layer 관리
- 이벤트 소스 매핑 관리

#### 7. CloudWatch 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess

aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess
```

**제공 권한**:
- CloudWatch Logs 생성/관리
- Metrics, Alarms 생성
- Dashboard 관리

#### 8. Route 53 관련 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess
```

**제공 권한**:
- Hosted Zone 생성/관리
- DNS 레코드 생성/수정/삭제
- Health Check 관리

#### 9. Elastic Load Balancing 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess
```

**제공 권한**:
- ALB, NLB 생성/관리
- Target Group 관리
- Listener, Rule 관리

#### 10. IAM 관련 권한 (제한적)
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
```

**제공 권한**:
- IAM Role, Policy 생성 (EKS, Lambda용)
- Service-Linked Role 생성
- OIDC Provider 생성

**⚠️ 주의**: IAMFullAccess는 강력한 권한이므로 신중하게 부여

#### 11. EventBridge 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess
```

**제공 권한**:
- EventBridge 규칙 생성
- 스케줄 관리
- 이벤트 버스 관리

#### 12. SNS 권한
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess
```

**제공 권한**:
- SNS Topic 생성/관리
- 구독 관리
- 메시지 발행

---

## 커스텀 정책 (최소 권한)

### 커스텀 정책 JSON

최소 권한 원칙에 따라 필요한 권한만 부여:

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
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:DescribeInternetGateways",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateNatGateway",
        "ec2:DeleteNatGateway",
        "ec2:DescribeNatGateways",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:DescribeAddresses",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:DescribeSecurityGroups",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateNetworkAcl",
        "ec2:DeleteNetworkAcl",
        "ec2:DescribeNetworkAcls",
        "ec2:CreateNetworkAclEntry",
        "ec2:DeleteNetworkAclEntry",
        "ec2:CreateVpcEndpoint",
        "ec2:DeleteVpcEndpoint",
        "ec2:DescribeVpcEndpoints",
        "ec2:CreateFlowLogs",
        "ec2:DeleteFlowLogs",
        "ec2:DescribeFlowLogs",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:DescribeTags"
      ],
      "Resource": "*"
    },
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
        "eks:TagResource",
        "eks:UntagResource",
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
        "eks:UpdateAddon"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2ForEKS",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceAttribute",
        "ec2:DescribeVolumes",
        "ec2:CreateVolume",
        "ec2:DeleteVolume",
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:DescribeImages",
        "ec2:DescribeKeyPairs",
        "ec2:CreateKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:DescribeLaunchTemplates",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:CreateLaunchConfiguration",
        "autoscaling:DeleteLaunchConfiguration",
        "autoscaling:DescribeLaunchConfigurations"
      ],
      "Resource": "*"
    },
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
        "rds:CreateOptionGroup",
        "rds:DeleteOptionGroup",
        "rds:DescribeOptionGroups",
        "rds:CreateDBSnapshot",
        "rds:DeleteDBSnapshot",
        "rds:DescribeDBSnapshots",
        "rds:AddTagsToResource",
        "rds:ListTagsForResource",
        "rds:RemoveTagsFromResource"
      ],
      "Resource": "*"
    },
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
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption",
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:GetBucketLifecycleConfiguration",
        "s3:PutBucketLifecycleConfiguration"
      ],
      "Resource": [
        "arn:aws:s3:::*dr-sync*",
        "arn:aws:s3:::*dr-sync*/*",
        "arn:aws:s3:::*backup*",
        "arn:aws:s3:::*backup*/*"
      ]
    },
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
        "lambda:PublishVersion",
        "lambda:CreateAlias",
        "lambda:DeleteAlias",
        "lambda:GetAlias",
        "lambda:InvokeFunction",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:AddPermission",
        "lambda:RemovePermission"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchManagement",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:CreateLogStream",
        "logs:DeleteLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboards",
        "cloudwatch:GetDashboard",
        "cloudwatch:ListDashboards"
      ],
      "Resource": "*"
    },
    {
      "Sid": "Route53Management",
      "Effect": "Allow",
      "Action": [
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:GetHostedZone",
        "route53:ListHostedZones",
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets",
        "route53:GetChange",
        "route53:CreateHealthCheck",
        "route53:DeleteHealthCheck",
        "route53:GetHealthCheck",
        "route53:ListHealthChecks",
        "route53:UpdateHealthCheck",
        "route53:GetHealthCheckStatus"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ELBManagement",
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
        "elasticloadbalancing:CreateRule",
        "elasticloadbalancing:DeleteRule",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMForServices",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
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
        "iam:ListPolicies",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:CreateServiceLinkedRole",
        "iam:DeleteServiceLinkedRole",
        "iam:GetServiceLinkedRoleDeletionStatus",
        "iam:PassRole",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:TagPolicy",
        "iam:UntagPolicy"
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
        "events:EnableRule",
        "events:DisableRule"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SNSManagement",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:ListTopics",
        "sns:SetTopicAttributes",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:ListSubscriptions",
        "sns:ListSubscriptionsByTopic",
        "sns:Publish"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateManagement",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/terraform-state-lock"
    }
  ]
}
```

### 커스텀 정책 생성 및 적용

```bash
# 1. 정책 JSON 파일 생성
cat > terraform-deployment-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    ... (위의 JSON 내용)
  ]
}
EOF

# 2. IAM 정책 생성
aws iam create-policy \
  --policy-name TerraformMultiCloudDRPolicy \
  --policy-document file://terraform-deployment-policy.json

# 3. 사용자에게 정책 연결
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::YOUR-ACCOUNT-ID:policy/TerraformMultiCloudDRPolicy
```

---

## IAM 사용자 생성 및 권한 부여

### 전체 프로세스

```bash
# 1. IAM 사용자 생성
aws iam create-user --user-name terraform-deploy-user

# 2. 프로그래밍 방식 액세스 키 생성
aws iam create-access-key --user-name terraform-deploy-user

# 출력 예시:
# {
#   "AccessKey": {
#     "UserName": "terraform-deploy-user",
#     "AccessKeyId": "AKIAIOSFODNN7EXAMPLE",
#     "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
#     "Status": "Active",
#     "CreateDate": "2024-01-01T00:00:00Z"
#   }
# }

# 3. 관리형 정책 연결 (방법 1 - 권장)
aws iam attach-user-policy \
  --user-name terraform-deploy-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess

aws iam attach-user-policy \
  --user-name terraform-deploy-user \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# ... (위의 모든 관리형 정책 연결)

# 또는

# 4. 커스텀 정책 연결 (방법 2)
aws iam attach-user-policy \
  --user-name terraform-deploy-user \
  --policy-arn arn:aws:iam::YOUR-ACCOUNT-ID:policy/TerraformMultiCloudDRPolicy

# 5. AWS CLI 설정
aws configure --profile terraform-deploy
# AWS Access Key ID: [위에서 생성한 AccessKeyId]
# AWS Secret Access Key: [위에서 생성한 SecretAccessKey]
# Default region name: ap-northeast-2
# Default output format: json

# 6. 프로필 사용
export AWS_PROFILE=terraform-deploy
aws sts get-caller-identity
```

---

## 권한 확인

### 현재 사용자 권한 확인

```bash
# 1. 현재 사용자 확인
aws sts get-caller-identity

# 2. 연결된 정책 목록
aws iam list-attached-user-policies --user-name your-username

# 3. 특정 정책 내용 확인
aws iam get-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy

# 4. 정책 버전 확인
aws iam get-policy-version \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy \
  --version-id v1
```

### 권한 테스트

```bash
# VPC 생성 권한 테스트
aws ec2 describe-vpcs --dry-run

# EKS 조회 권한 테스트
aws eks list-clusters

# RDS 조회 권한 테스트
aws rds describe-db-instances

# S3 버킷 생성 권한 테스트
aws s3 mb s3://test-permissions-bucket-$(date +%s) --region ap-northeast-2

# Lambda 함수 목록 조회
aws lambda list-functions
```

---

## 보안 권장사항

### 1. MFA (Multi-Factor Authentication) 활성화

```bash
# MFA 디바이스 생성
aws iam create-virtual-mfa-device \
  --virtual-mfa-device-name terraform-deploy-mfa \
  --outfile QRCode.png \
  --bootstrap-method QRCodePNG

# MFA 활성화
aws iam enable-mfa-device \
  --user-name terraform-deploy-user \
  --serial-number arn:aws:iam::ACCOUNT-ID:mfa/terraform-deploy-mfa \
  --authentication-code1 123456 \
  --authentication-code2 789012
```

### 2. 최소 권한 원칙

```bash
# 정기적으로 사용하지 않는 권한 제거
aws iam list-attached-user-policies --user-name your-username

# 불필요한 정책 제거
aws iam detach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/UNNECESSARY_POLICY
```

### 3. Access Key 정기 교체

```bash
# 새로운 Access Key 생성
aws iam create-access-key --user-name your-username

# 기존 Access Key 비활성화
aws iam update-access-key \
  --user-name your-username \
  --access-key-id OLD_ACCESS_KEY_ID \
  --status Inactive

# 기존 Access Key 삭제
aws iam delete-access-key \
  --user-name your-username \
  --access-key-id OLD_ACCESS_KEY_ID
```

### 4. CloudTrail 활성화 (감사 로깅)

```bash
# CloudTrail 추적 생성
aws cloudtrail create-trail \
  --name terraform-audit-trail \
  --s3-bucket-name my-cloudtrail-bucket

# 추적 시작
aws cloudtrail start-logging --name terraform-audit-trail
```

### 5. IAM Access Analyzer 활성화

```bash
# Access Analyzer 생성
aws accessanalyzer create-analyzer \
  --analyzer-name terraform-access-analyzer \
  --type ACCOUNT
```

---

## 권한 문제 해결

### 일반적인 오류 및 해결 방법

#### 1. "User is not authorized to perform: eks:CreateCluster"

**원인**: EKS 관련 권한 부족

**해결**:
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

#### 2. "User is not authorized to perform: iam:PassRole"

**원인**: IAM Role을 다른 서비스에 전달할 권한 부족

**해결**:
```bash
# PassRole 권한 추가
cat > passrole-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": [
            "eks.amazonaws.com",
            "lambda.amazonaws.com",
            "rds.amazonaws.com"
          ]
        }
      }
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name your-username \
  --policy-name PassRolePolicy \
  --policy-document file://passrole-policy.json
```

#### 3. "Access Denied" when creating VPC endpoints

**원인**: VPC Endpoint 생성 권한 부족

**해결**:
```bash
aws iam attach-user-policy \
  --user-name your-username \
  --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess
```

---

## 요약 체크리스트

### ✅ 빠른 설정 (개발/테스트)

```bash
# 1. 사용자 생성
aws iam create-user --user-name terraform-deploy-user

# 2. Access Key 생성
aws iam create-access-key --user-name terraform-deploy-user

# 3. 필수 관리형 정책 연결 (12개)
for policy in \
  "AmazonVPCFullAccess" \
  "AmazonEKSClusterPolicy" \
  "AmazonEKSWorkerNodePolicy" \
  "AmazonEKS_CNI_Policy" \
  "AmazonEKSVPCResourceController" \
  "AmazonEC2FullAccess" \
  "AmazonRDSFullAccess" \
  "AmazonS3FullAccess" \
  "AWSLambda_FullAccess" \
  "CloudWatchFullAccess" \
  "AmazonRoute53FullAccess" \
  "ElasticLoadBalancingFullAccess" \
  "IAMFullAccess" \
  "AmazonEventBridgeFullAccess" \
  "AmazonSNSFullAccess"; do
  aws iam attach-user-policy \
    --user-name terraform-deploy-user \
    --policy-arn "arn:aws:iam::aws:policy/$policy"
done

# 4. AWS CLI 설정
aws configure --profile terraform-deploy
```

### ✅ 프로덕션 설정 (최소 권한)

```bash
# 1. 커스텀 정책 생성
aws iam create-policy \
  --policy-name TerraformMultiCloudDRPolicy \
  --policy-document file://terraform-deployment-policy.json

# 2. 정책 연결
aws iam attach-user-policy \
  --user-name terraform-deploy-user \
  --policy-arn arn:aws:iam::ACCOUNT-ID:policy/TerraformMultiCloudDRPolicy

# 3. MFA 활성화
# (위의 MFA 섹션 참고)

# 4. CloudTrail 활성화
aws cloudtrail create-trail --name terraform-audit-trail ...
```

---

## 추가 리소스

- **AWS IAM 문서**: https://docs.aws.amazon.com/iam/
- **IAM Policy Simulator**: https://policysim.aws.amazon.com/
- **AWS Policy Generator**: https://awspolicygen.s3.amazonaws.com/policygen.html

---

**권한 설정이 완료되면 [README-DEPLOYMENT.md](./README-DEPLOYMENT.md)를 따라 배포를 진행하세요!**
