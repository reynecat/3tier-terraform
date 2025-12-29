# PocketBank CI/CD with ArgoCD & GitHub Actions

## 🎯 Overview

완전 자동화된 GitOps 기반 CI/CD 파이프라인입니다:
- **GitOps:** ArgoCD를 사용하여 Git을 Single Source of Truth로 관리
- **CI:** GitHub Actions로 이미지 태그 업데이트 자동화
- **CD:** ArgoCD가 Git 변경사항을 감지하여 자동 배포

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     Developer                                 │
│                                                               │
│  1. Update k8s manifests                                     │
│  2. Push to GitHub                                           │
└───────────────────┬──────────────────────────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │   GitHub Repository   │
        │                       │
        │  k8s/                 │
        │  ├── web/             │
        │  │   ├── deployment   │
        │  │   └── service      │
        │  └── was/             │
        │      ├── deployment   │
        │      └── service      │
        └───────────┬───────────┘
                    │
        ┌───────────┴───────────┐
        │                       │
        ▼                       ▼
┌───────────────┐       ┌──────────────────┐
│ GitHub Actions│       │     ArgoCD       │
│               │       │                  │
│ 1. Verify     │       │ 1. Poll Git      │
│ 2. Update Tag │       │ 2. Sync Changes  │
│ 3. Push       │       │ 3. Apply to K8s  │
└───────────────┘       └────────┬─────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │      Azure AKS         │
                    │                        │
                    │  ┌──────────────────┐  │
                    │  │  pocketbank-web  │  │
                    │  │  (2 replicas)    │  │
                    │  └──────────────────┘  │
                    │           │            │
                    │  ┌────────▼─────────┐  │
                    │  │  pocketbank-was  │  │
                    │  │  (2 replicas)    │  │
                    │  └──────────────────┘  │
                    └────────────────────────┘
```

## 📋 Deployed Components

### ArgoCD
- **Server URL:** http://4.230.156.102
- **Username:** admin
- **Password:** `1-4MDFGX9RtBnYuF`
- **Namespace:** argocd

### PocketBank Application
- **Web LoadBalancer:** http://4.230.55.106
- **Application Gateway:** http://4.230.65.57
- **Docker Images:**
  - `cloud039/pocketbank-web:latest`
  - `cloud039/pocketbank-was:latest`

## 🚀 Quick Start

### 1. ArgoCD 웹 UI 접속

```bash
# ArgoCD URL
echo "http://4.230.156.102"

# Admin 비밀번호
echo "1-4MDFGX9RtBnYuF"
```

웹 브라우저에서 접속 후:
1. Username: `admin`
2. Password: `1-4MDFGX9RtBnYuF`
3. Applications 탭에서 PocketBank 앱 확인

### 2. ArgoCD CLI 설치 (선택사항)

```bash
# Linux/macOS
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# Login
argocd login 4.230.156.102 \
  --username admin \
  --password '1-4MDFGX9RtBnYuF' \
  --insecure

# Application 목록
argocd app list

# Application 상세
argocd app get pocketbank
```

### 3. GitOps Repository 설정

GitHub에 repository를 생성한 후:

```bash
cd /home/ubuntu/3tier-terraform

# Git 초기화 (아직 안했다면)
git init
git add .
git commit -m "Initial commit: PocketBank GitOps setup"

# Remote 추가
git remote add origin https://github.com/your-org/3tier-terraform.git
git branch -M main
git push -u origin main
```

### 4. ArgoCD Application 생성

```bash
# argocd-application.yaml 수정
nano argocd-application.yaml

# repoURL을 실제 GitHub repository로 변경
# repoURL: https://github.com/your-org/3tier-terraform.git

# Application 생성
kubectl apply -f argocd-application.yaml

# 상태 확인
kubectl get application -n argocd
argocd app get pocketbank
```

## 🔄 CI/CD Workflow

### Scenario 1: Docker Image 업데이트

새 버전의 PocketBank 이미지를 배포할 때:

```bash
# 1. GitHub Actions에서 수동 트리거
# Repository > Actions > CI/CD - PocketBank > Run workflow
# image_tag: v1.2.3 입력

# 2. Workflow가 자동으로:
#    - k8s/web/deployment.yaml 업데이트
#    - k8s/was/deployment.yaml 업데이트
#    - Git commit & push

# 3. ArgoCD가 자동으로:
#    - Git 변경사항 감지 (3분 간격 폴링)
#    - AKS에 배포
#    - 롤아웃 모니터링
```

### Scenario 2: Kubernetes 매니페스트 수정

레플리카 수 변경, 리소스 제한 조정 등:

```bash
# 1. 로컬에서 매니페스트 수정
nano k8s/web/deployment.yaml

# replicas를 2에서 3으로 변경
spec:
  replicas: 3

# 2. Git에 push
git add k8s/
git commit -m "Scale web tier to 3 replicas"
git push

# 3. ArgoCD가 자동으로:
#    - 변경사항 감지
#    - AKS에 적용
#    - Sync 상태 업데이트
```

### Scenario 3: 긴급 롤백

```bash
# 방법 1: ArgoCD UI
# 1. Applications > pocketbank
# 2. History 탭
# 3. 이전 버전 선택 > Rollback

# 방법 2: ArgoCD CLI
argocd app rollback pocketbank <revision-number>

# 방법 3: kubectl
kubectl rollout undo deployment/pocketbank-web -n pocketbank
kubectl rollout undo deployment/pocketbank-was -n pocketbank

# 방법 4: Git revert (권장 - GitOps)
git revert HEAD
git push
# ArgoCD가 자동으로 이전 상태로 복구
```

## 📊 Monitoring

### ArgoCD Dashboard

```bash
# Web UI
http://4.230.156.102

# 확인 항목:
# - Sync Status: Synced / OutOfSync
# - Health Status: Healthy / Degraded / Progressing
# - Last Sync: 마지막 동기화 시간
# - Sync Policy: Auto / Manual
```

### Kubernetes Resources

```bash
# Pods 상태
kubectl get pods -n pocketbank

# Deployments
kubectl get deployments -n pocketbank

# Services
kubectl get svc -n pocketbank

# 이벤트
kubectl get events -n pocketbank --sort-by='.lastTimestamp'

# 로그
kubectl logs -f deployment/pocketbank-web -n pocketbank
kubectl logs -f deployment/pocketbank-was -n pocketbank
```

### Application Gateway

```bash
# Backend health
az network application-gateway show-backend-health \
  --resource-group rg-dr-blue \
  --name appgw-blue

# Backend pool
az network application-gateway address-pool show \
  --resource-group rg-dr-blue \
  --gateway-name appgw-blue \
  --name aks-backend-pool
```

## 🔧 Configuration

### ArgoCD Sync Policy

현재 설정 (자동 동기화):

```yaml
syncPolicy:
  automated:
    prune: true          # 삭제된 리소스 자동 제거
    selfHeal: true       # Drift 발생 시 자동 복구
    allowEmpty: false    # 빈 매니페스트 동기화 방지

  syncOptions:
  - CreateNamespace=true          # 네임스페이스 자동 생성
  - PrunePropagationPolicy=foreground
  - PruneLast=true                # 삭제는 마지막에 수행

  retry:
    limit: 5                      # 재시도 횟수
    backoff:
      duration: 5s                # 초기 대기 시간
      factor: 2                   # 지수 백오프
      maxDuration: 3m             # 최대 대기 시간
```

수동 동기화로 변경하려면:

```yaml
syncPolicy:
  automated: null  # 자동 동기화 비활성화
```

### GitHub Actions Secrets

Repository Settings > Secrets에 추가:

```bash
# Azure 자격증명
AZURE_CREDENTIALS={
  "clientId": "...",
  "clientSecret": "...",
  "subscriptionId": "fdc2f63f-a7bc-4ac7-901a-c730f7d317e9",
  "tenantId": "..."
}

# Database (선택사항)
DB_URL=jdbc:mysql://mysql-dr-blue.mysql.database.azure.com:3306/pocketbank
DB_USERNAME=mysqladmin
DB_PASSWORD=SecureP@ssw0rd123!
```

## 🛠️ Troubleshooting

### ArgoCD Application이 OutOfSync 상태

```bash
# 상태 확인
argocd app get pocketbank

# 수동 동기화
argocd app sync pocketbank

# Hard refresh (캐시 무시)
argocd app sync pocketbank --force

# Prune (삭제된 리소스 정리)
argocd app sync pocketbank --prune
```

### Pod가 ImagePullBackOff

```bash
# Pod 상세 확인
kubectl describe pod <pod-name> -n pocketbank

# 이미지 확인
# cloud039/pocketbank-web:latest
# cloud039/pocketbank-was:latest

# Docker Hub에서 이미지 존재 확인
docker pull cloud039/pocketbank-web:latest
docker pull cloud039/pocketbank-was:latest
```

### ArgoCD가 Git 변경사항을 감지하지 못함

```bash
# Repository 연결 확인
argocd repo list

# 수동 refresh
argocd app get pocketbank --refresh

# ArgoCD 로그 확인
kubectl logs -n argocd deployment/argocd-application-controller
kubectl logs -n argocd deployment/argocd-repo-server
```

### Application Gateway 502 에러

```bash
# Backend pool 확인
az network application-gateway address-pool show \
  --resource-group rg-dr-blue \
  --gateway-name appgw-blue \
  --name aks-backend-pool

# LoadBalancer IP 확인
kubectl get svc pocketbank-web -n pocketbank

# Backend 업데이트
WEB_IP=$(kubectl get svc pocketbank-web -n pocketbank -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

az network application-gateway address-pool update \
  --resource-group rg-dr-blue \
  --gateway-name appgw-blue \
  --name aks-backend-pool \
  --servers $WEB_IP
```

## 📁 Directory Structure

```
3tier-terraform/
├── .github/
│   └── workflows/
│       ├── ci-cd-pocketbank.yaml    # GitHub Actions workflow
│       └── deploy-pocketbank.yml    # Legacy (삭제 가능)
│
├── k8s/                              # GitOps manifests
│   ├── base/
│   │   └── namespace.yaml
│   ├── web/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── was/
│       ├── deployment.yaml
│       └── service.yaml
│
├── argocd-application.yaml          # ArgoCD App 정의
├── CICD-ARGOCD-GUIDE.md             # 이 문서
└── CI-CD-GUIDE.md                   # Legacy guide
```

## 🎓 Best Practices

### 1. Git as Single Source of Truth
- 모든 변경사항은 Git을 통해 관리
- 직접 `kubectl apply` 사용 지양
- Emergency 상황에서만 수동 개입

### 2. Immutable Infrastructure
- Docker 이미지는 태그로 버전 관리
- `latest` 태그 사용 지양 (운영 환경)
- Semantic versioning 권장 (v1.2.3)

### 3. Progressive Rollout
- Blue/Green 배포 고려
- Canary 배포 구현 (ArgoCD Rollouts)
- 자동 롤백 정책 설정

### 4. Security
- Secrets는 Git에 커밋하지 않음
- Sealed Secrets 또는 External Secrets 사용
- RBAC 적절히 설정

### 5. Monitoring & Alerting
- ArgoCD Notifications 설정
- Prometheus + Grafana 연동
- Slack/Email 알림 구성

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://www.gitops.tech/)
- [GitHub Actions Docs](https://docs.github.com/actions)
- [Azure AKS Best Practices](https://docs.microsoft.com/azure/aks/)

## ✅ Current Status

```
✅ ArgoCD installed and running
✅ PocketBank web deployed (2 replicas)
✅ PocketBank was deployed (2 replicas)
✅ LoadBalancer IP assigned: 4.230.55.106
✅ Application Gateway configured: 4.230.65.57
✅ GitHub Actions workflow created
✅ GitOps structure ready

🔗 Access URLs:
- ArgoCD UI: http://4.230.156.102
- PocketBank Web: http://4.230.55.106
- Application Gateway: http://4.230.65.57
```

---

**작성:** I2ST Blue Team
**최종 업데이트:** 2025-12-28
**버전:** 1.0
