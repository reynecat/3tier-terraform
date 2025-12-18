# 긴급 대응 Runbook

## 📋 체크리스트

- [ ] AWS 상태 확인 및 문서화
- [ ] 긴급 회의 소집
- [ ] 점검 페이지 배포
- [ ] Route53 Failover
- [ ] 데이터베이스 복구
- [ ] 애플리케이션 배포
- [ ] 서비스 검증
- [ ] 고객 공지

---

## Phase 1: 재해 감지 및 초기 대응 (T+0 ~ T+15분)

### 목표
- AWS 장애 확인
- 긴급 대응 체제 가동
- 사용자에게 점검 페이지 제공

### 1.1 AWS 상태 확인 (5분)

```bash
# AWS 접속 테스트
aws ec2 describe-regions --region ap-northeast-2

# EKS 클러스터 상태
aws eks describe-cluster --name prod-eks --region ap-northeast-2

# RDS 상태
aws rds describe-db-instances --region ap-northeast-2

# 결과: 연결 실패 또는 타임아웃 → AWS 장애 확정
```

**판단 기준:**
- ✗ 3개 이상 서비스 무응답 → 리전 전체 장애
- ✗ RDS만 무응답 → 데이터베이스 장애
- ✗ EKS만 무응답 → 컴퓨팅 장애

### 1.2 긴급 회의 소집 (3분)

**참석자:**
- [ ] 운영팀장
- [ ] 개발팀장
- [ ] DBA
- [ ] 네트워크 담당자
- [ ] 고객지원팀

**논의 사항:**
1. 장애 범위 확인
2. 복구 전략 결정
3. 역할 분담
4. 고객 공지 방법

### 1.3 점검 페이지 신속 배포 (7분)

```bash
# Azure 로그인 확인
az account show

# 점검 페이지 배포
cd /path/to/azure/scripts
chmod +x deploy-maintenance.sh
./deploy-maintenance.sh

# 예상 출력:
# Public IP: 20.xxx.xxx.xxx
# URL: http://20.xxx.xxx.xxx
```

**확인 사항:**
- [ ] 점검 페이지 접속 가능
- [ ] 내용 정확성 확인
- [ ] 고객지원팀 확인

### 1.4 Route53 Failover (선택사항)

```bash
# AWS 접속 가능하면 자동 Failover
# 불가능하면 수동으로 DNS 공급자에서 변경

# Route53 접속 가능한 경우:
cd /path/to/aws
terraform apply -var="force_failover=true"
```

**소요 시간:**
- DNS TTL: 60초
- 전파: 5분 이내
- 총: 최대 7분

---

## Phase 2: 데이터베이스 복구 (T+15 ~ T+60분)

### 목표
- Azure MySQL 생성
- 최신 백업으로 복구
- 데이터 무결성 검증

### 2.1 데이터베이스 복구 실행

```bash
cd /path/to/azure/scripts
chmod +x restore-database.sh
./restore-database.sh

# 프롬프트에 MySQL 비밀번호 입력
# Password: **********
```

**예상 소요 시간:**
- MySQL 서버 생성: 10분
- 백업 다운로드: 5분
- 데이터 복구: 10-30분 (크기에 따라)
- 검증: 2분
- **총: 27-47분**

### 2.2 복구 중 모니터링

```bash
# 로그 실시간 확인
tail -f /var/log/db-restore-*.log

# 주요 확인 사항:
# - MySQL 서버 생성 상태
# - 백업 파일 다운로드 진행률
# - 복구 진행 상황
```

### 2.3 데이터 검증

복구 스크립트가 자동으로 검증하지만, 수동 확인:

```bash
# MySQL 접속 정보 로드
source /tmp/mysql-connection-info.txt

# 테이블 레코드 수 확인
mysql -h $MYSQL_HOST -u $DB_USER -p"$DB_PASSWORD" -D $DB_NAME -e "
SELECT 
    'vets' AS table_name, COUNT(*) AS count FROM vets
UNION ALL
SELECT 'owners', COUNT(*) FROM owners
UNION ALL
SELECT 'pets', COUNT(*) FROM pets
UNION ALL
SELECT 'visits', COUNT(*) FROM visits;
"
```

**기대 결과:**
```
+-----------+-------+
| table_name| count |
+-----------+-------+
| vets      |     6 |
| owners    |    10 |
| pets      |    13 |
| visits    |    12 |
+-----------+-------+
```

---

## Phase 3: 애플리케이션 배포 (T+60 ~ T+90분)

### 목표
- Azure VM 생성
- PetClinic 배포
- 서비스 정상화

### 3.1 PetClinic 배포 실행

```bash
cd /path/to/azure/scripts
chmod +x deploy-petclinic.sh
./deploy-petclinic.sh
```

**예상 소요 시간:**
- WAS VM 생성: 10분
- Web VM 생성: 5분
- 애플리케이션 시작: 3-5분
- 검증: 2분
- **총: 20-22분**

### 3.2 배포 중 모니터링

```bash
# 로그 실시간 확인
tail -f /var/log/petclinic-deploy-*.log

# VM 상태 확인
az vm list \
    --resource-group rg-dr-prod \
    --query "[].{Name:name, Status:provisioningState}" \
    --output table
```

### 3.3 서비스 검증

#### 기본 접속 테스트

```bash
# 출력에서 IP 확인
WEB_IP=$(스크립트 출력에서 확인)
WAS_IP=$(스크립트 출력에서 확인)

# Health Check
curl http://$WAS_IP:8080/actuator/health
curl http://$WEB_IP/health

# 메인 페이지
curl http://$WEB_IP
```

#### 주요 기능 테스트

**브라우저에서 수동 테스트:**

1. **홈 페이지** (`http://$WEB_IP`)
   - [ ] 로딩 정상
   - [ ] 이미지 표시
   - [ ] 메뉴 작동

2. **Owners** (`http://$WEB_IP/owners`)
   - [ ] 목록 조회
   - [ ] 새 Owner 추가
   - [ ] Owner 정보 수정

3. **Veterinarians** (`http://$WEB_IP/vets`)
   - [ ] Vet 목록 조회
   - [ ] 전문 분야 표시

4. **Pets**
   - [ ] Pet 등록
   - [ ] Visit 추가
   - [ ] 정보 조회

#### 성능 테스트 (간단)

```bash
# 10회 요청 평균 응답 시간
for i in {1..10}; do
    curl -w "%{time_total}\n" -o /dev/null -s http://$WEB_IP
done | awk '{sum+=$1; n++} END {print "평균:", sum/n, "초"}'

# 기대값: < 1초
```

---

## Phase 4: 서비스 전환 (T+90 ~ T+120분)

### 목표
- 점검 페이지 → PetClinic 전환
- 최종 검증
- 고객 공지

### 4.1 Route53 업데이트

스크립트가 자동으로 수행하지만, 수동 확인:

```bash
# Route53 레코드 확인
aws route53 list-resource-record-sets \
    --hosted-zone-id Z1234567890ABC \
    --query "ResourceRecordSets[?Name=='petclinic.example.com.']"

# 변경 사항 확인
# - IP가 PetClinic Web IP로 변경되었는지 확인
```

### 4.2 DNS 전파 확인

```bash
# nslookup으로 DNS 확인
nslookup petclinic.example.com

# 여러 지역에서 확인
# https://www.whatsmydns.net/#A/petclinic.example.com

# 대기: 5-10분
```

### 4.3 최종 접속 테스트

```bash
# 도메인으로 접속 테스트
curl http://petclinic.example.com

# 주요 엔드포인트 확인
curl http://petclinic.example.com/owners
curl http://petclinic.example.com/vets
```

### 4.4 고객 공지

**공지 내용 (예시):**

```
제목: [복구 완료] 시스템 점검 종료 안내

안녕하세요, PetClinic 운영팀입니다.

긴급 시스템 점검이 완료되어 정상 서비스가 재개되었습니다.

- 점검 시작: 2024-12-16 10:00
- 복구 완료: 2024-12-16 13:30
- 소요 시간: 3시간 30분

복구 내용:
- 데이터베이스 복구 완료
- 모든 데이터 정상 복원
- 서비스 정상 운영 재개

불편을 드려 죄송합니다.
문의 사항은 고객센터(1588-1234)로 연락 주시기 바랍니다.

감사합니다.
```

**공지 채널:**
- [ ] 이메일
- [ ] SMS (VIP 고객)
- [ ] 웹사이트 공지
- [ ] 모바일 앱 푸시
- [ ] SNS (Twitter, Facebook)

---

## 모니터링 체크리스트

### 복구 후 30분간 집중 모니터링

```bash
# 1. 애플리케이션 로그
ssh azureuser@$WAS_IP
tail -f /var/log/petclinic.log

# 2. Nginx 로그
ssh azureuser@$WEB_IP
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log

# 3. Azure Monitor
az monitor metrics list \
    --resource vm-was \
    --resource-group rg-dr-prod \
    --metric-names "Percentage CPU" \
    --output table
```

### 모니터링 항목

- [ ] CPU 사용률 < 80%
- [ ] 메모리 사용률 < 80%
- [ ] 응답 시간 < 1초
- [ ] 에러율 < 1%
- [ ] Database Connection Pool 정상

---

## 문제 발생 시 대응

### Case 1: PetClinic 시작 실패

```bash
# 로그 확인
ssh azureuser@$WAS_IP
cat /var/log/petclinic.log

# 일반적인 원인:
# 1. DB 연결 실패
# 2. Port 충돌
# 3. 메모리 부족

# 재시작
sudo systemctl restart petclinic
```

### Case 2: 데이터베이스 연결 실패

```bash
# MySQL 접속 테스트
mysql -h $MYSQL_HOST -u $DB_USER -p"$DB_PASSWORD"

# 방화벽 확인
az mysql flexible-server firewall-rule list \
    --resource-group rg-dr-prod \
    --server-name mysql-dr-prod-*

# 필요시 방화벽 규칙 추가
az mysql flexible-server firewall-rule create \
    --resource-group rg-dr-prod \
    --server-name mysql-dr-prod-* \
    --name AllowAzureServices \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0
```

### Case 3: 성능 저하

```bash
# 리소스 확인
az vm show \
    --resource-group rg-dr-prod \
    --name vm-was \
    --query "hardwareProfile.vmSize"

# VM 크기 증가 (필요시)
az vm resize \
    --resource-group rg-dr-prod \
    --name vm-was \
    --size Standard_B4ms
```

---

## 복구 완료 보고서 작성

### 필수 포함 사항

1. **장애 요약**
   - 발생 시간
   - 감지 방법
   - 영향 범위
   - 복구 시간

2. **타임라인**
   - T+0: 장애 감지
   - T+15: 점검 페이지 배포
   - T+60: 데이터베이스 복구
   - T+90: 애플리케이션 배포
   - T+120: 서비스 정상화

3. **기술 상세**
   - 백업 파일 정보
   - 복구 방법
   - 사용한 리소스
   - 발생한 문제 및 해결

4. **개선 사항**
   - 잘된 점
   - 개선 필요 사항
   - 액션 아이템

---

## 연락처

| 역할 | 이름 | 전화번호 | 이메일 |
|------|------|----------|--------|
| 운영팀장 | 김철수 | 010-1234-5678 | kim@example.com |
| 개발팀장 | 박영희 | 010-2345-6789 | park@example.com |
| DBA | 이민수 | 010-3456-7890 | lee@example.com |
| 고객지원 | 정지영 | 1588-1234 | support@example.com |

## 참고 문서

- [DR_PLAN_B_README.md](../DR_PLAN_B_README.md)
- [Azure Scripts](../azure/scripts/)
- [비용 분석](../COST_ANALYSIS.md)
