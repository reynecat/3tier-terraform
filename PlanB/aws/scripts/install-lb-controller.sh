#!/bin/bash
# AWS Load Balancer Controller 설치 스크립트 (개선 버전)
# PlanB/aws/scripts/install-lb-controller.sh

set -e

echo "=========================================="
echo "AWS Load Balancer Controller 설치"
echo "=========================================="
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =================================================
# [1/8] 변수 설정 및 확인
# =================================================
log_info "[1/8] 변수 설정 중..."

# Terraform 디렉토리로 이동하여 클러스터 이름 가져오기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

# 클러스터 이름 확인
if [ ! -f "terraform.tfstate" ]; then
    log_error "terraform.tfstate 파일을 찾을 수 없습니다."
    log_error "먼저 'terraform apply'를 실행하세요."
    exit 1
fi

CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null)
if [ -z "$CLUSTER_NAME" ]; then
    log_error "EKS 클러스터 이름을 가져올 수 없습니다."
    exit 1
fi

# AWS 계정 ID 가져오기
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    log_error "AWS 계정 ID를 가져올 수 없습니다. AWS CLI 설정을 확인하세요."
    exit 1
fi

# 리전 설정
REGION=${AWS_REGION:-ap-northeast-2}

# OIDC Provider 가져오기
OIDC_PROVIDER=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query "cluster.identity.oidc.issuer" \
    --output text 2>/dev/null | sed -e "s/^https:\/\///")

if [ -z "$OIDC_PROVIDER" ]; then
    log_error "OIDC Provider를 가져올 수 없습니다."
    exit 1
fi

# 고유한 Role 이름 생성 (타임스탬프 사용)
ROLE_NAME="AWSLoadBalancerControllerRole-$(date +%s)"

log_info "변수 확인:"
echo "  - Cluster Name: $CLUSTER_NAME"
echo "  - Account ID: $ACCOUNT_ID"
echo "  - Region: $REGION"
echo "  - OIDC Provider: $OIDC_PROVIDER"
echo "  - Role Name: $ROLE_NAME"
echo ""

# =================================================
# [2/8] IAM Policy 확인 및 생성
# =================================================
log_info "[2/8] IAM Policy 확인 중..."

POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
    log_info "IAM Policy가 이미 존재합니다: $POLICY_ARN"
else
    log_warn "IAM Policy가 없습니다. 생성 중..."
    
    # Policy JSON 다운로드
    curl -sL https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json \
        -o /tmp/iam-policy.json
    
    # Policy 생성
    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/iam-policy.json \
        --description "IAM policy for AWS Load Balancer Controller"
    
    log_info "IAM Policy 생성 완료: $POLICY_ARN"
fi
echo ""

# =================================================
# [3/8] OIDC Provider 설정
# =================================================
log_info "[3/8] OIDC Provider 확인 중..."

OIDC_ID=$(echo "$OIDC_PROVIDER" | cut -d'/' -f5)

if aws iam list-open-id-connect-providers | grep -q "$OIDC_ID"; then
    log_info "OIDC Provider가 이미 존재합니다."
else
    log_warn "OIDC Provider가 없습니다. 생성 중..."
    
    # eksctl로 OIDC Provider 생성
    eksctl utils associate-iam-oidc-provider \
        --region "$REGION" \
        --cluster "$CLUSTER_NAME" \
        --approve
    
    log_info "OIDC Provider 생성 완료"
fi
echo ""

# =================================================
# [4/8] IAM Role 생성
# =================================================
log_info "[4/8] IAM Role 생성 중..."

# Trust Policy 생성
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
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
    }
  ]
}
EOF

# Role 생성
aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --description "IAM role for AWS Load Balancer Controller on $CLUSTER_NAME"

log_info "IAM Role 생성 완료: $ROLE_NAME"
echo ""

# =================================================
# [5/8] IAM Policy를 Role에 연결
# =================================================
log_info "[5/8] IAM Policy를 Role에 연결 중..."

aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN"

log_info "Policy 연결 완료"
echo ""

# =================================================
# [6/8] Kubernetes ServiceAccount 생성
# =================================================
log_info "[6/8] Kubernetes ServiceAccount 생성 중..."

# Role ARN 가져오기
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

# ServiceAccount 생성
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
  labels:
    app.kubernetes.io/name: aws-load-balancer-controller
    app.kubernetes.io/component: controller
EOF

log_info "ServiceAccount 생성 완료"
echo ""

# =================================================
# [7/8] Helm으로 Controller 설치
# =================================================
log_info "[7/8] Helm으로 Controller 설치 중..."

# Helm repo 추가
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

# VPC ID 가져오기
VPC_ID=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

log_info "VPC ID: $VPC_ID"

# 기존 설치 확인
if helm list -n kube-system | grep -q aws-load-balancer-controller; then
    log_warn "기존 설치가 있습니다. 업그레이드합니다..."
    
    helm upgrade aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region="$REGION" \
        --set vpcId="$VPC_ID"
else
    log_info "Controller 설치 중..."
    
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --set region="$REGION" \
        --set vpcId="$VPC_ID"
fi

log_info "Helm 설치 완료"
echo ""

# =================================================
# [8/8] 설치 확인
# =================================================
log_info "[8/8] 설치 확인 중..."
echo "Controller Pod 시작 대기 중..."

# Pod가 Ready 상태가 될 때까지 대기 (최대 2분)
for i in {1..24}; do
    READY=$(kubectl get pods -n kube-system \
        -l app.kubernetes.io/name=aws-load-balancer-controller \
        -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null || echo "false")
    
    if [[ "$READY" == *"true"* ]]; then
        echo ""
        log_info "Controller 준비 완료 ✓"
        break
    fi
    
    echo -n "."
    sleep 5
done
echo ""

# 최종 상태 출력
echo ""
echo "=========================================="
log_info "설치 완료!"
echo "=========================================="
echo ""

kubectl get deployment -n kube-system aws-load-balancer-controller
echo ""
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
echo ""

log_info "다음 단계:"
echo "  1. Ingress 생성 시 자동으로 ALB가 프로비저닝됩니다"
echo "  2. kubectl apply -f ingress/ingress.yaml"
echo "  3. kubectl get ingress -n <namespace>"
echo ""