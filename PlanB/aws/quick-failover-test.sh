#!/bin/bash
# quick-failover-test.sh
# 빠른 Failover 테스트 스크립트

set -e

cd ~/3tier-terraform/PlanB/aws

# 변수 설정
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
DOMAIN="blueisthenewblack.store"
PRIMARY_HC=$(terraform output -json route53_health_check_ids | jq -r '.primary')
ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${CLUSTER_NAME}" \
            "Name=tag:ingress.k8s.aws/stack,Values=web/web-ingress" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

echo "=========================================="
echo "Failover Test Script"
echo "=========================================="
echo "Domain: $DOMAIN"
echo "Primary HC: $PRIMARY_HC"
echo "ALB SG: $ALB_SG"
echo ""

# 함수: Health Check 상태 확인
check_health() {
    aws route53 get-health-check-status \
        --health-check-id $PRIMARY_HC \
        --query 'HealthCheckObservations[0].StatusReport.Status' \
        --output text
}

# 함수: DNS 확인
check_dns() {
    dig +short $DOMAIN | head -1
}

# 초기 상태
echo "=== 초기 상태 ==="
echo "Health Check: $(check_health)"
echo "DNS 응답: $(check_dns)"
echo ""

# 장애 발생
echo "=== 장애 발생 ==="
aws ec2 revoke-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "이미 제거됨"

echo "시작 시간: $(date '+%H:%M:%S')"
echo ""

# 90초 대기 (Health Check 실패 감지)
echo "Health Check 실패 감지 중..."
for i in {1..9}; do
    echo -n "."
    sleep 10
done
echo ""

# Failover 확인
echo ""
echo "=== Failover 상태 (90초 후) ==="
echo "Health Check: $(check_health)"
echo "DNS 응답: $(check_dns)"
echo ""

# 사용자 입력 대기
read -p "복구하시겠습니까? (y/n): " answer

if [[ $answer != "y" ]]; then
    echo "테스트 종료. 수동 복구 필요:"
    echo "aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0"
    exit 0
fi

# 복구
echo ""
echo "=== 복구 시작 ==="
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "이미 추가됨"

echo "복구 시간: $(date '+%H:%M:%S')"
echo ""

# 60초 대기 (Health Check 성공 감지)
echo "Health Check 복구 감지 중..."
for i in {1..6}; do
    echo -n "."
    sleep 10
done
echo ""

# 최종 상태
echo ""
echo "=== 최종 상태 (60초 후) ==="
echo "Health Check: $(check_health)"
echo "DNS 응답: $(check_dns)"
echo ""
echo "=========================================="
echo "테스트 완료!"
echo "=========================================="