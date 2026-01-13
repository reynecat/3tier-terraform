# 3-Tier Terraform 문서 📚

이 디렉토리에는 AWS/Azure 멀티클라우드 3-Tier 아키텍처 관련 모든 문서가 포함되어 있습니다.

---

## 🚨 긴급 상황 대응

### Terraform Destroy 에러
- **[EMERGENCY_FIX.md](./EMERGENCY_FIX.md)** - Security Group 의존성 에러 즉시 해결
- **[DESTROY_GUIDE.md](./DESTROY_GUIDE.md)** - Terraform destroy 사용 가이드

### DR 장애 대응
- **[dr-failover-procedure.md](./dr-failover-procedure.md)** - AWS → Azure DR 전환 절차
- **[DR_TEST_GUIDE.md](./DR_TEST_GUIDE.md)** - DR 테스트 가이드
- **[FAILOVER_CONFIGURATION.md](./FAILOVER_CONFIGURATION.md)** - Failover 설정

---

## 📖 배포 및 운영 가이드

### 배포 가이드
| 문서 | 설명 |
|------|------|
| [deployment-guide.md](./deployment-guide.md) | AWS 2. Service 배포 전체 가이드 |

### Terraform 운영
| 문서 | 설명 |
|------|------|
| [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) | Terraform destroy 사용 가이드 |
| [FIX_SUMMARY_FINAL.md](./FIX_SUMMARY_FINAL.md) | Destroy 에러 수정 완전 가이드 |
| [TERRAFORM_DESTROY_FIX.md](./TERRAFORM_DESTROY_FIX.md) | 에러 원인 분석 및 해결 방법 |

### 인프라 설정
| 문서 | 설명 |
|------|------|
| [BACKUP_INSTANCE_AZ_ALIGNMENT.md](./BACKUP_INSTANCE_AZ_ALIGNMENT.md) | 백업 인스턴스 AZ 정렬 가이드 |
| [route53-health-check-guide.md](./route53-health-check-guide.md) | Route53 헬스체크 설정 가이드 |

---

## 🔧 트러블슈팅

### 종합 트러블슈팅 가이드
- **[troubleshooting-complete.md](./troubleshooting-complete.md)** - 모든 문제와 해결 과정 완전 정리
- **[troubleshooting.md](./troubleshooting.md)** - 기존 트러블슈팅 가이드 (참고용)

### Security Group 의존성 에러
```
Error: deleting Security Group: DependencyViolation
```

**즉시 해결**:
```bash
cd /home/ubuntu/3tier-terraform
./docs/manual-cleanup.sh <VPC_ID>
```

자세한 내용: [EMERGENCY_FIX.md](./EMERGENCY_FIX.md)

---

## 📋 문서 카테고리

### 🚨 긴급 대응 (Emergency)
1. [EMERGENCY_FIX.md](./EMERGENCY_FIX.md) - Security Group 에러 해결
2. [manual-cleanup.sh](./manual-cleanup.sh) - 자동 정리 스크립트
3. [dr-failover-procedure.md](./dr-failover-procedure.md) - DR 전환 절차

### 📚 운영 가이드 (Operations)
1. [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) - Destroy 사용법
2. [FIX_SUMMARY_FINAL.md](./FIX_SUMMARY_FINAL.md) - 수정 요약
3. [TERRAFORM_DESTROY_FIX.md](./TERRAFORM_DESTROY_FIX.md) - 기술 문서

### 🔧 설정 가이드 (Configuration)
1. [BACKUP_INSTANCE_AZ_ALIGNMENT.md](./BACKUP_INSTANCE_AZ_ALIGNMENT.md) - 백업 설정
2. [route53-health-check-guide.md](./route53-health-check-guide.md) - Route53 설정

### 🛠️ 트러블슈팅 (Troubleshooting)
1. [troubleshooting.md](./troubleshooting.md) - 종합 가이드

---

## 🎯 시나리오별 가이드

### 시나리오 1: 처음 Terraform destroy 실행
→ [DESTROY_GUIDE.md](./DESTROY_GUIDE.md) 참조

### 시나리오 2: Security Group 에러 발생
→ [EMERGENCY_FIX.md](./EMERGENCY_FIX.md) 즉시 확인

### 시나리오 3: AWS 장애 발생 (DR 전환 필요)
→ [dr-failover-procedure.md](./dr-failover-procedure.md) 실행

### 시나리오 4: Route53 헬스체크 설정
→ [route53-health-check-guide.md](./route53-health-check-guide.md) 참조

### 시나리오 5: 백업 인스턴스 AZ 오류
→ [BACKUP_INSTANCE_AZ_ALIGNMENT.md](./BACKUP_INSTANCE_AZ_ALIGNMENT.md) 확인

---

## 🔗 빠른 링크

### 자주 사용하는 명령어

#### Terraform Destroy (안전)
```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
kubectl delete ingress --all --all-namespaces
kubectl delete svc --type=LoadBalancer --all --all-namespaces
sleep 180
terraform destroy
```

#### 긴급 정리 (Destroy 에러 시)
```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
terraform destroy
# cleanup provisioner가 자동으로 정리해줍니다
```

#### DR 전환 (CloudFront → Azure)
```bash
# 상세 절차는 dr-failover-procedure.md 참조
aws cloudfront update-distribution --id <DISTRIBUTION_ID> --if-match <ETAG> \
  --distribution-config file://cloudfront-azure.json
```

---

## 📊 문서 히스토리

| 날짜 | 문서 | 변경 내용 |
|------|------|-----------|
| 2026-01-07 | troubleshooting-complete.md | 모든 문제와 해결 과정 완전 정리 |
| 2026-01-04 | EMERGENCY_FIX.md | Security Group 에러 해결 가이드 생성 |
| 2026-01-04 | FIX_SUMMARY_FINAL.md | 최종 수정 요약 문서 생성 |
| 2026-01-04 | DESTROY_GUIDE.md | Terraform destroy 가이드 업데이트 |
| 2026-01-03 | BACKUP_INSTANCE_AZ_ALIGNMENT.md | AZ 정렬 가이드 |
| 2026-01-02 | route53-health-check-guide.md | Route53 설정 가이드 |
| 2025-12-29 | dr-failover-procedure.md | DR 전환 절차 문서화 |

---

## 📁 문서 구조

```
docs/
├── README.md                                   # 이 파일
├── troubleshooting-complete.md                 # 종합 트러블슈팅 (신규, 권장)
├── troubleshooting.md                          # 기존 트러블슈팅 (참고용)
│
├── 긴급 대응/
│   ├── EMERGENCY_FIX.md                       # Security Group 에러 긴급 해결
│   ├── DESTROY_GUIDE.md                       # Terraform destroy 가이드
│   ├── dr-failover-procedure.md               # DR 전환 절차
│   ├── DR_TEST_GUIDE.md                       # DR 테스트
│   └── FAILOVER_CONFIGURATION.md              # Failover 설정
│
├── 배포 및 운영/
│   ├── deployment-guide.md                    # 배포 가이드
│   ├── FIX_SUMMARY_FINAL.md                   # Destroy 수정 요약
│   └── TERRAFORM_DESTROY_FIX.md               # Destroy 에러 분석
│
└── 설정 가이드/
    ├── BACKUP_INSTANCE_AZ_ALIGNMENT.md        # 백업 인스턴스 AZ 정렬
    ├── route53-health-check-guide.md          # Route53 헬스체크
    └── SG_DEPENDENCY_FINAL_FIX.md             # SG 의존성 문제
```

---

## 🆘 추가 도움이 필요한 경우

1. **종합 트러블슈팅 먼저 확인**: [troubleshooting-complete.md](./troubleshooting-complete.md)
2. **문서 내 검색**: `grep -r "키워드" docs/`
3. **코드 참조**: 각 문서에 코드 파일 링크 포함

---

**마지막 업데이트**: 2026-01-07
**관리자**: DevOps Team
