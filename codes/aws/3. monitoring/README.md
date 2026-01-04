# AWS EKS Monitoring Module

이 모듈은 EKS 클러스터, ALB, RDS에 대한 종합 모니터링을 제공합니다.

## 주요 기능

- **CloudWatch Container Insights**: EKS 클러스터 메트릭 수집
- **CloudWatch Alarms**: 자동 알람 및 복구
- **Lambda Auto Recovery**: 장애 발생 시 자동 복구
- **CloudWatch Dashboard**: 통합 모니터링 대시보드
- **SNS Notifications**: 이메일 및 Slack 알림
- **Route53 Health Checks**: Multi-Cloud DR 헬스 체크 모니터링

## Destroy 후 재배포 가이드

### 1. 사전 준비

모니터링 모듈을 destroy하기 전에 현재 설정을 확인합니다:

```bash
cd "codes/aws/3. monitoring"

# 현재 terraform.tfvars 확인
cat terraform.tfvars

# 현재 상태 확인
terraform show
```

### 2. Destroy 실행

```bash
# Dry-run으로 삭제될 리소스 확인
terraform plan -destroy

# 실제 삭제
terraform destroy
```

### 3. 재배포

terraform.tfvars 파일은 이미 저장되어 있으므로 그대로 재사용할 수 있습니다:

```bash
# Terraform 초기화 (필요시)
terraform init

# 배포 계획 확인
terraform plan

# 배포 실행
terraform apply
```

### 4. 배포 후 확인

```bash
# 출력값 확인
terraform output

# 대시보드 URL 확인
terraform output dashboard_url

# SNS Topic ARN 확인
terraform output sns_topic_arn
```

## 주요 설정 파일

### terraform.tfvars

모든 환경 설정이 저장되어 있습니다:

- EKS 클러스터 이름
- ALB/RDS 식별자
- Route53 Health Check ID
- 알람 임계값
- Slack 설정 (선택사항)

**중요**: `terraform.tfvars` 파일이 git에 커밋되어 있으므로 destroy 후에도 동일한 설정으로 재배포할 수 있습니다.

### Lambda 코드

Lambda 함수 코드는 `lambda/index.py`에 저장되어 있으며, Terraform이 자동으로 zip 파일을 생성합니다.

- `lambda/index.py`: Lambda 소스 코드
- `lambda/auto_recovery_generated.zip`: Terraform이 자동 생성 (git 제외)

## CloudWatch 대시보드 구성

대시보드는 다음 섹션으로 구성되어 있습니다:

1. **EKS Cluster Monitoring Dashboard**: 전체 개요
2. **Node Metrics**: CPU, Memory, Disk, Node Count
3. **Container/Pod Metrics**: Pod CPU, Memory, Restart Count
4. **ALB Metrics**: Request Count, 5XX Errors, Latency, Surge Queue
5. **RDS Metrics**: CPU, Storage, Connections, Disk Queue
6. **RDS Enhanced Monitoring**: IOPS, Throughput, Network
7. **Route53 Health Check**: AWS ALB, CloudFront, Azure Blob 헬스체크

## 알람 목록

### Infrastructure Alarms
- Node CPU High
- Node Memory High
- Node Disk High
- Node Status Check Failed
- Node Count Low

### Application Alarms
- Pod CPU High
- Pod Memory High
- Pod Restart High (자동 복구 트리거)
- Container CPU High
- Container Memory High

### ALB Alarms
- ALB 5XX Errors
- Target 5XX Errors
- ALB Latency High
- Surge Queue High
- Unhealthy Host Count

### RDS Alarms
- RDS CPU High
- RDS Storage Low
- RDS Connections High
- RDS Disk Queue High
- RDS Read/Write Latency High
- RDS Memory Low

### Route53 Health Check Alarms
- Primary Health Check Failed
- Secondary Health Check Failed
- AWS ALB Health Check Failed
- Composite Alarm: All Sites Down

## Auto Recovery 기능

Lambda 함수가 다음 알람에 대해 자동 복구를 수행합니다:

1. **Node Status Check Failed**: 비정상 인스턴스 종료 및 교체
2. **Node Count Low**: ASG desired capacity 증가
3. **Pod Restart High**: 알림 및 조사 권장
4. **Resource Pressure**: 스케일 아웃 권장

## SNS Topic 구독

### 이메일 구독 (자동 생성되지 않음)

이메일 알림을 받으려면 SNS Topic을 수동으로 구독해야 합니다:

```bash
# SNS Topic ARN 확인
aws sns list-topics --region ap-northeast-2

# 이메일 구독 추가
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-northeast-2:ACCOUNT_ID:blue-eks-monitoring-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com

# 이메일 확인 후 구독 승인 필요
```

### Slack 연동 (AWS Chatbot)

Slack 알림은 AWS Chatbot을 통해 설정됩니다:

1. AWS Chatbot 콘솔에서 Slack 워크스페이스 연동
2. Slack Workspace ID 및 Channel ID 확인
3. `terraform.tfvars`에 ID 입력 후 재배포

```hcl
slack_workspace_id = "T01234567"  # Slack Team ID
slack_channel_id   = "C01234567"  # Slack Channel ID
```

## Route53 Health Check 설정

Route53 Health Check ID는 다음 명령으로 확인할 수 있습니다:

```bash
# Health Check 목록 조회
aws route53 list-health-checks --region us-east-1

# 특정 Health Check 상세 조회
aws route53 get-health-check --health-check-id HEALTH_CHECK_ID --region us-east-1
```

**중요**: Route53 메트릭은 `us-east-1` 리전에서만 사용 가능합니다.

## 문제 해결

### Lambda 함수가 생성되지 않는 경우

```bash
# Lambda 디렉토리 확인
ls -la lambda/

# index.py 파일 존재 확인
cat lambda/index.py

# Terraform 재초기화
terraform init -upgrade
```

### 대시보드가 표시되지 않는 경우

```bash
# 대시보드 확인
aws cloudwatch list-dashboards --region ap-northeast-2

# 대시보드 삭제 후 재생성
terraform taint aws_cloudwatch_dashboard.eks_monitoring
terraform apply
```

### 알람이 작동하지 않는 경우

```bash
# 알람 상태 확인
aws cloudwatch describe-alarms --region ap-northeast-2

# SNS Topic 구독 확인
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:ap-northeast-2:ACCOUNT_ID:blue-eks-monitoring-alerts
```

## 비용 최적화

- **CloudWatch Logs**: 30일 보존 기간 (변경 가능)
- **Lambda**: 최소 실행 빈도 (알람 발생 시에만 실행)
- **CloudWatch Metrics**: Container Insights 메트릭은 비용 발생
- **Route53 Health Checks**: Health Check 수에 따라 과금

비용을 줄이려면:
- `log_retention_days`를 7일로 단축
- 불필요한 알람 비활성화
- Container Insights 비활성화 (권장하지 않음)

## 참고 자료

- [AWS CloudWatch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html)
- [AWS Lambda Auto Recovery](https://aws.amazon.com/blogs/compute/building-well-architected-serverless-applications-implementing-application-resiliency/)
- [AWS Chatbot Slack Integration](https://docs.aws.amazon.com/chatbot/latest/adminguide/slack-setup.html)
- [Route53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
