# CI/CD Pipeline for PetClinic Multi-Cloud DR Project

## Overview

This directory contains the CI/CD configuration for automated deployment of the PetClinic application to AWS EKS and Azure AKS using GitHub Actions and ArgoCD.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Actions CI/CD                        │
│                                                                   │
│  1. Build & Test    →   2. Docker Build   →   3. Push to Hub    │
│  4. Update Manifests →  5. Deploy to EKS  →   6. Health Check   │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│                         ArgoCD GitOps                            │
│                                                                   │
│  Monitor Git Repo  →  Auto Sync  →  Deploy to K8s  →  Self Heal │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. GitHub Actions Pipeline
**Location**: `github-actions/petclinic-cicd.yaml`

**Jobs**:
1. **build**: Maven build and test
2. **code-quality**: SonarQube analysis
3. **security-scan**: Trivy vulnerability scan
4. **docker**: Build and push Docker images
5. **update-gitops**: Update K8s manifests with new image tags
6. **deploy-aws-eks**: Deploy to AWS EKS
7. **deploy-azure-aks**: Deploy to Azure AKS (manual trigger for DR)
8. **smoke-test**: Health checks and smoke tests
9. **notify**: Slack notifications
10. **rollback**: Manual rollback capability

### 2. ArgoCD Configuration
**Location**: `argocd/application.yaml`

**Features**:
- Automated sync from Git repository
- Self-healing for manual changes
- Automatic pruning of deleted resources
- Retry with exponential backoff

## Setup Instructions

### Prerequisites
1. GitHub repository with the code
2. DockerHub account
3. AWS EKS cluster (already deployed)
4. Azure AKS cluster (for DR)
5. ArgoCD installed on EKS

### Step 1: Configure GitHub Secrets

Add the following secrets to your GitHub repository:

```bash
# Docker
DOCKER_USERNAME=cloud039
DOCKER_PASSWORD=<your-dockerhub-password>

# AWS
AWS_ACCESS_KEY_ID=<your-aws-access-key>
AWS_SECRET_ACCESS_KEY=<your-aws-secret-key>

# Azure
AZURE_CREDENTIALS='<your-azure-service-principal-json>'

# Optional: Notifications
SLACK_WEBHOOK_URL=<your-slack-webhook>
```

### Step 2: Copy GitHub Actions Workflow

```bash
# Create .github/workflows directory in your project root
mkdir -p /path/to/your/repo/.github/workflows

# Copy the workflow file
cp github-actions/petclinic-cicd.yaml /path/to/your/repo/.github/workflows/
```

### Step 3: Install ArgoCD on EKS

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=5m

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 4: Access ArgoCD UI

```bash
# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open browser: https://localhost:8080
# Username: admin
# Password: (from step 3)
```

### Step 5: Deploy ArgoCD Application

```bash
# Apply the ArgoCD application
kubectl apply -f argocd/application.yaml

# Verify application
kubectl get applications -n argocd
```

## Current Deployment Status

### Images on DockerHub
- `cloud039/petclinic-web:v1` - Nginx web server
- `cloud039/petclinic-was:v1` - Spring Boot application (initial)
- `cloud039/petclinic-was:v2` - Spring Boot with v2 updates

### Deployed Resources
- **Namespace**: web, was
- **Deployments**:
  - web-nginx (1 replica)
  - was-spring (1 replica)
- **Services**:
  - web-service (ClusterIP)
  - was-service (ClusterIP)
- **Ingress**: web-ingress (AWS ALB)

### Current Version
- **WAS Image**: `cloud039/petclinic-was:v2`
- **Web Image**: `cloud039/petclinic-web:v1`
- **Application URL**: http://k8s-web-webingre-5d0cf16a97-840173904.ap-northeast-2.elb.amazonaws.com

## Testing the CI/CD Pipeline

### Automatic Trigger (Push to main)

```bash
# 1. Make changes to the code
cd /home/ubuntu/spring-petclinic
# Edit src/main/resources/templates/welcome.html

# 2. Commit and push
git add .
git commit -m "feat: update welcome message to v3"
git push origin main

# 3. GitHub Actions will automatically:
#    - Build the application
#    - Run tests
#    - Build Docker images
#    - Push to DockerHub
#    - Update K8s manifests
#    - Deploy to EKS
```

### Manual Trigger

```bash
# Trigger via GitHub UI
# Go to: Actions → PetClinic Multi-Cloud DR - CI/CD Pipeline → Run workflow
```

### Verify Deployment

```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Check deployment status
kubectl get pods -A | grep -E "web|was"

# Check image versions
kubectl get deployment was-spring -n was -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl get deployment web-nginx -n web -o jsonpath='{.spec.template.spec.containers[0].image}'

# Access application
ALB_URL=$(kubectl get ingress web-ingress -n web -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://${ALB_URL}/ | grep "Multi-Cloud"
```

## CI/CD Workflow Diagram

```
┌─────────────┐
│  Developer  │
│  Push Code  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────┐
│         GitHub Actions Triggered            │
├─────────────────────────────────────────────┤
│  1. Checkout Code                           │
│  2. Build with Maven                        │
│  3. Run Tests                               │
│  4. Security Scan (Trivy)                   │
│  5. Build Docker Images                     │
│     - cloud039/petclinic-web:YYYYMMDD-SHA  │
│     - cloud039/petclinic-was:YYYYMMDD-SHA  │
│  6. Push to DockerHub                       │
│  7. Update K8s Manifests in Git            │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│         ArgoCD Detects Changes              │
├─────────────────────────────────────────────┤
│  1. Monitor Git Repository                  │
│  2. Compare Current State vs Desired State │
│  3. Auto-Sync to Kubernetes                │
│  4. Apply New Manifests                    │
│  5. Rolling Update Deployment              │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│         Kubernetes Deployment               │
├─────────────────────────────────────────────┤
│  Namespace: web                             │
│  └── Deployment: web-nginx                 │
│      └── Pod: nginx (new image)            │
│                                             │
│  Namespace: was                             │
│  └── Deployment: was-spring                │
│      └── Pod: spring-boot (new image)      │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│         Health Check & Verification         │
├─────────────────────────────────────────────┤
│  1. Liveness Probe: GET /                  │
│  2. Readiness Probe: GET /                 │
│  3. Smoke Test: Check for v2 message      │
│  4. Notify: Slack/Email                    │
└─────────────────────────────────────────────┘
```

## Image Tagging Strategy

### Format
```
{DATE}-{SHORT_SHA}
```

### Example
- `20260112-a1b2c3d` - Production release on Jan 12, 2026
- `latest` - Always points to the latest main branch build

### Current Tags
```bash
# v1 - Initial release
cloud039/petclinic-was:v1
cloud039/petclinic-web:v1

# v2 - Updated with Multi-Cloud DR message
cloud039/petclinic-was:v2
cloud039/petclinic-was:latest

# Future automated tags
cloud039/petclinic-was:20260112-a1b2c3d
```

## Rollback Procedure

### Via ArgoCD

```bash
# 1. Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 2. Navigate to application
# 3. Click "History and Rollback"
# 4. Select previous version
# 5. Click "Rollback"
```

### Via kubectl

```bash
# Rollback to previous version
kubectl rollout undo deployment/was-spring -n was
kubectl rollout undo deployment/web-nginx -n web

# Check rollout status
kubectl rollout status deployment/was-spring -n was
kubectl rollout status deployment/web-nginx -n web
```

### Via GitHub Actions

```bash
# Trigger rollback workflow manually
# Go to: Actions → Select "Rollback to Previous Version" → Run workflow
```

## Monitoring and Observability

### Application Logs

```bash
# WAS logs
kubectl logs -f deployment/was-spring -n was

# Web logs
kubectl logs -f deployment/web-nginx -n web

# Previous pod logs
kubectl logs deployment/was-spring -n was --previous
```

### Deployment Events

```bash
# Watch deployment events
kubectl get events -n was --sort-by='.lastTimestamp' | tail -20
kubectl get events -n web --sort-by='.lastTimestamp' | tail -20
```

### Resource Usage

```bash
# Pod resource usage
kubectl top pods -n was
kubectl top pods -n web

# Node resource usage
kubectl top nodes
```

## Troubleshooting

### Issue 1: Image Pull Failed

```bash
# Check image pull policy
kubectl describe pod <pod-name> -n <namespace>

# Verify DockerHub credentials
docker pull cloud039/petclinic-was:latest

# Check imagePullSecrets if needed
kubectl get secret -n <namespace>
```

### Issue 2: Deployment Not Updating

```bash
# Check ArgoCD sync status
kubectl get application petclinic-aws -n argocd -o yaml

# Force sync
kubectl patch application petclinic-aws -n argocd \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}' \
  --type merge

# Manual apply
kubectl apply -f codes/aws/2.\ service/k8s-manifests/was/
```

### Issue 3: Health Check Failing

```bash
# Check pod status
kubectl describe pod <pod-name> -n was

# Check logs
kubectl logs <pod-name> -n was

# Test health endpoint directly
kubectl port-forward <pod-name> -n was 8080:8080
curl http://localhost:8080/
```

## Best Practices

1. **Always test in staging first**: Use branches for testing
2. **Use semantic versioning**: Tag releases appropriately
3. **Monitor deployments**: Watch logs during rollouts
4. **Keep secrets secure**: Never commit secrets to Git
5. **Regular backups**: Backup database before major changes
6. **Gradual rollouts**: Use canary or blue-green deployments for production
7. **Automated testing**: Ensure comprehensive test coverage

## Next Steps

1. ✅ Set up GitHub Actions workflow
2. ✅ Configure ArgoCD application
3. ✅ Test CI/CD pipeline with code changes
4. ⬜ Implement canary deployments
5. ⬜ Add automated E2E tests
6. ⬜ Configure Slack notifications
7. ⬜ Set up monitoring with Prometheus/Grafana
8. ⬜ Implement DR site deployment automation
