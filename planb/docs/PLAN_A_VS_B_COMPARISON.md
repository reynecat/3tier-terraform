# Plan A vs Plan B 상세 비교

## 개요

두 가지 DR 전략을 비교하여 프로젝트 요구사항에 맞는 선택을 돕습니다.

## 핵심 차이점

| 항목 | Plan A (Warm Standby) | Plan B (Pilot Light) |
|------|----------------------|---------------------|
| **전략** | 실시간 대기 | 최소 대기 |
| **VPN** | Site-to-Site VPN 항상 연결 | 없음 |
| **데이터 복제** | DMS 실시간 (1분 RPO) | Blob Storage 백업 (5분 RPO) |
| **Azure VM** | 항상 가동 (유지보수 페이지) | 재해 시만 생성 |
| **Azure DB** | 항상 가동 (실시간 동기화) | 재해 시만 생성 |
| **S3** | 이중화 백업 | 미사용 (리전 종속성) |
| **RTO** | 5분 | 2-4시간 |
| **RPO** | 1분 | 5분 |
| **월 비용** | ~$401 | ~$217 |
| **연 비용** | ~$4,812 | ~$2,604 |
| **복잡도** | 높음 | 낮음 |

## 상세 비교

### 1. 아키텍처

#### Plan A (Warm Standby)

```
AWS Primary (항상 가동)
├── EKS Cluster (PetClinic)
├── RDS MySQL (Primary)
└── DMS (실시간 복제)
     │
     │ VPN Tunnel
     ▼
Azure DR (항상 가동)
├── VM 2대 (유지보수 페이지)
├── MySQL (실시간 동기화)
└── Application Gateway

평상시:
- AWS: 100% 트래픽
- Azure: 0% 트래픽, 대기 상태

재해 시:
- Route53 Failover (30초)
- Azure로 자동 전환
```

#### Plan B (Pilot Light)

```
AWS Primary (항상 가동)
├── EKS Cluster (PetClinic)
├── RDS MySQL
└── Backup Instance (mysqldump)
     │
     │ Public Internet (HTTPS)
     ▼
Azure Storage (최소 리소스)
├── Blob Storage (백업만)
└── VNet (예약됨)

평상시:
- AWS: 100% 트래픽
- Azure: 백업 저장소만

재해 시:
1. 점검 페이지 배포 (15분)
2. DB 복구 (60분)
3. 앱 배포 (90분)
4. 서비스 전환 (120분)
```

### 2. 비용 상세 분석

#### Plan A 월 비용 ($401)

**AWS ($205)**
- EKS Control Plane: $73
- EKS Nodes (t3.small × 4): $60
- RDS t3.medium Multi-AZ: $85
- VPN Gateway: $36
- DMS t3.medium: $100
- NAT Gateway: $32
- 데이터 전송: $15
- 기타: $10
- ~~S3 백업~~: ~~$20~~ (제거)

**Azure ($196)**
- VM 2대 (B2s): $60
- MySQL Flexible Server: $50
- Application Gateway: $25
- VPN Gateway: $36
- 스토리지: $5
- 네트워크: $10
- 기타: $10

**총: $401/월**

#### Plan B 월 비용 ($217)

**AWS ($205)**
- EKS Control Plane: $73
- EKS Nodes (t3.small × 4): $60
- RDS t3.medium Multi-AZ: $85
- Backup Instance (t3.small): $15
- VPC Endpoints: $22 (NAT 대체)
- 데이터 전송: $10
- 기타: $10

**Azure ($12)**
- Blob Storage (100GB): $10
- VNet (예약): $0
- 모니터링: $2

**총: $217/월**

**절감액: $184/월 (46%)**
**연간 절감: $2,208**

### 3. 제거된 리소스 (Plan B)

#### AWS에서 제거

```terraform
# VPN Gateway ($36/월)
resource "aws_vpn_gateway" "main" { ... }  # 제거
resource "aws_vpn_connection" "azure" { ... }  # 제거

# DMS ($100/월)
resource "aws_dms_replication_instance" "main" { ... }  # 제거
resource "aws_dms_endpoint" "source" { ... }  # 제거
resource "aws_dms_endpoint" "target" { ... }  # 제거
resource "aws_dms_replication_task" "main" { ... }  # 제거

# S3 (AWS 리전 종속)
resource "aws_s3_bucket" "backup" { ... }  # 제거
```

#### Azure에서 제거 (평상시)

```terraform
# VM ($60/월)
resource "azurerm_linux_virtual_machine" "web" { ... }  # 재해시만 생성
resource "azurerm_linux_virtual_machine" "was" { ... }  # 재해시만 생성

# MySQL ($50/월)
resource "azurerm_mysql_flexible_server" "main" { ... }  # 재해시만 생성

# Application Gateway ($25/월)
resource "azurerm_application_gateway" "main" { ... }  # 재해시만 생성

# VPN Gateway ($36/월)
resource "azurerm_virtual_network_gateway" "main" { ... }  # 제거
```

### 4. 데이터 복제 방식

#### Plan A: DMS 실시간 복제

```
AWS RDS (Primary)
    │
    │ Binary Log Replication
    │ (실시간, 1초 이내)
    ▼
DMS Replication Instance
    │
    │ VPN Tunnel
    │ (Private Network)
    ▼
Azure MySQL (Replica)

장점:
✓ RPO 1분 (거의 실시간)
✓ 데이터 일관성 보장
✓ 자동 Failover 가능

단점:
✗ 비용 높음 ($100/월)
✗ VPN 필요 ($36/월)
✗ 설정 복잡
✗ AWS 리전 마비 시 의미 없음
```

#### Plan B: Blob Storage 백업

```
AWS RDS
    │
    │ mysqldump (5분마다)
    ▼
Backup EC2 Instance
    │
    │ Azure CLI + HTTPS
    │ (Public Internet)
    ▼
Azure Blob Storage

장점:
✓ 비용 저렴 ($15/월)
✓ VPN 불필요
✓ 설정 간단
✓ AWS 독립적

단점:
✗ RPO 5분
✗ 수동 복구 필요
✗ RTO 2-4시간
```

### 5. 네트워크 연결

#### Plan A: VPN Tunnel

```
AWS VPC (10.0.0.0/16)
    │
    │ Site-to-Site VPN
    │ IPsec Tunnel
    │ BGP Routing
    │
    ▼
Azure VNet (172.16.0.0/16)

장점:
✓ Private Network
✓ 보안성 높음
✓ 낮은 지연시간

단점:
✗ 비용 ($36 × 2 = $72/월)
✗ 설정 복잡
✗ AWS 마비 시 무용
```

#### Plan B: Public Internet

```
AWS EC2 (Private Subnet)
    │
    │ NAT Gateway → Internet Gateway
    │ 또는
    │ VPC Endpoint (S3, Secrets Manager)
    │
    ▼
Public Internet (HTTPS)
    │
    ▼
Azure Blob Storage (Public Endpoint)

장점:
✓ VPN 불필요
✓ 설정 간단
✓ 비용 저렴
✓ AWS 독립적

단점:
✗ 공인망 사용
✗ 지연시간 약간 높음
```

### 6. 재해 복구 절차

#### Plan A 절차 (5분)

```
T+0: AWS 장애 감지
    └─ Route53 Health Check 실패

T+1: 자동 Failover
    └─ Route53 DNS 자동 전환
    └─ Azure로 트래픽 라우팅

T+5: 서비스 정상화
    └─ 유지보수 페이지 제공
    └─ (선택) PetClinic 수동 전환

개입: 최소 (거의 자동)
```

#### Plan B 절차 (2-4시간)

```
T+0: AWS 장애 감지
    └─ 모니터링 알림
    └─ 긴급 회의 소집

T+15: 점검 페이지 배포
    └─ ./deploy-maintenance.sh
    └─ Route53 수동 전환

T+60: DB 복구
    └─ ./restore-database.sh
    └─ 최신 백업 다운로드
    └─ Azure MySQL 복구

T+90: PetClinic 배포
    └─ ./deploy-petclinic.sh
    └─ VM 생성 및 앱 배포

T+120: 서비스 전환
    └─ 점검 페이지 → PetClinic
    └─ 고객 공지

개입: 높음 (수동 작업 많음)
```

### 7. 파일 구조 비교

#### Plan A 파일들

```
aws/
├── main.tf (VPN, DMS 포함)
├── dms.tf (DMS 실시간 복제)
├── vpn.tf (Site-to-Site VPN)
└── s3.tf (이중화 백업)

azure/
├── main.tf (전체 리소스 항상 가동)
├── vm-web.tf
├── vm-was.tf
├── mysql.tf (항상 가동)
└── vpn.tf
```

#### Plan B 파일들

```
aws/
├── backup-instance-planb.tf (백업 인스턴스만)
├── vpc-endpoints.tf (비용 절감)
└── scripts/
    └── backup-instance-init-planb.sh

azure/
├── minimal-infrastructure.tf (Storage만)
└── scripts/
    ├── deploy-maintenance.sh
    ├── restore-database.sh
    └── deploy-petclinic.sh

runbooks/
└── emergency-response.md
```

### 8. 사용 사례

#### Plan A가 적합한 경우

- [ ] RTO < 10분 요구
- [ ] RPO < 5분 요구
- [ ] 예산 충분 ($4,000+/년)
- [ ] 자동화 필수
- [ ] 24/7 운영 필수
- [ ] 금융, 의료 등 미션 크리티컬

#### Plan B가 적합한 경우

- [x] RTO 2-4시간 허용
- [x] RPO 5분 허용
- [x] 예산 제한 ($3,000/년)
- [x] 수동 개입 가능
- [x] 일반 웹 서비스
- [x] **우리 프로젝트 (교육/데모)**

### 9. 장단점 요약

#### Plan A 장점
✓ 빠른 복구 (5분)
✓ 최소 데이터 손실 (1분)
✓ 자동화된 Failover
✓ 실시간 동기화

#### Plan A 단점
✗ 높은 비용 ($355/월)
✗ 복잡한 설정
✗ 관리 부담
✗ AWS 마비 시 VPN/DMS 무용

#### Plan B 장점
✓ 저렴한 비용 ($217/월, 38% 절감)
✓ 간단한 설정
✓ AWS 독립적
✓ 리전 장애 대응 가능

#### Plan B 단점
✗ 긴 복구 시간 (2-4시간)
✗ 수동 개입 필요
✗ 약간 높은 RPO (5분)
✗ 긴급 대응 훈련 필요

## 권장 사항

### 우리 프로젝트: Plan B 권장

**이유:**
1. **교육 목적**: 실제 DR 절차 학습
2. **비용 효율**: 38% 절감 ($1,656/년)
3. **충분한 RTO/RPO**: 교육용으로 2-4시간 허용 가능
4. **리전 독립성**: AWS 마비 시에도 복구 가능
5. **실전 경험**: 수동 복구 절차 직접 수행

### Git Branch 전략

```bash
# Main: Plan A 유지 (참고용)
main
├── Full Warm Standby
└── VPN + DMS + Always-On

# Feature: Plan B 개발 (실제 사용)
plan-b-pilot-light
├── Minimal Resources
├── Azure Blob Only
└── Emergency Scripts

# 전환
git checkout plan-b-pilot-light  # 실제 배포
git checkout main                 # 참고/비교
```

## 결론

**Plan B (Pilot Light)** 선택을 권장합니다:

- ✓ 비용 효율적 (38% 절감)
- ✓ 목적에 부합 (교육/데모)
- ✓ 실제 DR 학습 가능
- ✓ AWS 리전 독립적
- ✓ 충분한 RTO/RPO

**다음 단계:**
1. Plan B 브랜치 생성
2. Azure Storage 먼저 배포
3. AWS 백업 인스턴스 배포
4. DR 훈련 실시
