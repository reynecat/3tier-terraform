# DockerHub 설정 및 사용 가이드

## 개요

DockerHub는 컨테이너 이미지 저장소로, Tekton에서 빌드한 이미지를 저장하고 FluxCD/Kubernetes가 pull합니다.

## 1. DockerHub 계정 설정

### 계정 생성

1. https://hub.docker.com 접속
2. Sign Up 클릭
3. Docker ID, 이메일, 패스워드 입력
4. 이메일 인증

### Docker ID 확인

```bash
# Docker ID 예시: mycompany, john-doe
YOUR_DOCKER_ID=your-docker-id
```

## 2. Repository 생성

### Web UI에서 생성

1. DockerHub 로그인
2. Repositories 탭
3. Create Repository 클릭
4. Repository 정보 입력:
   - **Name**: `petclinic`
   - **Description**: `Spring PetClinic Application`
   - **Visibility**: 
     - **Public**: 무료, 누구나 pull 가능
     - **Private**: 유료 (1개 무료), 인증 필요

5. Create 클릭

### CLI로 생성

```bash
# Docker CLI 로그인
docker login

# Username: YOUR_DOCKER_ID
# Password: YOUR_PASSWORD

# 이미지 태그 및 푸시 (자동으로 Repository 생성됨)
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:latest
docker push YOUR_DOCKER_ID/petclinic:latest
```

## 3. Access Token 생성 (권장)

패스워드 대신 Access Token 사용을 권장합니다.

### Token 생성

1. DockerHub → Account Settings → Security
2. New Access Token 클릭
3. Access Token Description: `tekton-pipeline`
4. Access permissions:
   - **Read, Write, Delete**: Tekton push용
   - **Read-only**: Kubernetes pull용
5. Generate 클릭
6. **Token 복사 및 안전하게 저장** (다시 볼 수 없음)

```
dckr_pat_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## 4. Kubernetes Secret 생성

### DockerHub Pull Secret (Kubernetes용)

```bash
# Public 이미지는 불필요, Private 이미지만 필요
kubectl create secret docker-registry dockerhub-pull-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKER_ID \
  --docker-password=YOUR_ACCESS_TOKEN \
  --docker-email=YOUR_EMAIL \
  --namespace=petclinic

# ServiceAccount에 연결
kubectl patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"dockerhub-pull-secret"}]}' \
  --namespace=petclinic
```

### DockerHub Push Secret (Tekton용)

```bash
# Tekton이 이미지를 push하기 위한 Secret
kubectl create secret docker-registry dockerhub-push-secret \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=YOUR_DOCKER_ID \
  --docker-password=YOUR_ACCESS_TOKEN \
  --docker-email=YOUR_EMAIL \
  --namespace=tekton-pipelines
```

### Secret YAML 형식

```yaml
# dockerhub-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: dockerhub-credentials
  namespace: flux-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: BASE64_ENCODED_DOCKER_CONFIG
```

생성 방법:

```bash
# Docker config 생성
cat <<EOF > docker-config.json
{
  "auths": {
    "https://index.docker.io/v1/": {
      "username": "YOUR_DOCKER_ID",
      "password": "YOUR_ACCESS_TOKEN",
      "email": "YOUR_EMAIL",
      "auth": "$(echo -n YOUR_DOCKER_ID:YOUR_ACCESS_TOKEN | base64)"
    }
  }
}
EOF

# Base64 인코딩
cat docker-config.json | base64 -w 0

# Secret 생성
kubectl create secret generic dockerhub-credentials \
  --from-file=.dockerconfigjson=docker-config.json \
  --type=kubernetes.io/dockerconfigjson \
  --namespace=flux-system

# 정리
rm docker-config.json
```

## 5. 이미지 태깅 전략

### Semantic Versioning

```bash
# 버전 태그
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:1.0.0
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:1.0
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:1
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:latest

docker push YOUR_DOCKER_ID/petclinic:1.0.0
docker push YOUR_DOCKER_ID/petclinic:1.0
docker push YOUR_DOCKER_ID/petclinic:1
docker push YOUR_DOCKER_ID/petclinic:latest
```

### Git Commit SHA

```bash
# Git SHA로 태깅
GIT_SHA=$(git rev-parse --short HEAD)
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:$GIT_SHA
docker push YOUR_DOCKER_ID/petclinic:$GIT_SHA
```

### 날짜 기반

```bash
# 날짜로 태깅
DATE=$(date +%Y%m%d-%H%M%S)
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:$DATE
docker push YOUR_DOCKER_ID/petclinic:$DATE
```

### 환경별

```bash
# 환경별 태그
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:prod
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:staging
docker tag petclinic:latest YOUR_DOCKER_ID/petclinic:dev

docker push YOUR_DOCKER_ID/petclinic:prod
docker push YOUR_DOCKER_ID/petclinic:staging
docker push YOUR_DOCKER_ID/petclinic:dev
```

## 6. Tekton에서 DockerHub 사용

### Kaniko Task 설정

```yaml
apiVersion: tekton.dev/v1beta1
kind: Task
metadata:
  name: docker-build-push
spec:
  params:
    - name: IMAGE
      description: Full image name with registry
      type: string
    - name: TAG
      description: Image tag
      type: string
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
        - --destination=$(params.IMAGE):$(params.TAG)
        - --cache=true
        - --cache-ttl=24h
        - --compressed-caching=false
      volumeMounts:
        - name: docker-credentials
          mountPath: /tekton/home/.docker
  volumes:
    - name: docker-credentials
      secret:
        secretName: dockerhub-push-secret
        items:
          - key: .dockerconfigjson
            path: config.json
```

## 7. FluxCD에서 DockerHub 이미지 감시

### ImageRepository 설정

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: petclinic-image
  namespace: flux-system
spec:
  image: YOUR_DOCKER_ID/petclinic
  interval: 5m0s
  # Public 이미지는 secretRef 불필요
  # Private 이미지만 필요:
  secretRef:
    name: dockerhub-credentials
```

### ImagePolicy 설정

```yaml
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
      range: '>=1.0.0 <2.0.0'  # 1.x.x 버전만
  filterTags:
    pattern: '^[0-9]+\.[0-9]+\.[0-9]+$'  # Semver 형식만
```

## 8. DockerHub Webhook 설정 (선택사항)

### Webhook 생성

1. DockerHub Repository → Webhooks 탭
2. Webhook name: `flux-update`
3. Webhook URL: `http://<FLUX-WEBHOOK-URL>/hook`
4. Create

### Flux Webhook Receiver

```yaml
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: dockerhub-receiver
  namespace: flux-system
spec:
  type: generic
  secretRef:
    name: webhook-token
  resources:
    - apiVersion: image.toolkit.fluxcd.io/v1beta2
      kind: ImageRepository
      name: petclinic-image
---
apiVersion: v1
kind: Secret
metadata:
  name: webhook-token
  namespace: flux-system
type: Opaque
stringData:
  token: YOUR_RANDOM_TOKEN
```

## 9. Rate Limits 및 최적화

### DockerHub Rate Limits

**Anonymous (비로그인)**
- 100 pulls / 6시간 (IP 당)

**Free Account (로그인)**
- 200 pulls / 6시간

**Pro Account ($5/월)**
- Unlimited pulls

**Team Account ($7/월/사용자)**
- Unlimited pulls
- 무제한 private repositories

### Rate Limit 확인

```bash
# Docker CLI로 확인
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token)

curl -s -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest -I | grep -i ratelimit

# 출력 예시:
# ratelimit-limit: 100;w=21600
# ratelimit-remaining: 95;w=21600
```

### 최적화 방법

1. **ServiceAccount에 imagePullSecrets 추가**
   ```bash
   kubectl patch serviceaccount default \
     -p '{"imagePullSecrets":[{"name":"dockerhub-pull-secret"}]}' \
     --namespace=petclinic
   ```

2. **이미지 캐싱 (Harbor, ECR 사용)**
   ```yaml
   # Harbor를 DockerHub 프록시로 사용
   image: harbor.company.com/dockerhub/YOUR_DOCKER_ID/petclinic:latest
   ```

3. **AWS ECR로 미러링**
   ```bash
   # DockerHub → ECR 복사
   docker pull YOUR_DOCKER_ID/petclinic:latest
   docker tag YOUR_DOCKER_ID/petclinic:latest \
     123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic:latest
   docker push 123456789012.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic:latest
   ```

## 10. 보안 모범 사례

### 1. 절대 패스워드를 코드에 포함하지 말 것

```bash
# ❌ 나쁜 예
kubectl create secret docker-registry dockerhub \
  --docker-password=mypassword123

# ✅ 좋은 예
kubectl create secret docker-registry dockerhub \
  --docker-password=$DOCKERHUB_TOKEN
```

### 2. Access Token 사용

- 패스워드 대신 Access Token 사용
- Token은 필요한 권한만 부여
- 정기적으로 Token 교체

### 3. Private Repository 사용

```bash
# 중요한 애플리케이션은 Private Repository 사용
# 무료 계정: 1개 Private Repository
# Pro 계정: 무제한
```

### 4. 이미지 서명 (Docker Content Trust)

```bash
# Content Trust 활성화
export DOCKER_CONTENT_TRUST=1

# 서명된 이미지만 pull/push
docker push YOUR_DOCKER_ID/petclinic:latest
docker pull YOUR_DOCKER_ID/petclinic:latest
```

### 5. 취약점 스캔

```bash
# Docker Scout (DockerHub 내장)
docker scout cves YOUR_DOCKER_ID/petclinic:latest

# Trivy로 스캔
trivy image YOUR_DOCKER_ID/petclinic:latest
```

## 11. 문제 해결

### 인증 실패

```bash
# 로그인 재시도
docker logout
docker login -u YOUR_DOCKER_ID

# Token 확인
kubectl get secret dockerhub-pull-secret -o yaml
```

### Rate Limit 초과

```bash
# 에러 메시지:
# toomanyrequests: You have reached your pull rate limit

# 해결책:
# 1. DockerHub 로그인
# 2. imagePullSecrets 추가
# 3. ECR/Harbor 사용
```

### 이미지 pull 실패

```bash
# Pod 상태 확인
kubectl describe pod <pod-name> -n petclinic

# Events 확인:
# Failed to pull image "YOUR_DOCKER_ID/petclinic:latest"
# Error: ImagePullBackOff

# Secret 확인
kubectl get secret dockerhub-pull-secret -n petclinic -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

## 12. 대안 고려사항

### AWS ECR (Elastic Container Registry)

**장점:**
- AWS와 통합
- Rate Limit 없음
- IAM 기반 인증

**단점:**
- AWS 종속
- 비용 (저장 + 전송)

### Harbor

**장점:**
- Self-hosted
- Vulnerability 스캔
- Replication

**단점:**
- 운영 오버헤드

### GitHub Container Registry (ghcr.io)

**장점:**
- GitHub 통합
- 무료 Public + Private
- GitHub Actions 통합

**단점:**
- GitHub 종속

## 요약

### DockerHub 사용 플로우

```
Developer → Git Push → GitHub
                          │
                          ▼
                    Tekton Pipeline
                          │
                          ├─ Build Image
                          ├─ Run Tests
                          ├─ Push to DockerHub
                          │     (YOUR_DOCKER_ID/petclinic:v1.0.0)
                          │
                          ▼
                    Update Manifests
                          │
                          ▼
                    FluxCD Sync
                          │
                          ├─ Detect new image
                          ├─ Pull from DockerHub
                          │
                          ▼
                    Deploy to Kubernetes
```

### 체크리스트

- [ ] DockerHub 계정 생성
- [ ] Repository 생성 (petclinic)
- [ ] Access Token 생성
- [ ] Kubernetes Secrets 생성
- [ ] Tekton Task 설정
- [ ] FluxCD ImageRepository 설정
- [ ] Rate Limit 모니터링
- [ ] 이미지 취약점 스캔

## 참고 자료

- [DockerHub Documentation](https://docs.docker.com/docker-hub/)
- [Docker Content Trust](https://docs.docker.com/engine/security/trust/)
- [Kaniko](https://github.com/GoogleContainerTools/kaniko)
