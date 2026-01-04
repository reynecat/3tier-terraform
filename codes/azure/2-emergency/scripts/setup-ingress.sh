#!/bin/bash

set -e

echo "========================================="
echo "Azure AKS Ingress Setup Script"
echo "========================================="
echo ""

# 변수 설정
RESOURCE_GROUP="rg-dr-blue"
AKS_CLUSTER="aks-dr-blue"
APPGW_NAME="appgw-blue"
K8S_MANIFESTS_DIR="/home/ubuntu/3tier-terraform/codes/azure/2-emergency/k8s-manifests"

echo "► Step 1: AKS 클러스터 컨텍스트 확인"
kubectl config use-context aks-dr-blue
echo ""

echo "► Step 2: Application Gateway ID 가져오기"
APPGW_ID=$(az network application-gateway show \
  --resource-group $RESOURCE_GROUP \
  --name $APPGW_NAME \
  --query id -o tsv)
echo "Application Gateway ID: $APPGW_ID"
echo ""

echo "► Step 3: AGIC (Application Gateway Ingress Controller) 애드온 활성화"
echo "이미 활성화되어 있으면 스킵됩니다..."
az aks enable-addons \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_CLUSTER \
  --addons ingress-appgw \
  --appgw-id $APPGW_ID 2>&1 | grep -v "AAD role propagation" || true
echo ""

echo "► Step 4: AGIC Pod 상태 확인"
echo "AGIC Pod가 Running 상태가 될 때까지 대기 중..."
for i in {1..30}; do
  AGIC_STATUS=$(kubectl get pods -n kube-system | grep ingress-appgw | awk '{print $3}' || echo "NotFound")
  if [ "$AGIC_STATUS" = "Running" ]; then
    echo "✓ AGIC Pod가 Running 상태입니다."
    kubectl get pods -n kube-system | grep ingress-appgw
    break
  fi
  echo "  대기 중... ($i/30) - 현재 상태: $AGIC_STATUS"
  sleep 5
done
echo ""

echo "► Step 5: IngressClass 확인"
kubectl get ingressclass
echo ""

echo "► Step 6: Ingress 리소스 적용"
kubectl apply -f ${K8S_MANIFESTS_DIR}/web/ingress.yaml
echo ""

echo "► Step 7: Ingress 상태 확인 (ADDRESS 할당 대기)"
echo "Application Gateway IP가 할당될 때까지 대기 중..."
for i in {1..20}; do
  INGRESS_ADDRESS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$INGRESS_ADDRESS" ]; then
    echo "✓ Ingress에 IP가 할당되었습니다: $INGRESS_ADDRESS"
    break
  fi
  echo "  대기 중... ($i/20)"
  sleep 5
done
echo ""

echo "► Step 8: 최종 상태 확인"
kubectl get ingress -n web
echo ""

echo "► Step 9: 접속 테스트"
APPGW_IP=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -n "$APPGW_IP" ]; then
  echo "Application Gateway IP: $APPGW_IP"
  echo ""
  echo "HTTP 응답 확인:"
  curl -I http://$APPGW_IP/ 2>&1 | head -10
  echo ""
  echo "========================================="
  echo "✓ Ingress 설정 완료!"
  echo "접속 URL: http://$APPGW_IP/"
  echo "========================================="
else
  echo "⚠ Warning: Ingress IP가 아직 할당되지 않았습니다."
  echo "다음 명령으로 확인하세요:"
  echo "  kubectl get ingress -n web"
fi
