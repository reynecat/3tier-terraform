# others/lambda/dms-monitor.py
# Lambda 함수: DMS 복제 지연 모니터링

import json
import boto3
import os
from datetime import datetime

dms = boto3.client('dms')
cloudwatch = boto3.client('cloudwatch')
sns = boto3.client('sns')

# 환경 변수
REPLICATION_TASK_ARN = os.environ['REPLICATION_TASK_ARN']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
LATENCY_THRESHOLD = int(os.environ.get('LATENCY_THRESHOLD', '60'))  # 초

def lambda_handler(event, context):
    """
    DMS 복제 태스크의 지연 시간을 모니터링하고
    임계값을 초과하면 알림을 발송합니다.
    """
    
    try:
        # DMS 태스크 상태 조회
        response = dms.describe_replication_tasks(
            Filters=[
                {
                    'Name': 'replication-task-arn',
                    'Values': [REPLICATION_TASK_ARN]
                }
            ]
        )
        
        if not response['ReplicationTasks']:
            return {
                'statusCode': 404,
                'body': json.dumps('Replication task not found')
            }
        
        task = response['ReplicationTasks'][0]
        task_status = task['Status']
        
        # 복제 통계 조회
        stats = dms.describe_replication_task_assessment_results(
            ReplicationTaskArn=REPLICATION_TASK_ARN
        )
        
        # CDC 지연 시간 확인 (CDCLatencySource 메트릭)
        metrics = cloudwatch.get_metric_statistics(
            Namespace='AWS/DMS',
            MetricName='CDCLatencySource',
            Dimensions=[
                {
                    'Name': 'ReplicationTaskIdentifier',
                    'Value': task['ReplicationTaskIdentifier']
                }
            ],
            StartTime=datetime.utcnow().replace(minute=0, second=0, microsecond=0),
            EndTime=datetime.utcnow(),
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # 지연 시간 분석
        if metrics['Datapoints']:
            latest_metric = sorted(metrics['Datapoints'], 
                                 key=lambda x: x['Timestamp'])[-1]
            
            avg_latency = latest_metric.get('Average', 0)
            max_latency = latest_metric.get('Maximum', 0)
            
            print(f"Task Status: {task_status}")
            print(f"Average Latency: {avg_latency}s")
            print(f"Maximum Latency: {max_latency}s")
            
            # 임계값 초과 시 알림
            if max_latency > LATENCY_THRESHOLD:
                alert_message = f"""
                ⚠️ DMS 복제 지연 경고
                
                Task: {task['ReplicationTaskIdentifier']}
                Status: {task_status}
                Average Latency: {avg_latency:.2f}초
                Maximum Latency: {max_latency:.2f}초
                Threshold: {LATENCY_THRESHOLD}초
                
                조치 필요: DMS 태스크를 확인해주세요.
                """
                
                if SNS_TOPIC_ARN:
                    sns.publish(
                        TopicArn=SNS_TOPIC_ARN,
                        Subject='DMS 복제 지연 경고',
                        Message=alert_message
                    )
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'status': 'WARNING',
                        'message': 'Latency threshold exceeded',
                        'latency': max_latency
                    })
                }
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'OK',
                    'task_status': task_status,
                    'avg_latency': avg_latency,
                    'max_latency': max_latency
                })
            }
        
        else:
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'status': 'NO_DATA',
                    'message': 'No metrics available'
                })
            }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'ERROR',
                'error': str(e)
            })
        }
