# 멀티클라우드 기반 서비스 인프라 설계

**프로젝트명:** PlanB - Multi-Cloud DR Solution
**고객사:** PocketBank
**작성일:** 2025년 12월
**작성:** I2ST-blue

---

## 1. 프로젝트 개요

### 1.1 프로젝트 배경

PocketBank의 핵심 금융 서비스는 24시간 365일 무중단 운영이 필수적임. 단일 클라우드 환경에서 발생할 수 있는 리전 장애, 서비스 중단 등의 위험을 최소화하기 위해 멀티클라우드 기반의 재해복구(DR) 시스템을 구축함.

### 1.2 프로젝트 목표

- **고가용성 확보**: AWS 리전 장애 시에도 서비스 연속성 보장
- **데이터 무손실**: 5분 간격 백업으로 최대 5분 이내의 데이터만 손실(RPO ≤ 5분)
- **신속한 복구**: 장애 발생 후 최대 15분 이내 기본 서비스 복구(RTO ≤ 15분)
- **비용 최적화**: Pilot Light 패턴 적용으로 DR 대기 비용 월 $5~10 수준 유지

### 1.3 시스템 구성 요약

| 구분 | Primary Site (AWS) | Secondary Site (Azure) |
|------|-------------------|----------------------|
| 리전 | ap-northeast-2 (서울) | Korea Central |
| 역할 | 운영 환경 | DR 대기/복구 환경 |
| 상태 | Active | Standby (Pilot Light) |

---

## 2. 아키텍처 설계

### 2.1 전체 시스템 아키텍처

```
                                    ┌─────────────────────────────┐
                                    │         사용자 요청          │
                                    └─────────────┬───────────────┘
                                                  │
                                                  ▼
                                    ┌─────────────────────────────┐
                                    │     Amazon CloudFront       │
                                    │     (Origin Failover)       │
                                    └─────────────┬───────────────┘
                                                  │
                         ┌────────────────────────┼────────────────────────┐
                         │ Primary                │                Secondary│
                         ▼                        │                        ▼
            ┌────────────────────────┐            │           ┌────────────────────────┐
            │      AWS (서울)         │            │           │    Azure (한국 중부)    │
            │                        │            │           │                        │
            │  ┌──────────────────┐  │            │           │  ┌──────────────────┐  │
            │  │ Application LB   │  │            │           │  │ App Gateway      │  │
            │  └────────┬─────────┘  │            │           │  └────────┬─────────┘  │
            │           │            │            │           │           │            │
            │  ┌────────▼─────────┐  │            │           │  ┌────────▼─────────┐  │
            │  │ Amazon EKS       │  │            │           │  │ Azure AKS        │  │
            │  │ (Nginx + Spring) │  │            │           │  │ (Nginx + Spring) │  │
            │  └────────┬─────────┘  │            │           │  └────────┬─────────┘  │
            │           │            │            │           │           │            │
            │  ┌────────▼─────────┐  │   백업     │           │  ┌────────▼─────────┐  │
            │  │ Amazon RDS       │──┼───────────▶│           │  │ MySQL Flexible   │  │
            │  │ (MySQL 8.0)      │  │  (5분 간격) │           │  │ Server           │  │
            │  └──────────────────┘  │            │           │  └──────────────────┘  │
            └────────────────────────┘            │           └────────────────────────┘
                                                  │
                                    ┌─────────────▼───────────────┐
                                    │     Azure Blob Storage      │
                                    │     (백업 저장소)            │
                                    └─────────────────────────────┘
```

### 2.2 네트워크 설계

#### AWS VPC 구성

| 서브넷 티어 | CIDR | 용도 | 가용영역 |
|------------|------|------|---------|
| Public | 10.0.1-2.0/24 | ALB, NAT Gateway | 2a, 2c |
| Web Tier | 10.0.11-12.0/24 | EKS Web 노드 | 2a, 2c |
| WAS Tier | 10.0.21-22.0/24 | EKS WAS 노드, 백업 인스턴스 | 2a, 2c |
| RDS Tier | 10.0.31-32.0/24 | RDS Primary/Standby | 2a, 2c |

#### Azure VNet 구성

| 서브넷 | CIDR | 용도 |
|--------|------|------|
| snet-appgw | 172.16.1.0/24 | Application Gateway |
| snet-web | 172.16.11.0/24 | AKS Web 노드풀 |
| snet-was | 172.16.21.0/24 | AKS WAS 노드풀 |
| snet-db | 172.16.31.0/24 | MySQL Flexible Server |

**설계 근거:**
- AWS VPC(10.0.0.0/16)와 Azure VNet(172.16.0.0/16)의 CIDR을 분리하여 향후 VPN/ExpressRoute 연결 시 IP 충돌을 방지함
- 4-Tier 구조(Public → Web → WAS → DB)로 트래픽 흐름을 단방향으로 제한하여 보안 경계를 명확히 함
- Multi-AZ 구성으로 단일 가용영역 장애 시에도 서비스 지속성을 보장함

---

## 3. 기술 스택 및 선정 근거

### 3.1 인프라스트럭처 코드 (IaC)

| 기술 | 버전 | 선정 근거 |
|-----|------|----------|
| **Terraform** | 1.5+ | AWS와 Azure를 단일 코드베이스로 관리 가능함. 선언적 문법으로 인프라 상태를 명시적으로 정의하고, 변경 사항을 계획(plan) 후 적용(apply)할 수 있어 안전함. 모듈화를 통해 VPC, EKS, RDS 등을 재사용 가능한 컴포넌트로 구성함 |

### 3.2 컨테이너 오케스트레이션

| 기술 | 버전 | 환경 | 선정 근거 |
|-----|------|-----|----------|
| **Amazon EKS** | 1.34 | AWS | AWS 관리형 Kubernetes 서비스로 컨트롤 플레인 운영 부담이 없음. IAM 통합으로 세밀한 권한 관리가 가능하고, CloudWatch Container Insights와 네이티브 통합됨 |
| **Azure AKS** | 1.29 | Azure | Azure 관리형 Kubernetes 서비스임. EKS와 동일한 Kubernetes 버전을 사용하여 워크로드 이식성을 확보함. Azure AD 통합으로 엔터프라이즈급 인증/인가 지원함 |

**노드 그룹 설계:**
- Web Tier와 WAS Tier를 별도 노드 그룹으로 분리하여 독립적인 스케일링이 가능함
- 노드 레이블(tier=web, tier=was)을 통해 Pod 배치를 제어함
- Auto Scaling(min=2, max=4)으로 트래픽 변화에 자동 대응함

### 3.3 데이터베이스

| 기술 | 버전 | 환경 | 선정 근거 |
|-----|------|-----|----------|
| **Amazon RDS MySQL** | 8.0 | AWS | Multi-AZ 배포로 동기식 복제를 지원하여 데이터 무손실을 보장함. 자동 장애조치(30-60초), 자동 백업(7일 보관), 스토리지 자동 확장(20GB→100GB)을 지원함 |
| **Azure MySQL Flexible Server** | 8.0.21 | Azure | AWS RDS MySQL과 호환되는 버전을 선택하여 백업 복구 시 호환성 문제를 최소화함. Zone Redundant HA로 가용영역 장애에도 자동 복구됨 |

**스토리지 설계:**
- gp3 스토리지 타입 선택: IOPS와 처리량을 독립적으로 조정 가능하여 gp2 대비 비용 효율적임
- Slow Query Log 활성화(2초 이상 쿼리 기록): 성능 병목 지점을 사전에 식별할 수 있음

### 3.4 로드 밸런서 및 트래픽 관리

| 기술 | 환경 | 선정 근거 |
|-----|-----|----------|
| **Amazon CloudFront** | 글로벌 | Origin Failover 기능으로 Primary(AWS ALB) 장애 시 자동으로 Secondary(Azure)로 전환함. Route53 DNS Failover 대비 더 빠른 장애 감지(60초 vs 3-5분)가 가능함. Edge Location에서 처리하여 글로벌 사용자에게 낮은 지연시간을 제공함 |
| **AWS ALB** | AWS | Layer 7 로드밸런싱으로 HTTP/HTTPS 트래픽을 효율적으로 분산함. EKS Ingress Controller와 통합되어 Kubernetes Service를 자동으로 Target Group에 등록함 |
| **Azure Application Gateway** | Azure | AWS ALB와 동등한 L7 로드밸런싱 기능을 제공함. Zone Redundant 배포로 가용영역 장애에 대응함. Health Probe로 백엔드 상태를 지속적으로 모니터링함 |

### 3.5 애플리케이션 스택

| 기술 | 버전 | 계층 | 선정 근거 |
|-----|------|-----|----------|
| **Nginx** | 1.25-alpine | Web Tier | 경량 웹 서버로 리버스 프록시 및 정적 콘텐츠 서빙에 최적화됨. Alpine 기반으로 이미지 크기가 작아 배포 속도가 빠름 |
| **Spring Boot PetClinic** | Latest | WAS Tier | Java 기반 마이크로서비스 아키텍처의 표준 데모 애플리케이션임. Actuator를 통한 헬스체크, 메트릭 수집이 용이함 |

### 3.6 모니터링 및 관측성

| 기술 | 용도 | 선정 근거 |
|-----|------|----------|
| **CloudWatch Container Insights** | EKS 모니터링 | EKS 애드온으로 설치되어 별도 에이전트 배포 없이 노드/Pod/컨테이너 메트릭을 자동 수집함. CloudWatch Logs, Metrics, Alarms와 네이티브 통합됨 |
| **CloudWatch Alarms + SNS** | 알람 및 알림 | 다계층(노드→Pod→ALB→RDS) 임계값 기반 알람을 설정함. SNS를 통해 Slack, Lambda 자동 복구 함수로 알림을 전달함 |
| **Lambda 자동 복구** | 자동화 복구 | Pod 재시작 과다, 노드 장애 등 감지 시 자동으로 복구 작업을 수행함. 야간/주말 장애에도 신속히 대응 가능함 |

### 3.7 백업 및 재해복구

| 구성요소 | 기술 | 선정 근거 |
|---------|------|----------|
| **백업 인스턴스** | EC2 t3.small | mysqldump 실행을 위해 Lambda(15분 제한)가 아닌 EC2를 선택함. 대용량 DB 덤프도 안정적으로 처리 가능함 |
| **백업 저장소** | Azure Blob Storage | AWS S3가 아닌 Azure로 직접 백업하여 AWS 리전 장애 시에도 백업 데이터 접근이 가능함. 30일 Lifecycle Policy로 스토리지 비용을 관리함 |
| **자격증명 관리** | AWS Secrets Manager | RDS 비밀번호, Azure Storage Key 등 민감 정보를 안전하게 저장하고 IAM Role을 통해 접근 제어함 |

### 3.8 CI/CD 파이프라인 (권장 구성)

| 기술 | 역할 | 선정 근거 |
|-----|------|----------|
| **GitHub Actions / Jenkins** | CI | 빌드, 테스트, 이미지 생성 자동화. GitHub Actions는 별도 인프라 없이 사용 가능하고, Jenkins는 복잡한 파이프라인에 적합함 |
| **ArgoCD** | CD (GitOps) | Kubernetes 네이티브 GitOps 도구임. Git 레포지토리를 Single Source of Truth로 사용하여 배포 상태를 선언적으로 관리함. 자동 동기화, 롤백, 상태 시각화 기능을 제공함 |
| **DockerHub** | 컨테이너 레지스트리 | 퍼블릭/프라이빗 이미지 저장소로 AWS/Azure 양쪽에서 접근 가능함 |

---

## 4. DR 전략: Pilot Light 3단계 Failover

### 4.1 전략 개요

Pilot Light 패턴은 평상시에는 최소한의 리소스만 유지하고, 장애 발생 시 점진적으로 인프라를 활성화하는 방식임. 비용 효율성과 복구 속도의 균형점을 제공함.

### 4.2 단계별 구성

#### Stage 1: Always-On (상시 대기)

**배포 상태:** 항상 활성화
**월 비용:** ~$5~10
**복구 시간:** 즉시 (0분)

| 리소스 | 상태 | 역할 |
|--------|------|------|
| Resource Group | 활성 | 모든 Azure 리소스의 논리적 컨테이너 |
| VNet + Subnets | 활성 (무료) | 네트워크 CIDR 예약, 즉시 배포 가능한 상태 유지 |
| Storage Account | 활성 | AWS RDS 백업 수신, Static Website 호스팅 |
| 점검 페이지 | 활성 | AWS 장애 시 즉시 표시되는 유지보수 안내 페이지 |

**사용자 경험:**
- AWS 장애 발생 시 CloudFront가 자동으로 Azure Blob Storage의 점검 페이지를 표시함
- "시스템 점검 중입니다" 메시지로 사용자 이탈을 방지함

#### Stage 2: Emergency Response (긴급 대응)

**배포 시점:** AWS 장애 감지 후
**추가 월 비용:** +~$50
**복구 시간:** 10-15분

| 리소스 | 배포 순서 | 역할 |
|--------|----------|------|
| MySQL Flexible Server | 1 | 데이터베이스 서버 프로비저닝 |
| DB 백업 복구 | 2 | Blob Storage에서 최신 백업 다운로드 후 복구 |

**복구 절차:**
```bash
cd codes/azure/2-failover
terraform apply  # MySQL 프로비저닝 (~8-10분)
./restore-db.sh  # 최신 백업 복구 (~2-5분)
```

#### Stage 3: Complete Failover (완전 복구)

**배포 시점:** Stage 2 완료 후
**추가 월 비용:** +~$150
**복구 시간:** 15-20분 (Stage 2 이후)

| 리소스 | 배포 순서 | 역할 |
|--------|----------|------|
| Application Gateway | 1 | 외부 트래픽 수신 엔드포인트 |
| AKS Cluster | 2 | Kubernetes 워크로드 실행 환경 |
| Web/WAS Node Pool | 3 | 애플리케이션 컨테이너 실행 |
| PetClinic Pods | 4 | 실제 서비스 배포 |

**복구 완료 후:**
- CloudFront Secondary Origin을 Blob Storage에서 Application Gateway로 수동 변경함
- 정상적인 PetClinic 서비스가 Azure에서 제공됨

### 4.3 Failback (AWS 복구 시)

AWS 인프라가 정상화되면 다음 절차를 수행함:

1. AWS EKS 노드 그룹 복구 확인
2. AWS ALB Health Check 정상 확인
3. CloudFront Secondary Origin을 Blob Storage로 원복
4. CloudFront가 자동으로 Primary(AWS)로 트래픽 라우팅
5. Azure Stage 3 리소스 삭제 (비용 절감)

---

## 5. 백업 시스템

### 5.1 백업 아키텍처

```
┌─────────────────────────────────────────────────────────────────┐
│                          AWS 환경                                 │
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │  RDS MySQL       │      │ Secrets Manager  │                 │
│  │  (Primary DB)    │      │  - RDS Password  │                 │
│  │  Port: 3306      │      │  - Azure Keys    │                 │
│  └────────┬─────────┘      └────────┬─────────┘                 │
│           │ mysqldump               │ IAM Role                   │
│           ▼                         ▼                            │
│  ┌──────────────────────────────────────────────┐               │
│  │       백업 인스턴스 (EC2 t3.small)            │               │
│  │                                               │               │
│  │  Cron: */5 * * * * (5분 간격)                │               │
│  │  1. Secrets Manager에서 자격증명 로드         │               │
│  │  2. mysqldump --single-transaction            │               │
│  │  3. gzip 압축 (80% 크기 감소)                │               │
│  │  4. Azure Blob Storage 업로드                │               │
│  └──────────────────────┬────────────────────────┘               │
└─────────────────────────┼────────────────────────────────────────┘
                          │ HTTPS (Azure CLI)
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│                        Azure 환경                                 │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Storage Account (bloberry01)                                │  │
│  │                                                             │  │
│  │  Container: mysql-backups (private)                        │  │
│  │  ├── backups/backup-20251227-030000.sql.gz                │  │
│  │  ├── backups/backup-20251227-030500.sql.gz                │  │
│  │  └── ...                                                   │  │
│  │                                                             │  │
│  │  Lifecycle Policy: 30일 후 자동 삭제                        │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 백업 특징

| 항목 | 설정값 | 근거 |
|------|--------|------|
| 백업 주기 | 5분 (테스트) / 24시간 (운영) | RPO 요구사항에 따라 조정 가능 |
| 백업 방식 | mysqldump --single-transaction | 온라인 백업으로 서비스 중단 없음 |
| 압축 | gzip | 약 80% 용량 감소로 전송 시간 및 스토리지 비용 절감 |
| 저장 위치 | Azure Blob Storage | AWS 리전 장애 시에도 백업 데이터 접근 가능 |
| 보관 기간 | 30일 | Lifecycle Policy로 자동 삭제하여 비용 관리 |
| 접근 제어 | Private + Storage Key | 인터넷에서 직접 접근 불가, 인증 필수 |

---

## 6. 보안 설계

### 6.1 네트워크 보안

#### AWS Security Groups

| Security Group | Inbound Rule | Source |
|---------------|--------------|--------|
| ALB-SG | 80/443 | 0.0.0.0/0 (Internet) |
| EKS-WebSG | 8080 | ALB-SG |
| EKS-WASSG | 8080 | EKS-WebSG |
| RDS-SG | 3306 | EKS-WASSG, Backup-SG |
| Backup-SG | Outbound 443 | Azure Blob Storage |

#### Azure Network Security Groups

| NSG | Inbound Rule | Source |
|-----|--------------|--------|
| AppGW-NSG | 80/443 | Internet |
| Web-NSG | 8080 | AppGW Subnet |
| WAS-NSG | 8080 | Web Subnet |
| DB-NSG | 3306 | WAS Subnet |

**설계 원칙:**
- 최소 권한 원칙: 필요한 포트와 소스만 허용함
- 계층 간 단방향 통신: 상위 계층에서 하위 계층으로만 접근 허용
- 데이터베이스 격리: RDS/MySQL은 인터넷 접근 완전 차단

### 6.2 데이터 암호화

| 구분 | AWS | Azure |
|------|-----|-------|
| **전송 중 암호화** | ALB↔EKS: HTTPS, RDS↔EKS: TLS, Backup→Azure: HTTPS | AppGW↔AKS: HTTPS, MySQL↔AKS: TLS |
| **저장 시 암호화** | RDS: AES-256 (KMS), EBS: AES-256 | MySQL: TLS, Blob: SSE |

### 6.3 접근 제어

| 서비스 | 접근 제어 방식 |
|--------|---------------|
| AWS IAM | 역할 기반 접근 제어. EKS, RDS, Secrets Manager 등 서비스별 최소 권한 정책 적용 |
| Kubernetes RBAC | 네임스페이스(web, was)별 권한 분리, ServiceAccount를 통한 Pod 수준 IAM 연동(IRSA) |
| Azure RBAC | Resource Group Owner, AKS Operator, MySQL Admin 등 역할 분리 |
| Secrets Manager | IAM Role을 통해 백업 인스턴스만 접근 가능 |

---

## 7. 모니터링 체계

### 7.1 모니터링 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    CloudWatch Metrics                        │
│                                                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   EKS    │  │   ALB    │  │   RDS    │  │ Route53  │   │
│  │  Nodes   │  │ Metrics  │  │ Metrics  │  │  Health  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│       │             │             │             │           │
│       ▼             ▼             ▼             ▼           │
│  ┌──────────────────────────────────────────────────┐      │
│  │          Container Insights                       │      │
│  │   (Pod/Container Level Metrics)                  │      │
│  └──────────────────────────────────────────────────┘      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
            ┌───────────────────────┐
            │  CloudWatch Alarms    │
            └───────────┬───────────┘
                        │
            ┌───────────┴───────────┐
            ▼                       ▼
    ┌──────────────┐        ┌───────────┐
    │ AWS Chatbot  │        │  Lambda   │
    │   (Slack)    │        │   Auto    │
    │              │        │ Recovery  │
    └──────────────┘        └───────────┘
```

### 7.2 알람 임계값

#### 인프라 계층 (Node Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| node-cpu-high | node_cpu_utilization | 80% | 노드 CPU 과부하 |
| node-memory-high | node_memory_utilization | 85% | 노드 메모리 과부하 |
| node-disk-high | node_filesystem_utilization | 80% | 노드 디스크 부족 |
| node-count-low | cluster_node_count | < min_nodes | 노드 수 부족 |

#### 컨테이너 계층 (Pod Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| pod-cpu-high | pod_cpu_utilization | 85% | Pod CPU 과부하 |
| pod-memory-high | pod_memory_utilization | 85% | Pod 메모리 과부하 |
| pod-restart-high | pod_number_of_container_restarts | 5회/5분 | Pod 재시작 과다 (자동 복구 트리거) |

#### 애플리케이션 계층 (ALB Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| alb-5xx-errors-high | HTTPCode_ELB_5XX_Count | 10회/5분 | ALB 5xx 에러 과다 |
| alb-latency-high | TargetResponseTime (p95) | 2초 | 응답 지연 |
| unhealthy-hosts | UnHealthyHostCount | > 0 | 비정상 대상 감지 |

#### 데이터베이스 계층 (RDS Level)

| 알람명 | 메트릭 | 임계값 | 설명 |
|--------|--------|--------|------|
| rds-cpu-high | CPUUtilization | 80% | DB CPU 과부하 |
| rds-storage-low | FreeStorageSpace | < 10GB | 스토리지 부족 |
| rds-connections-high | DatabaseConnections | 800 | 연결 수 과다 |

### 7.3 자동 복구 시나리오

| 감지 조건 | 자동 복구 액션 |
|----------|---------------|
| Pod 재시작 5회 초과 | 문제 Pod 삭제 → Deployment가 새 Pod 생성 |
| 노드 상태 체크 실패 | Pod Drain → 노드 Terminate → ASG가 새 노드 생성 |
| ALB Unhealthy Host | 해당 Pod 재시작 → Health Check 통과 확인 |

---

## 8. 비용 분석

### 8.1 AWS 운영 비용 (예상)

| 리소스 | 사양 | 월 예상 비용 |
|--------|------|-------------|
| EKS 클러스터 | 관리형 Control Plane | ~$73 |
| EC2 노드 (4대) | t3.medium × 4 | ~$140 |
| RDS MySQL | db.t3.medium, Multi-AZ | ~$140 |
| ALB | 시간당 + LCU | ~$25 |
| NAT Gateway | 시간당 + 데이터 전송 | ~$45 |
| CloudFront | 요청 수 + 데이터 전송 | ~$10 |
| 기타 (EBS, S3, 로그) | - | ~$30 |
| **AWS 합계** | | **~$463/월** |

### 8.2 Azure DR 비용 (예상)

#### 평상시 (Pilot Light)

| 리소스 | 월 비용 |
|--------|---------|
| Resource Group | $0 |
| VNet + Subnets | $0 |
| Storage Account (10GB) | ~$5 |
| **합계** | **~$5/월** |

#### 장애 복구 시 (Full Activation)

| 리소스 | 월 비용 | 시간당 비용 |
|--------|---------|-------------|
| MySQL Flexible (B2s) | ~$50 | ~$0.07 |
| AKS 클러스터 (4 nodes) | ~$100 | ~$0.14 |
| Application Gateway v2 | ~$50 | ~$0.07 |
| Public IP (Standard) | ~$4 | ~$0.006 |
| **합계** | **~$204/월** | **~$0.28/시간** |

### 8.3 비용 최적화 전략

1. **Pilot Light 패턴**: 평상시 DR 비용을 월 $5 수준으로 최소화함
2. **Burstable SKU**: DR 리소스는 평상시 사용하지 않으므로 저렴한 Burstable 인스턴스 선택
3. **빠른 Failback**: AWS 복구 후 Azure 리소스 즉시 삭제하여 비용 절감
4. **Reserved Instance 미사용**: DR 리소스는 사용 빈도가 낮아 On-Demand가 유리함
5. **Lifecycle Policy**: 30일 이상 백업 자동 삭제로 스토리지 비용 관리

---

## 9. 운영 절차

### 9.1 일일 점검 사항

| 점검 항목 | 확인 방법 | 정상 기준 |
|----------|----------|----------|
| CloudWatch 대시보드 | AWS Console | 모든 알람 OK 상태 |
| Pod 상태 | kubectl get pods -A | 모든 Pod Running 상태 |
| RDS 상태 | AWS Console | Available, CPU < 70% |
| Azure 백업 | Blob Storage 확인 | 최신 백업 5분 이내 |

### 9.2 장애 대응 절차

#### AWS ALB 불응 감지 (자동)

| 시간 | 이벤트 |
|------|--------|
| T+0s | Health Check 실패 시작 |
| T+90s | 3회 연속 실패 → UNHEALTHY |
| T+120s | CloudFront Origin Failover 감지 |
| T+180s | 사용자 요청 → Azure 점검 페이지 |

#### 완전 복구 필요 시 (수동)

```bash
# Stage 2-3 배포
cd /home/ubuntu/3tier-terraform/codes/azure/2-failover
terraform init && terraform apply

# DB 복구
./restore-db.sh

# AKS 자격증명 획득
az aks get-credentials --resource-group rg-blue --name aks-dr-blue

# PetClinic 배포
kubectl apply -f k8s-manifests/

# CloudFront Secondary Origin 변경 (AWS Console)
# Blob Storage → Application Gateway IP
```

### 9.3 정기 점검

| 주기 | 점검 내용 |
|------|----------|
| 주간 | 알람 임계값 적정성 검토, Slow Query 로그 분석 |
| 월간 | 비용 검토, 리소스 사용 추세 분석, 용량 계획 |
| 분기 | DR 테스트 (실제 Failover 시뮬레이션), 보안 패치 적용 |

---

## 10. 결론

### 10.1 주요 성과

| 목표 | 달성 결과 |
|------|----------|
| 고가용성 | AWS Multi-AZ + Azure DR로 리전 장애에도 서비스 지속 가능 |
| 데이터 보호 | 5분 간격 크로스클라우드 백업으로 RPO ≤ 5분 달성 |
| 신속한 복구 | Pilot Light 패턴으로 RTO ≤ 15분 달성 (Stage 2) |
| 비용 효율성 | DR 대기 비용 월 $5 수준으로 최소화 |
| 운영 자동화 | IaC, 자동 백업, 자동 알람, 자동 복구 Lambda 구현 |

### 10.2 기대 효과

1. **비즈니스 연속성**: AWS 리전 장애 시에도 고객 서비스 중단 최소화
2. **신뢰성 향상**: 멀티클라우드 아키텍처로 단일 벤더 종속 위험 감소
3. **운영 효율성**: 인프라 코드화로 일관된 배포 및 변경 관리
4. **확장성**: 모듈화된 Terraform 구조로 환경별 복제 용이

### 10.3 향후 개선 사항

1. **VPN/ExpressRoute 연결**: AWS-Azure 간 프라이빗 네트워크 연결로 백업 전송 보안 강화
2. **양방향 DR**: Azure를 Primary로도 사용할 수 있도록 양방향 Failover 구현
3. **RTO 단축**: Warm Standby 패턴으로 RTO를 5분 이하로 단축
4. **자동화 강화**: Failover 판단 및 실행까지 완전 자동화

---

**문서 버전:** 1.0
**최종 업데이트:** 2025년 12월 27일
