# Multi-Cloud DR 프로젝트 문서 📚

AWS/Azure 멀티클라우드 Backup & Restore DR 솔루션 관련 모든 문서가 포함되어 있습니다.

---

## 📚 핵심 문서

### 전체 개요
- **[PORTFOLIO_REPORT.md](./PORTFOLIO_REPORT.md)** - 전체 프로젝트 개요 및 설계 철학

### 배포 및 운영
- **[deployment-guide.md](./deployment-guide.md)** - AWS 및 Azure 인프라 배포 가이드
- **[DESTROY_GUIDE.md](./DESTROY_GUIDE.md)** - Terraform destroy 사용 가이드

### DR 및 장애 대응
- **[dr-failover-procedure.md](./dr-failover-procedure.md)** - AWS → Azure DR 전환 절차
- **[DR_TEST_GUIDE.md](./DR_TEST_GUIDE.md)** - DR 테스트 가이드
- **[FAILOVER_CONFIGURATION.md](./FAILOVER_CONFIGURATION.md)** - Failover 설정

### 트러블슈팅
- **[troubleshooting.md](./troubleshooting.md)** - 종합 트러블슈팅 가이드

### 세부 설정
- **[route53-health-check-guide.md](./route53-health-check-guide.md)** - Route53 헬스체크 및 CloudFront Failover 설정

---

## 📋 문서 카테고리

### 📚 프로젝트 개요
1. [PORTFOLIO_REPORT.md](./PORTFOLIO_REPORT.md) - 전체 프로젝트 리포트

### 🚀 배포 및 운영
1. [deployment-guide.md](./deployment-guide.md) - 배포 가이드
2. [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) - 인프라 삭제 가이드

### 🚨 DR 및 장애 대응
1. [dr-failover-procedure.md](./dr-failover-procedure.md) - DR 전환 절차
2. [DR_TEST_GUIDE.md](./DR_TEST_GUIDE.md) - DR 테스트 가이드
3. [FAILOVER_CONFIGURATION.md](./FAILOVER_CONFIGURATION.md) - Failover 설정

### 🔧 설정 및 트러블슈팅
1. [troubleshooting.md](./troubleshooting.md) - 종합 트러블슈팅
2. [route53-health-check-guide.md](./route53-health-check-guide.md) - Route53/CloudFront 설정

---

## 🎯 시나리오별 가이드

### 시나리오 1: 처음 배포 시작
→ [deployment-guide.md](./deployment-guide.md) 참조

### 시나리오 2: AWS 장애 발생 (DR 전환 필요)
→ [dr-failover-procedure.md](./dr-failover-procedure.md) 실행

### 시나리오 3: DR 테스트 수행
→ [DR_TEST_GUIDE.md](./DR_TEST_GUIDE.md) 참조

### 시나리오 4: CloudFront Failover 설정
→ [route53-health-check-guide.md](./route53-health-check-guide.md) 참조

### 시나리오 5: 인프라 삭제
→ [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) 확인

### 시나리오 6: 문제 해결
→ [troubleshooting.md](./troubleshooting.md) 확인

---

## 🔗 빠른 링크

### 자주 사용하는 명령어

#### AWS 인프라 배포
```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
terraform init
terraform plan
terraform apply
```

#### Azure DR 배포
```bash
cd /home/ubuntu/3tier-terraform/codes/azure/2-emergency
terraform init
terraform apply

# PetClinic 애플리케이션 배포
./scripts/deploy-complete.sh
```

#### 인프라 삭제
```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
kubectl delete ingress --all --all-namespaces
kubectl delete svc --type=LoadBalancer --all --all-namespaces
sleep 180
terraform destroy
```

---

## 📊 문서 히스토리

| 날짜 | 문서 | 변경 내용 |
|------|------|-----------|
| 2026-01-13 | README.md | 불필요한 파일 삭제 및 문서 구조 정리 |
| 2026-01-12 | PORTFOLIO_REPORT.md | 전체 프로젝트 리포트 업데이트 |
| 2026-01-07 | troubleshooting.md | 종합 트러블슈팅 가이드 통합 |
| 2026-01-05 | DR_TEST_GUIDE.md | DR 테스트 가이드 생성 |
| 2026-01-04 | DESTROY_GUIDE.md | Terraform destroy 가이드 업데이트 |
| 2026-01-02 | route53-health-check-guide.md | Route53 설정 가이드 |
| 2025-12-29 | dr-failover-procedure.md | DR 전환 절차 문서화 |

---

## 📁 문서 구조

```
docs/
├── README.md                        # 이 파일 (문서 인덱스)
├── PORTFOLIO_REPORT.md              # 전체 프로젝트 개요 및 포트폴리오
│
├── 배포 및 운영/
│   ├── deployment-guide.md          # AWS/Azure 배포 가이드
│   └── DESTROY_GUIDE.md             # Terraform destroy 가이드
│
├── DR 및 장애 대응/
│   ├── dr-failover-procedure.md     # DR 전환 절차
│   ├── DR_TEST_GUIDE.md             # DR 테스트 가이드
│   └── FAILOVER_CONFIGURATION.md    # Failover 설정
│
└── 설정 및 트러블슈팅/
    ├── troubleshooting.md           # 종합 트러블슈팅 가이드
    └── route53-health-check-guide.md # CloudFront Failover 설정
```

---

## 🆘 추가 도움이 필요한 경우

1. **프로젝트 전체 개요**: [PORTFOLIO_REPORT.md](./PORTFOLIO_REPORT.md)
2. **트러블슈팅**: [troubleshooting.md](./troubleshooting.md)
3. **문서 내 검색**: `grep -r "키워드" docs/`
4. **각 코드 디렉토리의 README.md 참조**

---

**마지막 업데이트**: 2026-01-13
**작성자**: I2ST-blue
**프로젝트**: Multi-Cloud Backup & Restore DR Solution
