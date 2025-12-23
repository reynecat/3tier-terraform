# AWS 인프라  모니터링 가이드

## 목차
1. [개요](#개요)
2. [모니터링 아키텍처](#모니터링-아키텍처)
3. [모니터링 지표 상세](#모니터링-지표-상세)
4. [알람 설정](#알람-설정)
5. [자동 복구 메커니즘](#자동-복구-메커니즘)
6. [CloudWatch 대시보드](#cloudwatch-대시보드)

---

## 개요

AWS CloudWatch와 Container Insights를 활용하여 프로젝트에서 구축한 인프라를 

### 모니터링 목적
- **가용성 보장**: 시스템 장애를 조기에 감지하고 자동 복구
- **성능 최적화**: 리소스 사용률을 추적하여 병목 현상 예방
- **비용 최적화**: 과도한 리소스 사용 방지
- **DR 준비**: Route53 Health Check로 Failover 상태 감시

### 핵심 기능
- **다층 모니터링**: 인프라(Node) → 컨테이너(Pod) → 애플리케이션(ALB/RDS) 계층별 모니터링
- **실시간 알람**: SNS를 통한 이메일 알림
- **자동 복구**: Lambda를 통한 자동 복구 액션
- **시각화**: CloudWatch 대시보드를 통한 실시간 메트릭 확인

---

## 모니터링 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    CloudWatch Metrics                        │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   EKS    │  │   ALB    │  │   RDS    │  │ Route53  │   │
│  │  Nodes   │  │ Metrics  │  │ Metrics  │  │  Health  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│       ↓             ↓             ↓             ↓           │
│  ┌──────────────────────────────────────────────────┐      │
│  │          Container Insights                       │      │
│  │   (Pod/Container Level Metrics)                  │      │
│  └──────────────────────────────────────────────────┘      │
└───────────────────────┬─────────────────────────────────────┘
                        ↓
            ┌───────────────────────┐
            │  CloudWatch Alarms    │
            └───────────┬───────────┘
                        ↓
            ┌───────────────────────┐
            │     SNS Topic         │
            └───────┬───────┬───────┘
                    ↓       ↓
            ┌───────┐   ┌───────────┐
            │ Email │   │  Lambda   │
            │ Alert │   │   Auto    │
            │       │   │ Recovery  │
            └───────┘   └───────────┘
```

---

## 모니터링 지표 상세

### 1. EKS 노드 레벨 메트릭

#### 1.1 CPU 사용률 (node_cpu_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 80% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - CPU 과부하 시 애플리케이션 응답 지연 발생
  - 노드 확장(Scale-out) 필요 시점 판단
  - 워크로드 재분배 필요성 감지

#### 1.2 메모리 사용률 (node_memory_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 80% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 메모리 부족 시 OOMKilled 발생 위험
  - Pod Eviction 가능성 사전 감지
  - 메모리 누수 조기 발견

#### 1.3 디스크 사용률 (node_filesystem_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 80% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - 로그 및 임시 파일로 인한 디스크 고갈 방지
  - 컨테이너 이미지 저장 공간 확보
  - ImagePullBackOff 에러 예방

#### 1.4 노드 수 (cluster_node_count)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 2개 미만 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - 고가용성 유지 (최소 2개 노드 필요)
  - Auto Scaling 그룹 문제 조기 감지
  - Single Point of Failure 방지

#### 1.5 EC2 상태 체크 실패 (StatusCheckFailed)
- **네임스페이스**: `AWS/EC2`
- **임계값**: 0 초과
- **평가 주기**: 1분 (60초)
- **평가 횟수**: 2회 연속
- **통계**: Maximum
- **모니터링 이유**:
  - 하드웨어/네트워크 장애 감지
  - 자동 복구 트리거 (EC2 Auto Recovery)
  - 노드 교체 필요성 판단

---

### 2. Pod/Container 레벨 메트릭

#### 2.1 Pod CPU 사용률 (pod_cpu_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 85% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 애플리케이션 레벨 CPU 병목 감지
  - HPA(Horizontal Pod Autoscaler) 트리거 참고
  - CPU Throttling 가능성 확인

#### 2.2 Pod 메모리 사용률 (pod_memory_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 85% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 메모리 누수 패턴 감지
  - OOMKilled 위험 사전 경고
  - 리소스 할당량(Request/Limit) 조정 필요성 판단

#### 2.3 Pod 재시작 횟수 (pod_number_of_container_restarts) ⚠️ 자동 복구 트리거
- **네임스페이스**: `ContainerInsights`
- **임계값**: 5회 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 1회
- **통계**: Sum
- **모니터링 이유**:
  - CrashLoopBackOff 상태 감지
  - 애플리케이션 안정성 문제 조기 발견
  - 자동 복구 Lambda 함수 트리거 (Pod 재배포 등)
  - 지속적인 재시작 시 근본 원인 분석 필요

#### 2.4 컨테이너 CPU 사용률 (container_cpu_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 80% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 개별 컨테이너 성능 분석
  - Multi-container Pod 내 특정 컨테이너 병목 파악
  - Sidecar 컨테이너 리소스 사용 모니터링

#### 2.5 컨테이너 메모리 사용률 (container_memory_utilization)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 80% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 컨테이너별 메모리 사용 패턴 분석
  - 메모리 누수 컨테이너 식별
  - 효율적인 리소스 할당

#### 2.6 Pod 네트워크 RX/TX (pod_network_rx_bytes / pod_network_tx_bytes)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 100MB/s (100,000,000 bytes/sec)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 네트워크 대역폭 포화 감지
  - DDoS 공격 등 비정상 트래픽 패턴 발견
  - 마이크로서비스 간 통신 병목 파악
  - 네트워크 비용 최적화

#### 2.7 실행 중인 서비스 Pod 수 (service_number_of_running_pods)
- **네임스페이스**: `ContainerInsights`
- **임계값**: 1개 미만 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - 서비스 다운타임 즉각 감지
  - Deployment/ReplicaSet 문제 조기 발견
  - 최소 가용성 보장

---

### 3. ALB (Application Load Balancer) 메트릭

#### 3.1 Surge Queue Length
- **네임스페이스**: `AWS/ApplicationELB`
- **임계값**: 100 (기본값)
- **평가 주기**: 1분 (60초)
- **평가 횟수**: 2회 연속
- **통계**: Maximum
- **모니터링 이유**:
  - 백엔드 서버 처리 능력 부족 감지
  - 큐 대기로 인한 타임아웃 예방
  - Surge Queue가 1024 도달 시 요청 거부됨
  - Scale-out 필요성 판단

#### 3.2 HTTP 5XX 에러 (HTTPCode_ELB_5XX_Count / HTTPCode_Target_5XX_Count)
- **네임스페이스**: `AWS/ApplicationELB`
- **임계값**: 10회 (5분간)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 2회 연속
- **통계**: Sum
- **모니터링 이유**:
  - **ELB 5XX**: ALB 자체 문제 (잘못된 설정, 내부 오류)
  - **Target 5XX**: 백엔드 애플리케이션 에러
  - 서비스 장애 조기 감지
  - 사용자 경험 저하 방지

#### 3.3 응답 지연 시간 - p95 (TargetResponseTime)
- **네임스페이스**: `AWS/ApplicationELB`
- **임계값**: 2.0초 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: p95 (95th percentile)
- **모니터링 이유**:
  - p95를 사용하여 대부분의 사용자(95%) 경험 측정
  - 백엔드 성능 저하 감지
  - 데이터베이스 쿼리 최적화 필요성 파악
  - 사용자 이탈 방지 (응답 시간 > 3초 시 이탈률 증가)

#### 3.4 비정상 호스트 수 (UnHealthyHostCount)
- **네임스페이스**: `AWS/ApplicationELB`
- **임계값**: 0 초과
- **평가 주기**: 1분 (60초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - Health Check 실패한 백엔드 서버 감지
  - 서비스 가용성 저하 경고
  - 자동 복구 또는 수동 개입 필요성 판단

---

### 4. RDS (Relational Database Service) 메트릭

#### 4.1 CPU 사용률 (CPUUtilization)
- **네임스페이스**: `AWS/RDS`
- **임계값**: 80% (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 데이터베이스 성능 병목 감지
  - 비효율적인 쿼리 실행 가능성
  - 인스턴스 타입 업그레이드 필요성 판단
  - Read Replica 추가 고려

#### 4.2 여유 스토리지 공간 (FreeStorageSpace)
- **네임스페이스**: `AWS/RDS`
- **임계값**: 10GB 미만 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - 스토리지 고갈로 인한 쓰기 작업 실패 방지
  - 로그 파일 증가 추적
  - 스토리지 확장 계획 수립
  - 데이터 정리/아카이빙 필요성 판단

#### 4.3 데이터베이스 연결 수 (DatabaseConnections)
- **네임스페이스**: `AWS/RDS`
- **임계값**: 100개 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - Connection Pool 고갈 위험 감지
  - 최대 연결 수(max_connections) 초과 방지
  - 애플리케이션 Connection Leak 가능성 확인
  - Connection Pooling 설정 최적화 필요성

#### 4.4 디스크 큐 깊이 (DiskQueueDepth)
- **네임스페이스**: `AWS/RDS`
- **임계값**: 10 (기본값)
- **평가 주기**: 5분 (300초)
- **평가 횟수**: 3회 연속
- **통계**: Average
- **모니터링 이유**:
  - 디스크 I/O 병목 현상 감지
  - IOPS 부족 가능성 (Provisioned IOPS 증가 필요)
  - 대량의 쓰기 작업으로 인한 대기 큐 증가
  - 스토리지 타입 업그레이드 고려 (gp2 → gp3 → io1)

---

### 5. Route53 Health Check 메트릭

#### 5.1 Health Check 상태 (HealthCheckStatus)
- **네임스페이스**: `AWS/Route53`
- **임계값**: 1 미만 (0 = 비정상)
- **평가 주기**: 1분 (60초)
- **평가 횟수**: 2회 연속
- **통계**: Minimum
- **대상**:
  - Primary (AWS) Health Check
  - Secondary (Azure) Health Check
- **모니터링 이유**:
  - 엔드포인트 가용성 실시간 감시
  - DNS Failover 발생 시점 추적
  - Multi-Region DR 상태 확인
  - 글로벌 트래픽 라우팅 정상 작동 검증

#### 5.2 Health Check 정상 비율 (HealthCheckPercentageHealthy)
- **네임스페이스**: `AWS/Route53`
- **임계값**: 50% 미만
- **평가 주기**: 1분 (60초)
- **평가 횟수**: 2회 연속
- **통계**: Average
- **모니터링 이유**:
  - 글로벌 Health Checker 노드 중 정상 응답 비율 측정
  - 일시적 네트워크 문제와 실제 장애 구분
  - Failover 임박 상태 조기 경고
  - False Positive 알람 감소

#### 5.3 복합 알람 (Composite Alarm) - 모든 사이트 다운 ⚠️ CRITICAL
- **조건**: Primary AND Secondary Health Check 모두 실패
- **모니터링 이유**:
  - **전체 서비스 다운**: AWS와 Azure 모두 장애
  - 긴급 대응 필요 (최고 우선순위)
  - 수동 개입 또는 제3의 백업 사이트 활성화
  - 재난 복구 절차 실행

---

## 알람 설정

### 알람 전달 메커니즘

```
CloudWatch Alarm 발생
       ↓
   SNS Topic
       ↓
   ┌───┴───┐
   ↓       ↓
Email   Lambda
Alert    Auto
        Recovery
```

### SNS 토픽 구성
- **토픽 이름**: `{environment}-eks-monitoring-alerts`
- **구독자**:
  1. 이메일 알림 (운영자)
  2. Lambda 자동 복구 함수

### 알람 중요도 분류

| 중요도 | 알람 종류 | 예시 |
|--------|-----------|------|
| **CRITICAL** | 서비스 다운, 전체 시스템 장애 | 모든 사이트 Health Check 실패, 실행 중인 Pod 0개 |
| **HIGH** | 성능 심각 저하, 자동 복구 필요 | Pod 재시작 5회 초과, 노드 상태 체크 실패 |
| **MEDIUM** | 리소스 임계값 초과 | CPU/메모리 80% 초과, 디스크 공간 10GB 미만 |
| **LOW** | 경고성 알림 | 지연 시간 증가, 에러율 상승 추세 |

---

## 자동 복구 메커니즘

### Lambda 함수 개요
- **함수 이름**: `{environment}-eks-auto-recovery`
- **런타임**: Python 3.11
- **타임아웃**: 300초 (5분)
- **메모리**: 256MB
- **트리거**: SNS Topic 구독

### 자동 복구 시나리오

#### 1. Pod 재시작 과다 (pod_restart_high)
**감지 조건**:
- 5분 동안 Pod 재시작 5회 초과

**자동 복구 액션**:
1. 재시작이 많은 Pod 식별
2. Pod 로그 수집 및 SNS로 전송
3. 문제 Pod 삭제 (Deployment가 자동으로 새 Pod 생성)
4. 재생성된 Pod 상태 확인

**목적**:
- CrashLoopBackOff 상태 해소
- 손상된 Pod 제거 후 정상 Pod로 교체

#### 2. 노드 상태 체크 실패 (node_status_check_failed)
**감지 조건**:
- EC2 StatusCheckFailed > 0 (2회 연속)

**자동 복구 액션**:
1. 문제 노드 식별
2. 노드에서 실행 중인 Pod Drain (안전하게 다른 노드로 이동)
3. Auto Scaling Group에서 해당 인스턴스 Terminate
4. ASG가 자동으로 새 노드 생성
5. 새 노드 Ready 상태 확인

**목적**:
- 하드웨어/네트워크 장애 노드 교체
- 워크로드 중단 최소화

#### 3. 비정상 호스트 감지 (unhealthy_hosts)
**감지 조건**:
- ALB UnHealthyHostCount > 0 (2회 연속)

**자동 복구 액션**:
1. Target Group에서 Unhealthy Target 식별
2. 해당 Pod 재시작
3. Health Check 통과 확인
4. 실패 시 노드 레벨 점검

**목적**:
- 서비스 가용성 신속 복구
- 사용자 영향 최소화

### IAM 권한
Lambda 함수는 다음 권한을 가집니다:
- EKS 클러스터 조회 및 노드 그룹 관리
- Auto Scaling 그룹 관리
- EC2 인스턴스 종료/재부팅
- SNS 메시지 발행
- CloudWatch Logs 작성

---

## CloudWatch 대시보드

### 대시보드 구성
대시보드 이름: `{environment}-eks-monitoring-dashboard`

### 섹션별 구성

#### 1. Node Metrics (노드 메트릭)
- Node CPU Utilization (임계값 표시)
- Node Memory Utilization (임계값 표시)
- Node Disk Utilization (임계값 표시)
- Node Count & Status (Total/Failed Nodes)
- EC2 Status Check Failed (시스템/인스턴스 체크)

#### 2. Container/Pod Metrics (컨테이너/Pod 메트릭)
- Pod CPU Utilization
- Pod Memory Utilization
- Pod Restart Count (자동 복구 임계값 표시)
- Container CPU Utilization (임계값 표시)
- Container Memory Utilization (임계값 표시)
- Pod Network I/O (RX/TX)
- Running Pods & Services

#### 3. ALB Metrics (로드 밸런서 메트릭)
- Request Count (요청 수)
- HTTP 5XX Errors (ELB/Target 구분, 임계값 표시)
- Target Response Time (p50/p95/p99, 임계값 표시)
- Surge Queue Length (임계값 표시)
- Target Health Status (Healthy/Unhealthy)

#### 4. RDS Metrics (데이터베이스 메트릭)
- RDS CPU Utilization (임계값 표시)
- Free Storage Space (임계값 표시)
- Database Connections (임계값 표시)
- Disk Queue Depth (임계값 표시)

#### 5. Route53 Health Check & Failover Status
- Primary (AWS) Health Check Status
- Secondary (Azure) Health Check Status
- Health Check Percentage Healthy (Primary/Secondary, Failover 임계값 표시)

#### 6. Alarm Status & Auto Recovery
- Infrastructure Alarms (노드/EC2 관련 알람 상태)
- Application & Container Alarms (Pod/컨테이너 관련 알람 상태)

### 대시보드 접근 방법
1. AWS Console → CloudWatch 이동
2. 좌측 메뉴에서 "Dashboards" 선택
3. `{environment}-eks-monitoring-dashboard` 검색
4. 자동 새로고침 간격 설정 가능 (10초 ~ 15분)

---

## 로그 보존 정책

### CloudWatch Log Groups
1. **Container Insights Performance Logs**
   - 경로: `/aws/containerinsights/{cluster_name}/performance`
   - 보존 기간: 30일 (기본값)
   - 내용: 노드/Pod/컨테이너 성능 메트릭

2. **Application Logs**
   - 경로: `/aws/containerinsights/{cluster_name}/application`
   - 보존 기간: 30일 (기본값)
   - 내용: 애플리케이션 로그

3. **Lambda Function Logs**
   - 경로: `/aws/lambda/{environment}-eks-auto-recovery`
   - 보존 기간: 30일 (기본값)
   - 내용: 자동 복구 함수 실행 로그

**보존 기간 변경 방법**:
`variables.tf`에서 `log_retention_days` 값 수정 (7, 14, 30, 60, 90, 120, 180, 365일 등)

---

## 운영 가이드

### 일일 점검 사항
1. CloudWatch 대시보드 확인
   - 모든 메트릭이 정상 범위 내인지 확인
   - 알람 상태 점검 (모두 OK 상태여야 함)

2. Route53 Health Check 상태 확인
   - Primary/Secondary 모두 Healthy 상태 확인
   - HealthCheckPercentageHealthy가 100%인지 확인

3. 알람 이메일 확인
   - 야간 또는 주말에 발생한 알람 검토
   - 자동 복구 성공 여부 확인

### 알람 발생 시 대응 절차

#### CPU/메모리 임계값 초과
1. 대시보드에서 추세 확인 (일시적 스파이크 vs 지속적 증가)
2. 원인 분석:
   - 트래픽 증가: Scale-out 고려
   - 메모리 누수: 애플리케이션 재시작 또는 버그 수정
3. 즉각 조치가 필요한 경우 수동 스케일링

#### Pod 재시작 반복
1. 자동 복구 Lambda 로그 확인
2. Pod 로그 분석: `kubectl logs <pod-name> --previous`
3. 근본 원인 해결 (이미지 업데이트, 설정 수정 등)

#### RDS 연결 수 초과
1. 애플리케이션 Connection Pool 설정 확인
2. 슬로우 쿼리 로그 분석
3. Read Replica 추가 고려

#### Failover 발생 (Route53)
1. Primary 사이트 상태 점검
2. 수동 복구 또는 자동 복구 대기
3. Primary 복구 후 트래픽 재분배 확인

### 정기 점검 (주간/월간)
- **주간**: 알람 임계값 적정성 검토
- **월간**: 리소스 사용 추세 분석 및 용량 계획 수립
- **분기**: 모니터링 지표 추가/제거 검토


## 참고 자료

### 관련 파일
- [main.tf](../codes/aws/monitoring/main.tf) - 모니터링 리소스 정의
- [variables.tf](../codes/aws/monitoring/variables.tf) - 임계값 및 변수 설정
- [outputs.tf](../codes/aws/monitoring/outputs.tf) - 출력 값 정의

### AWS 공식 문서
- [Amazon CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Route53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-creating.html)


