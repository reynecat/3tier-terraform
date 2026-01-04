#!/bin/bash
# Test Destroy & Redeploy Script
#
# 이 스크립트는 destroy 후 재배포가 정상적으로 작동하는지 테스트합니다.
# 주의: 실제 리소스를 삭제하고 재생성하므로 주의해서 사용하세요.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Confirmation
confirm() {
    echo -e "${YELLOW}⚠️  WARNING ⚠️${NC}"
    echo "This script will:"
    echo "  1. Backup current state"
    echo "  2. Destroy all monitoring resources"
    echo "  3. Redeploy from scratch"
    echo ""
    echo "This is a destructive operation!"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_error "Aborted by user"
        exit 1
    fi
}

# Step 1: Backup
backup_state() {
    log_step "Step 1: Backing up current state..."

    # Backup terraform.tfvars
    if [ -f "terraform.tfvars" ]; then
        cp terraform.tfvars terraform.tfvars.test-backup
        log_info "Backed up terraform.tfvars ✓"
    fi

    # Backup state file
    if [ -f "terraform.tfstate" ]; then
        cp terraform.tfstate terraform.tfstate.test-backup
        log_info "Backed up terraform.tfstate ✓"
    fi

    # Save outputs
    terraform output > outputs.test-backup.txt 2>&1 || true
    log_info "Saved outputs ✓"

    echo ""
}

# Step 2: Destroy
destroy_resources() {
    log_step "Step 2: Destroying resources..."

    terraform destroy -auto-approve

    log_info "All resources destroyed ✓"
    echo ""
}

# Step 3: Verify destruction
verify_destruction() {
    log_step "Step 3: Verifying destruction..."

    # Check if state is empty
    if [ -f "terraform.tfstate" ]; then
        resource_count=$(terraform state list 2>/dev/null | wc -l)
        if [ "$resource_count" -eq 0 ]; then
            log_info "State is empty ✓"
        else
            log_warn "State still contains $resource_count resources"
        fi
    fi

    echo ""
}

# Step 4: Redeploy
redeploy_resources() {
    log_step "Step 4: Redeploying resources..."

    # Reinitialize
    log_info "Reinitializing Terraform..."
    terraform init -upgrade

    # Validate
    log_info "Validating configuration..."
    terraform validate

    # Plan
    log_info "Planning deployment..."
    terraform plan -out=tfplan

    # Apply
    log_info "Applying deployment..."
    terraform apply tfplan
    rm -f tfplan

    log_info "Redeployment complete ✓"
    echo ""
}

# Step 5: Verify redeployment
verify_redeployment() {
    log_step "Step 5: Verifying redeployment..."

    # Count resources
    resource_count=$(terraform state list | wc -l)
    log_info "Created $resource_count resources"

    # Check key resources
    log_info "Checking key resources..."

    # Dashboard
    if terraform state show aws_cloudwatch_dashboard.eks_monitoring &>/dev/null; then
        log_info "  ✓ CloudWatch Dashboard"
    else
        log_warn "  ✗ CloudWatch Dashboard not found"
    fi

    # Lambda
    if terraform state show aws_lambda_function.auto_recovery &>/dev/null; then
        log_info "  ✓ Lambda Function"
    else
        log_warn "  ✗ Lambda Function not found"
    fi

    # SNS Topic
    if terraform state show aws_sns_topic.alerts &>/dev/null; then
        log_info "  ✓ SNS Topic"
    else
        log_warn "  ✗ SNS Topic not found"
    fi

    # Alarms
    alarm_count=$(terraform state list | grep aws_cloudwatch_metric_alarm | wc -l)
    log_info "  ✓ Created $alarm_count alarms"

    echo ""
}

# Step 6: Compare outputs
compare_outputs() {
    log_step "Step 6: Comparing outputs..."

    # Save new outputs
    terraform output > outputs.test-new.txt

    # Compare (just show diff, don't fail)
    if [ -f "outputs.test-backup.txt" ]; then
        log_info "Output differences:"
        diff -u outputs.test-backup.txt outputs.test-new.txt || true
    fi

    echo ""
}

# Step 7: Show results
show_results() {
    log_step "Step 7: Test Results"

    echo ""
    log_info "=== Deployment Summary ==="
    terraform output
    echo ""

    log_info "=== Dashboard URL ==="
    terraform output -raw dashboard_url 2>/dev/null || echo "N/A"
    echo ""

    log_info "=== SNS Topic ARN ==="
    terraform output -raw sns_topic_arn 2>/dev/null || echo "N/A"
    echo ""
}

# Cleanup test files
cleanup() {
    log_step "Cleanup: Remove test backup files? (yes/no)"
    read -p "> " -r
    if [[ $REPLY =~ ^yes$ ]]; then
        rm -f terraform.tfvars.test-backup
        rm -f terraform.tfstate.test-backup
        rm -f outputs.test-backup.txt
        rm -f outputs.test-new.txt
        log_info "Test files removed ✓"
    else
        log_info "Test files kept for reference"
    fi
}

# Main
main() {
    log_info "=== Monitoring Module Test: Destroy & Redeploy ==="
    echo ""

    # Pre-flight checks
    if [ ! -f "terraform.tfvars" ]; then
        log_error "terraform.tfvars not found!"
        exit 1
    fi

    if [ ! -f "lambda/index.py" ]; then
        log_error "lambda/index.py not found!"
        exit 1
    fi

    # Confirm
    confirm

    # Execute test
    backup_state
    destroy_resources
    verify_destruction
    redeploy_resources
    verify_redeployment
    compare_outputs
    show_results

    echo ""
    log_info "=== Test Complete ==="
    log_info "The destroy & redeploy test completed successfully!"
    echo ""

    cleanup
}

# Run
main
