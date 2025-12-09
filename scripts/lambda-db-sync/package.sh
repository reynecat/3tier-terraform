#!/bin/bash
# Lambda 함수 패키징 스크립트
# Lambda 레이어와 함께 배포 가능한 ZIP 파일 생성

set -e

echo "🔧 Lambda 함수 패키징 시작..."

# 현재 디렉토리 저장
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 임시 디렉토리 생성
rm -rf package
mkdir -p package

echo "📦 Python 종속성 설치 중..."

# Python 패키지 설치
pip install -r requirements.txt -t package/ --platform manylinux2014_x86_64 --only-binary=:all:

echo "📄 Lambda 함수 코드 복사 중..."

# Lambda 함수 코드 복사
cp index.py package/

echo "🗜️  ZIP 파일 생성 중..."

# ZIP 파일 생성
cd package
zip -r ../lambda-db-sync.zip .
cd ..

# 정리
rm -rf package

echo "✅ Lambda 패키징 완료: lambda-db-sync.zip"
echo "📦 파일 크기: $(du -h lambda-db-sync.zip | cut -f1)"
