# Tekton CI Pipeline 설치 가이드

## 개요

Tekton은 Kubernetes 네이티브 CI/CD 프레임워크로, AWS EKS에서 실행됩니다.

## 아키텍처

```
GitHub Repository (spring-petclinic)
         │
         ├─ Webhook Trigger
         │
         ▼
    Tekton Pipeline (AWS EKS)
         │
         ├─ Task 1: Git Clone
         ├─ Task 2: Maven Build
         ├─ Task 3: Unit Tests
         ├─ Task 4: Docker Build (Kaniko)
         ├─ Task 5: Push to DockerHub
         └─ Task 6: Update K8s Manifests
                │
                ▼
         GitHub (k8s-manifests)
                │
                ▼
         FluxCD Auto-Deploy
```

## 1. Tekton 설치

### Tekton Pipelines 설치

```bash
# Tekton Pipelines 설치 (v0.54.0)
kubectl apply --filename \
  https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# 설치 확인
kubectl get pods -n tekton-pipelines

# 기대 출력:
# tekton-pipelines-controller-xxxxx   1/1     Running
# tekton-pipelines-webhook-xxxxx      1/1     Running
```

### Tekton Dashboard 설치 (선택사항)

```bash
# Tekton Dashboard 설치
kubectl apply --filename \
  https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml

# Dashboard 접속
kubectl port-forward -n tekton-pipelines \
  service/tekton-dashboard 9097:9097

# 브라우저에서 접속: http://localhost:9097
```

### Tekton CLI 설치 (tkn)

```bash
# macOS
brew install tektoncd-cli

# Linux
curl -LO https://github.com/tektoncd/cli/releases/download/v0.33.0/tkn_0.33.0_Linux_x86_64.tar.gz
sudo tar xvzf tkn_0.33.0_Linux_x86_64.tar.gz -C /usr/local/bin/ tkn

# 설치 확인
tkn version
```

## 2. Tekton Tasks 생성

### Task 1: Git Clone

```yaml
# tekton/tasks/git-clone-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: git-clone
  namespace: tekton-pipelines
spec:
  params:
    - name: url
      type: string
      description: Git repository URL
    - name: revision
      type: string
      description: Git revision (branch, tag, commit)
      default: main
  workspaces:
    - name: output
      description: The git repo will be cloned onto this workspace
  steps:
    - name: clone
      image: gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:v0.40.2
      script: |
        #!/bin/sh
        set -ex
        git clone $(params.url) $(workspaces.output.path)
        cd $(workspaces.output.path)
        git checkout $(params.revision)
        git log -1 --oneline
```

### Task 2: Maven Build

```yaml
# tekton/tasks/maven-build-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: maven-build
  namespace: tekton-pipelines
spec:
  workspaces:
    - name: source
  steps:
    - name: build
      image: maven:3.9-eclipse-temurin-21
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/bash
        set -ex
        
        # Maven 빌드 (테스트 포함)
        mvn clean package -DskipTests=false
        
        # 빌드 결과 확인
        ls -lh target/*.jar
    - name: test
      image: maven:3.9-eclipse-temurin-21
      workingDir: $(workspaces.source.path)
      script: |
        #!/bin/bash
        set -ex
        
        # 단위 테스트 실행
        mvn test
        
        # 통합 테스트 실행
        mvn verify
```

### Task 3: Docker Build (Kaniko)

```yaml
# tekton/tasks/docker-build-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: docker-build-push
  namespace: tekton-pipelines
spec:
  params:
    - name: image
      type: string
      description: Docker image name (e.g., username/petclinic)
    - name: tag
      type: string
      description: Docker image tag
      default: latest
  workspaces:
    - name: source
  steps:
    - name: build-and-push
      image: gcr.io/kaniko-project/executor:latest
      env:
        - name: DOCKER_CONFIG
          value: /tekton/home/.docker
      command:
        - /kaniko/executor
      args:
        - --dockerfile=$(workspaces.source.path)/Dockerfile
        - --context=$(workspaces.source.path)
        - --destination=$(params.image):$(params.tag)
        - --cache=true
        - --cache-ttl=24h
```

### Task 4: Update Manifest

```yaml
# tekton/tasks/update-manifest-task.yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: update-manifest
  namespace: tekton-pipelines
spec:
  params:
    - name: image
      type: string
    - name: tag
      type: string
    - name: manifest-repo
      type: string
      description: Git repo for k8s manifests
    - name: manifest-path
      type: string
      description: Path to deployment file
      default: k8s-manifests/was-deployment.yaml
  workspaces:
    - name: manifest
  steps:
    - name: clone-manifest-repo
      image: gcr.io/tekton-releases/github.com/tektoncd/pipeline/cmd/git-init:v0.40.2
      script: |
        #!/bin/sh
        set -ex
        git clone $(params.manifest-repo) $(workspaces.manifest.path)
    
    - name: update-image
      image: alpine/git
      workingDir: $(workspaces.manifest.path)
      script: |
        #!/bin/sh
        set -ex
        
        # yq 설치
        wget https://github.com/mikefarah/yq/releases/download/v4.35.1/yq_linux_amd64 -O /usr/bin/yq
        chmod +x /usr/bin/yq
        
        # 이미지 태그 업데이트
        yq eval -i \
          '.spec.template.spec.containers[0].image = "$(params.image):$(params.tag)"' \
          $(params.manifest-path)
        
        # 변경사항 커밋 및 푸시
        git config user.email "tekton@pipeline.local"
        git config user.name "Tekton Pipeline"
        git add $(params.manifest-path)
        git commit -m "Update image to $(params.image):$(params.tag)"
        git push origin main
```

## 3. Tekton Pipeline 생성

```yaml
# tekton/pipelines/petclinic-pipeline.yaml
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: petclinic-build-deploy
  namespace: tekton-pipelines
spec:
  params:
    - name: git-url
      type: string
      description: Application Git URL
    - name: git-revision
      type: string
      default: main
    - name: image-name
      type: string
      description: DockerHub image name
    - name: image-tag
      type: string
      default: latest
    - name: manifest-repo
      type: string
      description: K8s manifest repo URL
  
  workspaces:
    - name: shared-workspace
    - name: docker-credentials
    - name: git-credentials
  
  tasks:
    # Task 1: Clone Application Code
    - name: fetch-repository
      taskRef:
        name: git-clone
      params:
        - name: url
          value: $(params.git-url)
        - name: revision
          value: $(params.git-revision)
      workspaces:
        - name: output
          workspace: shared-workspace
    
    # Task 2: Build with Maven
    - name: build-app
      taskRef:
        name: maven-build
      runAfter:
        - fetch-repository
      workspaces:
        - name: source
          workspace: shared-workspace
    
    # Task 3: Build and Push Docker Image
    - name: build-push-image
      taskRef:
        name: docker-build-push
      runAfter:
        - build-app
      params:
        - name: image
          value: $(params.image-name)
        - name: tag
          value: $(params.image-tag)
      workspaces:
        - name: source
          workspace: shared-workspace
    
    # Task 4: Update Kubernetes Manifest
    - name: update-manifest
      taskRef:
        name: update-manifest
      runAfter:
        - build-push-image
      params:
        - name: image
          value: $(params.image-name)
        - name: tag
          value: $(params.image-tag)
        - name: manifest-repo
          value: $(params.manifest-repo)
      workspaces:
        - name: manifest
          workspace: shared-workspace
```

## 4. Secrets 및 Credentials 설정

### DockerHub Credentials

```bash
# DockerHub 로그인 정보로 Secret 생성
kubectl create secret docker-registry dockerhub-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKERHUB_USERNAME \
  --docker-password=YOUR_DOCKERHUB_PASSWORD \
  --docker-email=YOUR_EMAIL \
  -n tekton-pipelines

# ServiceAccount에 연결
kubectl patch serviceaccount default \
  -p '{"secrets":[{"name":"dockerhub-secret"}]}' \
  -n tekton-pipelines
```

### GitHub Credentials

```bash
# GitHub Personal Access Token으로 Secret 생성
kubectl create secret generic git-credentials \
  --from-literal=username=YOUR_GITHUB_USERNAME \
  --from-literal=password=YOUR_GITHUB_TOKEN \
  -n tekton-pipelines

# Git 인증 설정
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: git-ssh-key
  namespace: tekton-pipelines
  annotations:
    tekton.dev/git-0: github.com
type: kubernetes.io/ssh-auth
stringData:
  ssh-privatekey: |
    $(cat ~/.ssh/id_rsa)
  known_hosts: |
    $(ssh-keyscan github.com)
EOF
```

## 5. PipelineRun 실행

### PipelineRun 생성

```yaml
# tekton/pipelineruns/petclinic-pipelinerun.yaml
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: petclinic-build-run-$(date +%Y%m%d-%H%M%S)
  namespace: tekton-pipelines
spec:
  pipelineRef:
    name: petclinic-build-deploy
  params:
    - name: git-url
      value: https://github.com/spring-projects/spring-petclinic.git
    - name: git-revision
      value: main
    - name: image-name
      value: YOUR_DOCKERHUB_USERNAME/petclinic
    - name: image-tag
      value: v1.0.0
    - name: manifest-repo
      value: https://github.com/YOUR_USERNAME/k8s-manifests.git
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 5Gi
    - name: docker-credentials
      secret:
        secretName: dockerhub-secret
    - name: git-credentials
      secret:
        secretName: git-credentials
```

### 수동 실행

```bash
# PipelineRun 적용
kubectl apply -f tekton/pipelineruns/petclinic-pipelinerun.yaml

# 실행 상태 확인
tkn pipelinerun list -n tekton-pipelines

# 로그 확인
tkn pipelinerun logs -f -n tekton-pipelines

# Dashboard에서 확인
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097
```

## 6. GitHub Webhook 설정

### Tekton Trigger 설치

```bash
# Tekton Triggers 설치
kubectl apply --filename \
  https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml

kubectl apply --filename \
  https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml
```

### EventListener 생성

```yaml
# tekton/triggers/eventlistener.yaml
apiVersion: triggers.tekton.dev/v1beta1
kind: EventListener
metadata:
  name: github-listener
  namespace: tekton-pipelines
spec:
  serviceAccountName: tekton-triggers-sa
  triggers:
    - name: github-push-trigger
      interceptors:
        - ref:
            name: github
          params:
            - name: secretRef
              value:
                secretName: github-webhook-secret
                secretKey: secret
            - name: eventTypes
              value:
                - push
      bindings:
        - ref: github-push-binding
      template:
        ref: petclinic-trigger-template
---
apiVersion: v1
kind: Service
metadata:
  name: el-github-listener
  namespace: tekton-pipelines
spec:
  type: LoadBalancer
  ports:
    - port: 8080
      targetPort: 8080
  selector:
    eventlistener: github-listener
```

### GitHub Webhook 설정

1. GitHub Repository → Settings → Webhooks
2. Payload URL: `http://<ELB-DNS>:8080`
3. Content type: `application/json`
4. Secret: `<YOUR_WEBHOOK_SECRET>`
5. Events: `Push events`

## 7. 모니터링

### Tekton CLI로 모니터링

```bash
# Pipeline 목록
tkn pipeline list -n tekton-pipelines

# PipelineRun 목록
tkn pipelinerun list -n tekton-pipelines

# 실시간 로그
tkn pipelinerun logs -f <pipelinerun-name> -n tekton-pipelines

# Task 상태 확인
tkn taskrun list -n tekton-pipelines
```

### Dashboard 모니터링

```bash
# Port Forward
kubectl port-forward -n tekton-pipelines service/tekton-dashboard 9097:9097

# 접속: http://localhost:9097
```

## 8. 문제 해결

### Docker Build 실패

```bash
# Kaniko가 DockerHub에 푸시할 수 없는 경우
# Secret이 올바르게 설정되었는지 확인
kubectl get secret dockerhub-secret -n tekton-pipelines -o yaml

# ServiceAccount 확인
kubectl get sa default -n tekton-pipelines -o yaml
```

### Git Clone 실패

```bash
# Git credentials 확인
kubectl get secret git-credentials -n tekton-pipelines

# SSH 키 권한 확인
kubectl describe secret git-ssh-key -n tekton-pipelines
```

## 다음 단계

1. FluxCD 설치 (자동 배포)
2. ArgoCD 통합 (선택사항)
3. Slack 알림 설정
4. SonarQube 연동 (코드 품질)

## 참고 자료

- [Tekton Documentation](https://tekton.dev/docs/)
- [Tekton Catalog](https://hub.tekton.dev/)
- [Kaniko Documentation](https://github.com/GoogleContainerTools/kaniko)
