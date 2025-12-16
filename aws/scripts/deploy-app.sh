#!/bin/bash
set -e

echo "=========================================="
echo "EKS 애플리케이션 배포 시작"
echo "=========================================="

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. EKS 클러스터 연결
echo -e "${YELLOW}[1/8] EKS 클러스터 연결...${NC}"
aws eks update-kubeconfig --region ap-northeast-2 --name prod-eks

# 2. 노드 확인
echo -e "${YELLOW}[2/8] 노드 상태 확인...${NC}"
kubectl get nodes

# 3. 노드 레이블 설정
echo -e "${YELLOW}[3/8] 노드 레이블 설정...${NC}"

# Web 노드에 tier=web 레이블
kubectl get nodes -o name | grep -E 'ip-10-0-1[12]-' | while read node; do
    node_name=${node#node/}
    echo "  레이블 추가: $node_name → tier=web"
    kubectl label nodes $node_name tier=web --overwrite 2>/dev/null || true
done

# WAS 노드에 tier=was 레이블  
kubectl get nodes -o name | grep -E 'ip-10-0-2[12]-' | while read node; do
    node_name=${node#node/}
    echo "  레이블 추가: $node_name → tier=was"
    kubectl label nodes $node_name tier=was --overwrite 2>/dev/null || true
done

echo ""
echo "노드 레이블 확인:"
kubectl get nodes -L tier

# 4. Namespace 생성
echo -e "${YELLOW}[4/8] Namespace 생성...${NC}"
kubectl apply -f ../k8s-manifests/namespaces.yaml

# 5. Terraform output에서 RDS 정보 가져오기
echo -e "${YELLOW}[5/8] RDS 정보 가져오기...${NC}"
cd ..
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")
RDS_ADDRESS=$(terraform output -raw rds_address 2>/dev/null || echo "")
DB_NAME=$(terraform output -raw rds_database_name 2>/dev/null || echo "petclinic")
cd scripts

if [ -z "$RDS_ENDPOINT" ] && [ -z "$RDS_ADDRESS" ]; then
    echo -e "${RED}Terraform output에서 RDS 정보를 가져올 수 없습니다.${NC}"
    echo -n "RDS Endpoint를 수동으로 입력하세요: "
    read RDS_ENDPOINT
else
    # endpoint는 host:port 형식이므로 host만 추출
    RDS_HOST=$(echo $RDS_ENDPOINT | cut -d':' -f1)
    if [ -z "$RDS_HOST" ]; then
        RDS_HOST=$RDS_ADDRESS
    fi
    echo "RDS Host: $RDS_HOST"
fi

# 6. DB 비밀번호 입력
echo -e "${YELLOW}[6/8] DB 비밀번호 입력...${NC}"
echo -n "DB Password: "
read -s DB_PASSWORD
echo

if [ -z "$DB_PASSWORD" ]; then
    echo -e "${RED}DB 비밀번호가 입력되지 않았습니다.${NC}"
    exit 1
fi

# 7. DB Secret 생성
echo -e "${YELLOW}[7/8] DB Secret 생성...${NC}"

# JDBC URL 생성
DB_URL="jdbc:mysql://${RDS_HOST}:3306/${DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Seoul"

echo "DB URL: $DB_URL"
echo "DB Name: $DB_NAME"
echo "DB User: admin"

# 기존 Secret 삭제 (있다면)
kubectl delete secret db-credentials -n was 2>/dev/null || true

# 새 Secret 생성
kubectl create secret generic db-credentials \
  --from-literal=url="$DB_URL" \
  --from-literal=username="admin" \
  --from-literal=password="$DB_PASSWORD" \
  -n was

# Secret 확인
echo ""
echo "Secret 생성 확인:"
kubectl get secret db-credentials -n was
kubectl describe secret db-credentials -n was

# 8. 애플리케이션 배포
echo -e "${YELLOW}[8/8] 애플리케이션 배포...${NC}"

# WAS 배포
echo "WAS 배포 중..."
kubectl apply -f ../k8s-manifests/was/

# WAS Pod 시작 대기 (최대 3분)
echo "WAS Pod 시작 대기 중 (최대 3분)..."
kubectl wait --for=condition=ready pod -l app=was-spring -n was --timeout=180s || {
    echo -e "${RED}WAS Pod 시작 실패. 로그 확인:${NC}"
    kubectl get pods -n was
    kubectl logs -l app=was-spring -n was --tail=50
    exit 1
}

# Web 배포
echo "Web 배포 중..."
kubectl apply -f ../k8s-manifests/web/

# Web Pod 시작 대기
echo "Web Pod 시작 대기 중..."
kubectl wait --for=condition=ready pod -l app=web-nginx -n web --timeout=120s

# Ingress 배포
echo "Ingress 배포 중..."
kubectl apply -f ../k8s-manifests/ingress/

echo ""
echo -e "${GREEN}=========================================="
echo "배포 완료!"
echo "==========================================${NC}"
echo ""

# 상태 확인
echo "=== Pod 상태 ==="
kubectl get pods -n was -o wide
kubectl get pods -n web -o wide

echo ""
echo "=== Services ==="
kubectl get svc -n was
kubectl get svc -n web

echo ""
echo "=== Ingress ==="
kubectl get ingress -n web

echo ""
echo -e "${YELLOW}ALB 생성까지 3-5분 소요됩니다.${NC}"
echo ""
echo "접속 URL 확인:"
echo "kubectl get ingress -n web web-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
echo ""

# WAS 로그 확인
echo "WAS 로그 (최근 20줄):"
kubectl logs -l app=was-spring -n was --tail=20

echo ""
echo -e "${GREEN}배포 스크립트 완료!${NC}"
