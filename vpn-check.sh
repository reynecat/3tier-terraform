#!/bin/bash
# quick-vpn-check.sh

echo "=== VPN 설정 확인 ==="
echo ""

echo "[1] Azure VPN Gateway Public IP:"
az network public-ip show \
  --name pip-vpn-prod \
  --resource-group rg-dr-prod \
  --query ipAddress \
  --output tsv

echo ""
echo "[2] AWS VPN Tunnel IPs:"
cd aws 2>/dev/null
terraform output vpn_connection_tunnel1_address 2>/dev/null || echo "terraform output 실행 실패"
terraform output vpn_connection_tunnel2_address 2>/dev/null || echo "terraform output 실행 실패"

echo ""
echo "[3] AWS terraform.tfvars의 azure_vpn_gateway_ip:"
grep azure_vpn_gateway_ip terraform.tfvars 2>/dev/null || echo "파일 없음"

echo ""
echo "[4] Azure terraform.tfvars의 aws_vpn_gateway_ip:"
cd ../azure 2>/dev/null
grep aws_vpn_gateway_ip terraform.tfvars 2>/dev/null || echo "파일 없음"

echo ""
echo "[5] Pre-Shared Key 일치 확인:"
echo "AWS:"
cd ../aws 2>/dev/null
grep vpn_shared_key terraform.tfvars 2>/dev/null || echo "파일 없음"
echo "Azure:"
cd ../azure 2>/dev/null
grep vpn_shared_key terraform.tfvars 2>/dev/null || echo "파일 없음"

echo ""
echo "=== 확인 완료 ==="
echo ""
echo "다음 사항 확인:"
echo "1. [1]의 IP가 AWS terraform.tfvars의 azure_vpn_gateway_ip와 일치"
echo "2. [2]의 Tunnel1 IP가 Azure terraform.tfvars의 aws_vpn_gateway_ip와 일치"
echo "3. [5]의 두 Pre-Shared Key가 정확히 일치"
```

