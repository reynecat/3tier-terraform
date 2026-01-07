#!/bin/bash

###############################################################################
# CloudFront Traffic Switch to Azure
#
# Description: AWS 장애 시 CloudFront를 Azure Application Gateway로 전환
# Usage: ./switch-to-azure.sh
###############################################################################

set -e

CLOUDFRONT_ID="E2OX3Z0XHNDUN"
AZURE_RG="rg-dr-blue"
AZURE_APPGW_PIP="pip-appgw-dr-blue"

echo "========================================="
echo "CloudFront Failover to Azure"
echo "========================================="
echo ""

# Step 1: Azure Application Gateway IP 가져오기
echo "[1/5] Getting Azure Application Gateway IP..."
APPGW_IP=$(az network public-ip show \
  --resource-group "$AZURE_RG" \
  --name "$AZURE_APPGW_PIP" \
  --query ipAddress -o tsv 2>/dev/null)

if [ -z "$APPGW_IP" ]; then
  echo "ERROR: Could not get Azure Application Gateway IP"
  echo "Please ensure Azure infrastructure is deployed:"
  echo "  cd codes/azure/2-emergency"
  echo "  terraform apply"
  exit 1
fi

echo "✓ Azure Application Gateway IP: $APPGW_IP"
echo ""

# Step 2: 현재 CloudFront 설정 백업
echo "[2/5] Backing up current CloudFront configuration..."
BACKUP_FILE="/tmp/cloudfront-config-backup-$(date +%Y%m%d-%H%M%S).json"
aws cloudfront get-distribution-config --id "$CLOUDFRONT_ID" --output json > "$BACKUP_FILE"

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Failed to backup CloudFront configuration"
  exit 1
fi

echo "✓ Backup saved to: $BACKUP_FILE"
echo ""

# Step 3: ETag 추출 및 설정 수정
echo "[3/5] Preparing new CloudFront configuration..."
ETAG=$(cat "$BACKUP_FILE" | jq -r '.ETag')

cat "$BACKUP_FILE" | jq --arg ip "$APPGW_IP" '.DistributionConfig' | jq --arg ip "$APPGW_IP" '
# Azure Origin이 이미 있는지 확인하고 없으면 추가
if (.Origins.Items | map(.Id) | index("azure-appgw")) then
  # 이미 있으면 DomainName만 업데이트
  .Origins.Items |= map(
    if .Id == "azure-appgw" then
      .DomainName = $ip
    else
      .
    end
  )
else
  # 없으면 새로 추가
  .Origins.Items += [{
    "Id": "azure-appgw",
    "DomainName": $ip,
    "OriginPath": "",
    "CustomHeaders": {"Quantity": 0},
    "CustomOriginConfig": {
      "HTTPPort": 80,
      "HTTPSPort": 443,
      "OriginProtocolPolicy": "http-only",
      "OriginSslProtocols": {
        "Quantity": 1,
        "Items": ["TLSv1.2"]
      },
      "OriginReadTimeout": 30,
      "OriginKeepaliveTimeout": 5
    },
    "ConnectionAttempts": 3,
    "ConnectionTimeout": 10,
    "OriginShield": {"Enabled": false},
    "OriginAccessControlId": ""
  }] |
  .Origins.Quantity = (.Origins.Items | length)
end |
# Default Behavior를 Azure로 전환하고 Lambda@Edge 비활성화
.DefaultCacheBehavior.TargetOriginId = "azure-appgw" |
.DefaultCacheBehavior.LambdaFunctionAssociations = {"Quantity": 0, "Items": []} |
.Comment = "Multi-Cloud DR - Switched to Azure (Manual Failover at '"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"')"
' > /tmp/cf-azure-config.json

echo "✓ Configuration prepared"
echo ""

# Step 4: CloudFront 업데이트
echo "[4/5] Updating CloudFront distribution..."
echo "This may take 5-10 minutes..."

aws cloudfront update-distribution \
  --id "$CLOUDFRONT_ID" \
  --distribution-config file:///tmp/cf-azure-config.json \
  --if-match "$ETAG" \
  --output json > /tmp/cf-update-result.json

if [ $? -ne 0 ]; then
  echo "ERROR: Failed to update CloudFront"
  echo "Backup file: $BACKUP_FILE"
  exit 1
fi

echo "✓ CloudFront update initiated"
echo ""

# Step 5: 배포 완료 대기
echo "[5/5] Waiting for CloudFront deployment..."

for i in {1..40}; do
  STATUS=$(aws cloudfront get-distribution --id "$CLOUDFRONT_ID" --query 'Distribution.Status' --output text)

  if [ "$STATUS" = "Deployed" ]; then
    echo ""
    echo "✓ CloudFront deployment complete!"
    break
  fi

  echo -n "."
  sleep 15

  if [ $i -eq 40 ]; then
    echo ""
    echo "WARNING: Deployment is taking longer than expected"
    echo "Check status manually: aws cloudfront get-distribution --id $CLOUDFRONT_ID"
  fi
done

echo ""
echo "========================================="
echo "Failover Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Invalidate CloudFront cache (optional, for immediate effect):"
echo "   aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths '/*'"
echo ""
echo "2. Test the website:"
echo "   curl -I https://blueisthenewblack.store/"
echo ""
echo "3. Monitor Azure resources:"
echo "   kubectl get pods -A --context aks-dr-blue"
echo ""
echo "Backup file location: $BACKUP_FILE"
echo ""
