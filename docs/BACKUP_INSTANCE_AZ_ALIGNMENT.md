# 백업 인스턴스와 RDS 동일 AZ 배치

## 개요

백업 인스턴스가 RDS 인스턴스와 항상 동일한 가용영역(Availability Zone)에 배치되도록 코드를 수정했습니다.

## 변경 이유

1. **네트워크 지연 최소화**: 같은 AZ 내에서 데이터 전송 시 지연시간 감소
2. **데이터 전송 비용 절감**: 같은 AZ 간 데이터 전송은 무료
3. **백업 성능 향상**: 낮은 레이턴시로 인한 백업 속도 개선
4. **안정성**: AZ 장애 시 동시 영향을 받지만, 일반적인 경우 성능 우선

## 수정 내용

### 1. RDS 모듈 Output 추가

**파일**: [codes/aws/2. service/modules/rds/outputs.tf](modules/rds/outputs.tf)

```hcl
output "db_availability_zone" {
  description = "RDS 인스턴스 가용영역"
  value       = aws_db_instance.main.availability_zone
}
```

### 2. VPC 모듈 Output 추가

**파일**: [codes/aws/2. service/modules/vpc/outputs.tf](modules/vpc/outputs.tf)

```hcl
output "availability_zones" {
  description = "사용 중인 가용영역 리스트"
  value       = var.availability_zones
}

output "was_subnets_by_az" {
  description = "WAS 서브넷 ID를 AZ별로 매핑"
  value = zipmap(
    aws_subnet.was[*].availability_zone,
    aws_subnet.was[*].id
  )
}
```

**설명**: `was_subnets_by_az`는 가용영역을 키로, 서브넷 ID를 값으로 하는 맵을 생성합니다.

예시:
```
{
  "ap-northeast-2a" = "subnet-abc123"
  "ap-northeast-2c" = "subnet-def456"
}
```

### 3. 백업 인스턴스 배치 로직 수정

**파일**: [codes/aws/2. service/backup-instance.tf](backup-instance.tf)

**변경 전**:
```hcl
resource "aws_instance" "backup_instance" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  # 하드코딩된 인덱스 사용
  subnet_id                   = module.vpc.was_subnet_ids[1]  # ap-northeast-2c
  # ...
}
```

**변경 후**:
```hcl
resource "aws_instance" "backup_instance" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  # RDS와 동일한 AZ의 WAS 서브넷에 배치
  subnet_id                   = module.vpc.was_subnets_by_az[module.rds.db_availability_zone]
  availability_zone           = module.rds.db_availability_zone
  # ...
}
```

### 4. Output 정보 강화

**파일**: [codes/aws/2. service/outputs.tf](outputs.tf)

추가된 Output:
```hcl
output "rds_availability_zone" {
  description = "RDS 인스턴스 가용영역"
  value       = module.rds.db_availability_zone
}

output "backup_instance_availability_zone" {
  description = "백업 인스턴스 가용영역"
  value       = aws_instance.backup_instance.availability_zone
}
```

배포 요약에 AZ 정보 추가:
```hcl
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🗄️  RDS MySQL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
엔드포인트: ${module.rds.db_instance_address}:${module.rds.db_port}
Availability Zone: ${module.rds.db_availability_zone}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💾 백업 시스템 (Plan B)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
인스턴스 ID: ${aws_instance.backup_instance.id}
Private IP: ${aws_instance.backup_instance.private_ip}
Availability Zone: ${aws_instance.backup_instance.availability_zone}
✅ Same AZ as RDS: ${aws_instance.backup_instance.availability_zone == module.rds.db_availability_zone ? "YES" : "NO"}
```

## 동작 원리

1. **RDS 배포 시**: RDS 인스턴스가 특정 AZ에 생성됨 (예: `ap-northeast-2c`)
2. **AZ 감지**: `module.rds.db_availability_zone`으로 RDS의 AZ 정보 가져오기
3. **서브넷 선택**: `module.vpc.was_subnets_by_az[RDS_AZ]`로 동일 AZ의 WAS 서브넷 선택
4. **인스턴스 생성**: 백업 인스턴스가 RDS와 동일한 AZ의 서브넷에 생성됨

## 현재 상태 (2026-01-03)

### RDS
- **Availability Zone**: `ap-northeast-2c`
- **서브넷**: RDS 서브넷 그룹 (ap-northeast-2a, ap-northeast-2c)

### 백업 인스턴스 (변경 후)
- **Availability Zone**: `ap-northeast-2c` (RDS와 동일)
- **서브넷**: WAS 서브넷 (ap-northeast-2c)

## 배포 방법

### 1. 변경사항 확인

```bash
cd "codes/aws/2. service"

# Terraform plan 실행
terraform plan
```

### 2. 예상 변경사항

```
Plan: 새로운 리소스 생성 (백업 인스턴스 및 관련 리소스)

주요 변경:
- aws_instance.backup_instance
  - availability_zone: (known after apply) → ap-northeast-2c
  - subnet_id: module.vpc.was_subnets_by_az["ap-northeast-2c"]
```

### 3. 배포 실행

```bash
terraform apply
```

### 4. 확인

```bash
# Output 확인
terraform output rds_availability_zone
terraform output backup_instance_availability_zone

# 또는
terraform output deployment_summary
```

## 검증

### 1. AZ 일치 확인

```bash
# RDS AZ 확인
aws rds describe-db-instances \
  --db-instance-identifier blue-rds \
  --region ap-northeast-2 \
  --query 'DBInstances[0].AvailabilityZone' \
  --output text

# 백업 인스턴스 AZ 확인
aws ec2 describe-instances \
  --instance-ids $(terraform output -raw backup_instance_id) \
  --region ap-northeast-2 \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
  --output text
```

### 2. 네트워크 레이턴시 테스트

```bash
# 백업 인스턴스 접속
aws ssm start-session --target $(terraform output -raw backup_instance_id)

# RDS 연결 테스트
time mysql -h $(terraform output -raw rds_address) -u admin -p -e "SELECT 1;"
```

## 장점

✅ **성능**: 같은 AZ 내 데이터 전송으로 레이턴시 최소화
✅ **비용**: AZ 간 데이터 전송 비용 없음 ($0.01/GB 절약)
✅ **자동화**: RDS AZ가 변경되어도 백업 인스턴스 자동 추적
✅ **명확성**: Output에 AZ 정보 명시로 운영 편의성 향상

## 단점 및 고려사항

⚠️ **AZ 장애**: RDS와 백업 인스턴스가 동시에 영향받을 수 있음
- **완화 방법**: RDS는 Multi-AZ로 구성 가능 (현재 비활성화)
- **DR 전략**: Azure 백업이 리전 단위 DR 역할 수행

⚠️ **Multi-AZ RDS 사용 시**: Primary와 Standby가 다른 AZ에 있으므로 백업 인스턴스는 Primary AZ만 추적
- RDS 페일오버 시에도 백업 인스턴스는 원래 AZ에 유지

## RDS Multi-AZ 고려사항

현재 RDS는 Multi-AZ가 비활성화되어 있습니다 (`rds_multi_az = false`).

### Multi-AZ 활성화 시 동작

```hcl
# terraform.tfvars
rds_multi_az = true
```

- RDS Primary: `ap-northeast-2c` (예시)
- RDS Standby: `ap-northeast-2a` (자동 배치)
- **백업 인스턴스**: `ap-northeast-2c` (Primary와 동일 AZ 유지)

**페일오버 시나리오**:
1. Primary (ap-northeast-2c) 장애 발생
2. Standby (ap-northeast-2a)가 Primary로 승격
3. **백업 인스턴스는 여전히 ap-northeast-2c에 위치**
4. 다른 AZ 간 연결이 되므로 백업은 계속 작동하지만 약간의 레이턴시 증가

**권장사항**:
- 운영 환경에서는 Multi-AZ를 활성화하여 RDS 고가용성 확보
- 백업 인스턴스는 비용 효율성을 위해 단일 AZ 유지
- 레이턴시 민감도가 높다면 백업 인스턴스를 여러 AZ에 분산 배치 고려 (추가 비용 발생)

## 참고 자료

- [AWS EC2 Placement](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/placement-groups.html)
- [AWS RDS Availability Zones](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html)
- [AWS Data Transfer Pricing](https://aws.amazon.com/ec2/pricing/on-demand/#Data_Transfer)

## 버전 이력

- **2026-01-03**: 초기 구현 - RDS와 백업 인스턴스 동일 AZ 배치
