#!/bin/bash
# azure/scripts/deploy-petclinic.sh
# PetClinic 애플리케이션 배포 (점검 페이지 → 실제 서비스 전환)

set -e

LOG_FILE="/var/log/petclinic-deploy-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=========================================="
echo "PetClinic 배포 시작"
echo "시작 시간: $(date)"
echo "=========================================="

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 변수
RESOURCE_GROUP="rg-dr-prod"
LOCATION="koreacentral"
VNET_NAME="vnet-dr-prod"

# MySQL 접속 정보 로드
if [ ! -f /tmp/mysql-connection-info.txt ]; then
    echo -e "${RED}MySQL 접속 정보 없음${NC}"
    echo "먼저 ./restore-database.sh를 실행하세요"
    exit 1
fi

source /tmp/mysql-connection-info.txt

echo "MySQL Host: $MYSQL_HOST"
echo "Database: $DB_NAME"
echo ""

# =================================================
# Phase 1: WAS VM 생성 (10분)
# =================================================

echo -e "${YELLOW}[Phase 1/4] WAS VM 생성 및 초기화...${NC}"

# Public IP
echo "[1.1] Public IP 생성..."
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name pip-was \
    --allocation-method Static \
    --sku Standard \
    --location $LOCATION

# NSG
echo "[1.2] NSG 생성..."
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-was \
    --location $LOCATION

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-was \
    --name Allow-8080 \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 8080

# NIC
echo "[1.3] NIC 생성..."
az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name nic-was \
    --vnet-name $VNET_NAME \
    --subnet subnet-was \
    --public-ip-address pip-was \
    --network-security-group nsg-was \
    --location $LOCATION

# WAS VM 생성
echo "[1.4] WAS VM 생성..."

# Cloud-init 스크립트 생성
cat > /tmp/was-cloud-init.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true

packages:
  - openjdk-21-jdk
  - curl
  - wget

write_files:
  - path: /opt/petclinic/application.properties
    permissions: '0644'
    content: |
      spring.datasource.url=jdbc:mysql://$MYSQL_HOST:3306/$DB_NAME?useSSL=true&serverTimezone=Asia/Seoul
      spring.datasource.username=$DB_USER
      spring.datasource.password=$DB_PASSWORD
      spring.jpa.database=MYSQL
      spring.jpa.hibernate.ddl-auto=none
      server.port=8080

runcmd:
  - mkdir -p /opt/petclinic
  - cd /opt/petclinic
  - wget -O petclinic.jar https://github.com/spring-projects/spring-petclinic/releases/download/v3.1.0/spring-petclinic-3.1.0.jar
  - nohup java -jar petclinic.jar --spring.config.location=file:/opt/petclinic/application.properties > /var/log/petclinic.log 2>&1 &
  - echo "PetClinic started at \$(date)" >> /var/log/cloud-init-output.log
EOF

az vm create \
    --resource-group $RESOURCE_GROUP \
    --name vm-was \
    --location $LOCATION \
    --nics nic-was \
    --image Ubuntu2204 \
    --size Standard_B2s \
    --admin-username azureuser \
    --generate-ssh-keys \
    --custom-data @/tmp/was-cloud-init.yaml

WAS_IP=$(az network public-ip show \
    --resource-group $RESOURCE_GROUP \
    --name pip-was \
    --query ipAddress \
    --output tsv)

echo "WAS VM 생성 완료: $WAS_IP"

# =================================================
# Phase 2: Web VM 생성 (5분)
# =================================================

echo -e "${YELLOW}[Phase 2/4] Web VM 생성...${NC}"

# Public IP
echo "[2.1] Public IP 생성..."
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name pip-web \
    --allocation-method Static \
    --sku Standard \
    --location $LOCATION

# NSG
echo "[2.2] NSG 생성..."
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name nsg-web \
    --location $LOCATION

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name nsg-web \
    --name Allow-HTTP \
    --priority 100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 80

# NIC
echo "[2.3] NIC 생성..."
az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name nic-web \
    --vnet-name $VNET_NAME \
    --subnet subnet-web \
    --public-ip-address pip-web \
    --network-security-group nsg-web \
    --location $LOCATION

# Web VM 생성
echo "[2.4] Web VM 생성..."

# Nginx 설정 생성
cat > /tmp/web-cloud-init.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true

packages:
  - nginx

write_files:
  - path: /etc/nginx/sites-available/default
    permissions: '0644'
    content: |
      server {
          listen 80 default_server;
          server_name _;
          
          location / {
              proxy_pass http://$WAS_IP:8080;
              proxy_set_header Host \$host;
              proxy_set_header X-Real-IP \$remote_addr;
              proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
              proxy_connect_timeout 60s;
              proxy_send_timeout 60s;
              proxy_read_timeout 60s;
          }
          
          location /health {
              access_log off;
              return 200 "healthy\n";
              add_header Content-Type text/plain;
          }
      }

runcmd:
  - systemctl restart nginx
  - systemctl enable nginx
  - echo "Web server started at \$(date)" >> /var/log/cloud-init-output.log
EOF

az vm create \
    --resource-group $RESOURCE_GROUP \
    --name vm-web \
    --location $LOCATION \
    --nics nic-web \
    --image Ubuntu2204 \
    --size Standard_B2s \
    --admin-username azureuser \
    --generate-ssh-keys \
    --custom-data @/tmp/web-cloud-init.yaml

WEB_IP=$(az network public-ip show \
    --resource-group $RESOURCE_GROUP \
    --name pip-web \
    --query ipAddress \
    --output tsv)

echo "Web VM 생성 완료: $WEB_IP"

# =================================================
# Phase 3: 애플리케이션 시작 대기 (3-5분)
# =================================================

echo -e "${YELLOW}[Phase 3/4] PetClinic 시작 대기...${NC}"

echo "WAS 초기화 대기 중 (최대 5분)..."
for i in {1..60}; do
    if curl -s -f http://$WAS_IP:8080/actuator/health > /dev/null 2>&1; then
        echo ""
        echo "WAS 정상 시작 ✓"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

echo "Web 프록시 확인 중..."
for i in {1..20}; do
    if curl -s -f http://$WEB_IP/health > /dev/null 2>&1; then
        echo "Web 프록시 정상 ✓"
        break
    fi
    echo -n "."
    sleep 3
done
echo ""

# =================================================
# Phase 4: 헬스체크 및 검증 (2분)
# =================================================

echo -e "${YELLOW}[Phase 4/4] 서비스 검증...${NC}"

# WAS Health Check
echo "[4.1] WAS Health Check..."
WAS_HEALTH=$(curl -s http://$WAS_IP:8080/actuator/health)
echo "$WAS_HEALTH"

# Web 접속 테스트
echo "[4.2] Web 접속 테스트..."
if curl -s http://$WEB_IP | grep -q "PetClinic"; then
    echo "PetClinic 메인 페이지 확인 ✓"
else
    echo -e "${YELLOW}경고: PetClinic 메인 페이지 로드 확인 필요${NC}"
fi

# Database 연결 테스트
echo "[4.3] Database 연결 테스트..."
DB_TEST=$(curl -s http://$WAS_IP:8080/owners)
if echo "$DB_TEST" | grep -q "owners"; then
    echo "Database 연결 정상 ✓"
else
    echo -e "${YELLOW}경고: Database 연결 확인 필요${NC}"
fi

# =================================================
# Route53 업데이트 (점검 페이지 → PetClinic)
# =================================================

echo -e "${YELLOW}[5] Route53 업데이트...${NC}"

# Maintenance VM의 Public IP 제거하고 Web IP로 교체
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='petclinic.example.com.'].Id" \
    --output text | cut -d'/' -f3)

if [ ! -z "$HOSTED_ZONE_ID" ]; then
    cat > /tmp/route53-change.json <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "petclinic.example.com",
      "Type": "A",
      "SetIdentifier": "Azure-DR",
      "Failover": "SECONDARY",
      "TTL": 60,
      "ResourceRecords": [{
        "Value": "$WEB_IP"
      }]
    }
  }]
}
EOF

    aws route53 change-resource-record-sets \
        --hosted-zone-id $HOSTED_ZONE_ID \
        --change-batch file:///tmp/route53-change.json

    echo "Route53 업데이트 완료 ✓"
fi

# =================================================
# Maintenance VM 정리
# =================================================

echo "[6] 점검 페이지 VM 정리..."
az vm delete \
    --resource-group $RESOURCE_GROUP \
    --name vm-maintenance \
    --yes \
    --no-wait

echo "점검 페이지 VM 삭제 요청 완료"

# =================================================
# 완료 및 정보 출력
# =================================================

echo ""
echo -e "${GREEN}=========================================="
echo "PetClinic 배포 완료!"
echo "종료 시간: $(date)"
echo "==========================================${NC}"
echo ""
echo "서비스 접속 정보:"
echo "  PetClinic URL: http://$WEB_IP"
echo "  WAS Direct: http://$WAS_IP:8080"
echo ""
echo "Health Check URLs:"
echo "  WAS: http://$WAS_IP:8080/actuator/health"
echo "  Web: http://$WEB_IP/health"
echo ""
echo "주요 엔드포인트:"
echo "  홈: http://$WEB_IP"
echo "  Owners: http://$WEB_IP/owners"
echo "  Vets: http://$WEB_IP/vets"
echo "  Error: http://$WEB_IP/oups"
echo ""
echo "모니터링:"
echo "  WAS 로그: ssh azureuser@$WAS_IP 'tail -f /var/log/petclinic.log'"
echo "  Web 로그: ssh azureuser@$WEB_IP 'tail -f /var/log/nginx/access.log'"
echo ""
echo "다음 단계:"
echo "  1. 브라우저에서 서비스 테스트"
echo "  2. 주요 기능 검증 (로그인, 조회, 등록)"
echo "  3. 성능 모니터링"
echo "  4. 고객 공지"
echo ""
echo "로그 파일: $LOG_FILE"
