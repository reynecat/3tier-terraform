#!/bin/bash
# nuclear-option.sh
# Route53 완전 리셋 (강력)

cd ~/3tier-terraform/PlanB/aws

echo "=========================================="
echo "Route53 완전 리셋 (Nuclear Option)"
echo "=========================================="
echo ""

# 1. Terraform state 백업
cp terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d-%H%M%S)
echo "State 백업 완료"

# 2. Route53 리소스 state 제거
terraform state rm aws_route53_record.primary 2>/dev/null || true
terraform state rm aws_route53_record.secondary 2>/dev/null || true
terraform state rm aws_route53_health_check.primary 2>/dev/null || true
terraform state rm aws_route53_health_check.secondary 2>/dev/null || true

echo "Terraform state에서 Route53 리소스 제거 완료"
echo ""

# 3. terraform.tfvars 정리
sed -i '/azure_appgw_public_ip/d' terraform.tfvars

echo "Azure Secondary 설정 제거 완료"
echo ""

# 4. Import 없이 새로 생성
echo "Route53 레코드 재생성 중..."
terraform apply -auto-approve

echo ""
echo "=========================================="
echo "완료!"
echo "=========================================="
echo ""

# 5. 60초 대기
echo "DNS 전파 대기 (60초)..."
sleep 60

# 6. 확인
echo "DNS 확인:"
dig +short blueisthenewblack.store

echo ""
echo "HTTP 테스트:"
curl -I http://blueisthenewblack.store | head -3

echo ""
echo "HTTPS 테스트:"
curl -I https://blueisthenewblack.store | head -3