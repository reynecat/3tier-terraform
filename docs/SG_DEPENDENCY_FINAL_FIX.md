# 🚨 Security Group sg-067530e0bb78b53ec 삭제 불가 문제 해결

## 문제 상황

```
Error: deleting Security Group (sg-067530e0bb78b53ec): DependencyViolation
resource sg-067530e0bb78b53ec has a dependent object
```

- **Security Group**: sg-067530e0bb78b53ec
- **이름**: backup-instance-sg-20251228041008472200000009
- **VPC**: vpc-06e4fdfb8ec4950d1
- **설명**: Security group for backup instance

---

## ✅ 이미 완료된 조치

1. ✅ Terraform state에서 제거됨
   ```bash
   terraform state rm 'aws_security_group.backup_instance'
   ```

2. ✅ 모든 Security Group 간 상호 참조 제거됨

3. ✅ 확인된 리소스 없음:
   - ENI (Network Interface): 없음
   - EC2 Instance: 없음
   - Load Balancer: 없음
   - RDS: 없음
   - VPC Endpoint: 없음

---

## 🔍 원인 분석

AWS의 **숨겨진 의존성(Hidden Dependency)**:
- Security Group이 과거에 연결되었던 리소스의 메타데이터가 AWS 내부에 남아있을 수 있음
- 삭제된 ENI나 인스턴스의 레퍼런스가 완전히 정리되지 않은 상태
- AWS의 eventual consistency로 인한 지연

---

## 🛠️ 해결 방법

### 방법 1: AWS Console에서 수동 삭제 (권장)

1. **AWS Console 접속**
   - https://console.aws.amazon.com/ec2/
   - Region: ap-northeast-2 (Seoul)

2. **Security Groups 메뉴**
   - 좌측 메뉴 → Network & Security → Security Groups

3. **SG 찾기**
   - 검색: `sg-067530e0bb78b53ec`
   - 또는 이름: `backup-instance-sg-*`

4. **삭제 시도**
   - Security Group 선택
   - Actions → Delete security groups
   - 에러 메시지 확인

5. **에러 메시지 분석**
   - Console에서는 CLI보다 더 상세한 의존성 정보 제공
   - 정확히 어떤 리소스가 사용 중인지 표시됨

### 방법 2: 시간 경과 후 재시도

AWS의 eventual consistency로 인해 시간이 지나면 해결될 수 있음:

```bash
# 30분 ~ 1시간 대기 후
aws ec2 delete-security-group --group-id sg-067530e0bb78b53ec
```

### 방법 3: Terraform Destroy 계속 진행

Terraform state에서 이미 제거되었으므로:

```bash
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
terraform destroy
```

- 이 Security Group은 이제 Terraform이 관리하지 않음
- Destroy는 다른 리소스들을 정상적으로 삭제
- 이 SG만 AWS에 남게 됨 (수동 정리 필요)

### 방법 4: AWS Support 문의

위 방법으로도 해결 안 되면:
- AWS Support 티켓 생성
- 제목: "Cannot delete Security Group due to hidden dependency"
- 내용: SG ID와 이미 시도한 조치 설명

---

## 📋 최종 확인 스크립트

```bash
#!/bin/bash
SG_ID="sg-067530e0bb78b53ec"
VPC_ID="vpc-06e4fdfb8ec4950d1"

echo "=== Security Group 상태 확인 ==="
echo ""

# 1. SG 존재 여부
echo "1. Security Group 존재 여부:"
aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].[GroupId,GroupName,VpcId]' \
  --output table 2>/dev/null || echo "  Not found (이미 삭제됨)"
echo ""

# 2. Terraform state
echo "2. Terraform State:"
cd /home/ubuntu/3tier-terraform/codes/aws/2.\ service
terraform state list | grep backup || echo "  Not in state (정상)"
echo ""

# 3. 사용 중인 ENI
echo "3. Network Interfaces:"
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=$SG_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status]' \
  --output table 2>/dev/null || echo "  None (정상)"
echo ""

# 4. VPC 내 다른 SG들
echo "4. VPC 내 남은 Security Groups:"
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' \
  --output table
echo ""

echo "=== 삭제 시도 ==="
aws ec2 delete-security-group --group-id "$SG_ID" 2>&1 || true
```

---

## 💡 향후 방지책

### Terraform 코드 개선

[backup-instance.tf](../codes/aws/2.%20service/backup-instance.tf)에 다음 추가:

```hcl
resource "aws_security_group" "backup_instance" {
  # ... 기존 설정 ...

  # SG 삭제 전 리소스 정리 보장
  lifecycle {
    create_before_destroy = false
  }

  # 의존성 명시
  depends_on = [
    aws_instance.backup  # 인스턴스가 먼저 삭제되도록
  ]
}
```

### Cleanup Provisioner 개선

SG 삭제 전 강제 대기 추가:

```hcl
resource "null_resource" "cleanup_security_groups" {
  triggers = {
    vpc_id = var.vpc_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-BASH
      # 모든 리소스 정리 후 추가 대기
      echo "Waiting for AWS to clean up internal references..."
      sleep 60
    BASH
  }
}
```

---

## 🆘 긴급 상황 대응

### 즉시 인프라 정리가 필요한 경우

1. **Terraform Destroy 계속 진행**
   ```bash
   terraform destroy
   # SG 에러는 무시하고 계속 진행
   ```

2. **수동으로 남은 리소스 확인**
   ```bash
   # VPC 내 모든 리소스 조회
   aws ec2 describe-vpcs --vpc-ids vpc-06e4fdfb8ec4950d1

   # VPC 삭제 가능 여부 확인
   aws ec2 delete-vpc --vpc-id vpc-06e4fdfb8ec4950d1 --dry-run
   ```

3. **AWS Console에서 최종 정리**
   - VPC Dashboard에서 "Delete VPC" 클릭
   - VPC 삭제 시 연관된 모든 리소스 자동 확인
   - 남은 SG도 함께 삭제 가능

---

## 📊 현재 상태

| 항목 | 상태 | 비고 |
|------|------|------|
| Security Group 존재 | ✅ 존재 | AWS에 남아있음 |
| Terraform State | ✅ 제거됨 | Terraform 관리 대상 아님 |
| 사용 중인 ENI | ✅ 없음 | 모두 정리됨 |
| SG 상호 참조 | ✅ 제거됨 | 모두 정리됨 |
| 삭제 가능 여부 | ❌ 불가 | AWS 내부 의존성 |

---

## 🎯 권장 조치

### 즉시 (지금):
1. `terraform destroy` 계속 진행
2. 다른 리소스 정상 삭제 확인

### 단기 (1시간 내):
1. AWS Console에서 SG 수동 삭제 시도
2. 에러 메시지 확인

### 장기 (필요시):
1. AWS Support 티켓 생성
2. 또는 VPC 전체 삭제로 SG도 함께 제거

---

**작성일**: 2026-01-04
**상황**: Security Group 삭제 불가 (숨겨진 AWS 의존성)
**조치**: Terraform state 제거 완료, 수동 정리 필요
