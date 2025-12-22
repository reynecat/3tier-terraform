# 장애 대응 테스트

# cd ~/3tier-terraform/PlanB/azure/2-emergency

# App Gateway Public IP 확인
# AZURE_IP=$(terraform output -raw appgw_public_ip)
# echo "Azure IP: $AZURE_IP"

# HTTPS 접속 테스트 (Self-signed 경고 무시)
# curl -k -I https://$AZURE_IP

# HTTP도 확인
# curl -I http://$AZURE_IP

# 둘 다 200이면 실행 

cd ~/3tier-terraform/PlanB/aws

ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=$(terraform output -raw eks_cluster_name)" \
            "Name=tag:ingress.k8s.aws/stack,Values=web/web-ingress" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

PRIMARY_HC=$(terraform output -json route53_health_check_ids | jq -r '.primary')
SECONDARY_HC=$(terraform output -json route53_health_check_ids | jq -r '.secondary')

echo "=========================================="
echo "Failover 테스트 (HTTPS 지원 버전)"
echo "=========================================="
echo ""
echo "ALB SG: $ALB_SG"
echo "Primary HC: $PRIMARY_HC"
echo "Secondary HC: $SECONDARY_HC"
echo ""

# 초기 상태
echo "[초기 상태]"
echo "Primary HC: $(aws route53 get-health-check-status --health-check-id $PRIMARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)"
echo "Secondary HC: $(aws route53 get-health-check-status --health-check-id $SECONDARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)"
echo "DNS: $(dig +short blueisthenewblack.store | head -1)"
echo ""
echo "HTTP: $(curl -sI http://blueisthenewblack.store 2>&1 | head -1)"
echo "HTTPS: $(curl -sI https://blueisthenewblack.store 2>&1 | head -1)"
echo ""

read -p "장애 시뮬레이션 시작? (y/n): " start

if [[ "$start" != "y" ]]; then
    exit 0
fi

# 장애 발생
echo ""
echo "[장애 발생] $(date '+%H:%M:%S')"
aws ec2 revoke-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 revoke-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0
echo "HTTP/HTTPS 포트 차단 완료"
echo ""

# 모니터링 (2분)
echo "Failover 대기 중 (2분)..."
for i in {1..4}; do
    sleep 30
    echo ""
    echo "[+${i}분30초] $(date '+%H:%M:%S')"
    PRIMARY_STATUS=$(aws route53 get-health-check-status --health-check-id $PRIMARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)
    DNS_IP=$(dig +short blueisthenewblack.store | head -1)
    
    if [[ "$DNS_IP" == "52.141.46.243" ]]; then
        LOCATION="Azure ✓"
    else
        LOCATION="AWS"
    fi
    
    echo "  Primary HC: $PRIMARY_STATUS"
    echo "  DNS: $DNS_IP ($LOCATION)"
done

echo ""
echo "[Failover 완료 상태]"
echo "DNS: $(dig +short blueisthenewblack.store | head -1)"
echo "HTTP: $(curl -sI http://blueisthenewblack.store 2>&1 | head -1)"
echo "HTTPS: $(curl -k -sI https://blueisthenewblack.store 2>&1 | head -1)"
echo ""

read -p "복구? (y/n): " recover

if [[ "$recover" == "y" ]]; then
    echo ""
    echo "[복구 시작] $(date '+%H:%M:%S')"
    aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress --group-id $ALB_SG --protocol tcp --port 443 --cidr 0.0.0.0/0
    echo "포트 복구 완료"
    echo ""
    
    echo "Failback 대기 중 (3분)..."
    for i in {1..6}; do
        sleep 30
        echo ""
        echo "[+${i}분30초] $(date '+%H:%M:%S')"
        PRIMARY_STATUS=$(aws route53 get-health-check-status --health-check-id $PRIMARY_HC --query 'HealthCheckObservations[0].StatusReport.Status' --output text)
        DNS_IP=$(dig +short blueisthenewblack.store | head -1)
        
        if [[ "$DNS_IP" == "52.141.46.243" ]]; then
            LOCATION="Azure"
        else
            LOCATION="AWS ✓"
        fi
        
        echo "  Primary HC: $PRIMARY_STATUS"
        echo "  DNS: $DNS_IP ($LOCATION)"
    done
    
    echo ""
    echo "[최종 상태]"
    echo "DNS: $(dig +short blueisthenewblack.store | head -1)"
    echo "HTTPS: $(curl -sI https://blueisthenewblack.store 2>&1 | head -1)"
fi

echo ""
echo "테스트 완료!"