# AWS 인프라스트럭처 가이드

이 문서는 AWS Primary Site의 인프라 구성을 설명합니다. 각 모듈의 설계 철학, 서비스 간 연동 방식, 그리고 전체 서비스 플로우에서의 역할을 다룹니다.

---

## 목차

- [설계 철학](#설계-철학)
- [디렉토리 구조](#디렉토리-구조)
- [codes/aws/service - 핵심 인프라](#codesawsservice---핵심-인프라)
  - [VPC 모듈](#vpc-모듈)
  - [EKS 모듈](#eks-모듈)
  - [RDS 모듈](#rds-모듈)
  - [백업 인스턴스](#백업-인스턴스)
- [codes/aws/route53 - DNS 및 Failover](#codesawsroute53---dns-및-failover)
- [codes/aws/monitoring - 모니터링 및 자동 복구](#codesawsmonitoring---모니터링-및-자동-복구)
- [서비스 플로우](#서비스-플로우)
- [리소스 의존성](#리소스-의존성)

---

## 설계 철학

### 왜 이렇게 만들었는가?

**1. 3-Tier 아키텍처 분리**
- Web/WAS/DB 계층을 물리적으로 분리하여 보안과 확장성을 확보
- 각 Tier는 독립적으로 스케일링 가능하며, 장애 전파를 최소화
- 네트워크 보안 그룹으로 Tier 간 통신을 명시적으로 제어

**2. 모듈화된 Terraform 구조**
- 각 모듈(VPC, EKS, RDS)은 독립적으로 관리 및 재사용 가능
- 환경별(dev, staging, prod) 동일한 인프라 재현 가능
- 코드 리뷰와 변경 추적이 용이

**3. Multi-AZ 고가용성**
- 모든 주요 리소스는 2개 이상의 가용영역에 분산 배치
- 단일 AZ 장애에도 서비스 지속성 보장
- RDS는 동기식 Multi-AZ 복제로 데이터 무손실 보장

**4. 비용 최적화와 성능의 균형**
- 테스트 환경에서는 최소 사양으로 비용 절감
- 프로덕션에서는 Auto Scaling으로 트래픽에 맞게 리소스 조정
- NAT Gateway 단일화로 데이터 전송 비용 절감

---

## 디렉토리 구조

```
codes/aws/
├── service/                    # 핵심 인프라
│   ├── main.tf                 # 메인 구성 - 모듈 호출
│   ├── variables.tf            # 입력 변수 정의
│   ├── outputs.tf              # 출력값 정의
│   ├── backup-instance.tf      # 백업 EC2 인스턴스
│   └── modules/
│       ├── vpc/                # 네트워크 인프라
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── eks/                # Kubernetes 클러스터
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── rds/                # 데이터베이스
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── alb/                # 로드밸런서 (옵션)
│           └── main.tf
├── route53/                    # DNS 및 Failover
│   ├── main.tf                 # CloudFront + Route53 구성
│   ├── variables.tf
│   └── outputs.tf
└── monitoring/                 # 모니터링 및 자동 복구
    ├── main.tf                 # CloudWatch 알람, 대시보드, Lambda
    ├── variables.tf
    └── lambda/
        └── auto_recovery.zip   # 자동 복구 Lambda 함수
```

---

## codes/aws/service - 핵심 인프라

### VPC 모듈

**위치**: `codes/aws/service/modules/vpc/main.tf`

#### 역할과 기능

VPC 모듈은 전체 AWS 인프라의 네트워크 기반을 제공합니다. 4개 Tier의 서브넷을 생성하고, 인터넷 및 내부 통신 경로를 설정합니다.

#### 왜 이렇게 설계했는가?

| 설계 결정 | 이유 |
|-----------|------|
| **4-Tier 서브넷 구조** | Public(ALB) → Web(Nginx) → WAS(Spring) → RDS로 트래픽이 단방향으로 흐르며, 각 Tier 간 명확한 보안 경계 설정 |
| **Multi-AZ (2개 AZ)** | 단일 AZ 장애 시에도 서비스 지속 가능. 비용과 고가용성의 균형점 |
| **단일 NAT Gateway** | 모든 Private 서브넷이 하나의 NAT를 공유하여 비용 절감. 고가용성이 필요하면 AZ별 NAT 추가 가능 |
| **Kubernetes 태그** | `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb` 태그로 AWS Load Balancer Controller가 자동으로 서브넷 인식 |

#### 네트워크 구성

```
VPC: 10.0.0.0/16

┌─────────────────────────────────────────────────────────────────┐
│                        Internet Gateway                          │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
┌───────▼───────┐                         ┌────────▼───────┐
│ Public Subnet │                         │ Public Subnet  │
│ 10.0.1.0/24   │                         │ 10.0.2.0/24    │
│ (AZ-2a)       │                         │ (AZ-2c)        │
│ + NAT Gateway │                         │                │
└───────┬───────┘                         └────────────────┘
        │
        │ NAT
        ▼
┌───────────────────────────────────────────────────────────────┐
│                     Private Route Table                        │
└───────────────────────────────────────────────────────────────┘
        │
        ├──────────────────┬──────────────────┬─────────────────┐
        ▼                  ▼                  ▼                 ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌──────────────┐
│ Web Tier      │  │ Web Tier      │  │ WAS Tier      │  │ WAS Tier     │
│ 10.0.11.0/24  │  │ 10.0.12.0/24  │  │ 10.0.21.0/24  │  │ 10.0.22.0/24 │
│ EKS Web Nodes │  │ EKS Web Nodes │  │ EKS WAS Nodes │  │ EKS WAS Nodes│
└───────────────┘  └───────────────┘  └───────────────┘  └──────────────┘
                                              │
                                              │
                          ┌───────────────────┴───────────────────┐
                          ▼                                       ▼
                   ┌───────────────┐                      ┌───────────────┐
                   │ RDS Tier      │                      │ RDS Tier      │
                   │ 10.0.31.0/24  │                      │ 10.0.32.0/24  │
                   │ RDS Primary   │←─ 동기식 복제 ─→     │ RDS Standby   │
                   └───────────────┘                      └───────────────┘
```

#### 서비스 플로우에서의 역할

1. **인터넷 트래픽 수신**: Internet Gateway → ALB (Public Subnet)
2. **내부 라우팅**: ALB → EKS Web Nodes (Web Tier) → EKS WAS Nodes (WAS Tier)
3. **데이터베이스 접근**: WAS Tier → RDS Tier (포트 3306)
4. **아웃바운드 트래픽**: Private Subnet → NAT Gateway → Internet (패키지 다운로드, Azure 백업 등)

---

### EKS 모듈

**위치**: `codes/aws/service/modules/eks/main.tf`

#### 역할과 기능

EKS 모듈은 Kubernetes 클러스터를 생성하고 Web/WAS Tier용 노드 그룹을 관리합니다. 컨테이너화된 애플리케이션의 오케스트레이션을 담당합니다.

#### 왜 이렇게 설계했는가?

| 설계 결정 | 이유 |
|-----------|------|
| **2개의 노드 그룹 (Web/WAS)** | Tier별 독립적인 스케일링, 리소스 할당, 장애 격리 가능. 노드 레이블로 Pod 배치 제어 |
| **Managed Node Group** | AWS가 노드 프로비저닝, AMI 업데이트, 헬스체크 관리. 운영 부담 최소화 |
| **CloudWatch Observability Add-on** | Container Insights 자동 활성화. 별도 에이전트 설치 없이 메트릭/로그 수집 |
| **Public + Private Endpoint** | 개발자는 퍼블릭으로, 노드는 프라이빗으로 API 서버 접근 |
| **삭제 전 리소스 정리** | `null_resource`로 Ingress가 생성한 ALB/NLB를 EKS 삭제 전에 먼저 정리 |

#### 클러스터 구성

```
EKS Cluster (v1.34)
│
├── Control Plane (AWS Managed)
│   ├── API Server
│   ├── etcd
│   ├── Controller Manager
│   └── Scheduler
│
├── Web Node Group
│   ├── Subnet: web-subnet-1 (AZ-2a)
│   ├── Subnet: web-subnet-2 (AZ-2c)
│   ├── Instance Type: t3.medium
│   ├── Scaling: min=2, desired=2, max=4
│   └── Label: tier=web
│
└── WAS Node Group
    ├── Subnet: was-subnet-1 (AZ-2a)
    ├── Subnet: was-subnet-2 (AZ-2c)
    ├── Instance Type: t3.medium
    ├── Scaling: min=2, desired=2, max=4
    └── Label: tier=was
```

#### 설치되는 Add-ons

| Add-on | 역할 |
|--------|------|
| **vpc-cni** | Pod에 VPC IP 할당, 네이티브 AWS 네트워킹 |
| **kube-proxy** | 서비스 디스커버리 및 로드밸런싱 |
| **coredns** | 클러스터 내 DNS 해결 |
| **amazon-cloudwatch-observability** | Container Insights 메트릭/로그 자동 수집 |

#### 서비스 플로우에서의 역할

1. **트래픽 수신**: ALB → Nginx Ingress (Web Node) → Spring Boot (WAS Node)
2. **Pod 간 통신**: VPC CNI로 Pod-to-Pod 직접 통신
3. **외부 서비스 접근**: CoreDNS → NAT Gateway → 인터넷
4. **메트릭 수집**: CloudWatch Agent → Container Insights

---

### RDS 모듈

**위치**: `codes/aws/service/modules/rds/main.tf`

#### 역할과 기능

RDS 모듈은 MySQL 데이터베이스를 Multi-AZ 구성으로 프로비저닝합니다. 애플리케이션의 영구 데이터 저장소 역할을 합니다.

#### 왜 이렇게 설계했는가?

| 설계 결정 | 이유 |
|-----------|------|
| **Multi-AZ 배포** | 동기식 복제로 데이터 무손실, 자동 장애조치 (30-60초) |
| **MySQL 8.0** | 최신 기능(윈도우 함수, CTE), 향상된 성능, LTS 지원 |
| **gp3 스토리지** | IOPS와 처리량 독립 조정 가능, gp2 대비 비용 효율적 |
| **스토리지 자동 확장** | 20GB → 100GB 자동 확장으로 운영 부담 최소화 |
| **Slow Query 로깅** | 2초 이상 쿼리 기록으로 성능 병목 식별 |

#### 데이터베이스 구성

```
RDS MySQL Multi-AZ
│
├── Primary Instance (AZ-2a)
│   ├── Engine: MySQL 8.0
│   ├── Instance: db.t3.medium
│   ├── Storage: 20GB gp3 (Auto-scale to 100GB)
│   ├── Port: 3306
│   └── Endpoint: <db-identifier>.ap-northeast-2.rds.amazonaws.com
│
└── Standby Instance (AZ-2c)
    ├── 동기식 복제 (Synchronous Replication)
    ├── 자동 장애조치 (Automatic Failover)
    └── 읽기 불가 (Hot Standby)

Parameter Group:
├── character_set_server: utf8mb4
├── collation_server: utf8mb4_unicode_ci
├── max_connections: 1000
├── slow_query_log: 1
└── long_query_time: 2
```

#### 보안 구성

- **네트워크 격리**: RDS Tier 서브넷에만 배치 (인터넷 접근 불가)
- **Security Group**: EKS 노드의 Security Group에서만 3306 포트 접근 허용
- **암호화**: 저장 데이터 AES-256 암호화 (AWS KMS)
- **백업**: 7일 자동 백업, 03:00-04:00 UTC 백업 윈도우

---

### 백업 인스턴스

**위치**: `codes/aws/service/backup-instance.tf`

#### 역할과 기능

백업 인스턴스는 RDS 데이터를 Azure Blob Storage로 직접 백업합니다. AWS 리전 장애 시에도 Azure에서 데이터 복구가 가능하도록 합니다.

#### 왜 이렇게 설계했는가?

| 설계 결정 | 이유 |
|-----------|------|
| **EC2 기반 백업** | Lambda 15분 제한 회피, 대용량 DB 덤프 처리 가능 |
| **mysqldump** | 논리 백업으로 클라우드 간 이식성 확보, 압축으로 전송량 절감 |
| **Azure 직접 전송** | S3를 거치지 않고 Azure로 직접 전송하여 AWS 의존성 제거 |
| **Secrets Manager** | RDS 비밀번호, Azure Storage Key를 안전하게 관리 |
| **SSM Session Manager** | SSH 키 없이 안전한 콘솔 접근 |

#### 백업 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS 환경                                 │
│                                                                  │
│  ┌────────────────┐     ┌──────────────────┐                   │
│  │ RDS MySQL      │     │ Secrets Manager  │                   │
│  │ (3306)         │     │ - RDS Password   │                   │
│  │                │     │ - Azure Keys     │                   │
│  └───────┬────────┘     └────────┬─────────┘                   │
│          │ mysqldump             │ IAM Role                     │
│          │                       │                              │
│  ┌───────▼───────────────────────▼────────┐                    │
│  │    Backup Instance (EC2 t3.small)      │                    │
│  │                                         │                    │
│  │  Cron: */5 * * * * (테스트)            │                    │
│  │        0 3 * * *   (운영 - 매일 03:00) │                    │
│  └────────────────────┬───────────────────┘                    │
│                       │                                         │
└───────────────────────┼─────────────────────────────────────────┘
                        │ HTTPS (Azure CLI)
                        ▼
┌───────────────────────────────────────────────────────────────────┐
│                      Azure 환경                                    │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │ Storage Account (bloberry01)                                 │  │
│  │                                                              │  │
│  │  ┌────────────────────────────────────────────────────────┐ │  │
│  │  │ Container: mysql-backups (private)                      │ │  │
│  │  │                                                         │ │  │
│  │  │  backups/                                               │ │  │
│  │  │  ├── backup-20251224-030000.sql.gz                     │ │  │
│  │  │  └── backup-20251225-030000.sql.gz                     │ │  │
│  │  │                                                         │ │  │
│  │  │  Lifecycle: 30일 후 자동 삭제                           │ │  │
│  │  └────────────────────────────────────────────────────────┘ │  │
│  └─────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
```

#### 백업 프로세스

1. **Cron 트리거**: 설정된 스케줄에 따라 백업 스크립트 실행
2. **자격증명 로드**: Secrets Manager에서 RDS 비밀번호, Azure 키 조회
3. **mysqldump 실행**: 전체 데이터베이스 덤프 (--single-transaction)
4. **압축**: gzip으로 파일 크기 축소 (약 80% 감소)
5. **Azure 업로드**: Azure CLI로 Blob Storage에 업로드
6. **로컬 정리**: 24시간 이상 된 로컬 백업 파일 삭제

---

## codes/aws/route53 - DNS 및 Failover

**위치**: `codes/aws/route53/main.tf`

### 역할과 기능

Route53 모듈은 CloudFront를 통한 Origin Failover를 구성합니다. AWS 장애 시 자동으로 Azure 유지보수 페이지로 트래픽을 전환합니다.

### 왜 이렇게 설계했는가?

| 설계 결정 | 이유 |
|-----------|------|
| **CloudFront Origin Failover** | Route53 Failover 대비 더 빠른 장애 감지 (60초 vs 3-5분), Edge에서 처리 |
| **Origin Group** | Primary(AWS ALB) + Secondary(Azure)를 그룹화하여 자동 전환 |
| **캐시 비활성화 (TTL=0)** | 실시간 Failover 응답 보장, 동적 콘텐츠 처리 |
| **TLS 1.2+** | 최신 보안 표준 준수, ACM 인증서 자동 갱신 |

### CloudFront Origin Failover 구조

```
사용자 요청
    │
    ▼
┌───────────────────────────────────────────────────────────────┐
│                    CloudFront Distribution                     │
│                                                                │
│  Origin Group: multi-cloud-failover-group                     │
│  ├── Primary Origin: AWS ALB                                  │
│  │   └── Failover 조건: 500, 502, 503, 504 에러              │
│  └── Secondary Origin: Azure Blob Storage                     │
│       └── 점검 페이지 또는 App Gateway                        │
│                                                                │
│  Cache Behavior:                                               │
│  ├── TTL: 0 (캐시 없음)                                       │
│  ├── Viewer Protocol: HTTPS 리다이렉트                        │
│  └── Origin Protocol: HTTPS only                              │
└───────────────────────────────────────────────────────────────┘
    │                           │
    ▼ (정상 시)                  ▼ (장애 시)
┌─────────────────┐      ┌─────────────────────────────┐
│ AWS ALB         │      │ Azure Blob Static Website   │
│ (Primary)       │      │ 또는 App Gateway (Secondary)│
│                 │      │                             │
│ → EKS → RDS     │      │ → 점검 페이지 → AKS → MySQL │
└─────────────────┘      └─────────────────────────────┘
```

### 서비스 플로우에서의 역할

1. **DNS 해석**: Route53이 도메인을 CloudFront 배포로 연결
2. **Edge 처리**: 전 세계 Edge Location에서 요청 처리
3. **Origin 선택**: Origin Group이 Primary 상태 확인 후 라우팅
4. **Failover 실행**: Primary 5xx 에러 시 자동으로 Secondary로 전환

---

## codes/aws/monitoring - 모니터링 및 자동 복구

**위치**: `codes/aws/monitoring/main.tf`

### 역할과 기능

모니터링 모듈은 인프라 전반의 메트릭을 수집하고, 이상 감지 시 알람을 발생시키며, 자동 복구를 수행합니다.

### 왜 이렇게 설계했는가?

| 설계 결정 | 이유 |
|-----------|------|
| **Container Insights** | EKS 애드온으로 자동 메트릭 수집, 별도 에이전트 설치 불필요 |
| **다계층 알람** | 인프라(노드) → 컨테이너(Pod) → 애플리케이션(ALB) → DB(RDS) 순차 모니터링 |
| **Lambda 자동 복구** | SNS 알람 트리거로 자동 노드 교체, 스케일링 수행 |
| **통합 대시보드** | 모든 메트릭을 한 화면에서 확인, 빠른 상황 파악 |

### 알람 구성

#### 인프라 계층 (Node Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| `node-cpu-high` | node_cpu_utilization | 80% | 노드 CPU 과부하 |
| `node-memory-high` | node_memory_utilization | 85% | 노드 메모리 과부하 |
| `node-disk-high` | node_filesystem_utilization | 80% | 노드 디스크 부족 |
| `node-status-check-failed` | StatusCheckFailed | 0 | EC2 인스턴스 장애 |
| `node-count-low` | cluster_node_count | min_nodes | 노드 수 부족 |

#### 컨테이너 계층 (Pod/Container Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| `pod-cpu-high` | pod_cpu_utilization | 80% | Pod CPU 과부하 |
| `pod-memory-high` | pod_memory_utilization | 85% | Pod 메모리 과부하 |
| `pod-restart-high` | pod_number_of_container_restarts | 5회 | Pod 재시작 과다 |
| `container-cpu-high` | container_cpu_utilization | 90% | 컨테이너 CPU 과부하 |
| `container-memory-high` | container_memory_utilization | 90% | 컨테이너 메모리 과부하 |

#### 애플리케이션 계층 (ALB Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| `alb-5xx-errors-high` | HTTPCode_ELB_5XX_Count | 10회 | ALB 5xx 에러 과다 |
| `target-5xx-errors-high` | HTTPCode_Target_5XX_Count | 10회 | 백엔드 5xx 에러 과다 |
| `alb-latency-high` | TargetResponseTime (p95) | 2초 | 응답 지연 |
| `unhealthy-hosts` | UnHealthyHostCount | 0 | 비정상 대상 감지 |
| `alb-surge-queue-high` | SurgeQueueLength | 100 | 요청 대기열 증가 |

#### 데이터베이스 계층 (RDS Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| `rds-cpu-high` | CPUUtilization | 80% | DB CPU 과부하 |
| `rds-storage-low` | FreeStorageSpace | 5GB | 스토리지 부족 |
| `rds-connections-high` | DatabaseConnections | 800 | 연결 수 과다 |
| `rds-disk-queue-high` | DiskQueueDepth | 10 | 디스크 I/O 병목 |

### 자동 복구 Lambda

```
SNS 알람 → Lambda → 복구 작업
              │
              ├── 노드 장애 감지 → 비정상 노드 종료
              │                   (ASG가 자동 대체)
              │
              ├── Pod 과다 재시작 → 노드그룹 스케일 아웃
              │
              └── 복구 결과 → SNS 알림
```

### CloudWatch 대시보드

대시보드는 다음 섹션으로 구성됩니다:

1. **Cluster Overview**: 노드 CPU/메모리/디스크, 노드 수
2. **Container/Pod Metrics**: Pod CPU/메모리, 재시작 횟수
3. **ALB Metrics**: 요청 수, 5xx 에러, 지연 시간
4. **RDS Metrics**: DB CPU, 스토리지, 연결 수
5. **Route53 Health Check**: Primary/Secondary 상태
6. **Alarm Status**: 전체 알람 상태 요약

---

## 서비스 플로우

### 정상 운영 시 요청 흐름

```
[사용자]
    │
    ▼ HTTPS 요청
[Route53] → domain.com → CloudFront CNAME
    │
    ▼
[CloudFront Distribution]
    │ Origin Group → Primary Origin
    ▼
[AWS ALB] (Public Subnet)
    │ Port 80/443
    ▼
[EKS Web Nodes] (Web Tier Subnet)
    │ Nginx Ingress Controller
    │ Port 8080
    ▼
[EKS WAS Nodes] (WAS Tier Subnet)
    │ Spring Boot PocketBank
    │ Port 8080
    ▼
[RDS MySQL] (RDS Tier Subnet)
    │ Port 3306
    ▼
[응답 반환] → 역순으로 사용자에게 전달
```

### 백업 프로세스 (병렬 실행)

```
[Cron Scheduler] (매 5분 또는 매일 03:00 UTC)
    │
    ▼
[Backup EC2 Instance] (WAS Tier Subnet)
    │
    ├── 1. Secrets Manager에서 자격증명 로드
    │
    ├── 2. mysqldump로 RDS 전체 백업
    │      └── --single-transaction (온라인 백업)
    │
    ├── 3. gzip 압축
    │
    └── 4. Azure Blob Storage 업로드 (HTTPS)
           └── bloberry01.blob.core.windows.net
```

---

## 리소스 의존성

```
terraform apply 순서:

1. VPC 모듈
   ├── VPC
   ├── Internet Gateway
   ├── Subnets (Public, Web, WAS, RDS)
   ├── NAT Gateway
   └── Route Tables

2. EKS 모듈 (depends_on: VPC)
   ├── IAM Roles (Cluster, Nodes)
   ├── EKS Cluster
   ├── Node Groups (Web, WAS)
   └── Add-ons (VPC CNI, CoreDNS, CloudWatch)

3. RDS 모듈 (depends_on: VPC)
   ├── Subnet Group
   ├── Parameter Group
   ├── Security Group
   └── RDS Instance

4. Backup Instance (depends_on: VPC, RDS)
   ├── IAM Role
   ├── Security Group
   ├── Secrets Manager
   └── EC2 Instance

5. Monitoring 모듈 (depends_on: EKS, RDS)
   ├── SNS Topic
   ├── CloudWatch Alarms
   ├── Lambda Function
   └── Dashboard

6. Route53 모듈 (독립적 배포 가능)
   ├── CloudFront Distribution
   └── Route53 Record
```

---

## 참고 문서

- [Azure 인프라 가이드](azure-infrastructure.md) - DR 사이트 구성
- [사용자 가이드](user-guide.md) - 배포 절차
- [DR Failover 절차](dr-failover-procedure.md) - 장애 대응
- [트러블슈팅](troubleshooting.md) - 문제 해결

---

**마지막 업데이트**: 2025-12-27
**작성자**: I2ST-blue
