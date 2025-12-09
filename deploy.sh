#!/bin/bash
# PetClinic 멀티클라우드 배포 자동화 스크립트

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  PetClinic 멀티클라우드 DR 배포      ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"

# 1. Lambda 패키징
echo -e "\n${GREEN}[1/4]${NC} Lambda 함수 패키징..."
cd scripts/lambda-db-sync && ./package.sh && cd ../..

# 2. Terraform 배포
echo -e "\n${GREEN}[2/4]${NC} Terraform 인프라 배포..."
terraform init
terraform apply -auto-approve

# 3. Docker 이미지 빌드 (선택사항)
echo -e "\n${GREEN}[3/4]${NC} Docker 이미지 빌드는 수동으로 수행하세요:"
echo "  docker build -t petclinic:latest -f docker/Dockerfile ."

# 4. 배포 완료
echo -e "\n${GREEN}[4/4]${NC} 배포 완료!"
terraform output deployment_summary

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 인프라 배포가 완료되었습니다!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
