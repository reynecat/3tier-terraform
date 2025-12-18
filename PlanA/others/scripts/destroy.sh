#!/bin/bash
# others/scripts/destroy.sh
# 전체 리소스 삭제 스크립트

set -e

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "================================"
echo "  ⚠️  리소스 삭제 스크립트"
echo "================================"
echo ""

log_warn "이 스크립트는 모든 AWS 리소스를 삭제합니다!"
log_warn "데이터베이스 스냅샷을 제외한 모든 데이터가 삭제됩니다!"
echo ""

read -p "정말로 삭제하시겠습니까? (yes 입력): " confirm

if [ "$confirm" != "yes" ]; then
    log_warn "삭제가 취소되었습니다"
    exit 0
fi

echo ""
log_warn "Kubernetes 리소스 삭제 중..."
kubectl delete -f others/k8s-manifests/web/ --ignore-not-found=true
kubectl delete -f others/k8s-manifests/was/ --ignore-not-found=true
kubectl delete -f others/k8s-manifests/namespaces.yaml --ignore-not-found=true

echo ""
log_warn "Terraform 리소스 삭제 중... (10-15분 소요)"
cd aws
terraform destroy -auto-approve
cd ..

echo ""
log_warn "모든 리소스가 삭제되었습니다"
