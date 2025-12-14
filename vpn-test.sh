#!/bin/bash
# vpn-test.sh

echo "=========================================="
echo "VPN 연결 상태 테스트"
echo "=========================================="
echo ""

# 1. AWS VPN 상태
echo "[1/5] AWS VPN Tunnel 상태..."
aws ec2 describe-vpn-connections \
  --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=vpn-to-azure-prod" \
  --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status]' \
  --output table

echo ""

# 2. Azure VPN 상태
echo "[2/5] Azure VPN 연결 상태..."
az network vpn-connection show \
  --name vpn-to-aws-prod \
  --resource-group rg-dr-prod \
  --query 'connectionStatus' \
  --output tsv

echo ""

# 3. AWS Route Table
echo "[3/5] AWS에서 Azure CIDR 라우트 확인..."
aws ec2 describe-route-tables \
  --region ap-northeast-2 \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`172.16.0.0/16`]' \
  --output table

echo ""

# 4. Azure Effective Routes
echo "[4/5] Azure에서 AWS CIDR 라우트 확인..."
az network vnet-gateway list-learned-routes \
  --name vgw-prod \
  --resource-group rg-dr-prod \
  --query 'value[?network==`10.0.0.0/16`]' \
  --output table

echo ""
