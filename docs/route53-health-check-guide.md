# Route53 Health Check 구성 가이드

## 📋 개요

이 문서는 AWS Route53 헬스체크와 CloudWatch 알람을 통한 모니터링 및 장애 감지 시스템을 설명합니다.

## 🏗️ 아키텍처

### 헬스체크 구성

```
┌─────────────────────────────────────────────────────────────┐
│                   Route53 Health Checks                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. AWS ALB Direct Check (페일오버 감지용)                   │
│     ├─ Target: k8s-web-webingre-xxx.elb.amazonaws.com     │
│     ├─ Type: HTTP (Port 80)                               │
│     ├─ Purpose: AWS 장애 직접 감지                         │
│     └─ Alarm: route53-aws-alb-health-check-failed         │
│                                                             │
│  2. CloudFront End-to-End Check                            │
│     ├─ Target: blueisthenewblack.store                     │
│     ├─ Type: HTTPS_STR_MATCH (Search: "PetClinic")         │
│     ├─ Purpose: 전체 서비스 품질 확인                       │
│     └─ Alarm: route53-primary-health-check-failed         │
│                                                             │
│  3. Azure Blob Storage Check                               │
│     ├─ Target: bloberry01.z12.web.core.windows.net         │
│     ├─ Type: HTTPS (Port 443)                             │
│     ├─ Purpose: Azure 백업 사이트 상태 확인                 │
│     └─ Alarm: route53-secondary-health-check-failed       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 알람 발생 흐름

```
Route53 Health Checker (16개 글로벌 리전)
    ↓ (30초마다 체크)
Target Endpoint (ALB/CloudFront/Azure)
    ↓ (3회 연속 실패시 Unhealthy)
CloudWatch Metrics (us-east-1)
    ├─ HealthCheckStatus: 0 (실패) or 1 (성공)
    └─ HealthCheckPercentageHealthy: 0-100%
    ↓
CloudWatch Metric Alarm (ap-northeast-2)
    ├─ route53-aws-alb-health-check-failed
    ├─ route53-primary-health-check-failed
    └─ route53-secondary-health-check-failed
    ↓
SNS Topic: blue-eks-monitoring-alerts
    ↓
AWS Chatbot (Slack Integration)
    ↓
📢 Slack 채널 알림
    ↓
Lambda Auto Recovery (선택적)
```

## 📊 CloudWatch 대시보드

### 대시보드 위치
- **이름**: `blue-eks-monitoring-dashboard`
- **URL**: https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=blue-eks-monitoring-dashboard
- **섹션**: Row 8 - Route53 Health Check & Failover Status

### 위젯 구성

| 위젯 | 메트릭 | 설명 |
|------|--------|------|
| **AWS ALB Direct Health Check** | HealthCheckStatus | AWS ALB 직접 모니터링 (페일오버 감지) |
| **CloudFront (End-to-End) Health Check** | HealthCheckStatus | CloudFront를 통한 전체 서비스 확인 |
| **Azure Blob Storage Health Check** | HealthCheckStatus | Azure 백업 사이트 상태 |
| **Health Check Percentage** | HealthCheckPercentageHealthy | 각 헬스체크의 정상 체커 비율 |

## 🚨 알람 설정

### 1. AWS ALB Direct Health Check Alarm

**목적**: AWS 인프라 장애를 정확히 감지하여 CloudFront 자동 페일오버 트리거

```hcl
alarm_name          = "route53-aws-alb-health-check-failed"
comparison_operator = "LessThanThreshold"
threshold           = 1
metric_name         = "HealthCheckStatus"
namespace           = "AWS/Route53"
period              = 60
evaluation_periods  = 1
```

**트리거 조건**: ALB 헬스체크가 실패 (HealthCheckStatus < 1)
**결과**:
- ✅ Slack 알림 발송
- ✅ CloudFront가 자동으로 Azure로 페일오버
- ✅ Lambda 자동 복구 실행 (선택)

### 2. CloudFront End-to-End Alarm

**목적**: 최종 사용자 경험 모니터링

```hcl
alarm_name          = "route53-primary-health-check-failed"
comparison_operator = "LessThanThreshold"
threshold           = 1
metric_name         = "HealthCheckStatus"
```

**트리거 조건**: CloudFront를 통한 접속 실패 or "PetClinic" 문자열 미발견
**결과**: Slack 알림 (서비스 품질 저하 감지)

### 3. Azure Blob Storage Alarm

**목적**: Azure 백업 사이트 상태 확인

```hcl
alarm_name          = "route53-secondary-health-check-failed"
comparison_operator = "LessThanThreshold"
threshold           = 1
```

**트리거 조건**: Azure Blob Storage 접속 실패
**결과**: Slack 알림 (백업 사이트 장애)

### 4. Composite Alarm (All Sites Down)

**목적**: 전체 장애 상황 (Primary + Secondary 모두 실패)

```hcl
alarm_name  = "blue-all-sites-down-critical"
alarm_rule  = "ALARM(route53-primary-health-check-failed) AND ALARM(route53-secondary-health-check-failed)"
```

**트리거 조건**: Primary와 Secondary 모두 실패
**결과**: 🚨 CRITICAL 슬랙 알림 (즉시 대응 필요)

## 📝 Terraform 설정

### 1. Route53 모듈 (1. route53)

```hcl
# terraform.tfvars
enable_custom_domain        = true
domain_name                 = "blueisthenewblack.store"
health_check_search_string  = "PetClinic"
alb_dns_name                = "k8s-web-webingre-5d0cf16a97-1358663516.ap-northeast-2.elb.amazonaws.com"
```

**생성되는 리소스**:
- `aws_route53_health_check.aws_alb` - AWS ALB 직접 체크
- `aws_route53_health_check.cloudfront` - CloudFront 엔드투엔드 체크
- `aws_route53_health_check.azure_blob` - Azure Blob Storage 체크

### 2. 모니터링 모듈 (3. monitoring)

```hcl
# terraform.tfvars
enable_route53_monitoring = true
primary_health_check_id   = "a7fffe67-f2e0-4980-ae66-fb93d98a6cc7"  # CloudFront
secondary_health_check_id = "4d0d169e-269e-437f-bc03-f67c88c3c80f"  # Azure Blob
aws_alb_health_check_id   = "af0c24e7-40e6-4392-b6ee-86b291199243"  # AWS ALB Direct
```

**생성되는 리소스**:
- CloudWatch Metric Alarms (4개)
- CloudWatch Composite Alarm (1개)
- CloudWatch Dashboard 위젯

## 🔧 배포 순서

### 1단계: Route53 헬스체크 생성

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/1.\ route53
terraform init
terraform plan
terraform apply
```

**Output에서 헬스체크 ID 확인**:
```bash
terraform output health_check_ids
```

### 2단계: 모니터링 모듈에 헬스체크 ID 입력

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/3.\ monitoring
vi terraform.tfvars
```

다음 값을 Route53 output에서 가져온 ID로 업데이트:
```hcl
aws_alb_health_check_id   = "<Route53 output의 aws_alb_health_check_id>"
primary_health_check_id   = "<Route53 output의 cloudfront_health_check_id>"
secondary_health_check_id = "<Route53 output의 azure_blob_health_check_id>"
```

### 3단계: 모니터링 알람 배포

```bash
terraform plan
terraform apply
```

## 🧪 테스트 방법

### 1. 수동 알람 테스트

```bash
# 알람을 ALARM 상태로 변경
aws cloudwatch set-alarm-state \
  --alarm-name route53-aws-alb-health-check-failed \
  --state-value ALARM \
  --state-reason "Manual test"

# 슬랙에서 알림 확인 후 복구
aws cloudwatch set-alarm-state \
  --alarm-name route53-aws-alb-health-check-failed \
  --state-value OK \
  --state-reason "Test completed"
```

### 2. 실제 장애 시나리오 테스트

```bash
# AWS EKS Web Pod 중지 (CloudFront 페일오버 트리거)
kubectl config use-context arn:aws:eks:ap-northeast-2:822837196792:cluster/blue-eks
kubectl scale deployment web-nginx -n web --replicas=0

# 헬스체크 상태 모니터링 (1-2분 후 실패 예상)
aws route53 get-health-check-status \
  --health-check-id <aws_alb_health_check_id>

# CloudWatch 알람 상태 확인
aws cloudwatch describe-alarms \
  --alarm-names route53-aws-alb-health-check-failed

# 슬랙 알림 확인

# 서비스 복구
kubectl scale deployment web-nginx -n web --replicas=1
```

## 📈 모니터링 명령어

### 헬스체크 상태 확인

```bash
# AWS ALB 헬스체크
aws route53 get-health-check-status \
  --health-check-id af0c24e7-40e6-4392-b6ee-86b291199243

# CloudFront 헬스체크
aws route53 get-health-check-status \
  --health-check-id a7fffe67-f2e0-4980-ae66-fb93d98a6cc7

# Azure Blob 헬스체크
aws route53 get-health-check-status \
  --health-check-id 4d0d169e-269e-437f-bc03-f67c88c3c80f
```

### CloudWatch 알람 확인

```bash
# 모든 Route53 관련 알람 확인
aws cloudwatch describe-alarms \
  --alarm-name-prefix "route53" \
  --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
  --output table

# 특정 알람 상세 정보
aws cloudwatch describe-alarms \
  --alarm-names route53-aws-alb-health-check-failed
```

### 대시보드 확인

```bash
# CloudWatch 대시보드 URL 출력
echo "https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=blue-eks-monitoring-dashboard"
```

## 🎯 핵심 차이점

### 기존 vs 신규 구성

| 항목 | 기존 (CloudFront만 체크) | 신규 (AWS ALB 직접 체크) |
|------|-------------------------|------------------------|
| **감지 대상** | CloudFront 도메인 | AWS ALB 직접 |
| **AWS 장애 감지** | ❌ CloudFront가 Azure로 페일오버하면 여전히 정상 | ✅ AWS 인프라 장애 정확히 감지 |
| **페일오버 시점** | 사용자가 5XX 에러 경험 후 | AWS 장애 즉시 감지 |
| **알림 정확도** | 낮음 (False Negative 가능) | 높음 (실제 AWS 상태 반영) |
| **복구 자동화** | 어려움 | 가능 (Lambda 자동 복구) |

## 🔍 트러블슈팅

### 헬스체크가 실패하지 않는 경우

**문제**: Web Pod를 중지했는데도 헬스체크가 계속 성공
**원인**: CloudFront가 Azure로 자동 페일오버
**해결**: AWS ALB Direct 헬스체크 사용 (이미 설정됨)

### 알람이 발생하지 않는 경우

**확인사항**:
1. Route53 메트릭이 us-east-1에만 발행되는지 확인
2. CloudWatch 알람이 올바른 HealthCheckId를 참조하는지 확인
3. SNS 토픽이 Slack에 연결되었는지 확인

```bash
# SNS 구독 확인
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:ap-northeast-2:822837196792:blue-eks-monitoring-alerts
```

### 대시보드에 데이터가 없는 경우

**원인**: 헬스체크 메트릭은 us-east-1에만 발행
**해결**: 대시보드 위젯의 region을 "us-east-1"로 설정 (이미 설정됨)

## 📚 참고 자료

- [AWS Route53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
- [CloudWatch Metric Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [AWS Chatbot Slack Integration](https://docs.aws.amazon.com/chatbot/latest/adminguide/slack-setup.html)

## ✅ 체크리스트

- [x] Route53 헬스체크 3개 생성 (ALB, CloudFront, Azure)
- [x] CloudWatch 알람 4개 설정
- [x] CloudWatch 대시보드 위젯 추가
- [x] SNS → Slack 알림 연동
- [x] Terraform 코드 업데이트
- [x] 테스트 수행 및 검증 완료

---

**마지막 업데이트**: 2026-01-01
**작성자**: Claude Sonnet 4.5
