# AWS Route53 Failover Configuration

Route53을 사용하여 AWS (Primary)와 Azure (Secondary) 간 자동 Failover를 설정합니다.

## 📋 배포 순서

이 모듈은 전체 배포 순서에서 **1번째**로 배포됩니다:

```
1. aws/route53        ← 이 모듈 (Route53 Hosted Zone 설정)
2. azure/1-always     (Azure 기본 인프라)
3. aws/service        (AWS EKS, RDS, 백업 인스턴스)
4. aws/monitoring     (AWS CloudWatch 모니터링)
5. azure/2-failover   (Azure AKS, MySQL, Application Gateway)
```

## 🎯 목적

- Route53 Hosted Zone 및 DNS 레코드 관리
- AWS ALB (Primary)와 Azure AppGW (Secondary) 간 Failover 라우팅
- Health Check를 통한 자동 장애 감지 및 전환

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
도메인에 대한 ACM 인증서가 발급되어 있어야 합니다.

```bash
# 인증서 확인
ㅇ
```

인증서가 없다면:
1. [ACM 콘솔](https://console.aws.amazon.com/acm)에서 인증서 요청
2. DNS 또는 이메일로 도메인 소유권 검증

## 🚀 배포 방법

### 1단계: Route53 기본 설정 배포

```bash
cd codes/aws/route53

# terraform.tfvars 설정
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

**terraform.tfvars 설정 예시:**
```hcl
# 기본 설정
aws_region  = "ap-northeast-2"
environment = "blue"

# Route53 & Domain
enable_custom_domain = true
domain_name          = "bloberry.click"  # 실제 도메인으로 변경

# AWS Primary Site
eks_cluster_name = "blue-eks-cluster"

# Azure Secondary Site는 아직 비활성화
# azure_appgw_public_ip = ""  # 5단계에서 설정
```

```bash
# 초기화 및 배포
terraform init
terraform plan
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

### 4단계: Route53 업데이트 (Primary 추가)

aws/service 배포가 완료되면 ALB 정보를 Route53에 추가합니다.

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
# alb_zone_id  = "ZXXXXXXXXXXXXX"
```

```bash
# Primary (AWS) Failover 활성화
terraform apply

# Health Check 상태 확인
aws route53 get-health-check-status --health-check-id <primary-health-check-id>
```

### 5단계: Azure Failover 사이트 배포

```bash
cd ../../../azure/2-failover
terraform init
terraform apply

# Application Gateway Public IP 확인
terraform output appgw_public_ip
```

### 6단계: Route53 최종 업데이트 (Secondary 추가)

```bash
cd ../../aws/route53

# terraform.tfvars에 Azure AppGW Public IP 추가
vi terraform.tfvars
```

**terraform.tfvars 최종 설정:**
```hcl
# Azure Secondary Site (2-failover 배포 후)
azure_appgw_public_ip = "20.196.XXX.XXX"  # 실제 IP로 변경
```

```bash
# Secondary (Azure) Failover 활성화
terraform apply

# 전체 Health Check 상태 확인
terraform output monitoring_commands
```

## 📊 배포 후 확인

### 1. Route53 레코드 확인

```bash
# 배포 요약 확인
terraform output deployment_summary

# Route53 레코드 확인
aws route53 list-resource-record-sets \
  --hosted-zone-id <zone-id> \
  --query "ResourceRecordSets[?Name=='bloberry.click.']"
```

### 2. Health Check 모니터링

```bash
# Primary (AWS ALB) Health Check
aws route53 get-health-check-status --health-check-id <primary-hc-id>

# Secondary (Azure AppGW) Health Check
aws route53 get-health-check-status --health-check-id <secondary-hc-id>

# 모든 Health Check 목록
aws route53 list-health-checks
```

### 3. DNS 조회 테스트

```bash
# DNS 조회
dig bloberry.click
nslookup bloberry.click

# 브라우저 테스트
curl http://bloberry.click
```

### 4. Failover 동작 확인

**Primary (AWS) 정상 상태:**
```bash
# DNS 조회 시 AWS ALB DNS가 반환되어야 함
dig bloberry.click +short
# 결과: k8s-web-webingre-xxxxx.elb.ap-northeast-2.amazonaws.com
```

**Primary (AWS) 장애 발생 시:**
```bash
# AWS ALB Health Check가 실패하면
# DNS 조회 시 Azure AppGW IP가 반환됨
dig bloberry.click +short
# 결과: 20.196.XXX.XXX
```

## 🔄 Failover 테스트

### 방법 1: AWS ALB 수동 중단

```bash
# EKS Ingress 스케일 다운 (ALB 트래픽 차단)
kubectl scale deployment -n web web-deployment --replicas=0

# 약 2-3분 후 Health Check 실패 확인
aws route53 get-health-check-status --health-check-id <primary-hc-id>

# DNS 조회 시 Azure IP로 전환 확인
dig bloberry.click +short

# 복구
kubectl scale deployment -n web web-deployment --replicas=2
```

### 방법 2: Security Group 규칙 수정

```bash
# ALB Security Group의 인바운드 규칙 일시 차단
# (Route53 -> ALB HTTP Health Check 차단)

# Health Check 실패 및 Failover 확인
aws route53 get-health-check-status --health-check-id <primary-hc-id>

# 복구: Security Group 규칙 원복
```

## 📝 주요 Output

| Output | 설명 |
|--------|------|
| `route53_zone_id` | Hosted Zone ID |
| `route53_failover_status` | Primary/Secondary 활성화 상태 |
| `route53_health_check_ids` | Health Check ID (Primary, Secondary) |
| `route53_primary_record` | Primary 레코드 정보 (AWS ALB) |
| `route53_secondary_record` | Secondary 레코드 정보 (Azure AppGW) |
| `monitoring_commands` | 모니터링 명령어 모음 |

## 🧹 리소스 정리

```bash
# Route53 레코드 및 Health Check 삭제
terraform destroy

# 확인
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
aws route53 list-health-checks
```

⚠️ **주의:** Hosted Zone 자체는 삭제되지 않습니다. 도메인이 계속 사용 중이라면 삭제하지 마세요.

## 🔍 트러블슈팅

### Health Check가 계속 실패하는 경우

1. **ALB Security Group 확인:**
   ```bash
   # Route53 Health Checker IP 대역이 허용되어 있는지 확인
   # 0.0.0.0/0 또는 Route53 Health Checker IP 대역
   ```

2. **ALB 상태 확인:**
   ```bash
   aws elbv2 describe-load-balancers --names <alb-name>
   aws elbv2 describe-target-health --target-group-arn <tg-arn>
   ```

3. **Ingress 확인:**
   ```bash
   kubectl get ingress -n web
   kubectl describe ingress web-ingress -n web
   ```

### DNS가 업데이트되지 않는 경우

1. **TTL 대기:**
   - Route53 레코드 TTL (60초) 대기
   - 로컬 DNS 캐시 초기화: `sudo systemd-resolve --flush-caches`

2. **Propagation 확인:**
   ```bash
   # 다양한 DNS 서버에서 조회
   dig @8.8.8.8 bloberry.click
   dig @1.1.1.1 bloberry.click
   ```

### Failover가 동작하지 않는 경우

1. **Health Check 설정 확인:**
   ```bash
   aws route53 get-health-check --health-check-id <hc-id>
   ```

2. **Route53 레코드 확인:**
   ```bash
   # Failover routing policy가 올바르게 설정되었는지 확인
   aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
   ```

## 📚 참고 자료

- [AWS Route53 Failover Documentation](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover.html)
- [Route53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-failover-types.html)
- [Route53 Health Checker IP Ranges](https://ip-ranges.amazonaws.com/ip-ranges.json)
