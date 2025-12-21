#!/bin/bash
# PlanB/azure/3-failover/update-appgw.sh
# Application Gateway를 Blob Storage에서 AKS로 전환

set -e

echo "=========================================="
echo "Application Gateway 업데이트"
echo "Blob Storage → AKS 전환"
echo "=========================================="

cd ..
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-dr-blue")
APPGW_NAME="appgw-blue"

cd scripts

echo ""
echo "[1/6] kubectl 설정..."
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $(cd .. && terraform output -raw aks_cluster_name) \
  --overwrite-existing

echo ""
echo "[2/6] PetClinic Service IP 확인..."
PETCLINIC_IP=$(kubectl get svc petclinic -n petclinic -o jsonpath='{.spec.clusterIP}')

if [ -z "$PETCLINIC_IP" ]; then
    echo "ERROR: PetClinic Service를 찾을 수 없습니다."
    echo "먼저 ./deploy-petclinic.sh를 실행하세요."
    exit 1
fi

echo "PetClinic Service IP: $PETCLINIC_IP"

echo ""
echo "[3/6] Application Gateway Backend Pool 업데이트..."
az network application-gateway address-pool update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name blob-backend-pool \
    --servers $PETCLINIC_IP

echo ""
echo "[4/6] Health Probe 업데이트 (Http로 변경)..."
az network application-gateway probe update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name health-probe \
    --protocol Http \
    --path "/" \
    --host $PETCLINIC_IP \
    --interval 30 \
    --timeout 20 \
    --threshold 3

echo ""
echo "[5/6] HTTP Settings 업데이트..."
az network application-gateway http-settings update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name blob-http-settings \
    --port 8080 \
    --protocol Http \
    --host-name-from-backend-pool false \
    --probe health-probe

echo ""
echo "[6/6] 설정 적용 대기..."
sleep 10

echo ""
echo "=========================================="
echo "Application Gateway 업데이트 완료!"
echo "=========================================="
echo ""
APPGW_IP=$(az network public-ip show \
    --resource-group $RESOURCE_GROUP \
    --name pip-appgw-blue \
    --query ipAddress -o tsv)

echo "PetClinic URL: http://$APPGW_IP"
echo ""
echo "확인:"
echo "  curl http://$APPGW_IP"
echo ""
echo "Route53 Secondary Health Check가 이 IP를 모니터링합니다."
echo "AWS Primary가 실패하면 자동으로 Azure로 Failover됩니다."
echo ""