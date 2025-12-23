# Mermaid 다이어그램 파일

이 디렉토리는 architecture.md에서 분리된 Mermaid 다이어그램 파일들을 포함합니다.

## 📁 파일 목록

### 1. system-architecture.mmd
**설명:** 전체 시스템 아키텍처 다이어그램
- AWS Primary Site (VPC, EKS, RDS, ALB)
- Azure DR Site (3단계 페일오버 구조)
- Route53 DNS Failover
- 데이터 흐름 및 연결 관계

**주요 구성 요소:**
- DNS: Route53 Hosted Zone, Health Checks
- AWS: VPC (10.0.0.0/16), Web/WAS/RDS Tier, EKS Cluster, ALB
- Azure: VNet (172.16.0.0/16), Blob Storage, App Gateway, MySQL, AKS

### 2. data-flow-normal.mmd
**설명:** 정상 운영 시 데이터 흐름 (AWS)
- 사용자 → Route53 → ALB → Nginx → Spring Boot → RDS MySQL
- 백업 프로세스: EC2 → RDS (mysqldump) → Azure Blob (5분 간격)

**시퀀스:**
1. DNS 질의 (domain.com)
2. HTTPS 요청 → ALB
3. Nginx 프록시 (:8080)
4. Spring Boot 애플리케이션
5. RDS 데이터베이스 조회
6. 응답 반환

### 3. data-flow-failover.mmd
**설명:** 페일오버 시나리오 (AWS → Azure)
- AWS 장애 감지 → Health Check 실패 (3회)
- DNS 페일오버 (T+90s)
- Stage 1: Maintenance Page (Blob Storage)
- Stage 2: DB Restore (Azure MySQL, T+0~15분)
- Stage 3: Full Service (AKS Cluster, T+15~75분)

**타임라인:**
- T+0s: Health check failure 시작
- T+90s: UNHEALTHY 마킹
- T+150s: DNS 전환 (Azure AppGW)
- T+210s: 사용자 리다이렉트 완료

### 4. aws-vpc-network.mmd
**설명:** AWS VPC 네트워크 아키텍처
- 2개 Availability Zones (ap-northeast-2a, ap-northeast-2c)
- Public Subnets: Internet Gateway, NAT Gateway
- Private Subnets: Web Tier, WAS Tier, RDS Tier
- Security Groups: ALB-SG, EKS-WebSG, EKS-WASSG, RDS-SG

**서브넷 구성:**
- Public: 10.0.1-2.0/24
- Web: 10.0.11-12.0/24
- WAS: 10.0.21-22.0/24
- RDS: 10.0.31-32.0/24

### 5. azure-vnet-network.mmd
**설명:** Azure VNet 네트워크 아키텍처
- Resource Group: Korea Central
- VNet: 172.16.0.0/16
- Subnets: App Gateway, Web, WAS, DB, AKS
- NSGs: 각 서브넷별 네트워크 보안 그룹

**서브넷 구성:**
- App Gateway: 172.16.1.0/24
- Web: 172.16.11.0/24
- WAS: 172.16.21.0/24
- DB: 172.16.31.0/24
- AKS: 172.16.41.0/24

### 6. azure-failover-stages.mmd
**설명:** Azure 3단계 페일오버 전략 (State Diagram)

**Stage 1: Always-On ($50-100/month)**
- VNet 예약 (무료)
- Blob Storage (LRS)
- 30일 백업 보관
- Static Website 호스팅

**Stage 2: Emergency Response (+$200-300/month, 10-15분)**
- Application Gateway 활성화
- MySQL Flexible Server 배포
- 데이터베이스 복구
- 유지보수 페이지 표시

**Stage 3: Complete Failover (+$400-500/month, 15-20분)**
- AKS 클러스터 배포
- Nginx + Spring Boot Pods 배포
- 정상 서비스 복원

## 🔧 사용 방법

### Mermaid CLI로 렌더링
```bash
# PNG 이미지 생성
mmdc -i system-architecture.mmd -o system-architecture.png

# SVG 이미지 생성
mmdc -i system-architecture.mmd -o system-architecture.svg -t dark

# PDF 생성
mmdc -i system-architecture.mmd -o system-architecture.pdf
```

### VS Code에서 미리보기
1. Mermaid Preview 확장 설치
2. `.mmd` 파일 열기
3. `Ctrl+Shift+P` → "Mermaid: Preview"

### 온라인 에디터
- [Mermaid Live Editor](https://mermaid.live/)
- 파일 내용 복사 → 붙여넣기 → 실시간 미리보기

### Markdown에 임베딩
```markdown
## 시스템 아키텍처

\`\`\`mermaid
graph TB
    User["👥 User<br/>Browser"]
    ...
\`\`\`
```

## 📝 다이어그램 수정 가이드

### 1. 노드 추가
```mermaid
NewNode["노드 이름<br/>설명"]
```

### 2. 연결 추가
```mermaid
SourceNode -->|라벨| TargetNode
SourceNode -.->|점선| TargetNode
```

### 3. 스타일 변경
```mermaid
style NodeName fill:#색상코드,stroke:#테두리색,stroke-width:2px
```

### 4. 서브그래프 추가
```mermaid
subgraph SubgraphName["표시 이름"]
    Node1
    Node2
end
```

## 🎨 컬러 스키마

**AWS (파랑 계열):**
- Primary: `#e3f2fd` (fill), `#1976d2` (stroke)
- Web Tier: `#f3e5f5` (fill), `#7b1fa2` (stroke)
- WAS Tier: `#fce4ec` (fill), `#c2185b` (stroke)
- RDS Tier: `#e0f2f1` (fill), `#00796b` (stroke)

**Azure (빨강 계열):**
- Primary: `#ffe0e0` (fill), `#d32f2f` (stroke)
- Stage 1: `#c8e6c9` (fill), `#2e7d32` (stroke)
- Stage 2: `#ffccbc` (fill), `#d84315` (stroke)
- Stage 3: `#ffab91` (fill), `#bf360c` (stroke)

**DNS:**
- `#f0f4c3` (fill), `#f57f17` (stroke)

## 📚 참고 자료

- [Mermaid 공식 문서](https://mermaid.js.org/)
- [Mermaid Syntax Guide](https://mermaid.js.org/intro/syntax-reference.html)
- [Graph 다이어그램](https://mermaid.js.org/syntax/flowchart.html)
- [Sequence 다이어그램](https://mermaid.js.org/syntax/sequenceDiagram.html)
- [State 다이어그램](https://mermaid.js.org/syntax/stateDiagram.html)

---

**마지막 업데이트:** 2025-12-23
**작성자:** I2ST-blue
