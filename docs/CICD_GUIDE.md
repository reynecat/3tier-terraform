# CI/CD 파이프라인 가이드

이 문서는 AWS EKS와 Azure AKS 환경에서의 CI/CD 파이프라인 구성 및 운영 방법을 설명합니다.

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [Option A: Jenkins + ArgoCD](#option-a-jenkins--argocd)
3. [Option B: GitHub Actions + ArgoCD](#option-b-github-actions--argocd)
4. [ArgoCD 설정](#argocd-설정)
5. [GitOps 레포지토리 구조](#gitops-레포지토리-구조)
6. [환경별 설정](#환경별-설정)
7. [배포 절차](#배포-절차)
8. [롤백 절차](#롤백-절차)
9. [모니터링 및 알림](#모니터링-및-알림)
10. [보안 고려사항](#보안-고려사항)
11. [트러블슈팅](#트러블슈팅)

---

## 아키텍처 개요

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CI/CD Pipeline Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────┐    ┌────────────────────┐    ┌───────────────────────┐   │
│  │   GitHub     │───▶│  CI (Jenkins or    │───▶│  Container Registry   │   │
│  │  Repository  │    │  GitHub Actions)   │    │  (DockerHub)          │   │
│  └──────────────┘    └────────────────────┘    └───────────────────────┘   │
│         │                     │                          │                  │
│         │                     │                          │                  │
│         ▼                     ▼                          │                  │
│  ┌──────────────┐    ┌────────────────────┐              │                  │
│  │   GitOps     │◀───│  Update Image Tag  │              │                  │
│  │  Repository  │    │  (Kustomize)       │              │                  │
│  └──────────────┘    └────────────────────┘              │                  │
│         │                                                │                  │
│         │                                                │                  │
│         ▼                                                ▼                  │
│  ┌──────────────┐    ┌────────────────────┐    ┌───────────────────────┐   │
│  │   ArgoCD     │───▶│  Kubernetes        │◀───│  Pull Image           │   │
│  │   (CD)       │    │  Cluster           │    │                       │   │
│  └──────────────┘    └────────────────────┘    └───────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 주요 컴포넌트

| 컴포넌트 | 역할 | AWS | Azure |
|---------|------|-----|-------|
| CI Tool | 빌드, 테스트, 이미지 생성 | Jenkins / GitHub Actions | Jenkins / GitHub Actions |
| Container Registry | 이미지 저장소 | DockerHub | DockerHub |
| CD Tool | GitOps 기반 배포 | ArgoCD | ArgoCD |
| Kubernetes | 워크로드 실행 | Amazon EKS | Azure AKS |

---

## Option A: Jenkins + ArgoCD

### 사전 요구사항

1. **Jenkins 설치**
   ```bash
   # Helm 레포지토리 추가
   helm repo add jenkins https://charts.jenkins.io
   helm repo update

   # AWS EKS
   cd codes/aws/4-cicd/jenkins
   kubectl create namespace jenkins
   helm install jenkins jenkins/jenkins -f jenkins-values.yaml -n jenkins

   # Azure AKS
   cd codes/azure/4-cicd/jenkins
   kubectl create namespace jenkins
   helm install jenkins jenkins/jenkins -f jenkins-values.yaml -n jenkins
   ```

2. **Jenkins 초기 비밀번호 확인**
   ```bash
   kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- \
     /bin/cat /run/secrets/additional/chart-admin-password
   ```

3. **필수 플러그인 확인**
   - Kubernetes
   - Pipeline
   - Git
   - Docker Pipeline
   - AWS Credentials (AWS)
   - Azure Credentials (Azure)
   - SonarQube Scanner
   - Slack Notification

### Jenkins 파이프라인 단계

```
┌────────────┐    ┌────────────┐    ┌────────────┐    ┌────────────┐
│  Checkout  │───▶│   Build    │───▶│   Test     │───▶│  Analyze   │
└────────────┘    └────────────┘    └────────────┘    └────────────┘
                                                             │
┌────────────┐    ┌────────────┐    ┌────────────┐          │
│  Verify    │◀───│  Sync      │◀───│  Update    │◀─────────┘
│ Deployment │    │  ArgoCD    │    │  GitOps    │
└────────────┘    └────────────┘    └────────────┘
      │
      ▼
┌────────────┐    ┌────────────┐
│   Push     │◀───│  Security  │
│   Image    │    │   Scan     │
└────────────┘    └────────────┘
```

### Jenkins 자격 증명 설정

```groovy
// AWS 자격 증명
withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                  credentialsId: 'aws-credentials']]) {
    // AWS CLI 명령 실행
}

// Azure 자격 증명
withCredentials([azureServicePrincipal('azure-service-principal')]) {
    // Azure CLI 명령 실행
}
```

---

## Option B: GitHub Actions + ArgoCD

### 사전 요구사항

1. **GitHub Secrets 설정**

   **공통 (DockerHub):**
   | Secret Name | 설명 |
   |-------------|------|
   | `DOCKERHUB_USERNAME` | DockerHub 사용자명 |
   | `DOCKERHUB_TOKEN` | DockerHub Access Token |

   **AWS 환경:**
   | Secret Name | 설명 |
   |-------------|------|
   | `AWS_ACCESS_KEY_ID` | AWS Access Key |
   | `AWS_SECRET_ACCESS_KEY` | AWS Secret Key |
   | `SONAR_TOKEN` | SonarQube 토큰 |
   | `GITOPS_TOKEN` | GitOps 레포 접근 토큰 |
   | `ARGOCD_SERVER` | ArgoCD 서버 주소 |
   | `ARGOCD_AUTH_TOKEN` | ArgoCD 인증 토큰 |
   | `SLACK_WEBHOOK_URL` | Slack 알림 URL |

   **Azure 환경:**
   | Secret Name | 설명 |
   |-------------|------|
   | `AZURE_CREDENTIALS` | Azure 서비스 프린시펄 JSON |
   | `ARGOCD_SERVER_AZURE` | ArgoCD 서버 주소 |
   | `ARGOCD_AUTH_TOKEN_AZURE` | ArgoCD 인증 토큰 |
   | `TEAMS_WEBHOOK_URL` | Teams 알림 URL |

2. **워크플로우 파일 위치**
   ```
   .github/workflows/
   ├── ci-cd-aws.yaml      # AWS용 워크플로우
   └── ci-cd-azure.yaml    # Azure용 워크플로우
   ```

### GitHub Actions 워크플로우 구조

```yaml
jobs:
  build:           # 빌드 및 테스트
  code-quality:    # SonarQube 분석
  security-scan:   # OWASP, Trivy 스캔
  docker:          # 이미지 빌드 및 푸시
  update-gitops:   # GitOps 레포 업데이트
  argocd-sync:     # ArgoCD 동기화
  verify:          # 배포 검증
```

---

## ArgoCD 설정

### ArgoCD 설치

```bash
# Helm 레포지토리 추가
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# ArgoCD 설치 (AWS)
kubectl create namespace argocd
cd codes/aws/4-cicd/argocd
helm install argocd argo/argo-cd -f argocd-values.yaml -n argocd

# ArgoCD 설치 (Azure)
kubectl create namespace argocd
cd codes/azure/4-cicd/argocd
helm install argocd argo/argo-cd -f argocd-values.yaml -n argocd
```

### 초기 비밀번호 확인

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### ArgoCD Application 생성

```bash
# AWS용 Application
kubectl apply -f codes/aws/4-cicd/argocd/application.yaml

# Azure용 Application
kubectl apply -f codes/azure/4-cicd/argocd/application.yaml
```

### ArgoCD CLI 사용

```bash
# 로그인
argocd login argocd.example.com --username admin --password <password>

# 애플리케이션 목록 확인
argocd app list

# 애플리케이션 상태 확인
argocd app get pocketbank-aws
argocd app get pocketbank-azure

# 수동 동기화
argocd app sync pocketbank-aws

# 히스토리 확인
argocd app history pocketbank-aws
```

---

## GitOps 레포지토리 구조

```
pocketbank-gitops/
├── base/                          # 기본 Kubernetes 매니페스트
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── hpa.yaml
│   └── serviceaccount.yaml
│
├── overlays/                      # 환경별 오버레이
│   ├── aws-dev/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   │       ├── deployment-patch.yaml
│   │       └── ingress-patch.yaml
│   │
│   ├── aws-staging/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   │
│   ├── aws-prod/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   │       ├── deployment-patch.yaml
│   │       └── ingress-patch.yaml
│   │
│   ├── azure-dev/
│   │   ├── kustomization.yaml
│   │   └── patches/
│   │
│   └── azure-prod/
│       ├── kustomization.yaml
│       └── patches/
│           ├── deployment-patch.yaml
│           └── ingress-azure-patch.yaml
│
└── charts/                        # Helm 차트 (선택사항)
    └── pocketbank/
        ├── Chart.yaml
        ├── values.yaml
        └── templates/
```

### Kustomization 예시

```yaml
# overlays/aws-prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: pocketbank

resources:
  - ../../base

commonLabels:
  environment: production
  cloud: aws

images:
  - name: pocketbank
    newName: ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com/pocketbank
    newTag: 20241227-abc1234

patches:
  - path: patches/deployment-patch.yaml
  - path: patches/ingress-patch.yaml

replicas:
  - name: pocketbank
    count: 3
```

---

## 환경별 설정

### AWS 환경

| 항목 | 값 |
|------|-----|
| Container Registry | DockerHub |
| Kubernetes | Amazon EKS |
| Ingress Controller | AWS Load Balancer Controller |
| TLS Certificate | AWS Certificate Manager (ACM) |
| Secrets Management | AWS Secrets Manager / External Secrets |

### Azure 환경

| 항목 | 값 |
|------|-----|
| Container Registry | DockerHub |
| Kubernetes | Azure Kubernetes Service (AKS) |
| Ingress Controller | Application Gateway Ingress Controller (AGIC) |
| TLS Certificate | Azure Key Vault |
| Secrets Management | Azure Key Vault / External Secrets |

---

## 배포 절차

### 자동 배포 (GitOps)

1. **코드 변경 푸시**
   ```bash
   git add .
   git commit -m "feat: Add new feature"
   git push origin main
   ```

2. **CI 파이프라인 자동 실행**
   - 빌드 → 테스트 → 이미지 빌드 → 보안 스캔 → 이미지 푸시

3. **GitOps 레포지토리 업데이트**
   - CI에서 새 이미지 태그로 kustomization.yaml 업데이트

4. **ArgoCD 자동 동기화**
   - ArgoCD가 변경 감지 후 자동 배포
   - 또는 수동 동기화: `argocd app sync pocketbank-aws`

### 수동 배포

```bash
# 1. 이미지 태그 확인 (DockerHub)
# DockerHub 웹사이트 또는 Docker CLI로 확인
docker search <DOCKERHUB_USERNAME>/pocketbank

# 2. GitOps 레포에서 태그 업데이트
cd pocketbank-gitops/overlays/aws-prod
kustomize edit set image pocketbank=<DOCKERHUB_USERNAME>/pocketbank:NEW_TAG

# 3. 커밋 및 푸시
git add .
git commit -m "chore: Update image tag to NEW_TAG"
git push origin main

# 4. ArgoCD 동기화
argocd app sync pocketbank-aws
argocd app wait pocketbank-aws --timeout 300
```

---

## 롤백 절차

### ArgoCD를 통한 롤백

```bash
# 히스토리 확인
argocd app history pocketbank-aws

# 특정 리비전으로 롤백
argocd app rollback pocketbank-aws <REVISION_NUMBER>

# 롤백 상태 확인
argocd app get pocketbank-aws
```

### Kubernetes를 통한 롤백

```bash
# 배포 히스토리 확인
kubectl rollout history deployment/pocketbank -n pocketbank

# 이전 버전으로 롤백
kubectl rollout undo deployment/pocketbank -n pocketbank

# 특정 리비전으로 롤백
kubectl rollout undo deployment/pocketbank -n pocketbank --to-revision=2

# 롤백 상태 확인
kubectl rollout status deployment/pocketbank -n pocketbank
```

### GitOps 롤백

```bash
# 이전 커밋으로 되돌리기
cd pocketbank-gitops
git revert HEAD
git push origin main

# ArgoCD 동기화
argocd app sync pocketbank-aws
```

---

## 모니터링 및 알림

### Slack 알림 설정

```yaml
# ArgoCD Notifications
notifications:
  notifiers:
    service.slack: |
      token: $slack-token

  triggers:
    trigger.on-deployed: |
      - when: app.status.operationState.phase in ['Succeeded']
        send: [app-deployed]
    trigger.on-sync-failed: |
      - when: app.status.operationState.phase in ['Error', 'Failed']
        send: [app-sync-failed]
```

### Microsoft Teams 알림 (Azure)

```yaml
notifications:
  notifiers:
    service.teams: |
      webhookUrl: $teams-webhook-url
```

### 메트릭 수집

ArgoCD는 Prometheus 메트릭을 제공합니다:

```bash
# 메트릭 엔드포인트
curl http://argocd-metrics.argocd:8082/metrics

# 주요 메트릭
argocd_app_info                    # 애플리케이션 정보
argocd_app_sync_total              # 동기화 총 횟수
argocd_app_health_status           # 헬스 상태
argocd_app_reconcile_duration      # 조정 소요 시간
```

---

## 보안 고려사항

### Secrets 관리

1. **Sealed Secrets 사용**
   ```bash
   # kubeseal 설치
   brew install kubeseal

   # Secret 암호화
   kubeseal --format yaml < secret.yaml > sealed-secret.yaml
   ```

2. **External Secrets Operator**
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: pocketbank-db-secret
   spec:
     secretStoreRef:
       name: aws-secrets-manager  # 또는 azure-keyvault
       kind: SecretStore
     target:
       name: pocketbank-db-secret
     data:
       - secretKey: password
         remoteRef:
           key: pocketbank/database
           property: password
   ```

### 이미지 보안

1. **Trivy 스캔 정책**
   - HIGH, CRITICAL 취약점 발견 시 빌드 실패
   - 정기적인 베이스 이미지 업데이트

2. **이미지 서명 (선택사항)**
   ```bash
   # Cosign으로 이미지 서명
   cosign sign --key cosign.key <DOCKERHUB_USERNAME>/<REPOSITORY>:${IMAGE_TAG}
   ```

### RBAC 설정

```yaml
# ArgoCD RBAC 정책
rbac:
  policy.csv: |
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, sync, */pocketbank-dev, allow
    p, role:admin, applications, *, */*, allow
    g, DevOps-Team, role:admin
    g, Developers, role:developer
```

---

## 트러블슈팅

### 일반적인 문제

#### 1. ArgoCD 동기화 실패

```bash
# 애플리케이션 상태 확인
argocd app get pocketbank-aws

# 상세 이벤트 확인
kubectl describe application pocketbank-aws -n argocd

# 동기화 로그 확인
argocd app logs pocketbank-aws
```

#### 2. 이미지 풀 실패

```bash
# Pod 상태 확인
kubectl describe pod -l app=pocketbank -n pocketbank

# DockerHub 인증 확인
docker login -u <DOCKERHUB_USERNAME>

# Kubernetes에서 DockerHub 인증 설정 (Private Repository인 경우)
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=<DOCKERHUB_USERNAME> \
  --docker-password=<DOCKERHUB_TOKEN> \
  --docker-email=<EMAIL> \
  -n pocketbank
```

#### 3. Jenkins 빌드 실패

```bash
# Jenkins 로그 확인
kubectl logs -f -l app.kubernetes.io/name=jenkins -n jenkins

# Agent Pod 상태 확인
kubectl get pods -n jenkins -l jenkins/label=maven
```

#### 4. 배포 후 헬스체크 실패

```bash
# Pod 로그 확인
kubectl logs -f deployment/pocketbank -n pocketbank

# 헬스 엔드포인트 직접 확인
kubectl port-forward svc/pocketbank 8080:80 -n pocketbank
curl http://localhost:8080/actuator/health
```

### 유용한 명령어

```bash
# ArgoCD 애플리케이션 강제 동기화
argocd app sync pocketbank-aws --force

# ArgoCD 캐시 무효화
argocd app terminate-op pocketbank-aws
argocd app sync pocketbank-aws --prune

# 모든 리소스 상태 확인
argocd app resources pocketbank-aws

# GitOps 레포와의 차이 확인
argocd app diff pocketbank-aws
```

---

## 참고 자료

- [ArgoCD 공식 문서](https://argo-cd.readthedocs.io/)
- [Jenkins 공식 문서](https://www.jenkins.io/doc/)
- [GitHub Actions 문서](https://docs.github.com/en/actions)
- [Kustomize 문서](https://kustomize.io/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Azure AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
