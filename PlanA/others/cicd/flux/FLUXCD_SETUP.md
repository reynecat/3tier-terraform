# FluxCD GitOps 설치 가이드

## 개요

FluxCD는 Kubernetes용 GitOps 도구로, Git 저장소의 변경사항을 자동으로 클러스터에 적용합니다.

## 아키텍처

```
GitHub Repository (k8s-manifests)
         │
         ├─ manifests/
         │   ├─ web-deployment.yaml
         │   ├─ was-deployment.yaml
         │   └─ services.yaml
         │
         ▼
    Flux Source Controller
         │
         ├─ 5분마다 Git 폴링
         ├─ 변경사항 감지
         │
         ▼
    Flux Kustomize Controller
         │
         ├─ 매니페스트 적용
         │
         ▼
    AWS EKS Cluster
         │
         ├─ Web Pods
         └─ WAS Pods
```

## 1. FluxCD CLI 설치

### macOS

```bash
brew install fluxcd/tap/flux
```

### Linux

```bash
curl -s https://fluxcd.io/install.sh | sudo bash

# 또는 바이너리 직접 다운로드
wget https://github.com/fluxcd/flux2/releases/download/v2.2.0/flux_2.2.0_linux_amd64.tar.gz
tar -xzf flux_2.2.0_linux_amd64.tar.gz
sudo mv flux /usr/local/bin/

# 설치 확인
flux --version
```

### 사전 요구사항 확인

```bash
# Kubernetes 클러스터 연결 확인
kubectl cluster-info

# Flux 설치 가능 여부 확인
flux check --pre
```

## 2. FluxCD 설치

### GitHub Personal Access Token 생성

1. GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token (classic)
3. 필요한 권한:
   - `repo` (전체)
   - `workflow`
4. Token 저장: `ghp_xxxxxxxxxxxxxxxxxxxx`

### Flux 부트스트랩 (GitHub)

```bash
# GitHub Token 환경변수 설정
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
export GITHUB_USER=YOUR_GITHUB_USERNAME
export GITHUB_REPO=k8s-manifests

# Flux 설치 및 GitHub 연동
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=./clusters/aws-prod \
  --personal \
  --token-auth

# 설치 확인
flux check

# 기대 출력:
# ✔ all checks passed
```

### 설치된 컴포넌트 확인

```bash
# Flux 네임스페이스 및 Pod 확인
kubectl get pods -n flux-system

# 기대 출력:
# source-controller-xxxxx          1/1     Running
# kustomize-controller-xxxxx       1/1     Running
# helm-controller-xxxxx            1/1     Running
# notification-controller-xxxxx    1/1     Running
# image-reflector-controller-xxxxx 1/1     Running
# image-automation-controller-xxxxx 1/1     Running
```

## 3. Git 저장소 구조 설정

### 디렉토리 구조

```
k8s-manifests/
├── clusters/
│   ├── aws-prod/
│   │   ├── flux-system/           # Flux 자체 설정
│   │   │   ├── gotk-components.yaml
│   │   │   ├── gotk-sync.yaml
│   │   │   └── kustomization.yaml
│   │   └── apps/                  # 애플리케이션 설정
│   │       ├── sources.yaml       # GitRepository 정의
│   │       ├── kustomizations.yaml # Kustomization 정의
│   │       └── namespaces.yaml    # Namespace 생성
│   └── azure-dr/                  # Azure DR (선택사항)
│
├── apps/
│   └── petclinic/
│       ├── base/                  # 기본 매니페스트
│       │   ├── namespace.yaml
│       │   ├── web-deployment.yaml
│       │   ├── was-deployment.yaml
│       │   ├── services.yaml
│       │   ├── configmap.yaml
│       │   └── kustomization.yaml
│       └── overlays/
│           ├── prod/              # 프로덕션 오버레이
│           │   ├── kustomization.yaml
│           │   └── replicas.yaml
│           └── dev/               # 개발 오버레이
│               ├── kustomization.yaml
│               └── replicas.yaml
└── infrastructure/
    ├── ingress-nginx/
    └── cert-manager/
```

## 4. GitRepository 생성

```yaml
# clusters/aws-prod/apps/sources.yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: petclinic-repo
  namespace: flux-system
spec:
  interval: 5m0s
  url: https://github.com/${GITHUB_USER}/k8s-manifests
  ref:
    branch: main
  secretRef:
    name: flux-system
```

## 5. Kustomization 생성

```yaml
# clusters/aws-prod/apps/kustomizations.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: petclinic-app
  namespace: flux-system
spec:
  interval: 10m0s
  sourceRef:
    kind: GitRepository
    name: petclinic-repo
  path: ./apps/petclinic/overlays/prod
  prune: true
  wait: true
  timeout: 5m0s
  validation: client
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: petclinic-web
      namespace: petclinic
    - apiVersion: apps/v1
      kind: Deployment
      name: petclinic-was
      namespace: petclinic
```

## 6. 애플리케이션 매니페스트

### Namespace

```yaml
# apps/petclinic/base/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: petclinic
  labels:
    app: petclinic
```

### Web Deployment

```yaml
# apps/petclinic/base/web-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic-web
  namespace: petclinic
spec:
  replicas: 2
  selector:
    matchLabels:
      app: petclinic
      tier: web
  template:
    metadata:
      labels:
        app: petclinic
        tier: web
    spec:
      nodeSelector:
        tier: web
      containers:
      - name: nginx
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: petclinic-web-service
  namespace: petclinic
spec:
  type: LoadBalancer
  selector:
    app: petclinic
    tier: web
  ports:
  - port: 80
    targetPort: 80
```

### WAS Deployment

```yaml
# apps/petclinic/base/was-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic-was
  namespace: petclinic
spec:
  replicas: 2
  selector:
    matchLabels:
      app: petclinic
      tier: was
  template:
    metadata:
      labels:
        app: petclinic
        tier: was
    spec:
      nodeSelector:
        tier: was
      containers:
      - name: petclinic
        image: YOUR_DOCKERHUB_USERNAME/petclinic:latest
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "mysql"
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            configMapKeyRef:
              name: petclinic-config
              key: SPRING_DATASOURCE_URL
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: petclinic-secret
              key: SPRING_DATASOURCE_USERNAME
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: petclinic-secret
              key: SPRING_DATASOURCE_PASSWORD
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /actuator/health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: petclinic-was-service
  namespace: petclinic
spec:
  type: ClusterIP
  selector:
    app: petclinic
    tier: was
  ports:
  - port: 8080
    targetPort: 8080
```

### Kustomization (Base)

```yaml
# apps/petclinic/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: petclinic

resources:
  - namespace.yaml
  - web-deployment.yaml
  - was-deployment.yaml
  - configmap.yaml
  - secret.yaml

configMapGenerator:
  - name: nginx-config
    files:
      - default.conf

images:
  - name: YOUR_DOCKERHUB_USERNAME/petclinic
    newTag: latest
```

### Overlay (Production)

```yaml
# apps/petclinic/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: petclinic

bases:
  - ../../base

patchesStrategicMerge:
  - replicas.yaml

images:
  - name: YOUR_DOCKERHUB_USERNAME/petclinic
    newTag: v1.0.0  # Production tag
```

```yaml
# apps/petclinic/overlays/prod/replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic-web
spec:
  replicas: 3
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic-was
spec:
  replicas: 3
```

## 7. 이미지 자동 업데이트 설정

### ImageRepository 생성

```yaml
# clusters/aws-prod/apps/image-repository.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: petclinic-image
  namespace: flux-system
spec:
  image: YOUR_DOCKERHUB_USERNAME/petclinic
  interval: 5m0s
  secretRef:
    name: dockerhub-credentials
```

### ImagePolicy 생성

```yaml
# clusters/aws-prod/apps/image-policy.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: petclinic-policy
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: petclinic-image
  policy:
    semver:
      range: 1.0.x  # 1.0.0 ~ 1.0.9 자동 업데이트
```

### ImageUpdateAutomation 생성

```yaml
# clusters/aws-prod/apps/image-automation.yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: petclinic-automation
  namespace: flux-system
spec:
  interval: 30m0s
  sourceRef:
    kind: GitRepository
    name: petclinic-repo
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxcd@example.com
        name: FluxCD
      messageTemplate: |
        Automated image update
        
        Automation name: {{ .AutomationObject }}
        
        Files:
        {{ range $filename, $_ := .Updated.Files -}}
        - {{ $filename }}
        {{ end -}}
        
        Objects:
        {{ range $resource, $_ := .Updated.Objects -}}
        - {{ $resource.Kind }} {{ $resource.Name }}
        {{ end -}}
        
        Images:
        {{ range .Updated.Images -}}
        - {{.}}
        {{ end -}}
  update:
    path: ./apps/petclinic/overlays/prod
    strategy: Setters
```

### Deployment에 마커 추가

```yaml
# apps/petclinic/base/was-deployment.yaml에 추가
spec:
  template:
    spec:
      containers:
      - name: petclinic
        image: YOUR_DOCKERHUB_USERNAME/petclinic:latest # {"$imagepolicy": "flux-system:petclinic-policy"}
```

## 8. DockerHub Credentials 설정

```bash
# DockerHub 인증 정보로 Secret 생성
kubectl create secret docker-registry dockerhub-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKERHUB_USERNAME \
  --docker-password=YOUR_DOCKERHUB_PASSWORD \
  --docker-email=YOUR_EMAIL \
  -n flux-system
```

## 9. Flux 모니터링

### CLI로 상태 확인

```bash
# Flux 전체 상태
flux get all

# GitRepository 상태
flux get sources git

# Kustomization 상태
flux get kustomizations

# ImageRepository 상태
flux get images repository

# ImagePolicy 상태
flux get images policy

# 실시간 로그
flux logs --follow --all-namespaces
```

### 수동 동기화

```bash
# GitRepository 즉시 동기화
flux reconcile source git petclinic-repo

# Kustomization 즉시 적용
flux reconcile kustomization petclinic-app

# 이미지 스캔 즉시 실행
flux reconcile image repository petclinic-image
```

### Suspend/Resume

```bash
# Kustomization 일시 중지
flux suspend kustomization petclinic-app

# Kustomization 재개
flux resume kustomization petclinic-app
```

## 10. Slack 알림 설정

### Slack Webhook URL 생성

1. Slack → Apps → Incoming Webhooks
2. Add to Slack
3. Webhook URL 복사

### Provider 생성

```yaml
# clusters/aws-prod/apps/notification-provider.yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: "#gitops-notifications"
  address: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### Alert 생성

```yaml
# clusters/aws-prod/apps/alert.yaml
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: petclinic-alert
  namespace: flux-system
spec:
  summary: "PetClinic Deployment Alerts"
  providerRef:
    name: slack
  eventSeverity: info
  eventSources:
    - kind: GitRepository
      name: petclinic-repo
    - kind: Kustomization
      name: petclinic-app
  suspend: false
```

## 11. 문제 해결

### GitRepository 동기화 실패

```bash
# 상태 확인
flux get sources git petclinic-repo

# 상세 정보
kubectl describe gitrepository petclinic-repo -n flux-system

# Secret 확인
kubectl get secret flux-system -n flux-system
```

### Kustomization 적용 실패

```bash
# 상태 확인
flux get kustomizations

# 로그 확인
flux logs --kind=Kustomization --name=petclinic-app

# 매니페스트 검증
kubectl apply --dry-run=client -k apps/petclinic/overlays/prod
```

### 이미지 업데이트 안 됨

```bash
# ImageRepository 상태
flux get images repository

# ImagePolicy 상태
flux get images policy

# 수동 스캔
flux reconcile image repository petclinic-image
```

## 12. Azure DR Site에 FluxCD 설정 (선택사항)

```bash
# Azure Kubernetes 클러스터 컨텍스트 전환
kubectl config use-context azure-aks

# Flux 설치 (동일한 Git 저장소 사용)
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=./clusters/azure-dr \
  --personal

# 동일한 매니페스트가 Azure에도 자동 배포됨
```

## 다음 단계

1. ArgoCD 비교 (선택사항)
2. Helm Chart 관리
3. Multi-tenancy 설정
4. Policy as Code (OPA/Kyverno)

## 참고 자료

- [FluxCD Documentation](https://fluxcd.io/docs/)
- [FluxCD GitHub](https://github.com/fluxcd/flux2)
- [GitOps Toolkit](https://toolkit.fluxcd.io/)
