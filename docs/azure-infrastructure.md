# Azure 인프라스트럭처 가이드

이 문서는 Azure Secondary (DR) Site의 인프라 구성을 설명합니다. Pilot Light 패턴의 3단계 Failover 전략, 각 단계별 리소스 구성, 그리고 비용 최적화 방안을 다룹니다.

---

## 목차

- [설계 철학](#설계-철학)
- [디렉토리 구조](#디렉토리-구조)
- [Pilot Light 3단계 전략](#pilot-light-3단계-전략)
- [codes/azure/1-always - 상시 대기 리소스](#codesazure1-always---상시-대기-리소스)
- [codes/azure/2-failover - 재해 복구 리소스](#codesazure2-failover---재해-복구-리소스)
- [서비스 플로우](#서비스-플로우)
- [리소스 의존성](#리소스-의존성)
- [비용 분석](#비용-분석)

---

## 설계 철학

### 왜 이렇게 만들었는가?

**1. Pilot Light DR 패턴**
- AWS 장애 시에만 Azure 리소스를 활성화하여 대기 비용 최소화
- 평상시 월 $5~10 수준의 최소 비용으로 DR 체계 유지
- 복구 시간(RTO)과 비용의 균형점 확보

**2. 3단계 점진적 Failover**
- Stage 1: 즉시 점검 페이지 제공 (사용자 이탈 방지)
- Stage 2: 데이터베이스 복구 (데이터 무결성 확보)
- Stage 3: 전체 서비스 복구 (완전한 서비스 재개)
- 각 단계별 독립적 배포 가능

**3. AWS와 대칭적인 아키텍처**
- VNet CIDR: 172.16.0.0/16 (AWS VPC: 10.0.0.0/16과 충돌 방지)
- 동일한 4-Tier 서브넷 구조 (AppGW, Web, WAS, DB)
- AKS 노드 레이블과 EKS 동일 (tier=web, tier=was)
- 동일한 Kubernetes 매니페스트 재사용 가능

**4. Zone Redundant 고가용성**
- Application Gateway: 가용영역 1, 2에 분산
- MySQL Flexible Server: Zone Redundant HA (Primary + Standby)
- AKS 노드풀: 가용영역 1, 2에 분산
- Public IP: Zone Redundant SKU

---

## 디렉토리 구조

```
codes/azure/
├── 1-always/                  # Stage 1: 상시 대기 리소스
│   ├── main.tf                # Resource Group, VNet, Storage, 점검 페이지
│   ├── variables.tf           # 입력 변수 정의
│   └── outputs.tf             # 출력값 정의
│
└── 2-failover/                # Stage 2-3: 재해 복구 리소스
    ├── main.tf                # MySQL, AKS, Application Gateway
    ├── variables.tf           # 입력 변수 정의
    ├── outputs.tf             # 출력값 정의
    └── restore-db.sh          # 데이터베이스 복구 스크립트
```

### 디렉토리 분리 이유

| 디렉토리 | 배포 시점 | 비용 영향 | 목적 |
|----------|-----------|-----------|------|
| `1-always` | 최초 1회 | $5~10/월 | 백업 수신, 점검 페이지 대기 |
| `2-failover` | 장애 발생 시 | +$150~200/월 | 전체 서비스 복구 |

분리함으로써:
- 실수로 비용이 발생하는 리소스를 배포하는 것을 방지
- 각 단계의 상태를 독립적으로 관리 (terraform state 분리)
- 복구 시 필요한 단계만 선택적으로 배포 가능

---

## Pilot Light 3단계 전략

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AWS 장애 감지                                    │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  Stage 1: Always-On (즉시 - 0분)                                        │
│                                                                          │
│  ┌─────────────┐  ┌───────────────────────────────────────────────────┐ │
│  │ Blob Static │  │ 이미 배포됨:                                       │ │
│  │ Website     │  │ - Resource Group                                   │ │
│  │             │  │ - VNet + Subnets (무료)                           │ │
│  │ 점검 페이지 │  │ - Storage Account (백업 수신 중)                  │ │
│  │ 표시        │  │ - Route53 CNAME                                    │ │
│  └─────────────┘  └───────────────────────────────────────────────────┘ │
│                                                                          │
│  CloudFront Secondary Origin → Blob Static Website                      │
│  비용: ~$5/월                                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ terraform apply (codes/azure/2-failover)
┌─────────────────────────────────────────────────────────────────────────┐
│  Stage 2: Database Recovery (10-15분)                                   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ MySQL Flexible Server (Zone Redundant)                               ││
│  │ ├── Primary: Zone 1                                                  ││
│  │ └── Standby: Zone 2 (동기식 복제)                                   ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
│  복구 절차:                                                              │
│  1. MySQL Flexible Server 프로비저닝 (8-10분)                           │
│  2. Blob Storage에서 최신 백업 다운로드                                 │
│  3. mysql < backup.sql 로 데이터 복구                                   │
│                                                                          │
│  비용: +~$50/월                                                          │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ 동일한 terraform apply 계속
┌─────────────────────────────────────────────────────────────────────────┐
│  Stage 3: Full Service (15-75분)                                        │
│                                                                          │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────┐  │
│  │ Application      │  │ AKS Cluster       │  │ PetClinic Pods       │  │
│  │ Gateway          │  │ (Zone Redundant)  │  │                      │  │
│  │                  │  │                   │  │ ┌────────────────┐   │  │
│  │ Public IP        │→│ Web Node Pool    │→│ │ Nginx Ingress  │   │  │
│  │ (Zone Redundant) │  │ (Zone 1, 2)      │  │ └────────────────┘   │  │
│  │                  │  │                   │  │ ┌────────────────┐   │  │
│  │                  │  │ WAS Node Pool    │→│ │ Spring Boot    │   │  │
│  │                  │  │ (Zone 1, 2)      │  │ └────────────────┘   │  │
│  └──────────────────┘  └──────────────────┘  └──────────────────────┘  │
│                                                                          │
│  CloudFront Secondary Origin 변경: Blob → Application Gateway           │
│  비용: +~$150/월                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## codes/azure/1-always - 상시 대기 리소스

**위치**: `codes/azure/1-always/main.tf`

### 역할과 기능

1-always 모듈은 AWS 정상 운영 중에도 항상 실행되어야 하는 최소한의 Azure 리소스를 관리합니다. 백업 수신, 점검 페이지 호스팅, 네트워크 예약을 담당합니다.

### 리소스 구성

#### Resource Group

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-dr-${var.environment}"
  location = var.location  # koreacentral
}
```

- **역할**: 모든 DR 리소스의 논리적 컨테이너
- **비용**: 무료
- **왜 필요한가**: Azure 리소스 관리, 권한 경계, 비용 추적의 기본 단위

#### Virtual Network

```
VNet: 172.16.0.0/16 (Azure)
│
├── snet-appgw     172.16.1.0/24   Application Gateway 전용
├── snet-web       172.16.11.0/24  AKS Web 노드풀
├── snet-was       172.16.21.0/24  AKS WAS 노드풀
└── snet-db        172.16.31.0/24  MySQL Flexible Server
                                    (Service Delegation 포함)
```

- **역할**: DR 사이트의 네트워크 기반
- **비용**: 무료 (예약만, 리소스 미배포)
- **왜 필요한가**:
  - AWS VPC(10.0.0.0/16)와 충돌 방지
  - Stage 2-3 리소스가 즉시 배포 가능하도록 서브넷 사전 예약
  - MySQL Delegation으로 Flexible Server 요구사항 충족

#### Storage Account

```hcl
resource "azurerm_storage_account" "backups" {
  name                     = var.storage_account_name  # bloberry01
  account_tier             = "Standard"
  account_replication_type = "LRS"  # 단일 리전 복제

  static_website {
    index_document = "index.html"  # 점검 페이지
  }

  blob_properties {
    versioning_enabled = true
  }
}
```

- **역할**: AWS RDS 백업 수신 + 점검 페이지 호스팅
- **비용**: ~$5/월 (백업 데이터 양에 따라 변동)
- **왜 필요한가**:
  - AWS 리전 장애 시에도 데이터 복구 가능
  - Static Website로 즉시 점검 페이지 제공
  - Blob Versioning으로 백업 파일 보호

#### Backup Container

```hcl
resource "azurerm_storage_container" "mysql_backups" {
  name                  = "mysql-backups"
  container_access_type = "private"  # Storage Key 필수
}
```

- **역할**: mysqldump 파일 저장소
- **접근 제어**: Private (Storage Account Key 필요)
- **경로**: `mysql-backups/backups/backup-YYYYMMDD-HHMMSS.sql.gz`

#### Lifecycle Policy

```hcl
resource "azurerm_storage_management_policy" "backup_lifecycle" {
  rule {
    name    = "deleteOldBackups"
    filters {
      prefix_match = ["mysql-backups/backups/"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }
}
```

- **역할**: 30일 이상 된 백업 자동 삭제
- **왜 필요한가**: 스토리지 비용 관리, 불필요한 데이터 정리

#### 점검 페이지 (Static Website)

```hcl
resource "azurerm_storage_blob" "maintenance_page" {
  name                   = "index.html"
  storage_container_name = "$web"
  content_type           = "text/html"
  source_content         = <<HTML
    <!DOCTYPE html>
    <html>
    <head><title>서비스 점검 중</title></head>
    <body>
      <h1>시스템 점검 중입니다</h1>
      <p>DR 사이트 대기 중</p>
    </body>
    </html>
  HTML
}
```

- **역할**: AWS 장애 시 즉시 표시되는 점검 페이지
- **접근 URL**: `https://{storage_account_name}.z12.web.core.windows.net/`
- **왜 필요한가**: 사용자에게 서비스 상태 안내, 이탈 방지

#### Route53 CNAME

```hcl
resource "aws_route53_record" "azure_maintenance" {
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.subdomain_name  # azure.domain.com
  type    = "CNAME"
  ttl     = 300
  records = ["${var.storage_account_name}.z12.web.core.windows.net"]
}
```

- **역할**: 서브도메인을 Azure Static Website로 연결
- **왜 필요한가**: CloudFront Secondary Origin 설정에 사용

### 서비스 플로우에서의 역할

```
[AWS 장애 발생]
      │
      ▼
[CloudFront] Origin Group Failover 감지
      │ Primary (AWS ALB) → 5xx 에러
      │
      ▼
[Secondary Origin] → bloberry01.z12.web.core.windows.net
      │
      ▼
[Static Website] → index.html (점검 페이지)
      │
      ▼
[사용자] "시스템 점검 중입니다" 메시지 확인
```

---

## codes/azure/2-failover - 재해 복구 리소스

**위치**: `codes/azure/2-failover/main.tf`

### 역할과 기능

2-failover 모듈은 AWS 장애 시에만 배포되는 전체 서비스 복구 리소스를 관리합니다. MySQL, AKS, Application Gateway를 프로비저닝합니다.

### 리소스 구성

#### Data Sources (1-always 참조)

```hcl
data "azurerm_resource_group" "main" {
  name = var.resource_group_name  # rg-dr-prod
}

data "azurerm_virtual_network" "main" {
  name                = var.vnet_name
  resource_group_name = var.resource_group_name
}

data "azurerm_subnet" "appgw" { ... }
data "azurerm_subnet" "web" { ... }
data "azurerm_subnet" "was" { ... }
data "azurerm_subnet" "db" { ... }
```

- **역할**: 1-always에서 생성된 리소스 참조
- **왜 필요한가**: State 분리로 독립적 배포, 기존 리소스 재사용

#### MySQL Flexible Server

```hcl
resource "azurerm_mysql_flexible_server" "main" {
  name                   = "mysql-dr-${var.environment}"
  administrator_login    = var.db_username
  administrator_password = var.db_password

  sku_name = "B_Standard_B2s"  # Burstable tier (비용 최적화)
  version  = "8.0.21"

  # Zone Redundant 고가용성
  zone = "1"
  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  storage {
    size_gb = 32
  }
}
```

| 설정 | 값 | 이유 |
|------|-----|------|
| **SKU** | B_Standard_B2s | DR 복구 시에만 사용, Burstable로 비용 절감 |
| **HA Mode** | ZoneRedundant | AZ 장애에도 자동 Failover |
| **Version** | 8.0.21 | AWS RDS와 호환성 확보 |

#### Database 생성

```hcl
resource "azurerm_mysql_flexible_database" "main" {
  name        = var.db_name  # AWS RDS와 동일
  server_name = azurerm_mysql_flexible_server.main.name
  charset     = "utf8mb4"
  collation   = "utf8mb4_unicode_ci"
}
```

- **역할**: 빈 데이터베이스 생성 (백업 복구 대상)
- **왜 필요한가**: restore-db.sh 스크립트로 데이터 복구

#### AKS Cluster

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-dr-${var.environment}"
  kubernetes_version  = var.kubernetes_version
  dns_prefix          = "aks-dr-${var.environment}"

  # Web 노드풀 (default_node_pool)
  default_node_pool {
    name                = "web"
    vm_size             = "Standard_D2s_v3"
    zones               = ["1", "2"]  # Zone Redundant
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 4
    node_labels = {
      "tier" = "web"  # EKS와 동일한 레이블
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "10.240.0.0/16"
    dns_service_ip = "10.240.0.10"
  }
}
```

| 설정 | 값 | 이유 |
|------|-----|------|
| **Network Plugin** | Azure CNI | Pod-to-Pod 직접 통신, VNet 통합 |
| **Network Policy** | Azure | Pod 간 트래픽 제어 |
| **Zones** | [1, 2] | 가용영역 분산으로 고가용성 |
| **Auto Scaling** | 2-4 nodes | 트래픽에 따른 자동 조정 |

#### WAS 노드풀

```hcl
resource "azurerm_kubernetes_cluster_node_pool" "was" {
  name                  = "was"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D2s_v3"
  zones                 = ["1", "2"]
  enable_auto_scaling   = true
  min_count             = 2
  max_count             = 4

  node_labels = {
    "tier" = "was"
  }
}
```

- **역할**: Spring Boot 애플리케이션 실행
- **왜 분리했는가**: Web/WAS 독립 스케일링, 리소스 격리

#### Application Gateway

```hcl
resource "azurerm_application_gateway" "main" {
  name     = "appgw-${var.environment}"
  zones    = ["1", "2"]  # Zone Redundant

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  # Backend Pool → AKS LoadBalancer IP
  backend_address_pool {
    name         = "aks-backend-pool"
    ip_addresses = ["20.214.124.157"]  # AKS LB IP
  }

  # Health Probe → PetClinic 루트 경로
  probe {
    protocol            = "Http"
    path                = "/"
    interval            = 30
    timeout             = 20
    unhealthy_threshold = 3
    port                = 8080
  }

  # HTTP Listener → 80 포트
  http_listener {
    frontend_port_name = "http-port"
    protocol           = "Http"
  }

  # SSL Policy → TLS 1.2+
  ssl_policy {
    policy_name = "AppGwSslPolicy20220101"
  }
}
```

| 설정 | 값 | 이유 |
|------|-----|------|
| **SKU** | Standard_v2 | Zone Redundant 지원 |
| **Zones** | [1, 2] | 가용영역 분산 |
| **Backend** | AKS LB IP | AKS 서비스 로드밸런서로 트래픽 전달 |
| **SSL Policy** | 20220101 | TLS 1.2 최소 버전 강제 |

#### Zone Redundant Public IP

```hcl
resource "azurerm_public_ip" "appgw" {
  name              = "pip-appgw-${var.environment}"
  allocation_method = "Static"
  sku               = "Standard"
  zones             = ["1", "2"]
}
```

- **역할**: Application Gateway의 인터넷 엔드포인트
- **왜 Zone Redundant**: 단일 AZ 장애에도 IP 유지

### 서비스 플로우에서의 역할

```
[Stage 2-3 배포 완료 후]
      │
      ▼
[CloudFront Secondary Origin 수동 변경]
      │ bloberry01.z12.web.core.windows.net
      │ → pip-appgw-prod.koreacentral.cloudapp.azure.com
      │
      ▼
[Application Gateway] (20.xxx.xxx.xxx:80)
      │ Backend Pool
      ▼
[AKS LoadBalancer] (20.214.124.157:8080)
      │
      ├── Web Node Pool
      │   └── Nginx Ingress Pod
      │
      └── WAS Node Pool
          └── Spring Boot PetClinic Pod
                │
                ▼
[MySQL Flexible Server] (mysql-dr-prod.mysql.database.azure.com:3306)
      │
      ▼
[데이터 반환] → 역순으로 사용자에게 전달
```

---

## 서비스 플로우

### 정상 운영 시 (AWS Active)

```
[사용자]
    │
    ▼ HTTPS 요청
[CloudFront] → Primary Origin (AWS ALB)
    │
    ▼
[AWS EKS] → [RDS MySQL]
    │
    ▼
[응답 반환]

[Azure (Background)]
├── Storage Account: 5분/24시간마다 백업 수신 중
├── VNet: 예약됨 (비용 없음)
└── 점검 페이지: 대기 중
```

### Failover 시나리오

```
[T+0] AWS 장애 감지
    │
    ▼
[CloudFront] Origin Group Failover
    │ Primary (AWS ALB) → 5xx 에러
    │
    ▼
[T+1분] Secondary Origin 활성화
    │ → bloberry01.z12.web.core.windows.net
    │
    ▼
[사용자] 점검 페이지 확인

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[T+5분] 운영자 판단: 복구 필요

    cd codes/azure/2-failover
    terraform apply

[T+15분] MySQL Flexible Server 준비 완료
    │
    ▼
[운영자] 백업 복구 실행
    ./restore-db.sh

[T+20분] 데이터베이스 복구 완료

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[T+45분] AKS 클러스터 준비 완료
    │
    ▼
[운영자] Kubernetes 매니페스트 배포
    kubectl apply -f k8s-manifests/

[T+60분] PetClinic Pods Running
    │
    ▼
[운영자] CloudFront Secondary Origin 변경
    Blob Static Website → Application Gateway

[T+65분] 전체 서비스 복구 완료
    │
    ▼
[사용자] 정상 서비스 이용
```

---

## 리소스 의존성

### 1-always 배포 순서

```
terraform apply (codes/azure/1-always)
│
├── 1. Resource Group
│
├── 2. Virtual Network
│   └── Subnets (appgw, web, was, db)
│
├── 3. Storage Account
│   ├── mysql-backups container
│   ├── $web container (static website)
│   └── Lifecycle Policy
│
├── 4. Maintenance Page Upload
│   └── index.html
│
└── 5. Route53 CNAME (optional)
    └── azure.domain.com → blob static website
```

### 2-failover 배포 순서

```
terraform apply (codes/azure/2-failover)
│
├── Data Sources (1-always 참조)
│   ├── Resource Group
│   ├── VNet
│   ├── Subnets
│   └── Storage Account
│
├── 1. MySQL Flexible Server (8-10분)
│   └── Database 생성
│
├── 2. AKS Cluster (15-20분)
│   └── Web Node Pool (default)
│
├── 3. WAS Node Pool (5분, AKS 완료 후)
│   └── depends_on: AKS
│
├── 4. Role Assignments
│   ├── AKS → VNet (Network Contributor)
│   └── AKS → RG (Contributor)
│
├── 5. Public IP (1분)
│   └── Zone Redundant
│
└── 6. Application Gateway (10분)
    └── depends_on: Public IP, Subnet
```

### 수동 작업 순서

```
terraform apply 완료 후:

1. 데이터베이스 복구
   cd codes/azure/2-failover
   ./restore-db.sh

2. AKS 자격증명 획득
   az aks get-credentials \
     --resource-group rg-dr-prod \
     --name aks-dr-prod

3. Kubernetes 매니페스트 배포
   kubectl apply -f k8s-manifests/namespaces.yaml
   kubectl apply -f k8s-manifests/secrets.yaml
   kubectl apply -f k8s-manifests/deployments/
   kubectl apply -f k8s-manifests/services/

4. Pod 상태 확인
   kubectl get pods -A

5. CloudFront Secondary Origin 변경
   AWS Console → CloudFront → Distribution
   Origin: bloberry01.z12.web.core.windows.net
        → pip-appgw-prod IP 또는 DNS
```

---

## 비용 분석

### 평상시 (AWS Active, Azure Standby)

| 리소스 | 월 비용 | 설명 |
|--------|---------|------|
| Resource Group | $0 | 무료 |
| Virtual Network | $0 | 예약만, 리소스 미배포 |
| Subnets | $0 | 예약만 |
| Storage Account | ~$5 | LRS, 백업 데이터 10GB 기준 |
| **합계** | **~$5** | |

### 장애 복구 시 (Azure Full Activation)

| 리소스 | 월 비용 | 시간당 비용 |
|--------|---------|-------------|
| MySQL Flexible (B2s) | ~$50 | ~$0.07 |
| AKS Cluster (4 nodes) | ~$100 | ~$0.14 |
| Application Gateway v2 | ~$50 | ~$0.07 |
| Public IP (Standard) | ~$4 | ~$0.006 |
| **합계** | **~$204** | **~$0.28** |

### 복구 시간별 추가 비용 예상

| 복구 기간 | 추가 비용 |
|-----------|-----------|
| 1시간 | ~$0.30 |
| 8시간 | ~$2.30 |
| 24시간 | ~$6.80 |
| 1주일 | ~$47 |
| 1개월 | ~$204 |

### 비용 최적화 팁

1. **Burstable SKU 사용**: MySQL B_Standard, 복구 시에만 사용하므로 충분
2. **AKS 노드 최소화**: min_count=2로 시작, 트래픽에 따라 Auto Scaling
3. **복구 후 빠른 Failback**: AWS 복구되면 Azure 리소스 즉시 삭제
4. **Reserved Instance 미사용**: DR 리소스는 On-Demand가 적합

---

## 참고 문서

- [AWS 인프라 가이드](aws-infrastructure.md) - Primary Site 구성
- [백업 시스템](backup-system.md) - AWS → Azure 백업 구성
- [DR Failover 절차](dr-failover-procedure.md) - 장애 대응 절차
- [DR Failover 테스트 가이드](dr-failover-testing-guide.md) - 테스트 시나리오

---

**마지막 업데이트**: 2025-12-27
**작성자**: I2ST-blue
