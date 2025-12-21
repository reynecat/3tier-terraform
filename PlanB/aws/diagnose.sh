#!/bin/bash
# diagnose-http-https.sh

DOMAIN="blueisthenewblack.store"

echo "=========================================="
echo "HTTP vs HTTPS Routing Diagnosis"
echo "=========================================="
echo ""

# 1. DNS 조회
echo "=== DNS Resolution ==="
DNS_IPS=$(dig +short $DOMAIN)
echo "$DNS_IPS"
echo ""

# 2. HTTP 요청 (리다이렉트 따라가지 않음)
echo "=== HTTP Request (포트 80) ==="
HTTP_RESPONSE=$(curl -sI http://$DOMAIN 2>&1)
echo "$HTTP_RESPONSE" | head -10
echo ""

# 첫 번째 Location 헤더 확인
HTTP_LOCATION=$(echo "$HTTP_RESPONSE" | grep -i "^Location:" | head -1)
if [ -n "$HTTP_LOCATION" ]; then
    echo "HTTP 리다이렉트: $HTTP_LOCATION"
    echo ""
fi

# 3. HTTPS 요청
echo "=== HTTPS Request (포트 443) ==="
HTTPS_RESPONSE=$(curl -sI https://$DOMAIN 2>&1)
echo "$HTTPS_RESPONSE" | head -10
echo ""

# 4. 각 IP로 직접 접속
echo "=== Direct IP Test ==="
for IP in $DNS_IPS; do
    echo "IP: $IP"
    echo "  HTTP:  $(curl -sI http://$IP --connect-timeout 3 2>&1 | head -1)"
    echo "  HTTPS: $(curl -sIk https://$IP --connect-timeout 3 2>&1 | head -1)"
    echo ""
done

# 5. ALB DNS 확인
echo "=== AWS ALB ==="
cd ~/3tier-terraform/PlanB/aws
ALB_DNS=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$ALB_DNS" ]; then
    echo "ALB DNS: $ALB_DNS"
    ALB_IP=$(dig +short $ALB_DNS | head -1)
    echo "ALB IP: $ALB_IP"
else
    echo "ALB DNS를 찾을 수 없습니다"
fi
echo ""

# 6. Azure App Gateway 확인
echo "=== Azure App Gateway ==="
AZURE_IP=$(terraform output -raw azure_appgw_public_ip 2>/dev/null || echo "Not configured")
echo "Azure IP: $AZURE_IP"
echo ""

echo "=========================================="