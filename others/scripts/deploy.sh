#!/bin/bash
# others/scripts/deploy.sh
# 전체 배포 스크립트

set -e  # 오류 발생 시 즉시 종료

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 환경 변수 확인
check_prerequisites() {
    log_info "필수 도구 확인 중..."
    
    # Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform이 설치되지 않았습니다"
        exit 1
    fi
    
    # AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI가 설치되지 않았습니다"
        exit 1
    fi
    
    # kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되지 않았습니다"
        exit 1
    fi
    
    log_info "모든 필수 도구가 설치되어 있습니다 ✓"
}

# Terraform 초기화
terraform_init() {
    log_info "Terraform 초기화 중..."
    cd aws
    terraform init
    cd ..
    log_info "Terraform 초기화 완료 ✓"
}

# AWS 인프라 배포
deploy_aws() {
    log_info "AWS 인프라 배포 시작..."
    
    cd aws
    
    # Plan 확인
    log_info "배포 계획 확인 중..."
    terraform plan -out=tfplan
    
    # 사용자 확인
    echo ""
    read -p "배포를 진행하시겠습니까? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_warn "배포가 취소되었습니다"
        exit 0
    fi
    
    # Apply
    log_info "AWS 리소스 생성 중... (20-30분 소요)"
    terraform apply tfplan
    
    # Outputs 저장
    terraform output -json > ../outputs.json
    
    cd ..
    
    log_info "AWS 인프라 배포 완료 ✓"
}

# EKS 설정
configure_eks() {
    log_info "EKS 클러스터 설정 중..."
    
    # 클러스터 이름 가져오기
    CLUSTER_NAME=$(jq -r '.eks_cluster_name.value' outputs.json)
    AWS_REGION=$(jq -r '.aws_region.value' outputs.json)
    
    # kubeconfig 업데이트
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    # 연결 확인
    log_info "EKS 노드 확인 중..."
    kubectl get nodes
    
    log_info "EKS 설정 완료 ✓"
}

# Kubernetes 리소스 배포
deploy_k8s() {
    log_info "Kubernetes 리소스 배포 중..."
    
    # Namespace 생성
    log_info "Namespace 생성..."
    kubectl apply -f others/k8s-manifests/namespaces.yaml
    
    # DB Secret 생성
    log_info "DB Secret 생성..."
    DB_HOST=$(jq -r '.rds_endpoint.value' outputs.json | cut -d':' -f1)
    DB_NAME=$(jq -r '.database_name.value' outputs.json)
    
    read -sp "DB Password 입력: " DB_PASSWORD
    echo ""
    
    kubectl create secret generic db-credentials \
        --from-literal=host="$DB_HOST" \
        --from-literal=database="$DB_NAME" \
        --from-literal=username="admin" \
        --from-literal=password="$DB_PASSWORD" \
        -n was \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # WAS 배포
    log_info "WAS Tier 배포..."
    kubectl apply -f others/k8s-manifests/was/
    
    # WAS Pod 준비 대기
    log_info "WAS Pod 시작 대기 중..."
    kubectl wait --for=condition=ready pod -l app=was-spring -n was --timeout=300s
    
    # Web 배포
    log_info "Web Tier 배포..."
    kubectl apply -f others/k8s-manifests/web/
    
    # Web Pod 준비 대기
    log_info "Web Pod 시작 대기 중..."
    kubectl wait --for=condition=ready pod -l app=web-nginx -n web --timeout=300s
    
    log_info "Kubernetes 리소스 배포 완료 ✓"
}

# 배포 확인
verify_deployment() {
    log_info "배포 상태 확인 중..."
    
    echo ""
    log_info "=== Pods 상태 ==="
    kubectl get pods --all-namespaces
    
    echo ""
    log_info "=== Services 상태 ==="
    kubectl get svc --all-namespaces
    
    echo ""
    log_info "=== ALB URL ==="
    ALB_URL=$(jq -r '.alb_dns_name.value' outputs.json)
    echo "http://$ALB_URL"
    
    echo ""
    log_info "배포가 완료되었습니다! 🎉"
    log_info "약 5분 후 ALB URL로 접속해주세요"
}

# 메인 실행
main() {
    echo "================================"
    echo "  PetClinic 배포 스크립트"
    echo "================================"
    echo ""
    
    check_prerequisites
    terraform_init
    deploy_aws
    configure_eks
    deploy_k8s
    verify_deployment
    
    echo ""
    log_info "모든 배포가 완료되었습니다! ✅"
}

# 실행
main
