# 문서 목록 (Documentation Index)

Multi-Cloud DR 프로젝트의 문서 목록입니다.

---

## 주요 문서

| 문서 | 설명 |
|------|------|
| [architecture.md](architecture.md) | 전체 시스템 아키텍처 설명 (AWS/Azure 구성, 네트워크, 데이터 흐름) |
| [user-guide.md](user-guide.md) | 사용자 가이드 - 처음부터 끝까지 배포하는 단계별 안내 |
| [MONITORING.md](MONITORING.md) | AWS CloudWatch 모니터링 설정 및 알람 구성 가이드 |
| [backup-system.md](backup-system.md) | 백업 시스템 아키텍처 - AWS RDS → Azure Blob 백업 구성 |
| [dr-failover-procedure.md](dr-failover-procedure.md) | DR Failover 절차 - AWS 장애 시 Azure 전환 방법 |
| [dr-failover-testing-guide.md](dr-failover-testing-guide.md) | DR Failover 테스트 가이드 - 3단계 테스트 시나리오 |
| [troubleshooting.md](troubleshooting.md) | 트러블슈팅 가이드 - 일반적인 문제 해결 방법 |

---

## 다이어그램

[diagrams/](diagrams/) 폴더에 Mermaid 형식의 아키텍처 다이어그램이 있습니다.

| 파일 | 설명 |
|------|------|
| [system-architecture.mmd](diagrams/system-architecture.mmd) | 전체 시스템 아키텍처 |
| [full-architecture.mmd](diagrams/full-architecture.mmd) | 상세 전체 아키텍처 |
| [data-flow-normal.mmd](diagrams/data-flow-normal.mmd) | 정상 운영 시 데이터 흐름 |
| [data-flow-failover.mmd](diagrams/data-flow-failover.mmd) | Failover 시 데이터 흐름 |
| [aws-vpc-network.mmd](diagrams/aws-vpc-network.mmd) | AWS VPC 네트워크 구성 |
| [azure-vnet-network.mmd](diagrams/azure-vnet-network.mmd) | Azure VNet 네트워크 구성 |
| [azure-failover-stages.mmd](diagrams/azure-failover-stages.mmd) | Azure 3단계 Failover 구조 |

---

## 문서 용도별 분류

### 시작하기
1. [architecture.md](architecture.md) - 시스템 이해
2. [user-guide.md](user-guide.md) - 배포 가이드

### 운영
1. [MONITORING.md](MONITORING.md) - 모니터링 설정
2. [backup-system.md](backup-system.md) - 백업 관리

### 장애 대응
1. [dr-failover-procedure.md](dr-failover-procedure.md) - Failover 실행
2. [dr-failover-testing-guide.md](dr-failover-testing-guide.md) - Failover 테스트
3. [troubleshooting.md](troubleshooting.md) - 문제 해결
