# AWS EKS 모니터링 수동 구축 가이드
**Terraform 없이 타인의 인프라에 모니터링 시스템 구축하기**

---

## 목차
1. [사전 준비사항](#1-사전-준비사항)
2. [Container Insights 활성화](#2-container-insights-활성화)
3. [SNS 알림 설정](#3-sns-알림-설정)
4. [CloudWatch 알람 생성](#4-cloudwatch-알람-생성)
5. [Lambda 자동 복구 설정](#5-lambda-자동-복구-설정)
6. [CloudWatch 대시보드 생성](#6-cloudwatch-대시보드-생성)
7. [Route53 Health Check 설정](#7-route53-health-check-설정)

---

## 1. 사전 준비사항

### 1.1 필요한 정보 수집
다음 정보를 미리 수집하세요:

```bash
# EKS 클러스터 정보
EKS_CLUSTER_NAME="blue-eks"
AWS_REGION="ap-northeast-2"
ENVIRONMENT="blue"

# ALB 정보
ALB_NAME="k8s-web-webingre-5d0cf16a97"

# RDS 정보
RDS_INSTANCE_ID="blue-rds"

# 알림 이메일
ALERT_EMAIL="your-email@example.com"
```

### 1.2 AWS CLI 설치 및 설정
```bash
# AWS CLI 설치 확인
aws --version

# 자격 증명 설정
aws configure
# AWS Access Key ID: [입력]
# AWS Secret Access Key: [입력]
# Default region name: ap-northeast-2
# Default output format: json
```

### 1.3 kubectl 설정
```bash
# EKS 클러스터 접근 설정
aws eks update-kubeconfig --name blue-eks --region ap-northeast-2

# 연결 확인
kubectl get nodes
```

---

## 2. Container Insights 활성화

### 2.1 EKS Observability 애드온 사용 (권장)

EKS의 **amazon-cloudwatch-observability** 애드온을 사용하면 CloudWatch Agent와 Fluent Bit가 자동으로 설치됩니다.
수동으로 Agent를 설치할 필요가 없습니다.

**방법 1: AWS 콘솔에서 활성화 (가장 간단)**
1. EKS 콘솔 → 클러스터 선택 (blue-eks)
2. "추가 기능(Add-ons)" 탭 클릭
3. "추가 기능 가져오기" 클릭
4. "Amazon CloudWatch Observability" 선택
5. 설치 확인

**방법 2: AWS CLI로 활성화**
```bash
# CloudWatch Observability 애드온 설치
aws eks create-addon \
  --cluster-name blue-eks \
  --addon-name amazon-cloudwatch-observability \
  --region ap-northeast-2

# 설치 상태 확인
aws eks describe-addon \
  --cluster-name blue-eks \
  --addon-name amazon-cloudwatch-observability \
  --region ap-northeast-2
```

**방법 3: Terraform으로 관리 (IaC 환경)**
```hcl
# codes/aws/service/modules/eks/main.tf에 이미 포함되어 있습니다
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "amazon-cloudwatch-observability"
}
```

### 2.2 EKS 컨트롤 플레인 로깅 활성화

```bash
aws eks update-cluster-config \
  --name blue-eks \
  --region ap-northeast-2 \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}'
```

### 2.3 (선택사항) 수동 설치가 필요한 경우

아래 상황에서만 수동 설치를 고려하세요:
- 콘솔/CLI 접근 권한이 없는 타인의 인프라
- 커스텀 설정이 필요한 경우 (수집 주기, 특정 메트릭만 수집 등)
- 에어갭(air-gapped) 환경

<details>
<summary>수동 설치 방법 (클릭하여 펼치기)</summary>

```bash
# 네임스페이스 생성
kubectl create namespace amazon-cloudwatch

# CloudWatch Agent ConfigMap 생성
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
data:
  cwagentconfig.json: |
    {
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "cluster_name": "blue-eks",
            "metrics_collection_interval": 60
          }
        },
        "force_flush_interval": 5
      }
    }
EOF

# Fluent Bit 설치
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml
```

</details>

### 2.4 CloudWatch Log Group 생성 (선택사항)

> **참고:** Observability 애드온이 로그 그룹을 자동 생성하지만, 보존 기간을 명시적으로 설정하려면 아래 명령을 실행하세요.

```bash
# Container Insights 성능 로그 그룹
aws logs create-log-group \
  --log-group-name /aws/containerinsights/blue-eks/performance \
  --region ap-northeast-2

# 로그 보존 기간 설정 (30일)
aws logs put-retention-policy \
  --log-group-name /aws/containerinsights/blue-eks/performance \
  --retention-in-days 30 \
  --region ap-northeast-2

# 애플리케이션 로그 그룹
aws logs create-log-group \
  --log-group-name /aws/containerinsights/blue-eks/application \
  --region ap-northeast-2

aws logs put-retention-policy \
  --log-group-name /aws/containerinsights/blue-eks/application \
  --retention-in-days 30 \
  --region ap-northeast-2
```

---

## 3. SNS 알림 설정

### 3.1 SNS Topic 생성

```bash
# SNS Topic 생성
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name blue-eks-monitoring-alerts \
  --region ap-northeast-2 \
  --output text \
  --query 'TopicArn')

echo "SNS Topic ARN: $SNS_TOPIC_ARN"
```

### 3.2 이메일 구독 추가

```bash
# 이메일 구독 추가
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol email \
  --notification-endpoint "your-email@example.com" \
  --region ap-northeast-2
```

**중요:** 이메일 확인 링크를 클릭하여 구독을 확인하세요!

### 3.3 SNS Topic 태깅

```bash
aws sns tag-resource \
  --resource-arn $SNS_TOPIC_ARN \
  --tags Key=Environment,Value=blue Key=Project,Value=Multi-Cloud-DR
```

---

## 4. CloudWatch 알람 생성

### 4.1 필수 정보 수집

```bash
# ALB ARN Suffix 확인
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names k8s-web-webingre-5d0cf16a97 \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

ALB_ARN_SUFFIX=$(echo $ALB_ARN | cut -d'/' -f2-)
echo "ALB ARN Suffix: $ALB_ARN_SUFFIX"

# Target Group ARN Suffix 확인
TG_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn $ALB_ARN \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

TG_ARN_SUFFIX=$(echo $TG_ARN | cut -d':' -f6)
echo "Target Group ARN Suffix: $TG_ARN_SUFFIX"
```

### 4.2 Node Level 알람

#### 4.2.1 Node CPU 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-eks-node-cpu-high \
  --alarm-description "EKS 노드 CPU 사용률이 80%를 초과했습니다" \
  --metric-name node_cpu_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.2.2 Node 메모리 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-eks-node-memory-high \
  --alarm-description "EKS 노드 메모리 사용률이 80%를 초과했습니다" \
  --metric-name node_memory_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.2.3 Node 디스크 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-eks-node-disk-high \
  --alarm-description "EKS 노드 디스크 사용률이 80%를 초과했습니다" \
  --metric-name node_filesystem_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.2.4 Node 상태 체크 실패 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-eks-node-status-check-failed \
  --alarm-description "EKS 노드 상태 체크 실패 - 자동 복구 트리거" \
  --metric-name StatusCheckFailed \
  --namespace AWS/EC2 \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=AutoScalingGroupName,Value=blue-eks-nodes \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.2.5 Node 개수 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-eks-node-count-low \
  --alarm-description "EKS 클러스터 노드 수가 최소값 미만입니다" \
  --metric-name cluster_node_count \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 2 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

### 4.3 Pod/Container Level 알람

#### 4.3.1 Pod CPU 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-pod-cpu-high \
  --alarm-description "Pod CPU 사용률이 85%를 초과했습니다" \
  --metric-name pod_cpu_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.2 Pod 메모리 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-pod-memory-high \
  --alarm-description "Pod 메모리 사용률이 85%를 초과했습니다" \
  --metric-name pod_memory_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.3 Pod 재시작 횟수 알람 (자동 복구 트리거)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-pod-restart-high \
  --alarm-description "Pod 재시작 횟수가 5회를 초과했습니다 - 자동 복구 필요" \
  --metric-name pod_number_of_container_restarts \
  --namespace ContainerInsights \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.4 Container CPU 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-container-cpu-high \
  --alarm-description "컨테이너 CPU 사용률이 80%를 초과했습니다" \
  --metric-name container_cpu_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.5 Container 메모리 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-container-memory-high \
  --alarm-description "컨테이너 메모리 사용률이 80%를 초과했습니다" \
  --metric-name container_memory_utilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.6 Pod 네트워크 수신 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-pod-network-rx-high \
  --alarm-description "Pod 네트워크 수신량이 임계값을 초과했습니다" \
  --metric-name pod_network_rx_bytes \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 100000000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.7 Pod 네트워크 송신 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-pod-network-tx-high \
  --alarm-description "Pod 네트워크 송신량이 임계값을 초과했습니다" \
  --metric-name pod_network_tx_bytes \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 100000000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.3.8 실행 중인 서비스 Pod 수 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-service-count-low \
  --alarm-description "실행 중인 서비스 Pod 수가 1개 미만입니다" \
  --metric-name service_number_of_running_pods \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=ClusterName,Value=blue-eks \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

### 4.4 ALB 알람

#### 4.4.1 Surge Queue 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-alb-surge-queue-high \
  --alarm-description "ALB Surge Queue 길이가 100을 초과했습니다" \
  --metric-name SurgeQueueLength \
  --namespace AWS/ApplicationELB \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.4.2 ALB 5XX 에러 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-alb-5xx-errors-high \
  --alarm-description "ALB 5XX 에러가 10회를 초과했습니다" \
  --metric-name HTTPCode_ELB_5XX_Count \
  --namespace AWS/ApplicationELB \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching \
  --region ap-northeast-2
```

#### 4.4.3 Target 5XX 에러 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-target-5xx-errors-high \
  --alarm-description "Target 5XX 에러가 10회를 초과했습니다" \
  --metric-name HTTPCode_Target_5XX_Count \
  --namespace AWS/ApplicationELB \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching \
  --region ap-northeast-2
```

#### 4.4.4 응답 지연 알람 (p95)

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-alb-latency-high \
  --alarm-description "ALB 응답 지연 시간(p95)이 2초를 초과했습니다" \
  --metric-name TargetResponseTime \
  --namespace AWS/ApplicationELB \
  --extended-statistic p95 \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 2.0 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.4.5 비정상 호스트 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-unhealthy-hosts \
  --alarm-description "비정상 호스트가 감지되었습니다" \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=LoadBalancer,Value=$ALB_ARN_SUFFIX Name=TargetGroup,Value=$TG_ARN_SUFFIX \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

### 4.5 RDS 알람

#### 4.5.1 RDS 스토리지 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-rds-storage-low \
  --alarm-description "RDS 여유 스토리지가 10GB 미만입니다" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 10737418240 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=blue-rds \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.5.2 RDS 연결 수 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-rds-connections-high \
  --alarm-description "RDS 연결 수가 100개를 초과했습니다" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=blue-rds \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.5.3 RDS 디스크 큐 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-rds-disk-queue-high \
  --alarm-description "RDS 디스크 큐 깊이가 10을 초과했습니다" \
  --metric-name DiskQueueDepth \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=blue-rds \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

#### 4.5.4 RDS CPU 사용률 알람

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name blue-rds-cpu-high \
  --alarm-description "RDS CPU 사용률이 80%를 초과했습니다" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=DBInstanceIdentifier,Value=blue-rds \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region ap-northeast-2
```

---

## 5. Lambda 자동 복구 설정

### 5.1 Lambda 함수 코드 작성

Lambda 함수 디렉토리 생성:
```bash
mkdir -p /tmp/lambda-auto-recovery
cd /tmp/lambda-auto-recovery
```

`index.py` 파일 생성:
```python
import json
import boto3
import os
from datetime import datetime

# AWS 클라이언트 초기화
eks_client = boto3.client('eks')
ec2_client = boto3.client('ec2')
asg_client = boto3.client('autoscaling')
sns_client = boto3.client('sns')

CLUSTER_NAME = os.environ.get('CLUSTER_NAME', 'blue-eks')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'blue')

def handler(event, context):
    """
    CloudWatch 알람 이벤트를 받아서 자동 복구를 수행합니다.
    """
    print(f"Received event: {json.dumps(event)}")

    try:
        # SNS 메시지 파싱
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message.get('AlarmName', '')
        alarm_state = message.get('NewStateValue', '')

        print(f"Alarm: {alarm_name}, State: {alarm_state}")

        # ALARM 상태일 때만 처리
        if alarm_state != 'ALARM':
            print("Alarm state is not ALARM, skipping auto-recovery")
            return {'statusCode': 200, 'body': 'No action required'}

        # 알람 유형에 따라 복구 작업 수행
        recovery_action = None

        if 'pod-restart-high' in alarm_name.lower():
            recovery_action = handle_pod_restart()
        elif 'node-status-check-failed' in alarm_name.lower():
            recovery_action = handle_node_failure()
        elif 'unhealthy-hosts' in alarm_name.lower():
            recovery_action = handle_unhealthy_targets()
        else:
            print(f"No auto-recovery action defined for alarm: {alarm_name}")
            return {'statusCode': 200, 'body': 'No auto-recovery action defined'}

        # SNS 알림 전송
        if recovery_action:
            send_notification(alarm_name, recovery_action)

        return {
            'statusCode': 200,
            'body': json.dumps(f'Auto-recovery completed: {recovery_action}')
        }

    except Exception as e:
        print(f"Error during auto-recovery: {str(e)}")
        send_error_notification(str(e))
        raise

def handle_pod_restart():
    """Pod 재시작이 빈번할 때 노드 교체"""
    print("Handling pod restart issue - attempting node replacement")

    try:
        # EKS 노드 그룹 조회
        node_groups = eks_client.list_nodegroups(clusterName=CLUSTER_NAME)

        for ng_name in node_groups.get('nodegroups', []):
            # 노드 그룹 정보 가져오기
            ng_info = eks_client.describe_nodegroup(
                clusterName=CLUSTER_NAME,
                nodegroupName=ng_name
            )

            asg_name = ng_info['nodegroup']['resources']['autoScalingGroups'][0]['name']

            # ASG 인스턴스 순환 교체 (1개씩)
            asg_info = asg_client.describe_auto_scaling_groups(
                AutoScalingGroupNames=[asg_name]
            )

            instances = asg_info['AutoScalingGroups'][0]['Instances']

            if instances:
                # 가장 오래된 인스턴스 1개만 종료 (ASG가 자동으로 새 인스턴스 생성)
                oldest_instance = min(instances, key=lambda x: x['LaunchTime'])
                instance_id = oldest_instance['InstanceId']

                print(f"Terminating oldest instance: {instance_id}")

                asg_client.terminate_instance_in_auto_scaling_group(
                    InstanceId=instance_id,
                    ShouldDecrementDesiredCapacity=False
                )

                return f"Terminated problematic node instance: {instance_id}"

        return "No action taken - no nodegroups found"

    except Exception as e:
        print(f"Error in handle_pod_restart: {str(e)}")
        return f"Failed to handle pod restart: {str(e)}"

def handle_node_failure():
    """노드 상태 체크 실패 시 노드 재시작"""
    print("Handling node status check failure")

    try:
        # 실패한 인스턴스 찾기
        response = ec2_client.describe_instance_status(
            Filters=[
                {'Name': 'instance-status.status', 'Values': ['impaired']},
            ]
        )

        for instance in response['InstanceStatuses']:
            instance_id = instance['InstanceId']

            print(f"Rebooting failed instance: {instance_id}")
            ec2_client.reboot_instances(InstanceIds=[instance_id])

        return f"Rebooted {len(response['InstanceStatuses'])} failed instances"

    except Exception as e:
        print(f"Error in handle_node_failure: {str(e)}")
        return f"Failed to handle node failure: {str(e)}"

def handle_unhealthy_targets():
    """비정상 타겟 처리 - 노드 드레인 및 재시작"""
    print("Handling unhealthy targets - this may require manual intervention")
    return "Unhealthy targets detected - manual review recommended"

def send_notification(alarm_name, action):
    """SNS를 통해 복구 작업 알림 전송"""
    try:
        message = f"""
Auto-Recovery Action Completed
================================
Environment: {ENVIRONMENT}
Cluster: {CLUSTER_NAME}
Alarm: {alarm_name}
Action Taken: {action}
Timestamp: {datetime.utcnow().isoformat()}

This is an automated recovery action triggered by CloudWatch Alarms.
        """

        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{ENVIRONMENT}] Auto-Recovery: {alarm_name}",
            Message=message
        )

        print("Notification sent successfully")

    except Exception as e:
        print(f"Error sending notification: {str(e)}")

def send_error_notification(error):
    """에러 발생 시 알림"""
    try:
        message = f"""
Auto-Recovery Failed
====================
Environment: {ENVIRONMENT}
Cluster: {CLUSTER_NAME}
Error: {error}
Timestamp: {datetime.utcnow().isoformat()}

Manual intervention may be required.
        """

        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"[{ENVIRONMENT}] Auto-Recovery FAILED",
            Message=message
        )

    except Exception as e:
        print(f"Error sending error notification: {str(e)}")
```

### 5.2 Lambda 배포 패키지 생성

```bash
cd /tmp/lambda-auto-recovery
zip auto_recovery.zip index.py
```

### 5.3 IAM Role 생성

```bash
# Trust Policy 파일 생성
cat > /tmp/lambda-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# IAM Role 생성
aws iam create-role \
  --role-name blue-auto-recovery-lambda-role \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json

# Lambda 권한 정책 파일 생성
cat > /tmp/lambda-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListNodegroups",
        "eks:DescribeNodegroup",
        "eks:UpdateNodegroupConfig"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceStatus",
        "ec2:TerminateInstances",
        "ec2:RebootInstances"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "$SNS_TOPIC_ARN"
    }
  ]
}
EOF

# 정책 연결
aws iam put-role-policy \
  --role-name blue-auto-recovery-lambda-role \
  --policy-name blue-auto-recovery-lambda-policy \
  --policy-document file:///tmp/lambda-policy.json
```

### 5.4 Lambda 함수 생성

```bash
# IAM Role ARN 확인
LAMBDA_ROLE_ARN=$(aws iam get-role \
  --role-name blue-auto-recovery-lambda-role \
  --query 'Role.Arn' \
  --output text)

# Lambda 함수 생성
aws lambda create-function \
  --function-name blue-eks-auto-recovery \
  --runtime python3.11 \
  --role $LAMBDA_ROLE_ARN \
  --handler index.handler \
  --zip-file fileb:///tmp/lambda-auto-recovery/auto_recovery.zip \
  --timeout 300 \
  --memory-size 256 \
  --environment "Variables={CLUSTER_NAME=blue-eks,SNS_TOPIC_ARN=$SNS_TOPIC_ARN,ENVIRONMENT=blue}" \
  --region ap-northeast-2
```

### 5.5 CloudWatch Logs 설정

```bash
# Lambda 로그 그룹 생성
aws logs create-log-group \
  --log-group-name /aws/lambda/blue-eks-auto-recovery \
  --region ap-northeast-2

# 로그 보존 기간 설정
aws logs put-retention-policy \
  --log-group-name /aws/lambda/blue-eks-auto-recovery \
  --retention-in-days 30 \
  --region ap-northeast-2
```

### 5.6 SNS Topic에 Lambda 구독 추가

```bash
# Lambda 함수 ARN 확인
LAMBDA_ARN=$(aws lambda get-function \
  --function-name blue-eks-auto-recovery \
  --query 'Configuration.FunctionArn' \
  --output text)

# SNS Topic에서 Lambda 호출 권한 부여
aws lambda add-permission \
  --function-name blue-eks-auto-recovery \
  --statement-id AllowSNSInvoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn $SNS_TOPIC_ARN \
  --region ap-northeast-2

# SNS 구독 생성
aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol lambda \
  --notification-endpoint $LAMBDA_ARN \
  --region ap-northeast-2
```

---

## 6. CloudWatch 대시보드 생성

### 6.1 대시보드 JSON 파일 준비

```bash
cat > /tmp/dashboard.json <<'DASHBOARD_EOF'
{
  "widgets": [
    {
      "type": "text",
      "x": 0,
      "y": 0,
      "width": 24,
      "height": 1,
      "properties": {
        "markdown": "# EKS Cluster Monitoring Dashboard - blue"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 1,
      "width": 6,
      "height": 6,
      "properties": {
        "title": "Node CPU Utilization",
        "region": "ap-northeast-2",
        "metrics": [
          ["ContainerInsights", "node_cpu_utilization", "ClusterName", "blue-eks", {"stat": "Average"}]
        ],
        "period": 300,
        "yAxis": {
          "left": {"min": 0, "max": 100}
        },
        "annotations": {
          "horizontal": [{
            "value": 80,
            "label": "Threshold",
            "color": "#ff0000"
          }]
        }
      }
    },
    {
      "type": "metric",
      "x": 6,
      "y": 1,
      "width": 6,
      "height": 6,
      "properties": {
        "title": "Node Memory Utilization",
        "region": "ap-northeast-2",
        "metrics": [
          ["ContainerInsights", "node_memory_utilization", "ClusterName", "blue-eks", {"stat": "Average"}]
        ],
        "period": 300,
        "yAxis": {
          "left": {"min": 0, "max": 100}
        },
        "annotations": {
          "horizontal": [{
            "value": 80,
            "label": "Threshold",
            "color": "#ff0000"
          }]
        }
      }
    },
    {
      "type": "metric",
      "x": 12,
      "y": 1,
      "width": 6,
      "height": 6,
      "properties": {
        "title": "Pod CPU Utilization",
        "region": "ap-northeast-2",
        "metrics": [
          ["ContainerInsights", "pod_cpu_utilization", "ClusterName", "blue-eks", {"stat": "Average"}]
        ],
        "period": 300,
        "yAxis": {
          "left": {"min": 0, "max": 100}
        }
      }
    },
    {
      "type": "metric",
      "x": 18,
      "y": 1,
      "width": 6,
      "height": 6,
      "properties": {
        "title": "Pod Memory Utilization",
        "region": "ap-northeast-2",
        "metrics": [
          ["ContainerInsights", "pod_memory_utilization", "ClusterName", "blue-eks", {"stat": "Average"}]
        ],
        "period": 300,
        "yAxis": {
          "left": {"min": 0, "max": 100}
        }
      }
    }
  ]
}
DASHBOARD_EOF
```

### 6.2 대시보드 생성

```bash
aws cloudwatch put-dashboard \
  --dashboard-name blue-eks-monitoring-dashboard \
  --dashboard-body file:///tmp/dashboard.json \
  --region ap-northeast-2
```

**또는 AWS 콘솔에서 수동 생성:**

1. CloudWatch 콘솔 → 대시보드 → "대시보드 생성"
2. 대시보드 이름: `blue-eks-monitoring-dashboard`
3. 위젯 추가:
   - "숫자" 위젯: 주요 메트릭 표시
   - "선 그래프" 위젯: CPU, 메모리 추세
   - "로그 테이블" 위젯: 최근 알람 표시

---

## 7. Route53 Health Check 설정

### 7.1 Primary (AWS) Health Check 생성

```bash
# Health Check 생성
PRIMARY_HC_ID=$(aws route53 create-health-check \
  --caller-reference "blue-primary-$(date +%s)" \
  --health-check-config \
    Type=HTTPS,\
ResourcePath=/,\
FullyQualifiedDomainName=blueisthenewblack.store,\
Port=443,\
RequestInterval=30,\
FailureThreshold=3 \
  --health-check-tags Key=Name,Value=blue-primary-health-check Key=Environment,Value=blue \
  --query 'HealthCheck.Id' \
  --output text \
  --region us-east-1)

echo "Primary Health Check ID: $PRIMARY_HC_ID"
```

### 7.2 Secondary (Azure) Health Check 생성

```bash
# 만약 Azure 엔드포인트가 있다면
SECONDARY_HC_ID=$(aws route53 create-health-check \
  --caller-reference "blue-secondary-$(date +%s)" \
  --health-check-config \
    Type=HTTPS,\
ResourcePath=/,\
FullyQualifiedDomainName=azure-endpoint.example.com,\
Port=443,\
RequestInterval=30,\
FailureThreshold=3 \
  --health-check-tags Key=Name,Value=blue-secondary-health-check Key=Environment,Value=blue \
  --query 'HealthCheck.Id' \
  --output text \
  --region us-east-1)

echo "Secondary Health Check ID: $SECONDARY_HC_ID"
```

### 7.3 Route53 Health Check 알람 생성

```bash
# Primary Health Check 알람
aws cloudwatch put-metric-alarm \
  --alarm-name blue-route53-primary-unhealthy \
  --alarm-description "Primary (AWS) Route53 Health Check 실패 - Failover 발생 가능" \
  --metric-name HealthCheckStatus \
  --namespace AWS/Route53 \
  --statistic Minimum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=HealthCheckId,Value=$PRIMARY_HC_ID \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region us-east-1

# Primary Health Check Percentage 알람
aws cloudwatch put-metric-alarm \
  --alarm-name blue-route53-primary-percentage-low \
  --alarm-description "Primary Health Check 정상 비율이 50% 미만입니다" \
  --metric-name HealthCheckPercentageHealthy \
  --namespace AWS/Route53 \
  --statistic Average \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 50 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=HealthCheckId,Value=$PRIMARY_HC_ID \
  --alarm-actions $SNS_TOPIC_ARN \
  --ok-actions $SNS_TOPIC_ARN \
  --region us-east-1
```

---

## 8. 검증 및 테스트

### 8.1 Observability 애드온 및 Container Insights 확인

```bash
# Observability 애드온 상태 확인
aws eks describe-addon \
  --cluster-name blue-eks \
  --addon-name amazon-cloudwatch-observability \
  --region ap-northeast-2

# CloudWatch Agent Pod 상태 확인
kubectl get pods -n amazon-cloudwatch

# 메트릭 확인
aws cloudwatch list-metrics \
  --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value=blue-eks \
  --region ap-northeast-2 | head -50

# 로그 그룹 확인
aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/blue-eks \
  --region ap-northeast-2
```

### 8.2 알람 상태 확인

```bash
# 모든 알람 상태 확인
aws cloudwatch describe-alarms \
  --alarm-name-prefix blue \
  --region ap-northeast-2 \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table
```

### 8.3 테스트 알람 트리거

```bash
# CPU 부하 테스트 Pod 생성
kubectl run stress-test --image=polinux/stress --rm -it \
  -- stress --cpu 4 --timeout 300s
```

### 8.4 Lambda 함수 테스트

```bash
# Lambda 함수 수동 호출 테스트
aws lambda invoke \
  --function-name blue-eks-auto-recovery \
  --payload '{"Records":[{"Sns":{"Message":"{\"AlarmName\":\"test-alarm\",\"NewStateValue\":\"ALARM\"}"}}]}' \
  /tmp/lambda-response.json \
  --region ap-northeast-2

# 결과 확인
cat /tmp/lambda-response.json
```

---

## 9. 모니터링 유지보수

### 9.1 알람 임계값 조정

```bash
# 기존 알람 수정 예시
aws cloudwatch put-metric-alarm \
  --alarm-name blue-eks-node-cpu-high \
  --threshold 85 \
  --region ap-northeast-2
```

### 9.2 로그 확인

```bash
# Container Insights 로그 확인
aws logs tail /aws/containerinsights/blue-eks/performance --follow

# Lambda 로그 확인
aws logs tail /aws/lambda/blue-eks-auto-recovery --follow
```

### 9.3 대시보드 URL

CloudWatch 대시보드 접근:
```
https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=blue-eks-monitoring-dashboard
```

---

## 10. 트러블슈팅

### 10.1 Container Insights 메트릭이 수집되지 않는 경우

**Observability 애드온 사용 시:**
```bash
# 애드온 상태 확인
aws eks describe-addon \
  --cluster-name blue-eks \
  --addon-name amazon-cloudwatch-observability \
  --region ap-northeast-2

# CloudWatch Agent Pod 상태 확인
kubectl get pods -n amazon-cloudwatch

# CloudWatch Agent 로그 확인
kubectl logs -n amazon-cloudwatch -l app.kubernetes.io/name=cloudwatch-agent

# Fluent Bit 로그 확인
kubectl logs -n amazon-cloudwatch -l app.kubernetes.io/name=fluent-bit
```

**수동 설치 시:**
```bash
# CloudWatch Agent Pod 상태 확인
kubectl get pods -n amazon-cloudwatch

# CloudWatch Agent 로그 확인
kubectl logs -n amazon-cloudwatch -l name=cloudwatch-agent

# Fluent Bit 로그 확인
kubectl logs -n amazon-cloudwatch -l k8s-app=fluent-bit
```

### 10.2 알람이 트리거되지 않는 경우

```bash
# 메트릭 데이터 확인
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value=blue-eks \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region ap-northeast-2
```

### 10.3 Lambda 함수 실행 실패

```bash
# Lambda 실행 로그 확인
aws logs filter-log-events \
  --log-group-name /aws/lambda/blue-eks-auto-recovery \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --region ap-northeast-2

# IAM 권한 확인
aws iam get-role-policy \
  --role-name blue-auto-recovery-lambda-role \
  --policy-name blue-auto-recovery-lambda-policy
```

---

## 11. 비용 최적화

### 11.1 예상 비용

- **CloudWatch Logs**: 수집량에 따라 (약 $0.50/GB)
- **CloudWatch Metrics**: 커스텀 메트릭당 $0.30/월
- **CloudWatch Alarms**: 알람당 $0.10/월
- **Lambda**: 실행 횟수에 따라 (프리티어 포함)
- **SNS**: 알림 발송 횟수에 따라 (프리티어 포함)

### 11.2 비용 절감 팁

1. 로그 보존 기간을 필요한 만큼만 설정 (30일 권장)
2. 불필요한 메트릭 수집 비활성화
3. 알람 평가 주기 조정 (5분 → 10분)
4. 대시보드 위젯 수 최소화

---

## 12. 체크리스트

### 배포 완료 체크리스트

- [ ] CloudWatch Observability 애드온 설치 완료
- [ ] Container Insights 메트릭 수집 확인
- [ ] CloudWatch Log Groups 생성 완료 (선택사항)
- [ ] SNS Topic 및 이메일 구독 설정 완료
- [ ] Node Level 알람 (5개) 생성 완료
- [ ] Pod/Container Level 알람 (8개) 생성 완료
- [ ] ALB 알람 (5개) 생성 완료
- [ ] RDS 알람 (4개) 생성 완료
- [ ] Lambda 자동 복구 함수 생성 완료
- [ ] CloudWatch 대시보드 생성 완료
- [ ] Route53 Health Check 설정 완료 (선택)
- [ ] 알람 테스트 완료
- [ ] Lambda 함수 테스트 완료

### 운영 체크리스트

- [ ] 주간 대시보드 리뷰
- [ ] 월간 알람 임계값 검토
- [ ] 분기별 비용 리뷰 및 최적화
- [ ] 반기별 Lambda 함수 코드 업데이트

---

## 13. 추가 자료

### AWS 공식 문서
- [Container Insights 설정](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-EKS.html)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Lambda 자동화](https://docs.aws.amazon.com/lambda/latest/dg/lambda-services.html)

### 유용한 명령어 모음

```bash
# 모든 알람 삭제 (재배포 시)
aws cloudwatch describe-alarms --alarm-name-prefix blue \
  --query 'MetricAlarms[*].AlarmName' --output text | \
  xargs -n1 aws cloudwatch delete-alarms --alarm-names

# 모든 알람 비활성화
aws cloudwatch describe-alarms --alarm-name-prefix blue \
  --query 'MetricAlarms[*].AlarmName' --output text | \
  xargs -n1 aws cloudwatch disable-alarm-actions --alarm-names

# 모든 알람 활성화
aws cloudwatch describe-alarms --alarm-name-prefix blue \
  --query 'MetricAlarms[*].AlarmName' --output text | \
  xargs -n1 aws cloudwatch enable-alarm-actions --alarm-names
```

---

## 문의 및 지원

문제가 발생하거나 추가 지원이 필요한 경우:
1. CloudWatch Logs에서 에러 로그 확인
2. AWS Support 케이스 오픈
3. 내부 DevOps 팀에 문의

---

**작성일**: 2024
**버전**: 1.0
**작성자**: I2ST-blue
