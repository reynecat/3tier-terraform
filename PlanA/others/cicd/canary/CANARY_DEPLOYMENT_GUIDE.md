# Canary 배포 가이드

## Canary 배포란?

### 개념

새 버전을 일부 사용자에게만 먼저 배포하고, 문제가 없으면 점진적으로 확대하는 배포 전략입니다.

**이름의 유래**: 
탄광에서 카나리아 새를 데려가 유독 가스를 조기에 감지하던 것에서 유래

### 전통적 배포 vs Canary 배포

**전통적 배포 (All-at-once)**:
```
기존 버전 1.0 (100%)
         ↓
      업데이트
         ↓
새 버전 2.0 (100%)

문제 발생 시:
- 전체 사용자 영향
- 긴급 롤백 필요
- 큰 피해
```

**Canary 배포**:
```
1단계: 기존 1.0 (90%) + 신규 2.0 (10%)
       └─ 10% 사용자만 테스트
       
2단계: 문제 없으면 → 1.0 (70%) + 2.0 (30%)

3단계: 계속 확대 → 1.0 (50%) + 2.0 (50%)

4단계: 최종 → 2.0 (100%)

문제 발생 시:
- 10% 사용자만 영향
- 즉시 중단 (자동)
- 최소 피해
```

## Flagger 사용

### 설치

```bash
# 1. Flagger CRD 설치
kubectl apply -f https://raw.githubusercontent.com/fluxcd/flagger/main/artifacts/flagger/crd.yaml

# 2. Flagger 설치
kubectl apply -k github.com/fluxcd/flagger//kustomize/kubernetes

# 3. 확인
kubectl get pods -n flagger-system
```

### 기본 설정

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: petclinic-was
  namespace: was
spec:
  # 배포 대상
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: petclinic-was
  
  # Canary 분석 설정
  analysis:
    interval: 1m        # 1분마다 분석
    iterations: 10      # 10회 반복 (총 10분)
    threshold: 5        # 5회 실패하면 롤백
    maxWeight: 50       # 최대 50%까지 트래픽 전환
    stepWeight: 10      # 10%씩 증가
    
    # 성공 기준
    metrics:
      - name: request-success-rate
        thresholdRange:
          min: 99       # 99% 이상 성공률
        interval: 1m
      
      - name: request-duration
        thresholdRange:
          max: 500      # 500ms 이하 응답 시간
        interval: 1m
```

## Canary 배포 과정

### 단계별 진행

**T+0분: 배포 시작**
```
Developer → GitHub push
           ↓
      Tekton 빌드
           ↓
      DockerHub
           ↓
      FluxCD 감지
           ↓
    Flagger 시작
```

**T+1분: 10% 트래픽**
```
Stable (v1.0): 90% 트래픽
Canary (v2.0): 10% 트래픽

Flagger 모니터링:
├─ 성공률: 99.5% ✓
├─ 응답시간: 250ms ✓
└─ 에러율: 0.5% ✓

결과: 통과 → 다음 단계
```

**T+2분: 20% 트래픽**
```
Stable: 80%
Canary: 20%

계속 모니터링...
문제 없으면 계속 진행
```

**T+5분: 50% 트래픽**
```
Stable: 50%
Canary: 50%

이 시점에서 문제 발생!
├─ 성공률: 95% ✗ (99% 미만)
└─ 에러율: 5% ✗ (임계값 초과)

결과: 자동 롤백!
```

**자동 롤백**:
```
T+5분 10초: Flagger가 문제 감지
T+5분 20초: Canary 트래픽 0%로 변경
T+5분 30초: Stable 트래픽 100%로 복구
T+6분: 사용자 영향 최소화 완료

Slack 알림:
"⚠️ Canary 배포 실패 - 자동 롤백 완료
버전: v2.0
실패 원인: 성공률 95% (기준 99%)
영향: 최대 50% 사용자, 1분간"
```

### 성공 시나리오

**T+10분: 100% 전환**
```
모든 단계 통과:
├─ 10% → 성공
├─ 20% → 성공
├─ 30% → 성공
├─ 40% → 성공
└─ 50% → 성공

Flagger 판단: 안전함!
         ↓
Stable 버전을 v2.0으로 교체
         ↓
Canary Pod 종료
         ↓
배포 완료!

Slack 알림:
"✅ Canary 배포 성공
버전: v1.0 → v2.0
소요 시간: 10분
문제 없음"
```

## 트래픽 분산 메커니즘

### Kubernetes Service 구조

```yaml
# Primary Service (일반 사용자)
apiVersion: v1
kind: Service
metadata:
  name: petclinic-was
  namespace: was
spec:
  selector:
    app: petclinic-was
  ports:
  - port: 8080

# Canary Service (테스트 트래픽)
apiVersion: v1
kind: Service
metadata:
  name: petclinic-was-canary
  namespace: was
spec:
  selector:
    app: petclinic-was
    version: canary
  ports:
  - port: 8080
```

### 트래픽 분배 방식

**방법 1: Ingress 가중치**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: petclinic
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"
spec:
  rules:
  - host: petclinic.example.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: petclinic-was-canary
            port:
              number: 8080
```

**방법 2: Service Mesh (Istio)**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: petclinic-was
spec:
  hosts:
  - petclinic-was
  http:
  - match:
    - headers:
        cookie:
          regex: "^(.*?;)?(canary=always)(;.*)?$"
    route:
    - destination:
        host: petclinic-was
        subset: canary
      weight: 100
  - route:
    - destination:
        host: petclinic-was
        subset: stable
      weight: 90
    - destination:
        host: petclinic-was
        subset: canary
      weight: 10
```

## 모니터링 메트릭

### Prometheus 쿼리

**성공률 측정**:
```promql
# HTTP 요청 성공률
sum(rate(http_requests_total{status!~"5.."}[1m])) 
/ 
sum(rate(http_requests_total[1m])) 
* 100

# 예상 결과: 99.5%
```

**응답 시간 측정**:
```promql
# 평균 응답 시간
histogram_quantile(0.99, 
  sum(rate(http_request_duration_seconds_bucket[1m])) 
  by (le)
) * 1000

# 예상 결과: 250ms
```

**에러율 측정**:
```promql
# HTTP 5xx 에러율
sum(rate(http_requests_total{status=~"5.."}[1m])) 
/ 
sum(rate(http_requests_total[1m])) 
* 100

# 예상 결과: 0.5%
```

### CloudWatch 메트릭

```bash
# ALB 대상 그룹별 요청 수
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=TargetGroup,Value=targetgroup/petclinic-was-canary/xxx \
  --start-time 2024-01-09T10:00:00Z \
  --end-time 2024-01-09T11:00:00Z \
  --period 300 \
  --statistics Sum
```

## 배포 전략 비교

### Rolling Update (기본)

```
장점:
✓ 간단함
✓ 빠름
✓ 다운타임 없음

단점:
✗ 문제 발견 늦음
✗ 전체 영향
✗ 롤백 느림
```

### Blue-Green

```
장점:
✓ 즉시 전환
✓ 즉시 롤백
✓ 명확한 버전 분리

단점:
✗ 리소스 2배 필요
✗ 비용 높음
✗ 데이터베이스 마이그레이션 복잡
```

### Canary (우리 선택)

```
장점:
✓ 위험 최소화
✓ 자동 롤백
✓ 점진적 확대
✓ 실사용자 테스트

단점:
✗ 시간 오래 걸림 (10분)
✗ 설정 복잡함
✗ 모니터링 필수
```

## 실전 시나리오

### 시나리오 1: 신기능 배포

```bash
# 개발자가 새 기능 개발
git checkout -b feature/new-pet-search
# 코드 작성...
git commit -m "Add advanced pet search"
git push origin feature/new-pet-search

# Pull Request & Merge
# main 브랜치에 병합

# Tekton 자동 실행
# 1. 빌드 (3분)
# 2. 테스트 (2분)
# 3. Docker 이미지 생성 (2분)
# 4. DockerHub 푸시 (1분)

# FluxCD 감지 (5분 주기)
# Kubernetes manifest 업데이트 감지

# Flagger 시작
# T+0: Canary 10%
# T+1: 모니터링... 성공
# T+2: Canary 20%
# ...
# T+10: Canary 100% → Stable 교체

# 총 소요 시간: 20분
# 개발자 개입: 0번
```

### 시나리오 2: 긴급 버그 수정

```bash
# 운영 중 버그 발견!
git checkout -b hotfix/critical-bug
# 버그 수정
git commit -m "Fix critical payment bug"
git push origin hotfix/critical-bug

# 긴급 배포 (Canary 건너뛰기)
# annotations:
#   flagger.app/skip-analysis: "true"

# 즉시 100% 배포
# 소요 시간: 10분
```

### 시나리오 3: 배포 실패 및 롤백

```
T+0: 배포 시작
T+1: Canary 10% - 성공
T+2: Canary 20% - 성공
T+3: Canary 30% - 성공
T+4: Canary 40% - 성공
T+5: Canary 50% - 실패!
     └─ 에러율 5% (기준 1% 미만)

Flagger 자동 대응:
├─ Canary 트래픽 즉시 0%
├─ Stable 100% 복구
├─ Slack 알림 발송
└─ CloudWatch 로그 기록

개발자 확인:
├─ 로그 분석
├─ 문제 원인 파악
│   └─ DB 쿼리 성능 이슈
├─ 로컬에서 수정
└─ 재배포 (다음날)

피해 최소화:
- 영향받은 사용자: 50%
- 영향 시간: 1분
- 데이터 손실: 없음
```

## 고급 설정

### A/B 테스트와 결합

```yaml
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: petclinic-was
spec:
  analysis:
    # 헤더 기반 라우팅
    match:
      - headers:
          user-type:
            exact: "beta-tester"
    
    # Beta 사용자만 Canary로
    canaryReadyThreshold: 0
    iterations: 20
```

### 특정 사용자 타겟팅

```yaml
# 쿠키 기반 라우팅
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: petclinic
spec:
  http:
  - match:
    - headers:
        cookie:
          regex: "^(.*?;)?(canary=true)(;.*)?$"
    route:
    - destination:
        host: petclinic-was
        subset: canary
      weight: 100
```

### 점진적 롤아웃 스케줄

```yaml
analysis:
  # 첫 5분은 10%만
  stepWeightPromotion: 10
  
  # 5-10분: 20%
  # 10-15분: 30%
  # 15-20분: 50%
  # 20분 후: 100%
  
  # 각 단계마다 5분 대기
  interval: 5m
  iterations: 4
```

## 비용 영향

### 추가 리소스

```
Canary 배포 중:
- Stable Pods: 2개 (기존)
- Canary Pods: 2개 (추가)
- 총: 4개

배포 완료 후:
- Stable Pods: 2개
- Canary Pods: 0개 (삭제)
- 총: 2개

추가 비용:
- 10분간만 4개 실행
- 시간당 비용: $0.20
- 10분 비용: $0.03
- 월 30회 배포 시: $0.90/월
```

### Flagger 인프라

```
Flagger Controller:
- CPU: 100m
- Memory: 128Mi
- 비용: $3/월

Flagger Load Tester:
- CPU: 100m
- Memory: 128Mi
- 비용: $3/월

총 비용: $6/월 + $0.90/월 = $6.90/월
```

## 모범 사례

### 1. 점진적 단계 설정

```yaml
# 너무 급하게 (X)
stepWeight: 50  # 50%씩 증가 - 위험!

# 적절하게 (O)
stepWeight: 10  # 10%씩 증가 - 안전
```

### 2. 충분한 분석 시간

```yaml
# 너무 짧게 (X)
interval: 10s   # 10초마다 - 성급함

# 적절하게 (O)
interval: 1m    # 1분마다 - 충분한 데이터
```

### 3. 합리적인 임계값

```yaml
# 너무 엄격 (X)
metrics:
  - name: request-success-rate
    thresholdRange:
      min: 100  # 100% - 불가능

# 적절하게 (O)
metrics:
  - name: request-success-rate
    thresholdRange:
      min: 99   # 99% - 현실적
```

### 4. 알림 설정

```yaml
# Slack 알림 필수
webhooks:
  - name: slack-notification
    url: https://hooks.slack.com/...
    type: rollback
```

### 5. 로그 보관

```yaml
# CloudWatch 로그 그룹
/aws/eks/canary-deployments
├─ 성공 기록
├─ 실패 기록
└─ 메트릭 데이터

보관 기간: 30일
```

## 요약

**Canary 배포의 핵심**:
- 점진적 확대
- 자동 모니터링
- 자동 롤백
- 위험 최소화

**우리 프로젝트 설정**:
- 10%씩 증가
- 1분마다 분석
- 10분 완료
- 실패 시 즉시 롤백

**개발자 경험**:
- Git push만 하면 됨
- 자동으로 배포
- 문제 생기면 자동 롤백
- Slack으로 알림 받음

**비용**:
- 월 $7 정도
- 안전성 대비 저렴

Canary 배포로 안전하고 자신 있게 배포하세요! 🚀
