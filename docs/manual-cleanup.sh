#!/bin/bash
# Manual cleanup script for stuck Security Group dependencies
# Run this if terraform destroy fails with Security Group DependencyViolation

set -e

echo "=========================================="
echo " Manual AWS Resource Cleanup Script"
echo "=========================================="
echo ""

# Configuration
AWS_REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
VPC_ID="${1:-}"

if [ -z "$VPC_ID" ]; then
  echo "Usage: $0 <VPC_ID>"
  echo ""
  echo "Example: $0 vpc-06e4fdfb8ec4950d1"
  echo ""
  echo "Or get VPC ID from terraform:"
  echo "  terraform output -raw vpc_id"
  exit 1
fi

echo "Region: $AWS_REGION"
echo "VPC ID: $VPC_ID"
echo ""
echo "Starting cleanup in 5 seconds... (Ctrl+C to cancel)"
sleep 5

# Step 1: Delete all Load Balancers
echo ""
echo "=== Step 1: Deleting Load Balancers ==="
LB_ARNS=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text 2>/dev/null || echo "")

if [ -n "$LB_ARNS" ]; then
  for lb_arn in $LB_ARNS; do
    echo "  Deleting: $lb_arn"
    aws elbv2 delete-load-balancer \
      --region "$AWS_REGION" \
      --load-balancer-arn "$lb_arn" || true
  done
  echo "  Waiting 30 seconds for LBs to be deleted..."
  sleep 30
else
  echo "  No Load Balancers found"
fi

# Step 2: Delete all Target Groups
echo ""
echo "=== Step 2: Deleting Target Groups ==="
TG_ARNS=$(aws elbv2 describe-target-groups \
  --region "$AWS_REGION" \
  --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
  --output text 2>/dev/null || echo "")

if [ -n "$TG_ARNS" ]; then
  for tg_arn in $TG_ARNS; do
    echo "  Deleting: $tg_arn"
    aws elbv2 delete-target-group \
      --region "$AWS_REGION" \
      --target-group-arn "$tg_arn" || true
  done
else
  echo "  No Target Groups found"
fi

# Step 3: Delete all ENIs
echo ""
echo "=== Step 3: Deleting Network Interfaces ==="

# Try multiple times to catch ENIs that are being created/deleted
for attempt in {1..5}; do
  echo "  Attempt $attempt/5..."

  ENI_IDS=$(aws ec2 describe-network-interfaces \
    --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'NetworkInterfaces[?Status==`available` || contains(Description, `ELB`)].NetworkInterfaceId' \
    --output text 2>/dev/null || echo "")

  if [ -n "$ENI_IDS" ]; then
    for eni_id in $ENI_IDS; do
      echo "    Deleting ENI: $eni_id"

      # Check for attachment and detach if needed
      ATTACHMENT_ID=$(aws ec2 describe-network-interfaces \
        --region "$AWS_REGION" \
        --network-interface-ids "$eni_id" \
        --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
        --output text 2>/dev/null || echo "")

      if [ -n "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
        echo "      Detaching: $ATTACHMENT_ID"
        aws ec2 detach-network-interface \
          --region "$AWS_REGION" \
          --attachment-id "$ATTACHMENT_ID" \
          --force 2>/dev/null || true
        sleep 3
      fi

      # Delete the ENI
      aws ec2 delete-network-interface \
        --region "$AWS_REGION" \
        --network-interface-id "$eni_id" 2>/dev/null || true
    done
    sleep 10
  else
    echo "    No ENIs found"
    break
  fi
done

# Step 4: Check Security Groups
echo ""
echo "=== Step 4: Checking Security Groups ==="
SG_IDS=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query "SecurityGroups[?GroupName!='default'].GroupId" \
  --output text 2>/dev/null || echo "")

if [ -n "$SG_IDS" ]; then
  echo "  Found Security Groups:"
  for sg_id in $SG_IDS; do
    SG_NAME=$(aws ec2 describe-security-groups \
      --region "$AWS_REGION" \
      --group-ids "$sg_id" \
      --query 'SecurityGroups[0].GroupName' \
      --output text 2>/dev/null || echo "")
    echo "    - $sg_id ($SG_NAME)"

    # Check if anything is still using this SG
    USING_ENIS=$(aws ec2 describe-network-interfaces \
      --region "$AWS_REGION" \
      --filters "Name=group-id,Values=$sg_id" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' \
      --output text 2>/dev/null || echo "")

    if [ -n "$USING_ENIS" ]; then
      echo "      WARNING: Still used by ENIs: $USING_ENIS"
    fi
  done
else
  echo "  No non-default Security Groups found"
fi

# Step 5: Final wait
echo ""
echo "=== Step 5: Final cleanup wait ==="
echo "  Waiting 30 seconds for all dependencies to be resolved..."
sleep 30

echo ""
echo "=========================================="
echo " Cleanup completed!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Run: terraform destroy"
echo "  2. If you still get errors, check the Security Groups listed above"
echo "  3. Manual deletion might be needed via AWS Console"
echo ""
