#!/bin/bash
set -e

echo "=========================================="
echo "AWS Load Balancer Controller 설치"
echo "=========================================="

CLUSTER_NAME="prod-eks"
REGION="ap-northeast-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Account ID: $ACCOUNT_ID"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo ""

# 0. 기존 설치 확인
echo "[0/7] 기존 설치 확인..."
if kubectl get deployment -n kube-system aws-load-balancer-controller 2>/dev/null; then
    echo "이미 설치되어 있습니다."
    echo "현재 상태:"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
    
    echo ""
    echo "재설치가 필요하면:"
    echo "helm uninstall aws-load-balancer-controller -n kube-system"
    echo "kubectl delete serviceaccount aws-load-balancer-controller -n kube-system"
    exit 0
fi

# 1. IAM OIDC Provider 확인
echo "[1/7] IAM OIDC Provider 확인..."
OIDC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
echo "OIDC ID: $OIDC_ID"

if ! aws iam list-open-id-connect-providers | grep -q $OIDC_ID; then
    echo "OIDC Provider 생성 중..."
    eksctl utils associate-iam-oidc-provider --cluster=$CLUSTER_NAME --region=$REGION --approve
else
    echo "OIDC Provider 존재 ✓"
fi

# 2. IAM Policy 다운로드
echo "[2/7] IAM Policy 다운로드..."
curl -sS -o /tmp/iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

# 3. IAM Policy 생성
echo "[3/7] IAM Policy 생성..."
if aws iam get-policy --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy 2>/dev/null; then
    echo "Policy 존재 ✓"
else
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file:///tmp/iam_policy.json
    echo "Policy 생성 완료 ✓"
fi

# 4. 기존 ServiceAccount 정리
echo "[4/7] ServiceAccount 정리..."
kubectl delete serviceaccount aws-load-balancer-controller -n kube-system 2>/dev/null || true
sleep 2

# 5. ServiceAccount 생성
echo "[5/7] ServiceAccount 생성..."
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --region=$REGION \
  --approve

# 6. Helm으로 Controller 설치
echo "[6/7] Helm으로 Controller 설치..."

helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "VPC ID: $VPC_ID"

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID

# 7. 설치 확인
echo "[7/7] 설치 확인..."
echo "Controller Pod 시작 대기 중..."

for i in {1..24}; do
    READY=$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null || echo "false")
    if [[ "$READY" == *"true"* ]]; then
        echo ""
        echo "Controller 준비 완료 ✓"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

echo ""
echo "=========================================="
echo "설치 완료!"
echo "=========================================="