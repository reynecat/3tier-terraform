# 통합 CI/CD 파이프라인 구축 가이드

## 개요

Tekton (CI) + FluxCD (CD) + DockerHub (Registry)를 활용한 완전한 GitOps 파이프라인 구축 가이드입니다.

## 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CI/CD Pipeline                               │
└─────────────────────────────────────────────────────────────────────┘

Developer
    │
    ├─ git push (code)
    │
    ▼
┌─────────────────────┐
│ GitHub Repository   │
│ - spring-petclinic  │ ◄─┐
│ - k8s-manifests     │   │
└─────────────────────┘   │
    │                     │
    │ webhook             │ 6. Update manifests
    ▼                     │
┌─────────────────────────────────────┐
│ Tekton Pipeline (AWS EKS)           │
│                                     │
│ 1. Git Clone                        │
│ 2. Maven Build & Test               │
│ 3. Docker Build (Kaniko)            │
│ 4. Push to DockerHub ───────────┐  │
│ 5. Tag: v1.0.0                   │  │
└────────────────────────────────┬─┘  │
                                 │    │
                                 ▼    │
                         ┌─────────────────┐
                         │   DockerHub     │
                         │  petclinic:1.0.0│
                         └─────────────────┘
                                 │
                                 │ image pull
                                 │
    ┌────────────────────────────┼──────────────────────┐
    │                            │                      │
    ▼                            ▼                      │
┌─────────────────────────────────────┐                │
│ FluxCD (AWS EKS)                    │                │
│                                     │                │
│ 1. Poll Git (5min)                  │                │
│ 2. Detect manifest changes          │                │
│ 3. Pull new image from DockerHub ───┘                │
│ 4. Apply to Kubernetes                               │
└─────────────────────────────────────┘                │
                │                                      │
                ▼                                      │
┌─────────────────────────────────────┐                │
│ Kubernetes Workloads                │                │
│                                     │                │
│ - Web Pods (Nginx)                  │                │
│ - WAS Pods (Spring Boot) ───────────┘                │
│                                                      │
└──────────────────────────────────────────────────────┘
```

## 1. 사전 준비사항

### 1.1 필수 계정

- [x] GitHub 계정
- [x] DockerHub 계정
- [x] AWS 계정 (EKS 클러스터)

### 1.2 필수 도구 설치

```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Tekton CLI (tkn)
brew install tektoncd-cli  # macOS
# 또는
curl -LO https://github.com/tektoncd/cli/releases/download/v0.33.0/tkn_0.33.0_Linux_x86_64.tar.gz
sudo tar xvzf tkn_0.33.0_Linux_x86_64.tar.gz -C /usr/local/bin/ tkn

# Flux CLI
brew install fluxcd/tap/flux  # macOS
# 또는
curl -s https://fluxcd.io/install.sh | sudo bash

# Docker CLI
sudo apt-get install docker.io  # Ubuntu
brew install docker  # macOS

# 설치 확인
kubectl version --client
tkn version
flux version
docker version
```

### 1.3 EKS 클러스터 접속

```bash
# AWS CLI 설정
aws configure

# EKS kubeconfig 설정
aws eks update-kubeconfig --region ap-northeast-2 --name eks-prod

# 연결 확인
kubectl cluster-info
kubectl get nodes
```

## 2. 단계별 설치

### 2.1 DockerHub 설정 (15분)

```bash
# 1. DockerHub 로그인
export DOCKERHUB_USERNAME=your-username
export DOCKERHUB_TOKEN=dckr_pat_xxxxxxxxxxxxx

docker login -u $DOCKERHUB_USERNAME -p $DOCKERHUB_TOKEN

# 2. Repository 생성 (Web UI 또는 자동 생성)
# https://hub.docker.com → Create Repository → petclinic

# 3. Kubernetes Secret 생성
kubectl create namespace tekton-pipelines
kubectl create namespace flux-system
kubectl create namespace petclinic

# Tekton용 (Push)
kubectl create secret docker-registry dockerhub-push-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=$DOCKERHUB_USERNAME \
  --docker-password=$DOCKERHUB_TOKEN \
  --docker-email=your-email@example.com \
  -n tekton-pipelines

# Flux용 (Image Scan)
kubectl create secret docker-registry dockerhub-credentials \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=$DOCKERHUB_USERNAME \
  --docker-password=$DOCKERHUB_TOKEN \
  --docker-email=your-email@example.com \
  -n flux-system

# Kubernetes용 (Pull) - Private 이미지만 필요
kubectl create secret docker-registry dockerhub-pull-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=$DOCKERHUB_USERNAME \
  --docker-password=$DOCKERHUB_TOKEN \
  --docker-email=your-email@example.com \
  -n petclinic

kubectl patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"dockerhub-pull-secret"}]}' \
  -n petclinic
```

**상세 가이드**: `dockerhub/DOCKERHUB_SETUP.md`

### 2.2 Tekton 설치 (20분)

```bash
# 1. Tekton Pipelines 설치
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# 설치 확인
kubectl get pods -n tekton-pipelines --watch

# 2. Tekton Triggers 설치 (Webhook용)
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml

# 3. Tekton Dashboard 설치 (선택사항)
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Dashboard 접속
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097
# http://localhost:9097

# 4. Tasks 및 Pipeline 생성
kubectl apply -f tekton/tasks/
kubectl apply -f tekton/pipelines/

# 확인
tkn task list -n tekton-pipelines
tkn pipeline list -n tekton-pipelines
```

**상세 가이드**: `tekton/TEKTON_SETUP.md`

### 2.3 FluxCD 설치 (30분)

```bash
# 1. GitHub Personal Access Token 생성
# GitHub → Settings → Developer settings → Personal access tokens
# 권한: repo (전체), workflow
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxx
export GITHUB_USER=your-username
export GITHUB_REPO=k8s-manifests

# 2. Flux 사전 확인
flux check --pre

# 3. Flux Bootstrap
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=main \
  --path=./clusters/aws-prod \
  --personal \
  --token-auth

# 설치 확인
flux check
kubectl get pods -n flux-system

# 4. GitRepository 생성
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: petclinic-repo
  namespace: flux-system
spec:
  interval: 5m0s
  url: https://github.com/$GITHUB_USER/$GITHUB_REPO
  ref:
    branch: main
EOF

# 5. Kustomization 생성
cat <<EOF | kubectl apply -f -
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
EOF

# 6. ImageRepository 생성 (자동 이미지 업데이트)
cat <<EOF | kubectl apply -f -
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: petclinic-image
  namespace: flux-system
spec:
  image: $DOCKERHUB_USERNAME/petclinic
  interval: 5m0s
  secretRef:
    name: dockerhub-credentials
EOF

# 7. ImagePolicy 생성
cat <<EOF | kubectl apply -f -
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
      range: '>=1.0.0 <2.0.0'
EOF

# 상태 확인
flux get all
```

**상세 가이드**: `flux/FLUXCD_SETUP.md`

## 3. Git 저장소 구성

### 3.1 Application Repository (spring-petclinic)

```bash
# 1. Fork 또는 Clone
git clone https://github.com/spring-projects/spring-petclinic.git
cd spring-petclinic

# 2. Dockerfile 추가 (루트 디렉토리)
cat > Dockerfile <<'EOF'
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests -Dspring-boot.run.profiles=mysql

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar --spring.profiles.active=mysql"]
EOF

# 3. Push to your GitHub
git remote set-url origin https://github.com/$GITHUB_USER/spring-petclinic.git
git add Dockerfile
git commit -m "Add Dockerfile for CI/CD"
git push origin main
```

### 3.2 Manifest Repository (k8s-manifests)

```bash
# 1. 새 Repository 생성
git clone https://github.com/$GITHUB_USER/k8s-manifests.git
cd k8s-manifests

# 2. 디렉토리 구조 생성
mkdir -p clusters/aws-prod/apps
mkdir -p apps/petclinic/base
mkdir -p apps/petclinic/overlays/prod

# 3. Base 매니페스트 생성
cat > apps/petclinic/base/namespace.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: petclinic
EOF

cat > apps/petclinic/base/was-deployment.yaml <<EOF
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
        image: $DOCKERHUB_USERNAME/petclinic:latest # {"$imagepolicy": "flux-system:petclinic-policy"}
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "mysql"
        - name: SPRING_DATASOURCE_URL
          value: "jdbc:mysql://rds-endpoint:3306/petclinic"
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: petclinic-secret
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: petclinic-secret
              key: password
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
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
EOF

cat > apps/petclinic/base/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: petclinic
resources:
  - namespace.yaml
  - was-deployment.yaml
EOF

# 4. Production Overlay
cat > apps/petclinic/overlays/prod/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: petclinic
bases:
  - ../../base
patchesStrategicMerge:
  - replicas.yaml
images:
  - name: $DOCKERHUB_USERNAME/petclinic
    newTag: 1.0.0
EOF

cat > apps/petclinic/overlays/prod/replicas.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: petclinic-was
spec:
  replicas: 3
EOF

# 5. Push
git add .
git commit -m "Initial manifest structure"
git push origin main
```

## 4. 첫 번째 파이프라인 실행

### 4.1 수동 PipelineRun

```bash
# 1. PipelineRun 생성
cat <<EOF | kubectl apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: petclinic-build-$(date +%Y%m%d-%H%M%S)
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: petclinic-build-deploy
  params:
    - name: git-url
      value: https://github.com/$GITHUB_USER/spring-petclinic.git
    - name: git-revision
      value: main
    - name: image-name
      value: $DOCKERHUB_USERNAME/petclinic
    - name: image-tag
      value: 1.0.0
    - name: manifest-repo
      value: https://github.com/$GITHUB_USER/k8s-manifests.git
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
EOF

# 2. 실행 상태 확인
tkn pipelinerun logs -f -n tekton-pipelines

# 3. Dashboard에서 확인
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097
# http://localhost:9097
```

### 4.2 결과 확인

```bash
# 1. DockerHub에 이미지 확인
docker pull $DOCKERHUB_USERNAME/petclinic:1.0.0

# 2. Git manifest 업데이트 확인
cd k8s-manifests
git pull
cat apps/petclinic/overlays/prod/kustomization.yaml

# 3. FluxCD 동기화 확인
flux get kustomizations
flux reconcile kustomization petclinic-app

# 4. Kubernetes에 배포 확인
kubectl get pods -n petclinic
kubectl get svc -n petclinic

# 5. 애플리케이션 접속
kubectl port-forward -n petclinic service/petclinic-was-service 8080:8080
# http://localhost:8080
```

## 5. GitHub Webhook 설정 (자동 트리거)

### 5.1 Tekton EventListener 노출

```bash
# EventListener Service를 LoadBalancer로 노출
kubectl patch service el-github-listener \
  -n tekton-pipelines \
  -p '{"spec":{"type":"LoadBalancer"}}'

# External IP 확인
kubectl get svc el-github-listener -n tekton-pipelines

# 출력 예시:
# el-github-listener   LoadBalancer   10.100.x.x   a1b2c3...elb.amazonaws.com
```

### 5.2 GitHub Webhook 등록

1. GitHub Repository (`spring-petclinic`) → Settings → Webhooks
2. Add webhook 클릭
3. 입력:
   - **Payload URL**: `http://a1b2c3...elb.amazonaws.com:8080`
   - **Content type**: `application/json`
   - **Secret**: `<YOUR_WEBHOOK_SECRET>`
   - **Events**: `Just the push event`
4. Add webhook 클릭

### 5.3 테스트

```bash
# 코드 변경 및 Push
cd spring-petclinic
echo "// test" >> src/main/java/org/springframework/samples/petclinic/PetClinicApplication.java
git add .
git commit -m "Test CI/CD trigger"
git push origin main

# Tekton 자동 실행 확인
tkn pipelinerun list -n tekton-pipelines
tkn pipelinerun logs -f <latest-run> -n tekton-pipelines
```

## 6. 모니터링 및 알림

### 6.1 Tekton Dashboard

```bash
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097
# http://localhost:9097
```

### 6.2 Flux CLI

```bash
# 전체 상태
flux get all

# 실시간 로그
flux logs --follow --all-namespaces

# 특정 리소스 상태
flux get sources git
flux get kustomizations
flux get images repository
```

### 6.3 Slack 알림 (선택사항)

```bash
# Slack Webhook URL 생성 후
cat <<EOF | kubectl apply -f -
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack
  namespace: flux-system
spec:
  type: slack
  channel: "#gitops"
  address: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
---
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: petclinic-alert
  namespace: flux-system
spec:
  providerRef:
    name: slack
  eventSeverity: info
  eventSources:
    - kind: Kustomization
      name: petclinic-app
EOF
```

## 7. 문제 해결

### 7.1 Tekton Pipeline 실패

```bash
# 로그 확인
tkn pipelinerun logs <pipelinerun-name> -n tekton-pipelines

# Task 별 로그
tkn taskrun logs <taskrun-name> -n tekton-pipelines

# Pod 상태 확인
kubectl get pods -n tekton-pipelines | grep <pipelinerun-name>
kubectl logs <pod-name> -n tekton-pipelines
```

### 7.2 DockerHub Push 실패

```bash
# Secret 확인
kubectl get secret dockerhub-push-secret -n tekton-pipelines -o yaml

# Token 유효성 확인
docker login -u $DOCKERHUB_USERNAME -p $DOCKERHUB_TOKEN
```

### 7.3 FluxCD 동기화 안 됨

```bash
# GitRepository 상태
flux get sources git

# 수동 동기화
flux reconcile source git petclinic-repo
flux reconcile kustomization petclinic-app

# 로그 확인
flux logs
```

## 8. 베스트 프랙티스

### 8.1 이미지 태깅 전략

```yaml
# Semantic Versioning 사용
images:
  - name: username/petclinic
    newTag: 1.0.0  # Major.Minor.Patch
```

### 8.2 환경별 분리

```
apps/petclinic/
├── base/
├── overlays/
│   ├── dev/      # 개발 환경
│   ├── staging/  # 스테이징 환경
│   └── prod/     # 프로덕션 환경
```

### 8.3 Secret 관리

```bash
# Sealed Secrets 사용 (권장)
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# 또는 External Secrets Operator
# 또는 AWS Secrets Manager 통합
```

### 8.4 보안 스캔

```yaml
# Tekton Pipeline에 Trivy 추가
- name: security-scan
  image: aquasec/trivy
  command:
    - trivy
  args:
    - image
    - --severity HIGH,CRITICAL
    - $(params.image):$(params.tag)
```

## 9. 다음 단계

- [ ] Helm Chart 관리 (Flux HelmRelease)
- [ ] ArgoCD 비교/통합
- [ ] Multi-cluster 배포
- [ ] Progressive Delivery (Canary, Blue-Green)
- [ ] Policy as Code (OPA/Kyverno)
- [ ] Cost Optimization

## 참고 자료

- [Tekton Documentation](https://tekton.dev/docs/)
- [FluxCD Documentation](https://fluxcd.io/docs/)
- [DockerHub Documentation](https://docs.docker.com/docker-hub/)
- [GitOps Principles](https://opengitops.dev/)
