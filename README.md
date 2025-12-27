# Multi-Cloud Disaster Recovery Solution

**AWS (Primary) ↔ Azure (Secondary DR)**

엔터프라이즈급 3-tier 웹 애플리케이션을 위한 Multi-Cloud 재해 복구(DR) 솔루션입니다. Infrastructure as Code(Terraform)를 활용하여 AWS 장애 시 Azure로 자동 전환되는 고가용성 아키텍처를 구현했습니다.

---

## 🎯 프로젝트 목표

- **고가용성(HA)**: 단일 클라우드 장애에도 서비스 지속
- **자동화**: Terraform을 통한 인프라 코드화 및 재현 가능한 배포
- **비용 최적화**: Pilot Light 패턴으로 DR 사이트 대기 비용 최소화
- **실전 적용**: 실제 Spring PetClinic 애플리케이션 기반 검증

---

## 🏗️ 시스템 아키텍처

### 전체 구조

```
┌─────────────────────────────────────────────────────────────┐
│                         사용자                               │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
              ┌─────────────┐
              │ CloudFront  │ (Origin Failover)
              └──────┬──────┘
                     │
         ┌───────────┴───────────┐
         │                       │
    ┌────▼─────┐          ┌─────▼────────┐
    │ AWS ALB  │          │ Azure App GW │
    │ (Primary)│          │ (Secondary)  │
    └────┬─────┘          └──────┬───────┘
         │                       │
    ┌────▼─────┐          ┌─────▼─────┐
    │ EKS      │          │ AKS       │
    │ PetClinic│          │ PetClinic │
    └────┬─────┘          └─────┬─────┘
         │                      │
    ┌────▼─────┐          ┌────▼──────┐
    │ RDS      │──Backup→ │ MySQL     │
    │ MySQL    │          │ Flexible  │
    └──────────┘          └───────────┘
```

### 기술 스택

#### Infrastructure as Code
- **Terraform** 1.14.0+
  - AWS Provider ~> 6.0
  - Azure Provider ~> 3.0
  - Kubernetes Provider

#### AWS Services
- **Compute**: EKS (Kubernetes 1.34)
- **Database**: RDS MySQL Multi-AZ
- **Networking**: VPC, ALB, Route53, CloudFront
- **Backup**: EC2 Instance + Azure Blob Storage
- **Monitoring**: CloudWatch

#### Azure Services
- **Compute**: AKS (Azure Kubernetes Service)
- **Database**: MySQL Flexible Server
- **Networking**: VNet, Application Gateway
- **Storage**: Blob Storage (백업 수신)

#### Application
- **Spring PetClinic**: Spring Boot 2.x 기반 샘플 애플리케이션
- **Container**: Docker + Kubernetes Deployment

---

## 📂 프로젝트 구조

```
3tier-terraform/
├── codes/
│   ├── aws/
│   │   ├── service/          # AWS 인프라 (VPC, EKS, RDS, Backup)
│   │   ├── route53/          # DNS 및 CloudFront Failover
│   │   └── monitoring/       # CloudWatch 알람, 대시보드, 자동 복구 Lambda
│   └── azure/
│       ├── 1-always/         # 상시 대기 리소스 (Storage, VNet, 점검 페이지)
│       └── 2-failover/       # 재해 복구 리소스 (MySQL, AKS, App Gateway)
├── docs/
│   ├── aws-infrastructure.md     # AWS 인프라 상세 가이드 (신규)
│   ├── azure-infrastructure.md   # Azure 인프라 상세 가이드 (신규)
│   ├── architecture.md           # 전체 시스템 아키텍처
│   ├── user-guide.md             # 사용자 배포 가이드
│   ├── backup-system.md          # 백업 시스템 가이드
│   ├── troubleshooting.md        # 트러블슈팅
│   └── dr-failover-procedure.md  # DR 절차서
└── README.md
```

### 디렉토리별 상세 설명

| 디렉토리 | 설명 | 관련 문서 |
|----------|------|-----------|
| `codes/aws/service/` | VPC, EKS, RDS, 백업 인스턴스 - AWS Primary Site 핵심 인프라 | [aws-infrastructure.md](docs/aws-infrastructure.md) |
| `codes/aws/route53/` | CloudFront Origin Failover, Route53 DNS 관리 | [aws-infrastructure.md](docs/aws-infrastructure.md#codesawsroute53---dns-및-failover) |
| `codes/aws/monitoring/` | CloudWatch 알람 (20+), 대시보드, 자동 복구 Lambda | [aws-infrastructure.md](docs/aws-infrastructure.md#codesawsmonitoring---모니터링-및-자동-복구) |
| `codes/azure/1-always/` | 상시 대기 (~$5/월): VNet, Storage, 점검 페이지 | [azure-infrastructure.md](docs/azure-infrastructure.md#codesazure1-always---상시-대기-리소스) |
| `codes/azure/2-failover/` | 장애 시 배포: MySQL, AKS, Application Gateway | [azure-infrastructure.md](docs/azure-infrastructure.md#codesazure2-failover---재해-복구-리소스) |

---

## 🚀 핵심 기능

### 1. **Pilot Light DR 패턴**
- **평상시**: Azure에 최소 리소스만 유지 (Storage, VNet)
- **장애 시**: 15-20분 내 전체 인프라 자동 배포
- **비용 효율**: 대기 비용 ~$10/월, 복구 시에만 전체 비용 발생

### 2. **자동 백업 시스템**
```
AWS RDS → EC2 Backup Instance → Azure Blob Storage
         (매일 03:00 UTC)         (30일 보관)
```
- mysqldump 기반 논리 백업
- 압축 후 Azure Blob Storage 전송
- Blob Lifecycle Policy로 자동 정리

### 3. **Multi-Cloud Failover**
- **CloudFront Origin Failover**: Primary(AWS) 장애 시 Secondary(Azure)로 수동 전환
- **Application Gateway**: Azure AKS → PetClinic 서비스 프록시
- **SSL/TLS**: AppGwSslPolicy20220101 (TLS 1.2+)

### 4. **Infrastructure as Code**
```hcl
# 예시: Azure 2-failover 배포
cd codes/azure/2-failover
terraform init
terraform apply
# → 15-20분 내 MySQL, AKS, App Gateway 자동 생성
```

### 5. **모니터링 및 로깅**
- CloudWatch 대시보드 (EKS, RDS 메트릭)
- Kubernetes Pod 로그 수집
- Azure Monitor (AKS, MySQL)

---

## 🔑 핵심 기술 결정 사항

### 1. CloudFront vs Route53 Failover
- **선택**: CloudFront Origin Failover
- **이유**:
  - HTTPS 종단점 제공
  - 전 세계 엣지 캐싱으로 성능 향상
  - Origin Group 제거로 모든 HTTP 메서드 지원 (POST, PUT, DELETE)
- **트레이드오프**: 자동 failover 불가, 수동 전환 필요

### 2. Kubernetes 기반 배포
- **선택**: EKS(AWS) + AKS(Azure)
- **이유**:
  - 컨테이너 기반 일관된 배포
  - Auto-scaling으로 트래픽 대응
  - 양쪽 클라우드에서 동일한 배포 방식
- **트레이드오프**: VM 대비 복잡성 증가

### 3. MySQL Backup 전략
- **선택**: mysqldump + Azure Blob Storage
- **이유**:
  - 클라우드 간 이동 가능한 논리 백업
  - 압축으로 전송 비용 절감
  - Azure에서 직접 복원 가능
- **대안 고려**: AWS Database Migration Service (실시간 복제, 비용 높음)

### 4. Application Gateway Backend
- **선택**: AKS LoadBalancer IP 직접 참조
- **이유**: 간단한 구조, 빠른 구현
- **개선 필요**: Terraform data source로 동적 조회 (현재 하드코딩)

---

## 📊 재해 복구 시나리오

### 시나리오: AWS ap-northeast-2 리전 완전 마비

| 단계 | 작업 | 소요 시간 | 상태 |
|------|------|-----------|------|
| T+0  | AWS 장애 감지 | - | 🔴 서비스 중단 |
| T+1  | 담당자 CloudFront origin 수동 전환 | 1분 | 🟡 전환 중 |
| T+5  | CloudFront 배포 완료 | 4분 | 🟢 Azure로 서비스 |
| 합계 | | **5분** | ✅ 복구 완료 |

**RTO (Recovery Time Objective)**: 5분
**RPO (Recovery Point Objective)**: 24시간 (마지막 백업 기준)

---

## 🧪 테스트 및 검증

### 장애 시뮬레이션 테스트

```bash
# 1. AWS EKS 노드 그룹 스케일 다운
aws eks update-nodegroup-config \
  --cluster-name eks-prod \
  --nodegroup-name web-nodes \
  --scaling-config minSize=0,maxSize=0,desiredSize=0

# 2. CloudFront origin을 Azure로 전환
aws cloudfront update-distribution \
  --id E2OX3Z0XHNDUN \
  --distribution-config file://azure-config.json

# 3. 접속 확인
curl -I https://blueisthenewblack.store/
# HTTP/2 200 ✅
```

**검증 결과**: 5분 내 정상 서비스 복구 확인

---

## 💰 비용 분석

### 평상시 (AWS Primary + Azure Standby)
| 항목 | AWS | Azure | 합계 |
|------|-----|-------|------|
| Compute | EKS: $73/월 | - | $73 |
| Database | RDS Multi-AZ: $145/월 | - | $145 |
| Storage | - | Blob: $5/월 | $5 |
| Network | ALB: $25/월 | VNet: $0 | $25 |
| **월 합계** | **$243** | **$5** | **$248** |

### 장애 복구 시 (Azure Full Activation)
| 항목 | 비용 | 기간 |
|------|------|------|
| AKS | $73/월 | 복구 기간 |
| MySQL | $50/월 | 복구 기간 |
| App Gateway | $30/월 | 복구 기간 |
| **시간당** | **약 $0.21** | - |

---

## 🔧 개선 계획

### 단기 (1개월)
- [ ] Application Gateway Backend IP 동적 조회 (Terraform data source)
- [ ] 자동 failover 스크립트 (Python + AWS CLI)
- [ ] CI/CD 파이프라인 (GitHub Actions)

### 중기 (3개월)
- [ ] Azure Front Door 도입 (WAF, DDoS 보호)
- [ ] Prometheus + Grafana 모니터링
- [ ] 실시간 데이터베이스 복제 (AWS DMS)

### 장기 (6개월)
- [ ] Multi-region DR (AWS us-east-1 추가)
- [ ] Chaos Engineering 테스트 (Chaos Monkey)
- [ ] 완전 자동화된 DR 전환

---

## 📚 문서

### 인프라 가이드 (신규)
- **[AWS 인프라 가이드](docs/aws-infrastructure.md)**: VPC, EKS, RDS 모듈 설계 철학, 서비스 플로우, 리소스 의존성
- **[Azure 인프라 가이드](docs/azure-infrastructure.md)**: Pilot Light 3단계 전략, 1-always/2-failover 구성, 비용 분석

### 아키텍처 및 배포
- **[전체 아키텍처](docs/architecture.md)**: 시스템 아키텍처 개요, 네트워크 토폴로지, 데이터 흐름
- **[사용자 가이드](docs/user-guide.md)**: 처음부터 끝까지 배포 방법 (단계별 안내)

### 운영 및 장애 대응
- **[백업 시스템](docs/backup-system.md)**: AWS RDS → Azure Blob 백업 구성
- **[모니터링](docs/MONITORING.md)**: CloudWatch 알람, 대시보드, 자동 복구 설정
- **[DR 절차서](docs/dr-failover-procedure.md)**: 재해 복구 체크리스트
- **[트러블슈팅](docs/troubleshooting.md)**: 문제 해결 방법 (8개 섹션)

---

## 🤝 기여

이슈와 PR은 언제나 환영합니다!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 라이선스

이 프로젝트는 MIT 라이선스를 따릅니다.

---

## ✨ 주요 학습 포인트

이 프로젝트를 통해 다음을 학습할 수 있습니다:

- ✅ **Terraform**을 이용한 Infrastructure as Code
- ✅ **Multi-Cloud** 아키텍처 설계 및 구현
- ✅ **Kubernetes**(EKS, AKS) 컨테이너 오케스트레이션
- ✅ **DR(재해 복구)** 전략 수립 및 테스트
- ✅ **네트워크** 설계 (VPC, Subnet, Load Balancer)
- ✅ **데이터베이스** 백업 및 복구
- ✅ **모니터링 및 로깅**
- ✅ **문제 해결 능력** (실전 트러블슈팅)

---

**문서 버전**: v2.0
**최종 수정**: 2025-12-23
**작성자**: I2ST-blue

**프로젝트 데모**: https://blueisthenewblack.store
