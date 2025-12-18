#!/bin/bash
# cleanup-dependencies.sh

echo "=== AWS 리소스 의존성 정리 ==="

REGION="ap-northeast-2"
VPC_ID="vpc-03ef812b69212db97"

# 1. VPC의 모든 ENI 찾기
echo "[1/4] ENI 찾기..."
aws ec2 describe-network-interfaces \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
  --output table

# 2. ENI 삭제 (available 상태인 것만)
echo "[2/4] ENI 삭제 중..."
for ENI_ID in $(aws ec2 describe-network-interfaces \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' \
  --output text); do
  echo "  삭제: $ENI_ID"
  aws ec2 delete-network-interface --region $REGION --network-interface-id $ENI_ID || true
done

# 3. 모든 Elastic IP 찾기 및 해제
echo "[3/4] Elastic IP 찾기..."
aws ec2 describe-addresses \
  --region $REGION \
  --query 'Addresses[*].[PublicIp,AllocationId,AssociationId]' \
  --output table

echo "[4/4] Elastic IP 연결 해제 및 릴리스..."
for ADDR in $(aws ec2 describe-addresses \
  --region $REGION \
  --query 'Addresses[*].AllocationId' \
  --output text); do
  
  # 연결 해제
  ASSOC_ID=$(aws ec2 describe-addresses \
    --region $REGION \
    --allocation-ids $ADDR \
    --query 'Addresses[0].AssociationId' \
    --output text)
  
  if [ "$ASSOC_ID" != "None" ] && [ ! -z "$ASSOC_ID" ]; then
    echo "  연결 해제: $ASSOC_ID"
    aws ec2 disassociate-address --region $REGION --association-id $ASSOC_ID || true
    sleep 2
  fi
  
  # 릴리스
  echo "  릴리스: $ADDR"
  aws ec2 release-address --region $REGION --allocation-id $ADDR || true
done

echo "정리 완료!"