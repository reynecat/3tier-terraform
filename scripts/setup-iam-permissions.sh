#!/bin/bash
# AWS IAM 권한 일괄 추가 스크립트
# 사용법: ./setup-iam-permissions.sh [USER_NAME 또는 GROUP_NAME]

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  AWS IAM 권한 일괄 추가 스크립트"
echo "=========================================="
echo ""

# 사용자 입력
read -p "추가 대상을 선택하세요 (1: User, 2: Group): " TARGET_TYPE

if [ "$TARGET_TYPE" == "1" ]; then
    read -p "User 이름을 입력하세요: " TARGET_NAME
    ATTACH_CMD="attach-user-policy --user-name"
elif [ "$TARGET_TYPE" == "2" ]; then
    read -p "Group 이름을 입력하세요: " TARGET_NAME
    ATTACH_CMD="attach-group-policy --group-name"
else
    echo -e "${RED}잘못된 선택입니다.${NC}"
    exit 1
fi

echo ""
echo "대상: $TARGET_NAME"
echo ""

# AWS Managed Policies 목록
POLICIES=(
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess"
    "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    "arn:aws:iam::aws:policy/CloudWatchFullAccess"
    "arn:aws:iam::aws:policy/IAMFullAccess"
    "arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
    "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
    "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess"
    "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
)

TOTAL=${#POLICIES[@]}
SUCCESS=0
FAILED=0

echo "총 $TOTAL 개의 Policy를 추가합니다..."
echo ""

# 각 Policy 추가
for POLICY_ARN in "${POLICIES[@]}"; do
    POLICY_NAME=$(echo $POLICY_ARN | cut -d'/' -f2)
    printf "%-50s ... " "$POLICY_NAME"
    
    if aws iam $ATTACH_CMD $TARGET_NAME --policy-arn $POLICY_ARN 2>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((SUCCESS++))
    else
        # 이미 연결되어 있는 경우
        if aws iam $ATTACH_CMD $TARGET_NAME --policy-arn $POLICY_ARN 2>&1 | grep -q "EntityAlreadyExists\|already attached"; then
            echo -e "${YELLOW}(이미 연결됨)${NC}"
            ((SUCCESS++))
        else
            echo -e "${RED}✗${NC}"
            ((FAILED++))
        fi
    fi
done

echo ""
echo "=========================================="
echo -e "완료: ${GREEN}$SUCCESS${NC} / 실패: ${RED}$FAILED${NC} / 총: $TOTAL"
echo "=========================================="

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}모든 권한이 성공적으로 추가되었습니다!${NC}"
else
    echo -e "${YELLOW}일부 권한 추가에 실패했습니다. 로그를 확인하세요.${NC}"
fi
