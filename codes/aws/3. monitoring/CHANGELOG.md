# Changelog

All notable changes to the EKS Monitoring module will be documented in this file.

## [1.1.0] - 2025-01-03

### Changed
- Lambda 함수를 zip 파일 의존성 대신 `archive_file` data source를 사용하도록 변경
- Lambda 코드가 `lambda/index.py`에서 자동으로 zip 파일 생성
- `source_code_hash`를 추가하여 코드 변경 시 자동 업데이트

### Added
- `.gitignore` 파일 추가 (생성된 zip 파일 제외)
- `README.md` 파일 추가 (상세한 배포 가이드)
- `terraform.tfvars.example` 템플릿 파일 추가
- `deploy.sh` 배포 스크립트 추가
- `CHANGELOG.md` 변경 이력 파일 추가

### Fixed
- Destroy 후 재배포 시 Lambda zip 파일 누락 문제 해결
- terraform.tfvars 파일 보존으로 설정 유지

## [1.0.0] - 2024-12-23

### Initial Release
- EKS Container Insights 모니터링
- CloudWatch Alarms (Node, Pod, Container, ALB, RDS)
- Lambda Auto Recovery 기능
- CloudWatch Dashboard
- SNS/Slack 알림 통합
- Route53 Health Check 모니터링
