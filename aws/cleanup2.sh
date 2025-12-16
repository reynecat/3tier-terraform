#!/bin/bash
# cleanup-iam.sh

USER_NAME="azure-vm-s3-access-prod"

echo "=== IAM User 정책 정리 ==="

# 1. 인라인 정책 삭제
echo "[1/3] 인라인 정책 삭제..."
for POLICY in $(aws iam list-user-policies \
  --user-name $USER_NAME \
  --query 'PolicyNames[*]' \
  --output text); do
  echo "  삭제: $POLICY"
  aws iam delete-user-policy --user-name $USER_NAME --policy-name $POLICY
done

# 2. 연결된 정책 분리
echo "[2/3] 연결된 정책 분리..."
for POLICY_ARN in $(aws iam list-attached-user-policies \
  --user-name $USER_NAME \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text); do
  echo "  분리: $POLICY_ARN"
  aws iam detach-user-policy --user-name $USER_NAME --policy-arn $POLICY_ARN
done

# 3. Access Key 삭제
echo "[3/3] Access Key 삭제..."
for KEY_ID in $(aws iam list-access-keys \
  --user-name $USER_NAME \
  --query 'AccessKeyMetadata[*].AccessKeyId' \
  --output text); do
  echo "  삭제: $KEY_ID"
  aws iam delete-access-key --user-name $USER_NAME --access-key-id $KEY_ID
done

echo "정리 완료!"