#!/bin/bash
# EKS Monitoring Module Deployment Script
#
# Usage:
#   ./deploy.sh [plan|apply|destroy]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if terraform.tfvars exists
check_tfvars() {
    if [ ! -f "terraform.tfvars" ]; then
        log_error "terraform.tfvars not found!"
        log_info "Please create terraform.tfvars from terraform.tfvars.example"
        log_info "  cp terraform.tfvars.example terraform.tfvars"
        log_info "  vi terraform.tfvars"
        exit 1
    fi
    log_info "terraform.tfvars found ✓"
}

# Check if index.py exists
check_lambda() {
    if [ ! -f "lambda/index.py" ]; then
        log_error "lambda/index.py not found!"
        exit 1
    fi
    log_info "Lambda source code found ✓"
}

# Initialize Terraform
init_terraform() {
    log_info "Initializing Terraform..."
    terraform init
}

# Validate Terraform configuration
validate_terraform() {
    log_info "Validating Terraform configuration..."
    terraform validate
}

# Plan Terraform changes
plan_terraform() {
    log_info "Planning Terraform changes..."
    terraform plan -out=tfplan
    log_info "Plan saved to tfplan"
}

# Apply Terraform changes
apply_terraform() {
    if [ -f "tfplan" ]; then
        log_info "Applying Terraform plan..."
        terraform apply tfplan
        rm -f tfplan
    else
        log_warn "No plan file found. Running plan first..."
        plan_terraform
        log_info "Applying Terraform plan..."
        terraform apply tfplan
        rm -f tfplan
    fi
}

# Destroy Terraform resources
destroy_terraform() {
    log_warn "This will destroy all monitoring resources!"
    log_warn "Press Ctrl+C to cancel, or Enter to continue..."
    read

    log_info "Destroying Terraform resources..."
    terraform destroy
}

# Show outputs
show_outputs() {
    log_info "Terraform Outputs:"
    echo ""
    terraform output
    echo ""

    log_info "Dashboard URL:"
    terraform output -raw dashboard_url 2>/dev/null || echo "N/A"
    echo ""

    log_info "SNS Topic ARN:"
    terraform output -raw sns_topic_arn 2>/dev/null || echo "N/A"
    echo ""
}

# Main script
main() {
    local action="${1:-plan}"

    log_info "EKS Monitoring Deployment Script"
    log_info "Action: $action"
    echo ""

    # Pre-flight checks
    check_tfvars
    check_lambda
    echo ""

    # Execute action
    case "$action" in
        init)
            init_terraform
            ;;
        validate)
            init_terraform
            validate_terraform
            ;;
        plan)
            init_terraform
            validate_terraform
            plan_terraform
            ;;
        apply)
            init_terraform
            validate_terraform
            apply_terraform
            show_outputs
            ;;
        destroy)
            destroy_terraform
            ;;
        output)
            show_outputs
            ;;
        *)
            log_error "Unknown action: $action"
            echo "Usage: $0 [init|validate|plan|apply|destroy|output]"
            exit 1
            ;;
    esac

    log_info "Done!"
}

# Run main
main "$@"
