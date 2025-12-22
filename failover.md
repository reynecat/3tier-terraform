🔴 Failover 테스트 가이드 (2-Emergency)
📋 사전 준비
1. 현재 상태 확인

# DNS 확인
dig blueisthenewblack.store +short
# 예상 결과: AWS ALB IP (52.78.38.146, 52.78.138.16)

# 웹사이트 접속 확인
curl -I https://blueisthenewblack.store
# 예상 결과: HTTP 200 OK (PetClinic)

# AWS EKS Pod 상태
kubectl config use-context arn:aws:eks:ap-northeast-2:822837196792:cluster/blue-eks
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: web-nginx 2개, was-spring 2개 Running
🔥 Step 1: AWS Primary 장애 발생
명령어:

# AWS EKS 컨텍스트로 전환
kubectl config use-context arn:aws:eks:ap-northeast-2:822837196792:cluster/blue-eks

# Web과 WAS Pod를 0으로 스케일 다운 (장애 시뮬레이션)
kubectl scale deployment web-nginx -n web --replicas=0
kubectl scale deployment was-spring -n was --replicas=0

# 확인
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: No resources found
장애 확인:

# 웹사이트 접속 시도
curl -I https://blueisthenewblack.store
# 예상 결과: HTTP 503 Service Unavailable
⚡ Step 2: Route53 Failover 발동
명령어:

# Health Check를 Inverted 모드로 설정 (Success를 Failure로 해석)
aws route53 update-health-check \
  --health-check-id 1deed710-2ce3-431c-8fee-2c4b4433f7f9 \
  --region us-east-1 \
  --inverted

# DNS 전파 대기 (약 30초)
sleep 30

# DNS 변경 확인
dig blueisthenewblack.store +short
# 예상 결과: 52.141.46.243 (Azure IP)
Failover 확인:

# 웹사이트 접속
curl -I http://blueisthenewblack.store
# 예상 결과: HTTP 200 OK

# 페이지 내용 확인
curl -s http://blueisthenewblack.store | grep title
# 예상 결과: <title>서비스 점검 중</title>
✅ Step 3: Failover 성공 확인

# Route53 Health Check 상태
aws route53 get-health-check-status \
  --health-check-id 1deed710-2ce3-431c-8fee-2c4b4433f7f9 \
  --region us-east-1 \
  | jq '.HealthCheckObservations[0].StatusReport.Status'

# Azure 페이지 직접 접속
curl -I http://52.141.46.243
# 예상 결과: HTTP 200 OK (Blob Storage)
🔄 복원: AWS Primary로 Failback
Step 1: AWS Pod 복구

# AWS EKS 컨텍스트
kubectl config use-context arn:aws:eks:ap-northeast-2:822837196792:cluster/blue-eks

# Pod 복구
kubectl scale deployment web-nginx -n web --replicas=2
kubectl scale deployment was-spring -n was --replicas=2

# Pod 시작 확인 (약 60초 대기)
kubectl get pods -n web
kubectl get pods -n was
# 예상 결과: web-nginx 2/2 Running, was-spring 2/2 Running
Step 2: Health Check 정상화

# Health Check Inversion 해제
aws route53 update-health-check \
  --health-check-id 1deed710-2ce3-431c-8fee-2c4b4433f7f9 \
  --region us-east-1 \
  --no-inverted

# DNS 전파 대기 (약 60초)
sleep 60

# DNS 복구 확인
dig blueisthenewblack.store +short
# 예상 결과: AWS ALB IP (52.78.38.146, 52.78.138.16)
Step 3: 복구 확인

# 웹사이트 접속
curl -I https://blueisthenewblack.store
# 예상 결과: HTTP 200 OK

# PetClinic 페이지 확인
curl -s https://blueisthenewblack.store | grep title
# 예상 결과: <title>PetClinic :: a Spring Framework demonstration</title>