# AWS CloudFront + Route53 Configuration

CloudFront Origin Failover와 Route53을 사용하여 AWS (Primary)와 Azure (Secondary) 간 자동 Failover를 설정합니다.

## 📋 배포 순서

이 모듈은 전체 배포 순서에서 **1번째**로 배포됩니다:

```
1. aws/route53        ← 이 모듈 (CloudFront + Route53 설정)
2. azure/1-always     (Azure 기본 인프라 - Blob Storage)
3. aws/service        (AWS EKS, RDS, 백업 인스턴스)
4. aws/monitoring     (AWS CloudWatch 모니터링)
5. azure/2-failover   (Azure AKS, MySQL, Application Gateway)
```

## 🎯 목적

- **CloudFront Origin Failover**: AWS ALB (Primary)와 Azure Blob Storage (Secondary) 간 자동 Failover
- **Route53 DNS 관리**: 커스텀 도메인 → CloudFront Alias 레코드
- **글로벌 CDN**: CloudFront를 통한 콘텐츠 캐싱 및 성능 최적화
- **HTTPS 지원**: ACM 인증서를 통한 SSL/TLS 암호화

## 📦 사전 요구사항

### 1. Route53 Hosted Zone
도메인이 Route53에 등록되어 있어야 합니다.

```bash
# Hosted Zone 확인
aws route53 list-hosted-zones
```

도메인이 없다면:
1. [Route53 콘솔](https://console.aws.amazon.com/route53)에서 Hosted Zone 생성
2. 도메인 등록 업체에서 Name Server를 Route53 NS 레코드로 변경

### 2. ACM 인증서 (HTTPS 사용 시)
⚠️ **중요**: CloudFront용 ACM 인증서는 **us-east-1** 리전에 생성되어야 합니다.

```bash
# us-east-1 리전의 인증서 확인
aws acm list-certificates --region us-east-1

# 특정 도메인 인증서 확인
aws acm list-certificates --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='bloberry.click']"
```

인증서가 없다면:
1. [ACM 콘솔 (us-east-1)](https://console.aws.amazon.com/acm/home?region=us-east-1)에서 인증서 요청
2. DNS 또는 이메일로 도메인 소유권 검증
3. 상태가 "Issued"로 변경될 때까지 대기 (5-30분)

### 3. Azure Blob Storage (Secondary Origin)
Azure에 정적 웹사이트 호스팅이 활성화된 Blob Storage가 필요합니다.

```bash
# Azure Storage Account 확인
az storage account show --name bloberry01 --query "primaryEndpoints.web"
```

아직 없다면 `azure/1-always` 모듈을 먼저 배포하세요.

## 🚀 배포 방법

### 1단계: CloudFront + Route53 초기 배포

이 단계에서는 Route53과 CloudFront의 기본 구조를 생성합니다. (ALB는 아직 없음)

```bash
cd codes/aws/route53

# terraform.tfvars 설정
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

**terraform.tfvars 초기 설정:**
```hcl
# 기본 설정
aws_region  = "ap-northeast-2"
environment = "blue"

# Route53 & Domain
enable_custom_domain = true
domain_name          = "blueisthenewblack.store"  # 실제 도메인으로 변경

# Azure Secondary Origin (Blob Storage)
azure_storage_account_name = "bloberry01"  # Azure 1-always에서 생성된 Storage Account

# AWS Primary Origin은 아직 없음 (3단계에서 추가)
# eks_cluster_name = ""
# alb_dns_name = ""
```

⚠️ **주의**: 이 단계에서는 ALB가 없으므로 CloudFront가 생성되지 않습니다. Route53 Hosted Zone만 확인됩니다.

```bash
# 초기화
terraform init
terraform plan

# ALB 없이 실행하면 CloudFront는 생성 안 됨 (정상)
terraform apply
```

### 2단계: Azure 기본 인프라 배포

```bash
cd ../../../azure/1-always
terraform init
terraform apply
```

### 3단계: AWS 서비스 배포

```bash
cd ../../aws/service
terraform init
terraform apply

# ALB DNS 확인
terraform output
```

### 4단계: CloudFront + Route53 업데이트 (Primary Origin 추가)

aws/service 배포가 완료되면 ALB 정보를 추가하여 CloudFront를 생성합니다.

```bash
cd ../route53

# terraform.tfvars에 ALB 정보 추가
vi terraform.tfvars
```

**terraform.tfvars 업데이트:**
```hcl
# Option 1: EKS 클러스터 이름으로 자동 검색 (권장)
eks_cluster_name = "blue-eks-cluster"

# Option 2: ALB 정보를 직접 입력
# alb_dns_name = "k8s-web-webingre-xxxxxxxxxxxxx.elb.ap-northeast-2.amazonaws.com"
# alb_zone_id  = "ZWKZPGTI48KDX"
```

```bash
# CloudFront Distribution 생성
terraform apply

# 배포 완료 확인 (약 15-20분 소요)
terraform output deployment_summary
```

**CloudFront 배포 상태 확인:**
```bash
# Distribution ID 가져오기
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

# 배포 상태 확인
aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.Status' --output text

# Status가 "Deployed"가 될 때까지 대기
watch -n 30 "aws cloudfront get-distribution --id $DIST_ID --query 'Distribution.Status' --output text"
```

### 5단계: Azure Failover 사이트 배포

```bash
cd ../../codes/azure/2-failover
terraform init
terraform apply

# Application Gateway Public IP 확인
terraform output appgw_public_ip
```

### 6단계: CloudFront Origin 수동 변경 (장애 장기화 시)

⚠️ **이 단계는 선택사항입니다.** Azure로 장기간 Failover가 필요할 때만 수행합니다.

CloudFront는 초기에 Azure Blob Storage를 Secondary Origin으로 사용합니다.
장애가 장기화되어 Azure App Gateway로 변경해야 할 경우:

```bash
# Azure App Gateway Public IP 확인
cd ../../azure/2-failover
terraform output appgw_public_ip

# CloudFront Distribution Config 다운로드
cd ../../aws/route53
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution-config --id $DIST_ID > dist-config.json

# ETag 저장
ETAG=$(aws cloudfront get-distribution-config --id $DIST_ID \
  --query 'ETag' --output text)

# dist-config.json 편집:
# "secondary-azure" origin의 DomainName을 변경:
# "bloberry01.z12.web.core.windows.net" → "20.196.XXX.XXX" (App Gateway IP)

# CloudFront 업데이트
aws cloudfront update-distribution \
  --id $DIST_ID \
  --if-match $ETAG \
  --distribution-config file://dist-config.json

# 배포 완료 대기 (5-10분)
aws cloudfront wait distribution-deployed --id $DIST_ID
```

**참고**: Terraform에서 `lifecycle { ignore_changes = [origin] }`가 설정되어 있어 수동 변경이 유지됩니다.

## 📊 배포 후 확인

### 1. CloudFront 배포 상태 확인

```bash
# 배포 요약 확인
terraform output deployment_summary

# CloudFront Distribution 상태
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.{Status:Status,DomainName:DomainName,Enabled:DistributionConfig.Enabled}'

# Origin 설정 확인
aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DistributionConfig.Origins.Items[*].{Id:Id,Domain:DomainName}'
```

### 2. Route53 DNS 레코드 확인

```bash
# Route53 레코드 확인
ZONE_ID=$(terraform output -raw route53_zone_id)
DOMAIN=$(terraform output -raw route53_zone_name)

aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Name=='$DOMAIN']"

# A 레코드가 CloudFront를 가리키는지 확인
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='A' && Name=='$DOMAIN'].AliasTarget"
```

### 3. DNS 조회 테스트

```bash
# DNS 조회 (CloudFront domain이 반환되어야 함)
dig blueisthenewblack.store

# CNAME 체인 확인
nslookup blueisthenewblack.store

# HTTP/HTTPS 테스트
curl -I https://blueisthenewblack.store

# 브라우저 테스트
open https://blueisthenewblack.store  # macOS
xdg-open https://blueisthenewblack.store  # Linux
```

### 4. CloudFront Origin Failover 테스트

**정상 상태 (Primary: AWS ALB):**
```bash
# CloudFront를 통해 접속
curl -v https://blueisthenewblack.store

# Response Header에서 확인:
# - X-Cache: Hit from cloudfront 또는 Miss from cloudfront
# - Age: 캐시 시간 (초)
# - Via: CloudFront version
```

**Failover 테스트 (Primary 장애 시 Secondary로 전환):**
```bash
# 1. AWS ALB 중단 (EKS Pod 스케일 다운)
kubectl scale deployment -n web web-deployment --replicas=0

# 2. CloudFront가 500 에러를 감지하고 Secondary Origin으로 전환
# 약 30-60초 후 Azure Blob Storage에서 응답

# 3. 접속 테스트
curl -v https://blueisthenewblack.store
# Secondary Origin (Azure Blob)에서 정적 페이지 반환

# 4. 복구
kubectl scale deployment -n web web-deployment --replicas=2
```

## 🔄 CloudFront Origin Failover 동작 원리

CloudFront는 다음 상황에서 자동으로 Secondary Origin으로 전환합니다:

1. **Primary Origin 응답 실패**: HTTP 500, 502, 503, 504 에러
2. **연결 타임아웃**: Origin이 응답하지 않을 때
3. **자동 재시도**: Primary 실패 시 즉시 Secondary Origin 시도

**Route53 Health Check와의 차이점:**
- Route53 Failover: DNS 레벨에서 전환 (TTL 대기 필요, 2-3분 소요)
- CloudFront Failover: 요청마다 실시간 전환 (TTL 무관, 즉시 전환)

## 🧹 CloudFront 캐시 관리

### 캐시 무효화 (Cache Invalidation)

콘텐츠를 즉시 업데이트해야 할 때:

```bash
DIST_ID=$(terraform output -raw cloudfront_distribution_id)

# 전체 캐시 삭제
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"

# 특정 경로만 삭제
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/index.html" "/css/*"

# Invalidation 상태 확인
aws cloudfront list-invalidations --distribution-id $DIST_ID

# 특정 Invalidation 상세 정보
aws cloudfront get-invalidation \
  --distribution-id $DIST_ID \
  --id <invalidation-id>
```

⚠️ **비용 주의**: 매달 첫 1,000개의 무효화 경로는 무료, 이후 $0.005/경로

### 캐시 동작 확인

```bash
# 캐시 히트/미스 확인
curl -I https://blueisthenewblack.store

# Response Headers:
# - X-Cache: Hit from cloudfront (캐시 히트)
# - X-Cache: Miss from cloudfront (캐시 미스)
# - Age: 캐시된 시간 (초)
```

## 📝 주요 Output

| Output | 설명 |
|--------|------|
| `route53_zone_id` | Route53 Hosted Zone ID |
| `route53_zone_name` | Hosted Zone 도메인 이름 |
| `dns_record` | Route53 DNS 레코드 정보 (CloudFront Alias) |
| `cloudfront_distribution_id` | CloudFront Distribution ID |
| `cloudfront_domain_name` | CloudFront CDN Endpoint |
| `cloudfront_url` | HTTPS 접속 URL |
| `cloudfront_status` | Distribution 배포 상태 |
| `origin_failover_config` | Origin Failover 구성 정보 |
| `ssl_certificate_info` | ACM 인증서 정보 |
| `management_commands` | CloudFront 관리 명령어 |
| `monitoring_commands` | 모니터링 명령어 모음 |
| `deployment_summary` | 배포 요약 (시각화) |

## 🧹 리소스 정리

```bash
# CloudFront Distribution 및 Route53 레코드 삭제
cd /home/ubuntu/3tier-terraform/codes/aws/route53
terraform destroy

# 확인
aws cloudfront list-distributions
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

⚠️ **주의사항:**
- Hosted Zone 자체는 삭제되지 않습니다 (도메인이 사용 중일 수 있음)
- CloudFront Distribution은 비활성화 후 삭제되므로 시간이 걸립니다 (5-10분)
- 캐시 무효화 중인 경우 완료될 때까지 대기

## 🔍 트러블슈팅

### CloudFront 배포가 완료되지 않는 경우

```bash
# Distribution 상태 확인
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.Status'

# "InProgress" → "Deployed" 전환 대기 (보통 15-20분)
# "Deployed"가 되어야 정상 접속 가능
```

### SSL 인증서 오류 (us-east-1 리전 문제)

```bash
# us-east-1 리전에 인증서가 있는지 확인
aws acm list-certificates --region us-east-1

# 없다면 us-east-1에 새로 생성
aws acm request-certificate \
  --domain-name blueisthenewblack.store \
  --validation-method DNS \
  --region us-east-1

# DNS 검증 레코드 추가 후 대기
aws acm describe-certificate \
  --certificate-arn <arn> \
  --region us-east-1 \
  --query 'Certificate.Status'
```

### Origin 연결 오류 (502 Bad Gateway)

1. **ALB가 실제로 동작하는지 확인:**
   ```bash
   # ALB에 직접 접속 테스트
   curl -I http://k8s-web-webingre-xxxxx.elb.ap-northeast-2.amazonaws.com

   # Target Group 상태 확인
   aws elbv2 describe-target-health --target-group-arn <tg-arn>
   ```

2. **ALB Security Group 확인:**
   ```bash
   # CloudFront IP 대역이 허용되어 있는지 확인
   # 권장: 0.0.0.0/0 (HTTP/HTTPS) 허용
   ```

3. **CloudFront Origin 설정 확인:**
   ```bash
   aws cloudfront get-distribution --id $DIST_ID \
     --query 'Distribution.DistributionConfig.Origins.Items[0]'
   ```

### DNS가 CloudFront를 가리키지 않는 경우

```bash
# Route53 A 레코드 확인
ZONE_ID=$(terraform output -raw route53_zone_id)
aws route53 list-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --query "ResourceRecordSets[?Type=='A']"

# Alias Target이 CloudFront domain인지 확인
# (예: d1234567890abc.cloudfront.net)

# DNS 캐시 초기화
sudo systemd-resolve --flush-caches  # Linux
sudo dscacheutil -flushcache         # macOS

# 외부 DNS 서버로 확인
dig @8.8.8.8 blueisthenewblack.store
dig @1.1.1.1 blueisthenewblack.store
```

### Origin Failover가 동작하지 않는 경우

```bash
# Origin Group 설정 확인
aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DistributionConfig.OriginGroups.Items[0]'

# Failover Criteria 확인 (500, 502, 503, 504)
aws cloudfront get-distribution --id $DIST_ID \
  --query 'Distribution.DistributionConfig.OriginGroups.Items[0].FailoverCriteria'

# Secondary Origin (Azure Blob) 접속 테스트
curl -I https://bloberry01.z12.web.core.windows.net
```

## 📚 참고 자료

- [CloudFront Origin Failover](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html)
- [Route53 with CloudFront](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-cloudfront-distribution.html)
- [CloudFront Cache Invalidation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Invalidation.html)
- [ACM Certificates for CloudFront](https://docs.aws.amazon.com/acm/latest/userguide/acm-regions.html)
- [CloudFront Functions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html)

## 💡 추가 팁

### CloudFront 성능 최적화

1. **캐시 정책 설정**: TTL 값 조정으로 캐시 히트율 향상
2. **압축 활성화**: Gzip/Brotli 압축으로 전송 속도 개선 (현재 활성화됨)
3. **Lambda@Edge**: 엣지에서 동적 콘텐츠 처리 (고급 기능)

### 비용 절감

1. **Price Class**: 현재 `PriceClass_100` (북미/유럽) 사용 중
   - 글로벌 서비스 필요 시 `PriceClass_All`로 변경
   - 비용 절감 시 `PriceClass_100` 유지

2. **캐시 무효화 최소화**: 매달 1,000개까지 무료
   - 전체 무효화(`/*`) 대신 특정 경로만 무효화
   - 버저닝 사용 권장 (예: `/app.js?v=1.2.3`)

### 보안 강화

1. **WAF 연동**: CloudFront에 AWS WAF 연결 가능
2. **Origin Access Identity**: S3 Origin 직접 접근 차단
3. **Geo Restriction**: 특정 국가 차단/허용

### 모니터링

CloudWatch를 통해 다음 지표 확인 가능:
- **Requests**: 총 요청 수
- **BytesDownloaded**: 전송량
- **ErrorRate**: 4xx/5xx 오류율
- **CacheHitRate**: 캐시 히트율
