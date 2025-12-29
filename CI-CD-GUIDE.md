# PocketBank CI/CD Pipeline Guide

## 🚀 개요

PocketBank 애플리케이션을 위한 완전 자동화된 CI/CD 파이프라인입니다. GitHub Actions를 사용하여 코드 푸시 시 자동으로 빌드, 테스트, 배포가 진행됩니다.

## 📋 목차

- [아키텍처](#아키텍처)
- [사전 요구사항](#사전-요구사항)
- [GitHub Secrets 설정](#github-secrets-설정)
- [로컬 개발](#로컬-개발)
- [자동 배포](#자동-배포)
- [수동 배포](#수동-배포)

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
│                                                               │
│  app/                                                         │
│  ├── Dockerfile          # 애플리케이션 이미지 빌드          │
│  ├── nginx.conf          # Nginx 설정                        │
│  └── public/                                                 │
│      └── index.html      # PocketBank 웹 UI                  │
│                                                               │
│  .github/workflows/                                          │
│  └── deploy-pocketbank.yml  # CI/CD 파이프라인              │
└───────────────────┬─────────────────────────────────────────┘
                    │ Push to main
                    ▼
        ┌───────────────────────┐
        │   GitHub Actions      │
        │   1. Build Image      │
        │   2. Push to DockerHub│
        │   3. Deploy to AKS    │
        └───────────┬───────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌──────────────────┐   ┌─────────────────────┐
│   Docker Hub     │   │    Azure AKS        │
│                  │   │                     │
│ cloud039/        │   │  ┌───────────────┐  │
│  pocketbank      │──▶│  │   Pods        │  │
│   :latest        │   │  │  (2 replicas) │  │
│   :sha-xxxxxxx   │   │  └───────────────┘  │
└──────────────────┘   └─────────────────────┘
```

## 📦 사전 요구사항

### 1. Docker Hub 계정
- https://hub.docker.com 에서 계정 생성
- Personal Access Token 생성

### 2. Azure 자격증명
- Azure Portal에서 Service Principal 생성
- AKS 클러스터에 대한 접근 권한

### 3. 필요한 도구
```bash
# 로컬 개발 시 필요
- Docker Desktop
- kubectl
- Azure CLI
```

## 🔐 GitHub Secrets 설정

Repository Settings > Secrets and variables > Actions에서 다음 Secrets를 추가하세요:

### Docker Hub Secrets
```
DOCKER_USERNAME=cloud039
DOCKER_PASSWORD=<your-docker-hub-token>
```

### Azure Secrets
```bash
# Azure Service Principal 생성
az ad sp create-for-rbac \
  --name "github-actions-pocketbank" \
  --role contributor \
  --scopes /subscriptions/{subscription-id}/resourceGroups/rg-dr-blue \
  --sdk-auth

# 출력 결과를 AZURE_CREDENTIALS로 저장
```

```json
AZURE_CREDENTIALS={
  "clientId": "<client-id>",
  "clientSecret": "<client-secret>",
  "subscriptionId": "<subscription-id>",
  "tenantId": "<tenant-id>"
}
```

### Database Secrets
```
DB_URL=jdbc:mysql://mysql-dr-blue.mysql.database.azure.com:3306/pocketbank
DB_USERNAME=mysqladmin
DB_PASSWORD=<your-mysql-password>
```

## 💻 로컬 개발

### 1. 애플리케이션 수정

```bash
# HTML 편집
nano app/public/index.html

# Nginx 설정 수정
nano app/nginx.conf
```

### 2. 로컬 빌드 및 테스트

```bash
# Docker 이미지 빌드
cd app
docker build -t pocketbank:local .

# 로컬에서 실행
docker run -d -p 8080:80 pocketbank:local

# 테스트
curl http://localhost:8080
```

### 3. 로컬에서 AKS에 직접 배포 (선택사항)

```bash
# ConfigMap 업데이트
kubectl create configmap pocketbank-html \
  --from-file=index.html=app/public/index.html \
  -n pocketbank \
  --dry-run=client -o yaml | kubectl apply -f -

# Deployment 재시작
kubectl rollout restart deployment/pocketbank -n pocketbank
```

## 🚀 자동 배포

### 트리거 조건

다음 조건에서 자동으로 배포가 시작됩니다:

1. **main 브랜치에 Push**
   ```bash
   git add app/
   git commit -m "Update PocketBank UI"
   git push origin main
   ```

2. **app/ 디렉토리 변경 시**
   - app/public/index.html
   - app/Dockerfile
   - app/nginx.conf

3. **수동 트리거**
   - GitHub Actions 탭에서 "Run workflow" 클릭

### 배포 프로세스

```
1. Checkout Code          (5초)
   └─ Git clone

2. Build Docker Image      (30-60초)
   ├─ Docker Buildx setup
   ├─ Build multi-arch image
   └─ Cache layers

3. Push to Docker Hub      (10-20초)
   ├─ Tag: latest
   └─ Tag: sha-xxxxxxx

4. Deploy to AKS          (30-60초)
   ├─ Azure login
   ├─ Get AKS credentials
   ├─ Update deployment
   └─ Wait for rollout

Total: ~2-3분
```

### 배포 확인

```bash
# GitHub Actions 로그 확인
https://github.com/<your-repo>/actions

# AKS에서 확인
kubectl get pods -n pocketbank
kubectl describe deployment pocketbank -n pocketbank

# 실행 중인 이미지 태그 확인
kubectl get deployment pocketbank -n pocketbank \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

## 🛠️ 수동 배포

### 방법 1: kubectl (ConfigMap 사용)

```bash
# 1. HTML을 ConfigMap으로 생성
kubectl create configmap pocketbank-html \
  --from-file=index.html=app/public/index.html \
  -n pocketbank -o yaml --dry-run=client | kubectl apply -f -

# 2. Deployment 업데이트
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pocketbank
  namespace: pocketbank
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pocketbank
  template:
    metadata:
      labels:
        app: pocketbank
    spec:
      containers:
      - name: pocketbank
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: html-volume
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html-volume
        configMap:
          name: pocketbank-html
EOF

# 3. 배포 확인
kubectl rollout status deployment/pocketbank -n pocketbank
```

### 방법 2: Docker Hub 이미지 사용

```bash
# 1. 이미지 빌드 및 푸시
docker build -t cloud039/pocketbank:v1.0 app/
docker push cloud039/pocketbank:v1.0

# 2. AKS에 배포
kubectl set image deployment/pocketbank \
  pocketbank=cloud039/pocketbank:v1.0 \
  -n pocketbank

# 3. 롤아웃 대기
kubectl rollout status deployment/pocketbank -n pocketbank
```

## 📊 모니터링

### 배포 상태 확인

```bash
# Pods 상태
kubectl get pods -n pocketbank -w

# Deployment 이벤트
kubectl describe deployment pocketbank -n pocketbank

# 로그 확인
kubectl logs -f deployment/pocketbank -n pocketbank --tail=100
```

### Application Gateway 접근

```bash
# Public IP 확인
terraform output -raw appgw_public_ip

# 웹 접속
curl http://$(terraform output -raw appgw_public_ip)
```

### LoadBalancer 직접 접근

```bash
# Service IP 확인
kubectl get svc pocketbank -n pocketbank \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# 웹 접속
curl http://$(kubectl get svc pocketbank -n pocketbank \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):8080
```

## 🔄 롤백

### GitHub Actions를 통한 롤백

```bash
# 1. 이전 커밋으로 되돌리기
git revert HEAD
git push origin main

# 2. 특정 커밋으로 되돌리기
git reset --hard <commit-sha>
git push -f origin main
```

### kubectl을 통한 롤백

```bash
# 이전 버전으로 롤백
kubectl rollout undo deployment/pocketbank -n pocketbank

# 특정 리비전으로 롤백
kubectl rollout history deployment/pocketbank -n pocketbank
kubectl rollout undo deployment/pocketbank -n pocketbank --to-revision=2
```

## 🐛 트러블슈팅

### 이미지 Pull 실패

```bash
# Docker Hub 자격증명 확인
kubectl get secret -n pocketbank

# 새로운 Secret 생성 (필요시)
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=cloud039 \
  --docker-password=<token> \
  -n pocketbank
```

### Pod가 Ready 상태가 되지 않음

```bash
# Pod 로그 확인
kubectl logs <pod-name> -n pocketbank

# Pod 이벤트 확인
kubectl describe pod <pod-name> -n pocketbank

# Health check 확인
kubectl exec <pod-name> -n pocketbank -- wget -O- http://localhost/health
```

### GitHub Actions 실패

1. **Azure 로그인 실패**
   - AZURE_CREDENTIALS Secret 확인
   - Service Principal 권한 확인

2. **Docker Hub Push 실패**
   - DOCKER_USERNAME, DOCKER_PASSWORD Secret 확인
   - Docker Hub 계정 상태 확인

3. **AKS 배포 실패**
   - kubectl 권한 확인
   - Namespace 존재 여부 확인

## 📈 성능 최적화

### 빌드 캐시 활용

```yaml
# .github/workflows/deploy-pocketbank.yml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max  # GitHub Actions 캐시 사용
```

### Multi-stage Build (향후 적용 가능)

```dockerfile
# 빌드 단계
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# 실행 단계
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
```

## 📚 추가 리소스

- [GitHub Actions 문서](https://docs.github.com/actions)
- [Docker Hub 문서](https://docs.docker.com/docker-hub/)
- [Azure AKS 문서](https://docs.microsoft.com/azure/aks/)
- [Kubernetes 문서](https://kubernetes.io/docs/)

---

**작성:** I2ST Blue Team
**최종 업데이트:** 2025-12-28
**버전:** 1.0
