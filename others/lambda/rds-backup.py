# others/lambda/rds-backup.py
# Lambda 함수: RDS 백업 자동화 및 전송

import json
import boto3
import os
from datetime import datetime, timedelta

rds = boto3.client('rds')
s3 = boto3.client('s3')
sns = boto3.client('sns')

# 환경 변수
DB_INSTANCE_ID = os.environ['DB_INSTANCE_ID']
S3_BUCKET = os.environ['S3_BUCKET']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')
RETENTION_DAYS = int(os.environ.get('RETENTION_DAYS', '7'))

def lambda_handler(event, context):
    """
    RDS 수동 스냅샷 생성 및 S3 백업 관리
    """
    
    timestamp = datetime.now().strftime('%Y-%m-%d-%H%M')
    snapshot_id = f"{DB_INSTANCE_ID}-manual-{timestamp}"
    
    try:
        # 1. 수동 스냅샷 생성
        print(f"Creating snapshot: {snapshot_id}")
        
        snapshot_response = rds.create_db_snapshot(
            DBSnapshotIdentifier=snapshot_id,
            DBInstanceIdentifier=DB_INSTANCE_ID,
            Tags=[
                {'Key': 'Type', 'Value': 'Manual'},
                {'Key': 'CreatedBy', 'Value': 'Lambda'},
                {'Key': 'Timestamp', 'Value': timestamp}
            ]
        )
        
        snapshot_arn = snapshot_response['DBSnapshot']['DBSnapshotArn']
        print(f"Snapshot created: {snapshot_arn}")
        
        # 2. 오래된 스냅샷 삭제 (보존 기간 초과)
        delete_old_snapshots()
        
        # 3. S3에 메타데이터 저장
        metadata = {
            'snapshot_id': snapshot_id,
            'db_instance': DB_INSTANCE_ID,
            'timestamp': timestamp,
            'arn': snapshot_arn
        }
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=f'snapshots/{timestamp}.json',
            Body=json.dumps(metadata, indent=2),
            ContentType='application/json'
        )
        
        # 4. 성공 알림
        if SNS_TOPIC_ARN:
            message = f"""
            ✅ RDS 백업 완료
            
            Snapshot ID: {snapshot_id}
            DB Instance: {DB_INSTANCE_ID}
            Timestamp: {timestamp}
            ARN: {snapshot_arn}
            
            S3 Bucket: {S3_BUCKET}
            """
            
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject='RDS 백업 성공',
                Message=message
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'SUCCESS',
                'snapshot_id': snapshot_id,
                'timestamp': timestamp
            })
        }
    
    except Exception as e:
        error_message = f"백업 실패: {str(e)}"
        print(error_message)
        
        # 실패 알림
        if SNS_TOPIC_ARN:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject='RDS 백업 실패',
                Message=f"❌ {error_message}"
            )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'ERROR',
                'error': str(e)
            })
        }

def delete_old_snapshots():
    """
    보존 기간이 지난 수동 스냅샷 삭제
    """
    
    try:
        # 수동 스냅샷 목록 조회
        snapshots = rds.describe_db_snapshots(
            DBInstanceIdentifier=DB_INSTANCE_ID,
            SnapshotType='manual'
        )['DBSnapshots']
        
        # 날짜 기준 정렬
        snapshots.sort(key=lambda x: x['SnapshotCreateTime'], reverse=True)
        
        # 보존 기간 계산
        cutoff_date = datetime.now() - timedelta(days=RETENTION_DAYS)
        
        deleted_count = 0
        for snapshot in snapshots:
            snapshot_date = snapshot['SnapshotCreateTime'].replace(tzinfo=None)
            
            # 보존 기간 초과 확인
            if snapshot_date < cutoff_date:
                snapshot_id = snapshot['DBSnapshotIdentifier']
                
                # Lambda가 생성한 스냅샷만 삭제
                if 'manual' in snapshot_id:
                    print(f"Deleting old snapshot: {snapshot_id}")
                    rds.delete_db_snapshot(
                        DBSnapshotIdentifier=snapshot_id
                    )
                    deleted_count += 1
        
        if deleted_count > 0:
            print(f"Deleted {deleted_count} old snapshots")
        
    except Exception as e:
        print(f"Error deleting old snapshots: {str(e)}")
