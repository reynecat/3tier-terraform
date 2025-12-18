#!/usr/bin/env python3
"""
AWS Lambda - RDS MySQL 백업 스크립트
RDS에서 mysqldump를 실행하고 S3에 업로드
"""

import os
import boto3
import subprocess
import gzip
from datetime import datetime
import logging

# 로깅 설정
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# 환경변수
RDS_ENDPOINT = os.environ['RDS_ENDPOINT']
RDS_DATABASE = os.environ['RDS_DATABASE']
RDS_USERNAME = os.environ['RDS_USERNAME']
RDS_PASSWORD = os.environ.get('RDS_PASSWORD', '')  # Secrets Manager 사용 권장
S3_BUCKET = os.environ['S3_BUCKET']
ENVIRONMENT = os.environ['ENVIRONMENT']

s3_client = boto3.client('s3')
secrets_client = boto3.client('secretsmanager')


def get_rds_password():
    """
    AWS Secrets Manager에서 RDS 비밀번호 가져오기
    환경변수에 없으면 Secrets Manager에서 조회
    """
    if RDS_PASSWORD:
        return RDS_PASSWORD
    
    try:
        secret_name = f"rds-password-{ENVIRONMENT}"
        response = secrets_client.get_secret_value(SecretId=secret_name)
        return response['SecretString']
    except Exception as e:
        logger.error(f"Secrets Manager 조회 실패: {str(e)}")
        raise


def create_backup():
    """
    mysqldump를 사용하여 RDS 백업 생성
    """
    timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
    backup_file = f"/tmp/{RDS_DATABASE}-{timestamp}.sql"
    compressed_file = f"{backup_file}.gz"
    
    try:
        # RDS 비밀번호 가져오기
        password = get_rds_password()
        
        # mysqldump 명령 실행
        logger.info(f"백업 시작: {RDS_DATABASE}")
        
        # mysqldump 명령어 구성
        dump_cmd = [
            'mysqldump',
            f'--host={RDS_ENDPOINT.split(":")[0]}',
            f'--user={RDS_USERNAME}',
            f'--password={password}',
            '--single-transaction',
            '--quick',
            '--lock-tables=false',
            '--routines',
            '--triggers',
            '--events',
            RDS_DATABASE
        ]
        
        # 백업 실행
        with open(backup_file, 'w') as f:
            subprocess.run(dump_cmd, stdout=f, check=True)
        
        logger.info(f"백업 완료: {backup_file}")
        
        # gzip 압축
        logger.info("파일 압축 중...")
        with open(backup_file, 'rb') as f_in:
            with gzip.open(compressed_file, 'wb') as f_out:
                f_out.writelines(f_in)
        
        # 원본 파일 삭제
        os.remove(backup_file)
        
        logger.info(f"압축 완료: {compressed_file}")
        return compressed_file, timestamp
        
    except subprocess.CalledProcessError as e:
        logger.error(f"mysqldump 실패: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"백업 생성 실패: {str(e)}")
        raise


def upload_to_s3(file_path, timestamp):
    """
    백업 파일을 S3에 업로드
    """
    try:
        s3_key = f"backups/{ENVIRONMENT}/{RDS_DATABASE}-{timestamp}.sql.gz"
        
        logger.info(f"S3 업로드 시작: s3://{S3_BUCKET}/{s3_key}")
        
        # S3에 업로드
        s3_client.upload_file(
            file_path,
            S3_BUCKET,
            s3_key,
            ExtraArgs={
                'ServerSideEncryption': 'AES256',
                'StorageClass': 'STANDARD_IA',  # 비용 절감
                'Metadata': {
                    'source': 'rds-backup-lambda',
                    'database': RDS_DATABASE,
                    'timestamp': timestamp,
                    'environment': ENVIRONMENT
                }
            }
        )
        
        logger.info(f"S3 업로드 완료: {s3_key}")
        
        # 로컬 파일 삭제
        os.remove(file_path)
        
        return s3_key
        
    except Exception as e:
        logger.error(f"S3 업로드 실패: {str(e)}")
        raise


def cleanup_old_backups():
    """
    30일 이상 된 백업 파일 삭제
    """
    try:
        prefix = f"backups/{ENVIRONMENT}/"
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET,
            Prefix=prefix
        )
        
        if 'Contents' not in response:
            logger.info("삭제할 오래된 백업 없음")
            return
        
        from datetime import timedelta
        cutoff_date = datetime.utcnow() - timedelta(days=30)
        
        deleted_count = 0
        for obj in response['Contents']:
            if obj['LastModified'].replace(tzinfo=None) < cutoff_date:
                s3_client.delete_object(
                    Bucket=S3_BUCKET,
                    Key=obj['Key']
                )
                deleted_count += 1
                logger.info(f"삭제됨: {obj['Key']}")
        
        logger.info(f"총 {deleted_count}개 오래된 백업 삭제 완료")
        
    except Exception as e:
        logger.warning(f"오래된 백업 정리 실패 (무시됨): {str(e)}")


def handler(event, context):
    """
    Lambda 핸들러 함수
    """
    try:
        logger.info("=== RDS 백업 Lambda 시작 ===")
        logger.info(f"환경: {ENVIRONMENT}")
        logger.info(f"데이터베이스: {RDS_DATABASE}")
        
        # 1. 백업 생성
        backup_file, timestamp = create_backup()
        
        # 2. S3 업로드
        s3_key = upload_to_s3(backup_file, timestamp)
        
        # 3. 오래된 백업 정리
        cleanup_old_backups()
        
        logger.info("=== RDS 백업 완료 ===")
        
        return {
            'statusCode': 200,
            'body': {
                'message': 'Backup successful',
                's3_key': s3_key,
                'timestamp': timestamp
            }
        }
        
    except Exception as e:
        logger.error(f"백업 실패: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'message': 'Backup failed',
                'error': str(e)
            }
        }
