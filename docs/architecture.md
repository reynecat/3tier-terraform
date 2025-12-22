# 3-Tier Terraform Multi-Cloud DR Architecture

## 📋 프로젝트 개요

**PlanB** - 다중 클라우드 재해 복구(DR) 솔루션으로, **AWS(주)**와 **Azure(보조)**를 연동한 3계층 아키텍처입니다.
자동 DNS 페일오버를 통해 AWS 장애 시 단계별로 Azure 리소스를 활성화합니다.

- **Infrastructure as Code:** Terraform + Kubernetes
- **Primary Site:** AWS (ap-northeast-2, Seoul)
- **Secondary Site:** Azure (Korea Central, 3-stage failover)
- **Application:** Spring Boot PetClinic + Nginx
- **Database:** MySQL 8.0 Multi-AZ

---

## 🏗️ 전체 시스템 아키텍처

```mermaid
graph TB
    User["👥 User<br/>Browser"]

    subgraph DNS["☁️ Route53 DNS Failover"]
        R53["Route53<br/>Hosted Zone"]
        HC1["🟢 Health Check<br/>Primary"]
        HC2["🔴 Health Check<br/>Secondary"]
    end

    subgraph AWS["🔵 AWS Primary Site<br/>ap-northeast-2"]
        subgraph VPC["VPC: 10.0.0.0/16"]
            IGW["Internet<br/>Gateway"]
            NAT["NAT<br/>Gateway"]

            subgraph WebTier["Web Tier<br/>10.0.11-12.0/24"]
                EKS_Web["EKS Web Nodes<br/>t3.medium × 2"]
                Nginx["Nginx Pods<br/>1.25-alpine<br/>2 replicas"]
            end

            subgraph WASTier["WAS Tier<br/>10.0.21-22.0/24"]
                EKS_WAS["EKS WAS Nodes<br/>t3.medium × 2"]
                Spring["Spring Boot Pods<br/>PetClinic<br/>2 replicas"]
                Backup["Backup EC2<br/>t3.small"]
            end

            subgraph RDSTier["RDS Tier<br/>10.0.31-32.0/24"]
                RDS["RDS MySQL 8.0<br/>Multi-AZ<br/>db.t3.medium"]
            end

            ALB["ALB<br/>Internet-facing<br/>80/443"]
        end
    end

    subgraph Azure["🔴 Azure DR Site<br/>Korea Central"]
        subgraph Stage1["Stage 1: Always-On<br/>💰 $50-100/month"]
            VNet["VNet: 172.16.0.0/16"]
            Blob["Blob Storage<br/>mysql-backups<br/>Static Website"]
        end

        subgraph Stage2["Stage 2: Emergency<br/>💰 +$200-300/month<br/>⏱️ T+0~15분"]
            AppGW["Application<br/>Gateway<br/>Standard_v2"]
            AzureMySQL["MySQL Flexible<br/>Server<br/>B_Standard_B2s"]
            Maintenance["Maintenance<br/>Page"]
        end

        subgraph Stage3["Stage 3: Failover<br/>💰 +$400-500/month<br/>⏱️ T+15~75분"]
            AKS["AKS Cluster<br/>v1.29<br/>3 Nodes"]
            AKS_Nginx["Nginx Pods<br/>2 replicas"]
            AKS_Spring["Spring Boot Pods<br/>2 replicas"]
        end
    end

    User -->|HTTPS| R53
    R53 -->|Monitor| HC1
    R53 -->|Monitor| HC2
    HC1 -->|Health Check| ALB
    HC2 -->|Health Check| AppGW

    R53 -.->|Primary<br/>Healthy| ALB
    R53 -.->|Failover<br/>Unhealthy| AppGW

    ALB --> IGW
    IGW --> NAT
    NAT --> Nginx
    NAT --> Spring

    Nginx -->|proxy_pass<br/>:8080| Spring
    Spring -->|JDBC<br/>:3306| RDS

    EKS_Web -.->|Host| Nginx
    EKS_WAS -.->|Host| Spring

    Backup -->|mysqldump<br/>5분 간격| RDS
    Backup -->|Upload<br/>gzip| Blob

    AppGW -->|Stage 1<br/>Static Site| Blob
    AppGW -->|Stage 2<br/>Restore DB| AzureMySQL
    AppGW -->|Stage 3<br/>Full Stack| AKS

    AKS -.->|Deploy| AKS_Nginx
    AKS -.->|Deploy| AKS_Spring

    AKS_Nginx -->|proxy_pass| AKS_Spring
    AKS_Spring -->|JDBC| AzureMySQL

    Blob -.->|Restore<br/>Latest Backup| AzureMySQL

    style AWS fill:#e3f2fd,stroke:#1976d2,stroke-width:3px
    style Azure fill:#ffe0e0,stroke:#d32f2f,stroke-width:3px
    style DNS fill:#f0f4c3,stroke:#f57f17,stroke-width:2px
    style VPC fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    style WebTier fill:#f3e5f5,stroke:#7b1fa2
    style WASTier fill:#fce4ec,stroke:#c2185b
    style RDSTier fill:#e0f2f1,stroke:#00796b
    style Stage1 fill:#c8e6c9,stroke:#2e7d32,stroke-width:2px
    style Stage2 fill:#ffccbc,stroke:#d84315,stroke-width:2px
    style Stage3 fill:#ffab91,stroke:#bf360c,stroke-width:2px
```

---

## 🔄 데이터 흐름 (Data Flow)

### **정상 운영 시 (AWS)**

```mermaid
sequenceDiagram
    participant User as 👥 User
    participant R53 as Route53
    participant ALB as AWS ALB
    participant Nginx as Nginx Pod
    participant Spring as Spring Boot
    participant RDS as RDS MySQL
    participant Backup as Backup EC2
    participant Blob as Azure Blob

    User->>R53: DNS Query (domain.com)
    R53->>User: Primary: ALB IP
    User->>ALB: HTTPS Request
    ALB->>Nginx: HTTP :8080
    Nginx->>Spring: Proxy :8080
    Spring->>RDS: JDBC :3306
    RDS-->>Spring: Data
    Spring-->>Nginx: Response
    Nginx-->>ALB: Response
    ALB-->>User: HTTPS Response

    loop Every 5 minutes
        Backup->>RDS: mysqldump
        RDS-->>Backup: backup.sql
        Backup->>Blob: Upload gzip
    end
```

### **페일오버 시나리오 (AWS → Azure)**

```mermaid
sequenceDiagram
    participant User as 👥 User
    participant R53 as Route53
    participant HC as Health Check
    participant ALB as AWS ALB
    participant AppGW as Azure AppGW
    participant Blob as Blob Storage
    participant MySQL as Azure MySQL
    participant AKS as AKS Cluster

    Note over ALB: AWS Failure
    HC->>ALB: Health Check
    ALB-->>HC: Timeout (3 failures)
    HC->>R53: Mark Unhealthy

    Note over R53: T+90s: DNS Failover
    User->>R53: DNS Query
    R53->>User: Secondary: AppGW IP

    Note over AppGW,Blob: Stage 1: Maintenance Page
    User->>AppGW: HTTPS Request
    AppGW->>Blob: Static Website
    Blob-->>AppGW: index.html
    AppGW-->>User: Maintenance Page

    Note over MySQL: Stage 2: DB Restore (T+0~15분)
    Blob->>MySQL: Restore Latest Backup

    Note over AKS: Stage 3: Full Failover (T+15~75분)
    AKS->>AKS: Deploy Pods
    AppGW->>AKS: Route Traffic
    AKS->>MySQL: Connect DB
    User->>AppGW: HTTPS Request
    AppGW->>AKS: Forward
    AKS-->>AppGW: Response
    AppGW-->>User: Full Service
```

---

## 📊 AWS VPC 네트워크 아키텍처

```mermaid
graph TB
    subgraph Internet["🌐 Internet"]
        Users["Users"]
    end

    subgraph AZ1["Availability Zone: ap-northeast-2a"]
        subgraph Public1["Public Subnet<br/>10.0.1.0/24"]
            IGW1["Internet Gateway"]
            NAT1["NAT Gateway<br/>Elastic IP"]
        end

        subgraph Web1["Web Tier<br/>10.0.11.0/24"]
            EKS_Web1["EKS Web Node"]
            SG_Web1["SG: 8080 from ALB"]
        end

        subgraph WAS1["WAS Tier<br/>10.0.21.0/24"]
            EKS_WAS1["EKS WAS Node"]
            Backup1["Backup EC2"]
            SG_WAS1["SG: 8080 from Web"]
        end

        subgraph RDS1["RDS Tier<br/>10.0.31.0/24"]
            RDS_Primary["RDS Primary"]
            SG_RDS1["SG: 3306 from EKS"]
        end
    end

    subgraph AZ2["Availability Zone: ap-northeast-2c"]
        subgraph Public2["Public Subnet<br/>10.0.2.0/24"]
            NAT2["NAT Gateway<br/>Optional"]
        end

        subgraph Web2["Web Tier<br/>10.0.12.0/24"]
            EKS_Web2["EKS Web Node"]
        end

        subgraph WAS2["WAS Tier<br/>10.0.22.0/24"]
            EKS_WAS2["EKS WAS Node"]
        end

        subgraph RDS2["RDS Tier<br/>10.0.32.0/24"]
            RDS_Standby["RDS Standby<br/>Multi-AZ"]
        end
    end

    ALB["Application<br/>Load Balancer"]

    Users -->|HTTPS| ALB
    ALB --> IGW1
    IGW1 --> NAT1
    NAT1 --> EKS_Web1
    NAT1 --> EKS_WAS1
    NAT1 --> EKS_Web2
    NAT1 --> EKS_WAS2

    EKS_Web1 --> SG_Web1
    EKS_WAS1 --> SG_WAS1
    RDS_Primary --> SG_RDS1

    EKS_WAS1 -->|Private| RDS_Primary
    RDS_Primary <-.->|Sync Replication| RDS_Standby

    style AZ1 fill:#e3f2fd,stroke:#1976d2
    style AZ2 fill:#e3f2fd,stroke:#1976d2
    style Public1 fill:#fff3e0,stroke:#f57c00
    style Public2 fill:#fff3e0,stroke:#f57c00
    style Web1 fill:#f3e5f5,stroke:#7b1fa2
    style Web2 fill:#f3e5f5,stroke:#7b1fa2
    style WAS1 fill:#fce4ec,stroke:#c2185b
    style WAS2 fill:#fce4ec,stroke:#c2185b
    style RDS1 fill:#e0f2f1,stroke:#00796b
    style RDS2 fill:#e0f2f1,stroke:#00796b
```

---

## 🔵 Azure VNet 네트워크 아키텍처

```mermaid
graph TB
    subgraph Internet2["🌐 Internet"]
        Users2["Users<br/>Failover"]
    end

    subgraph RG["Resource Group: Korea Central"]
        subgraph VNet["VNet: 172.16.0.0/16"]
            subgraph AppGW_Subnet["App Gateway Subnet<br/>172.16.1.0/24"]
                AppGW2["Application Gateway<br/>Public IP<br/>Standard_v2"]
                NSG_AppGW["NSG: 80/443"]
            end

            subgraph Web_Subnet["Web Subnet<br/>172.16.11.0/24"]
                AKS_Web["AKS Web Nodes<br/>Stage 3"]
                NSG_Web2["NSG: 8080"]
            end

            subgraph WAS_Subnet["WAS Subnet<br/>172.16.21.0/24"]
                AKS_WAS["AKS App Nodes<br/>Stage 3"]
                NSG_WAS2["NSG: 8080"]
            end

            subgraph DB_Subnet["DB Subnet<br/>172.16.31.0/24"]
                MySQL2["MySQL Flexible<br/>Server<br/>Stage 2"]
                NSG_DB["NSG: 3306"]
            end

            subgraph AKS_Subnet["AKS Subnet<br/>172.16.41.0/24"]
                AKS2["AKS System<br/>& User Nodes"]
                NSG_AKS["NSG: 443"]
            end
        end

        Blob2["Blob Storage<br/>mysql-backups<br/>Static Website<br/>Stage 1"]
    end

    Users2 -->|Failover| AppGW2
    AppGW2 -->|Stage 1| Blob2
    AppGW2 -->|Stage 2| MySQL2
    AppGW2 -->|Stage 3| AKS2

    AKS2 --> AKS_Web
    AKS2 --> AKS_WAS
    AKS_WAS --> MySQL2

    Blob2 -.->|Restore| MySQL2

    style RG fill:#ffe0e0,stroke:#d32f2f,stroke-width:2px
    style VNet fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style AppGW_Subnet fill:#fff3e0,stroke:#f57c00
    style Web_Subnet fill:#f3e5f5,stroke:#7b1fa2
    style WAS_Subnet fill:#fce4ec,stroke:#c2185b
    style DB_Subnet fill:#e0f2f1,stroke:#00796b
    style AKS_Subnet fill:#e1f5fe,stroke:#01579b
```

---

## 🚀 Azure 3단계 페일오버 전략

```mermaid
stateDiagram-v2
    [*] --> Stage1_Always: 평상시 (AWS 정상)

    state "Stage 1: Always-On" as Stage1_Always {
        [*] --> VNet_Ready
        VNet_Ready --> Blob_Active
        Blob_Active --> Backup_Receiving
        Backup_Receiving --> Static_Website

        note right of Blob_Active
            💰 Cost: $50-100/month
            - VNet (예약, 무료)
            - Blob Storage (LRS)
            - 30일 백업 보관
        end note
    }

    Stage1_Always --> Stage2_Emergency: AWS 장애 감지<br/>(T+0분)

    state "Stage 2: Emergency Response" as Stage2_Emergency {
        [*] --> Deploy_AppGW
        Deploy_AppGW --> Deploy_MySQL
        Deploy_MySQL --> Restore_DB
        Restore_DB --> Show_Maintenance

        note right of Deploy_MySQL
            💰 Cost: +$200-300/month
            ⏱️ Time: 10-15분
            - App Gateway 활성화
            - MySQL 복구
            - 유지보수 페이지
        end note
    }

    Stage2_Emergency --> Stage3_Failover: 완전 복구 필요<br/>(T+15분)

    state "Stage 3: Complete Failover" as Stage3_Failover {
        [*] --> Deploy_AKS
        Deploy_AKS --> Deploy_Pods
        Deploy_Pods --> Connect_DB
        Connect_DB --> Full_Service

        note right of Deploy_AKS
            💰 Cost: +$400-500/month
            ⏱️ Time: 15-20분
            - AKS 클러스터
            - Nginx + Spring Boot
            - 정상 서비스
        end note
    }

    Stage3_Failover --> AWS_Recovered: AWS 복구 완료
    AWS_Recovered --> Stage1_Always: Failback
```

---

## 🛠️ Terraform 모듈 구조

### **AWS 구성**

**주요 파일:**
- `main.tf` - VPC, EKS, RDS 모듈 호출
- `route53.tf` - DNS Failover 설정
- `backup-instance.tf` - 백업 자동화 EC2

**모듈 구조:**
- `modules/vpc/` - 네트워크 인프라 (VPC, Subnets, IGW, NAT)
- `modules/eks/` - Kubernetes 클러스터 (v1.34, 2 Node Groups)
- `modules/rds/` - MySQL 데이터베이스 (Multi-AZ, db.t3.medium)
- `modules/alb/` - 로드밸런서 (Internet-facing, 80/443)

**EKS 구성:**
- Web Tier Node Group: t3.medium × 2-4 (Auto-scaling)
- WAS Tier Node Group: t3.medium × 2-4 (Auto-scaling)
- Add-ons: vpc-cni, kube-proxy, coredns

**RDS 구성:**
- Engine: MySQL 8.0
- Instance: db.t3.medium
- Storage: 20GB gp3 (Auto-scale to 100GB)
- Multi-AZ: Enabled (Primary + Standby)
- Backup: 7-day retention
- Encryption: AES-256

### **Azure 구성**

**1-always/ (Stage 1):**
- `main.tf` - Resource Group, VNet, Subnets
- `storage.tf` - Blob Storage, Lifecycle policy
- `static-website.tf` - Maintenance page

**2-emergency/ (Stage 2):**
- `mysql.tf` - MySQL Flexible Server (B_Standard_B2s)
- `appgw.tf` - Application Gateway (Standard_v2)

**3-failover/ (Stage 3):**
- `aks.tf` - AKS Cluster (v1.29, 3 nodes)

---

## 📈 Kubernetes 배포 구조

### **네임스페이스**
- `web` - Nginx 웹 서버
- `was` - Spring Boot 애플리케이션

### **Web Tier (Nginx)**

**Deployment:**
- Image: `nginx:1.25-alpine`
- Replicas: 2
- Resources: CPU 200m-400m, Memory 256Mi-512Mi
- Port: 8080

**Service:**
- Type: LoadBalancer (via ALB Ingress)
- Port: 80 → 8080

**Probes:**
- Liveness: `/health` (10s)
- Readiness: `/health` (5s)
- Startup: `/health` (3s)

### **WAS Tier (Spring Boot)**

**Deployment:**
- Image: `springio/petclinic:latest`
- Replicas: 2
- Resources: CPU 1-2, Memory 1Gi-2Gi
- Port: 8080

**Service:**
- Type: ClusterIP (internal)
- Port: 8080 → 8080

**Environment:**
- `SPRING_DATASOURCE_URL` (from Secret)
- `SPRING_DATASOURCE_USERNAME` (from Secret)
- `SPRING_DATASOURCE_PASSWORD` (from Secret)
- `SPRING_PROFILES_ACTIVE=mysql`

**Probes:**
- Startup: `/actuator/health` (30 attempts × 3s)
- Liveness: `/actuator/health` (10s)
- Readiness: `/actuator/health` (5s)

---

## 🔐 보안 아키텍처

### **네트워크 보안**

**AWS Security Groups:**
- ALB-SG: Inbound 80/443 (from Internet)
- EKS-WebSG: Inbound 8080 (from ALB)
- EKS-WASSG: Inbound 8080 (from Web)
- RDS-SG: Inbound 3306 (from EKS)
- Backup-SG: Outbound 443 (to Azure)

**Azure Network Security Groups:**
- AppGW-NSG: Inbound 80/443 (Internet)
- Web-NSG: Inbound 8080 (from App Gateway)
- WAS-NSG: Inbound 8080 (from Web)
- DB-NSG: Inbound 3306 (from WAS)
- AKS-NSG: Inbound 443 (Kubernetes API)

### **데이터 암호화**

**AWS:**
- In Transit: RDS ↔ EKS (TLS), Backup → Azure (HTTPS), ALB ↔ Internet (HTTPS/ACM)
- At Rest: RDS (AES-256/KMS), EBS (AES-256), Secrets Manager (KMS)

**Azure:**
- In Transit: MySQL ↔ AKS (TLS), App Gateway ↔ Internet (HTTPS), Blob (HTTPS)
- At Rest: MySQL (TLS), Blob (SSE), Key Vault (AES-256)

### **접근 제어**

**AWS IAM:**
- EKS Cluster Role: EKS service permissions
- Node Role: ECR, CloudWatch, EBS, RDS
- Backup Role: Secrets Manager, RDS, S3
- ALB Role: Load balancer controller (via IRSA)

**Kubernetes RBAC:**
- System: Cluster admin (kube-system)
- Users: Limited (web, was namespaces)
- Service accounts: Pod-level IAM (IRSA)

**Azure RBAC:**
- Resource Group Owner: Deployment
- AKS Operator: Cluster management
- MySQL Admin: Database access
- Storage Contributor: Blob access

---

## 🔍 모니터링 및 로깅

### **AWS CloudWatch**

**Metrics:**
- EKS: cluster_node_count, pod_cpu_utilization, pod_memory_utilization, pod_network_io
- ALB: RequestCount, TargetResponseTime, HTTPCode_Target_5XX, UnHealthyHostCount
- RDS: CPUUtilization, DatabaseConnections, DiskQueueDepth, Replication Lag, Read/WriteLatency
- EC2 Backup: StatusCheckFailed, NetworkIn/Out, CPUUtilization

**Logs:**
- EKS Control Plane: api, audit, authenticator, controllerManager, scheduler
- Application Logs: /var/log/containers/*
- RDS Logs: error, general, slowquery, audit
- VPC Flow Logs: Network traffic analysis

### **Azure Monitor**

**Metrics:**
- AKS: Node CPU/Memory, Pod Count, Network Bytes
- MySQL: CPU/Memory/Storage Percent, Active Connections, Replication Lag
- App Gateway: Current Connections, Total Requests, Failed Requests, Response Time
- Blob Storage: Used Capacity, Blob Count, Transaction

**Alerts:**
- High CPU (> 80%)
- High Memory (> 85%)
- Database Connection Errors
- Backup Failure
- App Gateway Health
- Static Website Availability

---

## 🚀 배포 순서

### **Phase 1: AWS 프로덕션 (1~2시간)**

1. **Terraform init & plan** (AWS credentials configured)
2. **VPC 생성** (5분) - VPC, Subnets, IGW, NAT
3. **EKS 클러스터 생성** (15분) - Cluster endpoint 준비
4. **EKS Node Groups 생성** (20분) - Web & WAS node groups
5. **RDS 인스턴스 생성** (15-20분) - Multi-AZ 설정, Database 초기화
6. **ALB 생성** (5분) - Target groups, listeners
7. **Route53 구성** (2분) - Health checks, Failover policy
8. **Backup EC2 생성** (5분) - IAM role, security group, User data script
9. **Kubernetes 매니페스트 배포** (10분) - Namespaces, deployments, services, ingress
10. **검증 및 테스트** (15분) - DNS failover test, Pod readiness check, Database connectivity

### **Phase 2: Azure DR 기초 (30~40분)**

1. **Stage 1: Always-On 배포** (15분) - Resource Group, VNet & Subnets, Storage Account, Blob containers, Static website
2. **백업 스크립트 테스트** (10분) - mysqldump → Azure Blob 확인
3. **Route53 Health Check 활성화** (5분) - Secondary endpoint 모니터링

### **Phase 3: Stage 2-3 준비 (옵션)**

Stage 2-3 Terraform 코드를 준비하고 긴급 시 `terraform apply` 실행:
- **Stage 2:** MySQL Flexible Server, Application Gateway
- **Stage 3:** AKS 클러스터, Kubernetes 매니페스트

---

## 🛠️ 운영 절차

### **정상 운영 시 확인사항**

**Daily:**
- AWS CloudWatch 대시보드 확인 (EKS Pod, RDS CPU/Memory < 70%, ALB 응답시간 < 200ms, Route53 Health Check: OK)
- Azure 백업 확인 (Blob Storage: 최신 backup 파일 존재)

**Weekly:**
- RDS Slow Query 로그 확인
- EKS Node 상태 확인 (CPU/Memory usage, Disk usage)
- ALB Target Health 확인
- Backup 복구 테스트 (선택)

**Monthly:**
- 비용 검토 (AWS + Azure)
- 보안 패치 적용 (EKS 버전 업그레이드, Node AMI 업데이트, Kubernetes manifests 검토)
- DR 테스트 (DNS failover 시뮬레이션, Azure Stage 2-3 deployment 테스트)
- 용량 계획 (Scaling 필요성 검토)

### **장애 대응 절차**

**AWS ALB 불응 감지 (자동):**
- **T+0s:** Health check failure 시작 (매 30초)
- **T+90s:** 3번 연속 실패 → UNHEALTHY
- **T+150s:** DNS 레코드 전환 (Route53) → Secondary record (Azure App Gateway)
- **T+210s:** 사용자 요청 → Azure로 리다이렉트

**사용자 영향:**
- 브라우저 캐시 TTL: 60초
- 약 1-3분 후 Azure 유지보수 페이지 표시

**복구 절차:**
- AWS 장애 원인 파악 & 복구
- ALB Health check → HEALTHY
- Route53 자동 전환: Primary (AWS)로 복원
- 사용자: AWS로 자동 복귀 (DNS TTL 후)

**수동 복구 (필요시):**
- AWS 수동 확인 (EC2, RDS, EKS 상태)
- Route53 failover preference 수동 변경
- 수동 DNS 전환 또는 Route53 health check 비활성화

### **주요 모니터링 항목**

**Critical:**
- Route53 Health Check Status (Primary & Secondary)
- ALB Target Health (All targets HEALTHY)
- EKS Node Status (Ready)
- RDS Instance Status (Available)
- Database Connections (< max_connections)
- Azure Blob Backup (Latest < 5 minutes old)

**Warning:**
- Pod CPU/Memory Usage (> 80%)
- RDS CPU/Memory (> 70%)
- ALB Response Time (> 500ms)
- Database Replication Lag (Multi-AZ)
- Disk Usage (RDS auto-scaling utilized)
- Backup File Size (Growing normally)

**Info:**
- Request rate & patterns
- Error rates by endpoint
- API response time percentiles
- Database query patterns
- Cost trends (AWS + Azure)

---

## 📚 주요 파일 및 경로

```
/home/ubuntu/3tier-terraform/
├── README.md
├── docs/
│   ├── architecture.md (이 문서)
│   ├── failover.md
│   └── backup.md
├── codes/
│   ├── aws/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── route53.tf
│   │   ├── backup-instance.tf
│   │   ├── modules/
│   │   │   ├── vpc/
│   │   │   ├── eks/
│   │   │   ├── rds/
│   │   │   └── alb/
│   │   ├── k8s-manifests/
│   │   │   ├── namespaces.yaml
│   │   │   ├── web/
│   │   │   ├── was/
│   │   │   └── ingress/
│   │   └── scripts/
│   └── azure/
│       ├── 1-always/
│       │   ├── main.tf
│       │   ├── storage.tf
│       │   └── static-website.tf
│       ├── 2-emergency/
│       │   ├── mysql.tf
│       │   └── appgw.tf
│       └── 3-failover/
│           └── aks.tf
└── .gitignore
```

---

## ✅ 체크리스트

### **배포 전 확인**

- [ ] AWS 계정 접근 가능 (ap-northeast-2 region)
- [ ] Azure 구독 접근 가능 (Korea Central region)
- [ ] Terraform v1.0+ 설치
- [ ] kubectl 설치
- [ ] AWS CLI v2 설치
- [ ] Azure CLI 설치
- [ ] Domain name 소유 (Route53 hosted zone 생성 가능)
- [ ] ACM SSL 인증서 요청 (AWS)

### **배포 후 확인**

- [ ] AWS EKS 클러스터 정상 실행
- [ ] 모든 Pod RUNNING 상태
- [ ] RDS MySQL 데이터베이스 접근 가능
- [ ] ALB가 Nginx & Spring Boot 정상 응답
- [ ] Route53 Health Check: Primary HEALTHY
- [ ] Azure Blob에 첫 백업 파일 생성
- [ ] DNS failover 테스트 성공

### **운영 준비**

- [ ] CloudWatch 대시보드 설정
- [ ] Azure Monitor 알림 설정
- [ ] 백업 복구 테스트
- [ ] DR 테스트 계획 수립
- [ ] 팀 교육 (운영 절차)
- [ ] 비상 연락처 등록
- [ ] 문서화 완료

---

**마지막 업데이트:** 2025-12-22
**작성자:** DevOps Team
**상태:** Production Ready
