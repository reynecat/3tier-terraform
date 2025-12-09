# Azure DR Site

Azure VM 기반 DR (Disaster Recovery) 사이트 구성입니다. AKS를 사용하지 않고 VM으로 구성하여 비용을 절감했습니다.

## 아키텍처

```
Internet
   │
   ├─ Application Gateway (Public IP)
   │
   └─ VNet (172.16.0.0/16)
       ├─ Web Subnet (172.16.11.0/24)
       │   └─ Web VM (Nginx)
       │
       ├─ WAS Subnet (172.16.21.0/24)
       │   └─ WAS VM (Spring Boot)
       │
       └─ DB Subnet (172.16.31.0/24)
           └─ Azure MySQL Flexible Server
```

## 리소스

### Compute
- **Web VM**: Standard_B2s (2 vCPU, 4GB RAM) - Ubuntu 22.04 + Nginx
- **WAS VM**: Standard_B2ms (2 vCPU, 8GB RAM) - Ubuntu 22.04 + Spring Boot
  
### Database
- **Azure MySQL Flexible Server**: B_Standard_B2s
- Backup: 7일 보관
- Version: MySQL 8.0.21

### Networking
- **Virtual Network**: 172.16.0.0/16
- **Application Gateway**: Standard_v2 (Layer 7)
- **NSG**: Web/WAS 보안 그룹

## 배포 방법

### 1. 변수 파일 생성

terraform.tfvars 파일을 생성하세요:

```hcl
environment    = "prod"
location       = "koreacentral"
admin_username = "azureuser"
admin_ip       = "YOUR_IP/32"  # 관리자 IP
ssh_public_key = file("~/.ssh/id_rsa.pub")

db_username = "mysqladmin"
db_password = "YOUR_SECURE_PASSWORD"
```

### 2. Terraform 초기화

```bash
terraform init
```

### 3. 계획 확인

```bash
terraform plan
```

### 4. 배포

```bash
terraform apply
```

## 배포 후 확인

### VM 상태 확인

```bash
# Web VM SSH 접속
ssh azureuser@<WEB_VM_PUBLIC_IP>

# Nginx 상태 확인
sudo systemctl status nginx

# WAS VM 접속 (Web VM을 통해)
ssh azureuser@<WAS_VM_PRIVATE_IP>

# Spring Boot 상태 확인
sudo systemctl status petclinic
sudo journalctl -u petclinic -f
```

### 애플리케이션 접속

```bash
# Application Gateway를 통한 접속
curl http://<APPGW_PUBLIC_IP>

# 또는 브라우저에서
http://<APPGW_PUBLIC_IP>
```

## DR 시나리오

### Warm Standby 상태
- VM은 최소 사양으로 실행 중
- 애플리케이션은 항상 실행 상태
- Azure MySQL은 대기 상태

### Failover 절차
1. Route 53이 자동으로 Azure Application Gateway로 트래픽 전환
2. 필요시 VM 스케일업:
   ```bash
   az vm resize --resource-group rg-dr-prod \
                --name vm-web-prod \
                --size Standard_D2s_v3
   
   az vm resize --resource-group rg-dr-prod \
                --name vm-was-prod \
                --size Standard_D4s_v3
   ```
3. MySQL 리소스 증설
4. 모니터링 확인

### Failback 절차
1. AWS 인프라 복구 확인
2. 데이터 역동기화
3. Route 53을 AWS ALB로 재전환
4. VM 스케일다운
5. Warm Standby 상태로 복귀

## 비용 최적화

### 현재 구성 비용 (월간 예상)
- Web VM (B2s): ~$30
- WAS VM (B2ms): ~$60
- MySQL Flexible (B_Standard_B2s): ~$50
- Application Gateway (Standard_v2): ~$150
- **총 예상 비용**: ~$290/월

### 절감 포인트
- AKS 미사용으로 약 $300/월 절감
- Burstable VM 사용
- 최소 리소스로 Warm Standby 유지

## 모니터링

### Azure Portal에서 확인
1. 리소스 그룹 `rg-dr-prod`
2. VM 메트릭 (CPU, Memory, Disk)
3. Application Gateway 메트릭
4. MySQL 모니터링

### Azure CLI로 확인
```bash
# VM 상태
az vm get-instance-view --resource-group rg-dr-prod --name vm-web-prod

# Application Gateway 상태
az network application-gateway show --resource-group rg-dr-prod --name appgw-prod

# MySQL 상태
az mysql flexible-server show --resource-group rg-dr-prod --name mysql-dr-prod
```

## 문제 해결

### VM에 SSH 접속 불가
- NSG 규칙 확인: admin_ip가 올바른지 확인
- Public IP 확인
- SSH 키 확인

### 애플리케이션 접속 불가
- Application Gateway 상태 확인
- Backend Pool Health 확인
- Nginx/Spring Boot 로그 확인

### 데이터베이스 연결 실패
- MySQL 방화벽 규칙 확인
- VNet Integration 확인
- 연결 문자열 확인

## 리소스 정리

```bash
terraform destroy
```

주의: 모든 리소스가 삭제됩니다. 데이터 백업을 확인하세요.
