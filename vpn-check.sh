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

## 일반적인 실수

### 실수 1: IP 주소 방향 혼동
```
잘못된 설정:
AWS terraform.tfvars:
  azure_vpn_gateway_ip = "3.36.138.62"  # ❌ 이건 AWS 자신의 IP

올바른 설정:
AWS terraform.tfvars:
  azure_vpn_gateway_ip = "20.196.xxx.xxx"  # ✅ Azure Gateway IP
```

### 실수 2: Tunnel 2 사용
```
AWS는 2개 터널을 제공하지만 Azure Local Network Gateway는 1개만 지정:

aws_vpn_gateway_ip = "3.36.138.62"  # ✅ Tunnel 1
# Tunnel 2는 사용 안 함 (Active-Standby)
```

### 실수 3: Pre-Shared Key 대소문자
```
Pre-Shared Key는 대소문자 구분:

AWS: "MySecureKey123"
Azure: "mysecurekey123"  # ❌ 연결 안 됨

둘 다 정확히 같아야 함