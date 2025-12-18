#!/bin/bash
# azure/scripts/deploy-app.sh
# 재해 시: PetClinic 애플리케이션 배포 (90분)

set -e

echo "=========================================="
echo "PetClinic 배포 (Plan B - Emergency)"
echo "시작 시간: $(date)"
echo "=========================================="

# 1. WAS VM 생성
echo "[1/3] WAS VM 생성 (10분)..."
terraform apply \
    -target=azurerm_linux_virtual_machine.was \
    -auto-approve

# 2. Web VM 생성
echo "[2/3] Web VM 생성 (5분)..."
terraform apply \
    -target=azurerm_linux_virtual_machine.web \
    -auto-approve

# 3. Application Gateway 생성
echo "[3/3] Application Gateway 생성 (15분)..."
terraform apply \
    -target=azurerm_application_gateway.main \
    -auto-approve

APP_GATEWAY_IP=$(terraform output -raw app_gateway_public_ip)

echo ""
echo "=========================================="
echo "PetClinic 배포 완료!"
echo "=========================================="
echo ""
echo "URL: http://$APP_GATEWAY_IP"
echo ""
echo "다음 단계:"
echo "  1. 서비스 동작 확인"
echo "  2. Route53 전환"
echo "  3. 고객 공지"
echo ""
