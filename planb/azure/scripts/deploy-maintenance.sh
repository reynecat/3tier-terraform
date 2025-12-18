#!/bin/bash
# azure/scripts/deploy-maintenance.sh
# 긴급 점검 페이지 배포 (15분 목표)

set -e

LOG_FILE="/var/log/emergency-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=========================================="
echo "긴급 점검 페이지 배포"
echo "시작 시간: $(date)"
echo "=========================================="

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 변수
RESOURCE_GROUP="rg-dr-prod"
LOCATION="koreacentral"
VNET_NAME="vnet-dr-prod"
STORAGE_ACCOUNT=$(az storage account list -g $RESOURCE_GROUP --query "[0].name" -o tsv)

echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Storage Account: $STORAGE_ACCOUNT"
echo ""

# =================================================
# Phase 1: 최소 리소스 생성 (5분)
# =================================================

echo -e "${YELLOW}[Phase 1/4] 최소 리소스 생성 중...${NC}"

# 1. Public IP 생성
echo "[1.1] Public IP 생성..."
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name pip-maintenance-$(date +%s) \
    --allocation-method Static \
    --sku Standard \
    --location $LOCATION

PUBLIC_IP=$(az network public-ip show \
    --resource-group $RESOURCE_GROUP \
    --name pip-maintenance-* \
    --query ipAddress \
    --output tsv)

echo "Public IP: $PUBLIC_IP"

# 2. Network Security Group 생성
echo "[1.2] NSG 생성..."
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-maintenance \
    --location $LOCATION

# HTTP 허용
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-maintenance \
    --name Allow-HTTP \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 80

# 3. Network Interface 생성
echo "[1.3] NIC 생성..."
SUBNET_ID=$(az network vnet subnet show \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --name subnet-web \
    --query id \
    --output tsv)

az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name nic-maintenance \
    --vnet-name $VNET_NAME \
    --subnet subnet-web \
    --public-ip-address pip-maintenance-* \
    --network-security-group nsg-maintenance \
    --location $LOCATION

# =================================================
# Phase 2: VM 생성 및 초기화 (5분)
# =================================================

echo -e "${YELLOW}[Phase 2/4] VM 생성 및 초기화...${NC}"

# VM 생성
echo "[2.1] VM 생성..."
az vm create \
    --resource-group $RESOURCE_GROUP \
    --name vm-maintenance \
    --location $LOCATION \
    --nics nic-maintenance \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --admin-username azureuser \
    --generate-ssh-keys \
    --custom-data @maintenance-cloud-init.yaml

echo "VM 부팅 대기 중 (60초)..."
sleep 60

# =================================================
# Phase 3: Nginx 및 점검 페이지 배포 (3분)
# =================================================

echo -e "${YELLOW}[Phase 3/4] 점검 페이지 배포...${NC}"

# Cloud-init이 완료될 때까지 대기
for i in {1..30}; do
    if az vm run-command invoke \
        --resource-group $RESOURCE_GROUP \
        --name vm-maintenance \
        --command-id RunShellScript \
        --scripts "systemctl is-active nginx" \
        --query 'value[0].message' -o tsv | grep -q "active"; then
        echo "Nginx 시작 확인 ✓"
        break
    fi
    echo "Nginx 시작 대기 중... ($i/30)"
    sleep 10
done

# =================================================
# Phase 4: Route53 업데이트 (2분)
# =================================================

echo -e "${YELLOW}[Phase 4/4] Route53 Failover 전환...${NC}"

# AWS 자격증명 확인
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}AWS 자격증명 필요${NC}"
    echo "aws configure를 먼저 실행하세요"
    exit 1
fi

# Route53 Health Check 업데이트
echo "[4.1] Route53 Health Check 업데이트..."

# Azure IP를 Secondary로 추가
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='petclinic.example.com.'].Id" \
    --output text | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo -e "${YELLOW}Route53 Hosted Zone 없음 (도메인 미설정)${NC}"
else
    # Failover 레코드 생성
    cat > /tmp/route53-change.json <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "petclinic.example.com",
      "Type": "A",
      "SetIdentifier": "Azure-DR",
      "Failover": "SECONDARY",
      "TTL": 60,
      "ResourceRecords": [{
        "Value": "$PUBLIC_IP"
      }]
    }
  }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id $HOSTED_ZONE_ID \
        --change-batch file:///tmp/route53-change.json

    rm -f /tmp/route53-change.json
    
    echo "Route53 Failover 설정 완료 ✓"
fi

# =================================================
# 완료 및 확인
# =================================================

echo ""
echo -e "${GREEN}=========================================="
echo "긴급 점검 페이지 배포 완료!"
echo "종료 시간: $(date)"
echo "==========================================${NC}"
echo ""
echo "점검 페이지 URL:"
echo "  http://$PUBLIC_IP"
echo ""
echo "접속 테스트:"
curl -s http://$PUBLIC_IP | head -n 20
echo ""
echo "다음 단계:"
echo "  1. 브라우저에서 점검 페이지 확인"
echo "  2. 데이터베이스 복구: ./restore-database.sh"
echo "  3. PetClinic 배포: ./deploy-petclinic.sh"
echo ""
echo "로그 파일: $LOG_FILE"
