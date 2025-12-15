#!/bin/bash
set -e

echo "=========================================="
echo "EKS 애플리케이션 배포 시작"
echo "=========================================="

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. EKS 클러스터 연결
echo -e "${YELLOW}[1/7] EKS 클러스터 연결...${NC}"
aws eks update-kubeconfig --region ap-northeast-2 --name prod-eks

# 2. 노드 확인
echo -e "${YELLOW}[2/7] 노드 상태 확인...${NC}"
kubectl get nodes

# 3. 노드 레이블 설정
echo -e "${YELLOW}[3/7] 노드 레이블 설정...${NC}"

# Web 노드에 tier=web 레이블
kubectl get nodes -o name | grep -E 'ip-10-0-1[12]-' | while read node; do
    node_name=${node#node/}
    echo "  레이블 추가: $node_name → tier=web"
    kubectl label nodes $node_name tier=web --overwrite
done

# WAS 노드에 tier=was 레이블  
kubectl get nodes -o name | grep -E 'ip-10-0-2[12]-' | while read node; do
    node_name=${node#node/}
    echo "  레이블 추가: $node_name → tier=was"
    kubectl label nodes $node_name tier=was --overwrite
done

echo ""
echo "노드 레이블 확인:"
kubectl get nodes -L tier


# 4. Namespace 생성
echo -e "${YELLOW}[4/7] Namespace 생성...${NC}"
kubectl apply -f ../k8s-manifests/namespaces.yaml

# 5. DB Secret 생성
echo -e "${YELLOW}[5/7] DB Secret 생성...${NC}"
echo -n "RDS Endpoint: "
read RDS_ENDPOINT
echo -n "DB Password: "
read -s DB_PASSWORD
echo

kubectl create secret generic db-credentials \
  --from-literal=host="prod-rds.ciyiccb2k2z8.ap-northeast-2.rds.amazonaws.com" \
  --from-literal=database="petclinic" \
  --from-literal=username="admin" \
  --from-literal=password="$DB_PASSWORD" \
  -n was \
  --dry-run=client -o yaml | kubectl apply -f -

# 6. 애플리케이션 배포
echo -e "${YELLOW}[6/7] WAS 배포...${NC}"
kubectl apply -f ../k8s-manifests/was/

echo -e "${YELLOW}[7/7] Web 배포...${NC}"
kubectl apply -f ../k8s-manifests/web/

# Ingress 배포
kubectl apply -f ../k8s-manifests/ingress/

echo ""
echo -e "${GREEN}=========================================="
echo "배포 완료!"
echo "==========================================${NC}"
echo ""
echo "Pod 상태 확인:"
kubectl get pods -n was
kubectl get pods -n web
echo ""
echo "Ingress 확인 (ALB 생성까지 3-5분 소요):"
kubectl get ingress -n web
echo ""
echo "접속 URL은 다음 명령어로 확인:"
echo "kubectl get ingress -n web web-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
