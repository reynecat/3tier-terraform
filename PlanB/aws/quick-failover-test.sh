#!/bin/bash
# complete-failover-test.sh
# AWS → Azure 완전 Failover 테스트

cd ~/3tier-terraform/PlanB/aws

echo "=========================================="
echo "완전 Failover 테스트"
echo "AWS Primary → Azure Secondary"
echo "=========================================="
echo ""

# 변수 설정
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
DOMAIN=$(terraform output -raw domain_name)
PRIMARY_HC=$(terraform output -json route53_health_check_ids | jq -r '.primary')
SECONDARY_HC=$(terraform output -json route53_health_check_ids | jq -r '.secondary')

ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=${CLUSTER_NAME}" \
            "Name=tag:ingress.k8s.aws/stack,Values=web/web-ingress" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

echo "Domain: $DOMAIN"
echo "Primary HC: $PRIMARY_HC"
echo "Secondary HC: $SECONDARY_HC"
echo "ALB SG: $ALB_SG"
echo ""

# 초기 상태
echo "=========================================="
echo "초기 상태 (정상 운영)"
echo "=========================================="
echo ""

echo "Health Check:"
echo "  Primary:   $(aws route53 get-health-check-status --health-check-id $PRIMARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)"
echo "  Secondary: $(aws route53 get-health-check-status --health-check-id $SECONDARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)"
echo ""

echo "DNS:"
INITIAL_DNS=$(dig +short $DOMAIN | head -1)
echo "  $INITIAL_DNS"
echo ""

echo "서비스 접속:"
echo "  HTTPS: $(curl -sI https://$DOMAIN | head -1)"
echo ""

read -p "장애 시뮬레이션을 시작하시겠습니까? (y/n): " start_test

if [[ "$start_test" != "y" ]]; then
    echo "테스트 취소"
    exit 0
fi

# 장애 발생
echo ""
echo "=========================================="
echo "Phase 1: AWS 장애 발생"
echo "=========================================="
echo ""

echo "HTTPS 포트 차단..."
aws ec2 revoke-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "  이미 차단됨"

START_TIME=$(date '+%H:%M:%S')
echo "장애 시작: $START_TIME"
echo ""

# Failover 대기
echo "Failover 진행 중..."
echo "  - Primary Health Check 실패 감지: 90초"
echo "  - DNS Failover: 60초"
echo "  - 예상 총 시간: 2-3분"
echo ""

for i in {150..1}; do
    if [ $((i % 30)) -eq 0 ]; then
        CURRENT_STATUS=$(aws route53 get-health-check-status \
            --health-check-id $PRIMARY_HC \
            --query 'HealthCheckObservations[0].StatusReport.Status' \
            --output text)
        CURRENT_DNS=$(dig +short $DOMAIN | head -1)
        echo "  [$(date '+%H:%M:%S')] Primary: $CURRENT_STATUS | DNS: $CURRENT_DNS"
    fi
    sleep 1
done

echo ""

# Failover 후 상태
echo "=========================================="
echo "Phase 2: Failover 완료 상태"
echo "=========================================="
echo ""

echo "Health Check:"
PRIMARY_STATUS=$(aws route53 get-health-check-status \
    --health-check-id $PRIMARY_HC \
    --query 'HealthCheckObservations[0].StatusReport.Status' \
    --output text)
SECONDARY_STATUS=$(aws route53 get-health-check-status \
    --health-check-id $SECONDARY_HC \
    --query 'HealthCheckObservations[0].StatusReport.Status' \
    --output text)

echo "  Primary:   $PRIMARY_STATUS"
echo "  Secondary: $SECONDARY_STATUS"
echo ""

echo "DNS:"
FAILOVER_DNS=$(dig +short $DOMAIN | head -1)
echo "  $FAILOVER_DNS"

if [[ "$FAILOVER_DNS" != "$INITIAL_DNS" ]]; then
    echo "  ✓ Failover 성공! (AWS → Azure)"
else
    echo "  ⚠ DNS가 아직 변경되지 않았습니다"
fi
echo ""

echo "서비스 접속 (Azure Secondary는 HTTP만 제공):"
echo "  HTTP:  $(curl -sI http://$DOMAIN | head -1)"
echo "  HTTPS: $(timeout 5 curl -sI https://$DOMAIN 2>&1 | head -1 || echo 'Timeout (예상됨 - Secondary는 HTTP만 제공)')"
echo ""

echo "브라우저 테스트:"
echo "  http://$DOMAIN (점검 페이지 또는 PetClinic)"
echo ""

read -p "복구하시겠습니까? (y/n): " do_recovery

if [[ "$do_recovery" != "y" ]]; then
    echo ""
    echo "테스트 종료. 수동 복구 필요:"
    echo "  aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0"
    exit 0
fi

# 복구
echo ""
echo "=========================================="
echo "Phase 3: AWS 복구 (Failback)"
echo "=========================================="
echo ""

echo "HTTPS 포트 복구..."
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0 2>/dev/null || echo "  이미 열려있음"

RECOVERY_TIME=$(date '+%H:%M:%S')
echo "복구 시작: $RECOVERY_TIME"
echo ""

echo "Failback 진행 중..."
echo "  - Primary Health Check 복구: 90초"
echo "  - DNS Failback: 60초"
echo "  - 예상 총 시간: 2-3분"
echo ""

for i in {150..1}; do
    if [ $((i % 30)) -eq 0 ]; then
        CURRENT_STATUS=$(aws route53 get-health-check-status \
            --health-check-id $PRIMARY_HC \
            --query 'HealthCheckObservations[0].StatusReport.Status' \
            --output text)
        CURRENT_DNS=$(dig +short $DOMAIN | head -1)
        echo "  [$(date '+%H:%M:%S')] Primary: $CURRENT_STATUS | DNS: $CURRENT_DNS"
    fi
    sleep 1
done

echo ""

# 최종 상태
echo "=========================================="
echo "Phase 4: Failback 완료 상태"
echo "=========================================="
echo ""

echo "Health Check:"
echo "  Primary:   $(aws route53 get-health-check-status --health-check-id $PRIMARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)"
echo "  Secondary: $(aws route53 get-health-check-status --health-check-id $SECONDARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)"
echo ""

echo "DNS:"
FINAL_DNS=$(dig +short $DOMAIN | head -1)
echo "  $FINAL_DNS"

if [[ "$FINAL_DNS" == "$INITIAL_DNS" ]]; then
    echo "  ✓ Failback 성공! (Azure → AWS)"
else
    echo "  ⚠ DNS가 아직 원래대로 돌아오지 않았습니다"
fi
echo ""

echo "서비스 접속:"
echo "  HTTPS: $(curl -sI https://$DOMAIN | head -1)"
echo ""

echo "=========================================="
echo "테스트 완료!"
echo "=========================================="
echo ""

echo "타임라인 요약:"
echo "  장애 시작: $START_TIME"
echo "  복구 시작: $RECOVERY_TIME"
echo "  종료 시각: $(date '+%H:%M:%S')"
echo ""

echo "Failover 결과:"
echo "  초기 DNS: $INITIAL_DNS (AWS)"
echo "  장애 시 DNS: $FAILOVER_DNS (Azure)"
echo "  복구 후 DNS: $FINAL_DNS (AWS)"
echo ""