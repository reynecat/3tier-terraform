# DR Plan B - Pilot Light 시나리오

## 개요

이 브랜치는 **Pilot Light** DR 전략을 구현합니다.

### Plan A vs Plan B 비교

| 항목 | Plan A (Warm Standby) | Plan B (Pilot Light) |
|------|----------------------|---------------------|
| VPN 연결 | ✓ 항상 연결 | ✗ 없음 |
| 데이터 복제 | DMS 실시간 | Blob Storage 백업 (5분) |
| Azure VM | 항상 가동 | 비상시만 생성 |
| Azure DB | 항상 가동 | 비상시만 생성 |
| 비용 | ~$150/월 | ~$30/월 |
| RTO | 5분 | 2-4시간 |
| RPO | 1분 | 5분 |
| 복잡도 | 높음 | 낮음 |

## 아키텍처

### 평상시 (Normal Operation)

```
┌─────────────────────────────────────┐
│           AWS Primary               │
│                                     │
│  ┌─────┐  ┌─────┐  ┌──────┐       │
│  │ EKS │──│ RDS │  │  S3  │       │
│  └─────┘  └──┬──┘  └──────┘       │
│             │                       │
│             │ Backup EC2            │
│             ▼                       │
│  ┌─────────────────────┐           │
│  │  Backup Instance    │           │
│  │  - mysqldump (5분)  │           │
│  │  - Azure CLI        │           │
│  └──────────┬──────────┘           │
│             │                       │
└─────────────┼───────────────────────┘
              │
              │ HTTPS (Public Internet)
              │
              ▼
┌─────────────────────────────────────┐
│         Azure (Minimal)             │
│                                     │
│  ┌──────────────────────┐          │
│  │  Blob Storage        │          │
│  │  mysql-backups/      │          │
│  │  - backup_xxx.sql.gz │          │
│  │  - backup_yyy.sql.gz │          │
│  └──────────────────────┘          │
│                                     │
│  [Azure VMs: 없음]                 │
│  [Azure DB: 없음]                  │
│  [VNet: 생성됨, 리소스 없음]       │
└─────────────────────────────────────┘

월 비용: ~$30
- AWS Backup EC2: $15
- Azure Blob Storage: $10
- Route53: $1
- 기타: $4
```

### 재해 발생 시 (Disaster Recovery)

```
T+0분: AWS Korea Region 마비 감지
       └─ 관리자 알림

T+15분: 긴급 대응 시작
        └─ Azure 점검 페이지 배포
        └─ Route53 트래픽 전환

T+30분: 회의 및 복구 계획 수립
        └─ Azure DB 생성 및 복구 시작
        └─ Azure VM 생성 시작

T+90분: Azure 인프라 구축 완료
        └─ DB 복구 확인
        └─ PetClinic 배포

T+120분: 서비스 정상화
         └─ 점검 페이지 → PetClinic 전환
         └─ 전체 테스트

┌─────────────────────────────────────┐
│         Azure DR Site               │
│         (Emergency Mode)            │
│                                     │
│  ┌──────────────────────┐          │
│  │  Blob Storage        │          │
│  │  mysql-backups/      │          │
│  └────────┬─────────────┘          │
│           │                         │
│           ▼ 복구                    │
│  ┌──────────────────────┐          │
│  │  Azure MySQL         │          │
│  │  (복구됨)            │          │
│  └────────┬─────────────┘          │
│           │                         │
│           ▼                         │
│  ┌──────────────────────┐          │
│  │  Azure VMs           │          │
│  │  - Web (Nginx)       │          │
│  │  - WAS (PetClinic)   │          │
│  └────────┬─────────────┘          │
│           │                         │
│           ▼                         │
│  ┌──────────────────────┐          │
│  │  Application Gateway │          │
│  └──────────────────────┘          │
└─────────────────────────────────────┘

Route53 설정:
┌─────────────────────┐
│ petclinic.example   │
│                     │
│ Primary: AWS ALB    │ ✗ Health Check Failed
│ Failover: Azure AG  │ ✓ Active
└─────────────────────┘
```

## 디렉토리 구조

```
dr-plan-b/
├── aws/
│   ├── main.tf                    # EKS, RDS (기존)
│   ├── backup-instance.tf         # Blob Storage 백업
│   ├── vpc-endpoints.tf           # 비용 절감
│   └── route53-failover.tf        # DNS Failover
│
├── azure/
│   ├── minimal-infrastructure.tf  # VNet, Storage만
│   ├── emergency-deployment.tf    # 비상시 리소스
│   └── scripts/
│       ├── deploy-maintenance.sh  # 점검 페이지 배포
│       ├── restore-database.sh    # DB 복구
│       └── deploy-petclinic.sh    # PetClinic 배포
│
├── runbooks/
│   ├── 01-disaster-detection.md   # 재해 감지
│   ├── 02-emergency-response.md   # 긴급 대응
│   ├── 03-database-recovery.md    # DB 복구
│   ├── 04-service-deployment.md   # 서비스 배포
│   └── 05-failback.md             # 원상 복구
│
└── README.md                       # 이 문서
```

## Git Branch 전략

```bash
# Main Branch: Plan A (Warm Standby)
main
├── VPN 구성
├── DMS 실시간 복제
├── Azure VM 항상 가동
└── 비용: 높음

# New Branch: Plan B (Pilot Light)
plan-b-pilot-light
├── VPN 제거
├── Blob Storage 백업만
├── Azure 최소 리소스
└── 비용: 낮음
```

### Branch 생성 및 전환

```bash
# Plan B 브랜치 생성
git checkout -b plan-b-pilot-light

# Plan A로 돌아가기
git checkout main

# Plan B로 전환
git checkout plan-b-pilot-light
```

## 평상시 운영 (Normal Operation)

### 1. AWS 백업 인스턴스만 가동

```bash
cd aws
terraform apply

# 백업 확인
aws ssm start-session --target <backup-instance-id>
sudo tail -f /var/log/mysql-backup-to-azure.log
```

### 2. Azure는 Storage만 존재

```bash
cd azure
terraform apply -target=azurerm_storage_account.backups
terraform apply -target=azurerm_storage_container.mysql_backups

# VM, DB, AppGW는 생성하지 않음
```

### 3. 백업 모니터링

```bash
# Azure Blob 확인
az storage blob list \
    --account-name drbackupstorage1234 \
    --container-name mysql-backups \
    --output table

# 최근 백업 시간 확인
az storage blob list \
    --account-name drbackupstorage1234 \
    --container-name mysql-backups \
    --query "[?properties.lastModified>'2024-12-16'].{name:name, modified:properties.lastModified}" \
    --output table
```

## 재해 발생 시 대응 (Disaster Recovery)

### Phase 1: 재해 감지 및 초기 대응 (0-15분)

**목표**: 사용자에게 점검 페이지 제공

```bash
# 1. AWS 상태 확인
aws ec2 describe-instance-status --region ap-northeast-2
# ✗ RequestLimitExceeded 또는 연결 실패

# 2. 긴급 회의 소집
# - 상황 파악
# - 복구 계획 수립
# - 역할 분담

# 3. Azure 점검 페이지 신속 배포
cd azure/scripts
./deploy-maintenance.sh

# 4. Route53 Failover 수동 전환 (필요시)
cd aws
terraform apply -var="force_failover=true"
```

### Phase 2: 데이터베이스 복구 (15-60분)

**목표**: 최신 백업으로 Azure MySQL 복구

```bash
# 1. Azure MySQL 생성
cd azure
terraform apply -target=azurerm_mysql_flexible_server.main
terraform apply -target=azurerm_mysql_flexible_database.main

# 2. 최신 백업 다운로드 및 복구
cd azure/scripts
./restore-database.sh

# 실행 내용:
# - 최신 backup.sql.gz 다운로드
# - 압축 해제
# - Azure MySQL에 복구
# - 데이터 무결성 검증
```

### Phase 3: 애플리케이션 배포 (60-90분)

**목표**: PetClinic 서비스 정상화

```bash
# 1. Azure VMs 생성
cd azure
terraform apply -target=azurerm_linux_virtual_machine.web
terraform apply -target=azurerm_linux_virtual_machine.was

# 2. Application Gateway 생성
terraform apply -target=azurerm_application_gateway.main

# 3. PetClinic 배포
cd azure/scripts
./deploy-petclinic.sh

# 4. 헬스체크 확인
curl http://<azure-appgw-ip>/actuator/health
```

### Phase 4: 서비스 전환 (90-120분)

**목표**: 점검 페이지 → PetClinic 전환

```bash
# 1. PetClinic 정상 동작 확인
curl http://<azure-appgw-ip>
# 수동 테스트 (로그인, 조회, 등록 등)

# 2. Application Gateway 라우팅 변경
cd azure
terraform apply -var="enable_petclinic=true"

# 3. 최종 확인
curl http://<azure-appgw-ip>
# PetClinic 메인 페이지 확인

# 4. 모니터링 강화
# - CloudWatch 대신 Azure Monitor
# - 로그 수집
# - 알림 설정
```

## 원상 복구 (Failback)

### AWS 복구 후 Failback

```bash
# 1. AWS 정상 동작 확인
aws ec2 describe-regions --region ap-northeast-2

# 2. AWS RDS 데이터 동기화
cd aws/scripts
./restore-from-azure.sh

# 3. Route53 Failback
cd aws
terraform apply -var="force_failover=false"

# 4. 점진적 트래픽 전환
# Route53 Weighted Routing:
# - AWS: 10%
# - Azure: 90%
# ... 점진적으로 AWS 비중 증가

# 5. Azure 리소스 정리
cd azure
terraform destroy -target=azurerm_linux_virtual_machine.web
terraform destroy -target=azurerm_linux_virtual_machine.was
terraform destroy -target=azurerm_application_gateway.main

# Storage는 유지 (백업 용도)
```

## 비용 분석

### 평상시 (Normal)

```
AWS:
- EKS Cluster: $73/월
- RDS MySQL: $85/월
- Backup EC2: $15/월
- VPC Endpoints: $22/월
- 기타: $10/월
소계: $205/월

Azure:
- Blob Storage (100GB): $10/월
- 기타: $2/월
소계: $12/월

총 평상시 비용: $217/월
```

### 재해 발생 시 (Emergency)

```
Azure 추가 리소스 (4시간 가동):
- VM 2대: $0.50
- MySQL: $2.00
- Application Gateway: $0.50
- 네트워크: $0.30
소계: $3.30/4시간

재해 1회 비용: $3.30
월 1회 DR 훈련: $3.30
```

### Plan A vs Plan B 비용 비교

```
항목              Plan A        Plan B      절감
───────────────────────────────────────────────
평상시 비용       $355/월       $217/월     $138
DR 훈련 비용      $0            $3.30       -$3.30
───────────────────────────────────────────────
월 비용 (훈련1회) $355          $220.30     $134.70

연간 비용         $4,260        $2,643.60   $1,616.40
연간 절감율                                  38%
```

## DR 훈련 계획

### 월간 훈련 (Tabletop Exercise)

```
목적: 절차 숙지 및 문서 검증
소요: 1시간
비용: $0

절차:
1. 시나리오 발표
2. 역할별 대응 방법 논의
3. 체크리스트 검토
4. 문서 업데이트
```

### 분기별 훈련 (Partial Failover)

```
목적: 실제 스크립트 검증
소요: 2시간
비용: $3.30

절차:
1. Azure 점검 페이지 배포
2. Route53 일부 트래픽 전환 (10%)
3. 복구 스크립트 실행 (Dry-run)
4. 원상 복구
```

### 연간 훈련 (Full DR Test)

```
목적: 전체 프로세스 검증
소요: 4시간
비용: $3.30

절차:
1. AWS 일부 중단 시뮬레이션
2. 전체 Failover 실행
3. Azure에서 서비스 운영
4. 성능 및 데이터 검증
5. Failback 실행
```

## 체크리스트

### 평상시 운영

- [ ] AWS 백업 인스턴스 정상 가동
- [ ] 5분마다 백업 실행 확인
- [ ] Azure Blob Storage 저장 확인
- [ ] Route53 Health Check 정상
- [ ] 백업 로그 정기 검토
- [ ] 월간 DR 회의 진행

### 재해 발생 시

- [ ] AWS 상태 확인 및 문서화
- [ ] 긴급 회의 소집 (15분 이내)
- [ ] Azure 점검 페이지 배포 (30분 이내)
- [ ] Route53 Failover 전환
- [ ] 고객 공지 발송
- [ ] 데이터베이스 복구 시작 (1시간 이내)
- [ ] 애플리케이션 배포 (2시간 이내)
- [ ] 서비스 정상화 확인 (3시간 이내)
- [ ] 사후 보고서 작성

### Failback 시

- [ ] AWS 정상화 확인
- [ ] 데이터 동기화
- [ ] Route53 점진적 전환
- [ ] Azure 리소스 정리
- [ ] 백업 재개 확인
- [ ] 사후 분석 회의

## 다음 단계

1. **Branch 생성 및 코드 작성**
   ```bash
   git checkout -b plan-b-pilot-light
   ```

2. **Azure 최소 인프라 구성**
   - Storage Account만 생성
   - VM/DB 제거

3. **Runbook 작성**
   - 재해 대응 절차 문서화
   - 스크립트 자동화

4. **DR 훈련 실시**
   - 분기별 1회
   - 절차 개선

5. **모니터링 강화**
   - 백업 실패 알림
   - AWS Health Check
   - Azure Blob 저장 확인

## 참고 문서

- `runbooks/` - 상세 대응 절차
- `azure/scripts/` - 자동화 스크립트
- `COST_ANALYSIS.md` - 비용 분석
- `DR_TRAINING_GUIDE.md` - 훈련 가이드
