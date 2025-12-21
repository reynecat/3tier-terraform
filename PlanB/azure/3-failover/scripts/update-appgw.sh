#!/bin/bash
# PlanB/azure/3-failover/scripts/update-appgw.sh
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
echo "[1/7] kubectl 설정..."
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $(cd .. && terraform output -raw aks_cluster_name) \
  --overwrite-existing

echo ""
echo "[2/7] PetClinic Service IP 확인..."
PETCLINIC_IP=$(kubectl get svc petclinic -n petclinic -o jsonpath='{.spec.clusterIP}')

if [ -z "$PETCLINIC_IP" ]; then
    echo "ERROR: PetClinic Service를 찾을 수 없습니다."
    echo "먼저 ./deploy-petclinic.sh를 실행하세요."
    exit 1
fi

echo "PetClinic Service IP: $PETCLINIC_IP"

echo ""
echo "[3/7] HTTP Settings에서 Probe 연결 해제..."
az network application-gateway http-settings update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name blob-http-settings \
    --remove probe

echo ""
echo "[4/7] HTTP Settings를 Http로 변경..."
az network application-gateway http-settings update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name blob-http-settings \
    --port 8080 \
    --protocol Http \
    --host-name-from-backend-pool false

echo ""
echo "[5/7] Health Probe를 Http로 변경..."
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
echo "[6/7] HTTP Settings에 Probe 다시 연결..."
az network application-gateway http-settings update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name blob-http-settings \
    --probe health-probe

echo ""
echo "[7/7] Backend Pool을 PetClinic으로 변경..."
az network application-gateway address-pool update \
    --resource-group $RESOURCE_GROUP \
    --gateway-name $APPGW_NAME \
    --name blob-backend-pool \
    --servers $PETCLINIC_IP

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