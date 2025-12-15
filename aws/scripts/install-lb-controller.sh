#!/bin/bash
set -e

echo "=========================================="
echo "AWS Load Balancer Controller 설치"
echo "=========================================="

# IAM Policy 다운로드
curl -o iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# IAM Policy 생성
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam-policy.json \
    --region ap-northeast-2 2>/dev/null || echo "Policy already exists"

# OIDC Provider 연결
eksctl utils associate-iam-oidc-provider \
  --cluster prod-eks \
  --region ap-northeast-2 \
  --approve

# Service Account 생성 (기존 것 삭제 후 재생성)
echo ""
echo "ServiceAccount 생성 중..."
eksctl delete iamserviceaccount \
  --cluster=prod-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --region=ap-northeast-2 2>/dev/null || true

sleep 5

eksctl create iamserviceaccount \
  --cluster=prod-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --region=ap-northeast-2 \
  --approve

# ServiceAccount 생성 확인 및 재시도
echo ""
echo "ServiceAccount 확인 중..."
sleep 10

if ! kubectl get serviceaccount -n kube-system aws-load-balancer-controller &>/dev/null; then
    echo "WARNING: ServiceAccount가 자동 생성되지 않았습니다. 수동 생성 중..."
    
    # IAM Role ARN 찾기
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-prod-eks-addon-iamserviceaccount-ku')].RoleName" --output text | head -1)
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    
    echo "Using Role ARN: $ROLE_ARN"
    
    # ServiceAccount 수동 생성
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF
fi

# 최종 확인
kubectl get serviceaccount -n kube-system aws-load-balancer-controller
echo "✓ ServiceAccount 준비 완료"

# Helm 설치
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# VPC ID 가져오기
VPC_ID=$(cd .. && terraform output -raw vpc_id)

# Controller 설치
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=prod-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId=$VPC_ID

echo ""
echo "Controller 설치 완료!"
echo "Pod 시작 대기 중 (최대 2분)..."

# Pod 시작 대기
sleep 20
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=aws-load-balancer-controller \
  -n kube-system \
  --timeout=120s || echo "WARNING: Pod 시작 시간 초과. 수동 확인 필요."

echo ""
echo "Pod 상태 확인:"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

rm -f iam-policy.json