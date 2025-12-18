#!/bin/bash
# azure/scripts/deploy-maintenance.sh
# 재해 시: 점검 페이지 신속 배포 (15분)

set -e

echo "=========================================="
echo "점검 페이지 배포 (Plan B - Emergency)"
echo "시작 시간: $(date)"
echo "=========================================="

# Azure 로그인 확인
if ! az account show > /dev/null 2>&1; then
    echo "Azure 로그인 필요"
    az login
fi

# Terraform 배포
terraform apply \
    -target=azurerm_public_ip.maintenance \
    -target=azurerm_network_interface.maintenance \
    -target=azurerm_linux_virtual_machine.maintenance \
    -auto-approve

PUBLIC_IP=$(terraform output -raw maintenance_public_ip)

echo ""
echo "=========================================="
echo "점검 페이지 배포 완료!"
echo "=========================================="
echo ""
echo "URL: http://$PUBLIC_IP"
echo ""
echo "다음 단계:"
echo "  1. 브라우저에서 점검 페이지 확인"
echo "  2. Route53 Failover (필요시)"
echo "  3. DB 복구: ./restore-db.sh"
echo ""
