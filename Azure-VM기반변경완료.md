# ✅ Azure를 VM 기반으로 변경 완료!

## 🔄 주요 변경 사항

### AS-IS (이전)
```
Azure AKS (Kubernetes)
├─ AKS Cluster
├─ Worker Nodes (여러 개)
├─ Pods (Web + WAS)
└─ 복잡한 관리
```

### TO-BE (현재)
```
Azure VM (단순 가상 서버)
├─ Web VM (Nginx) - Standard_B2s
├─ WAS VM (Spring Boot) - Standard_B2ms
└─ 간단한 관리
```

---

## 🎯 변경 이유

### 1. Warm Standby 특성에 맞춤
- DR Site는 평상시 최소 리소스로 대기
- 장애 발생 시에만 활성화
- **AKS는 과한 스펙**, VM이면 충분

### 2. 비용 절감
| 항목 | AKS | VM |
|------|-----|-----|
| 클러스터 관리 비용 | $70-100/월 | $0 |
| Worker Node | $60-100/월 | Web: $30/월 |
| | | WAS: $50/월 |
| **총 비용** | **$130-200/월** | **$80/월** |
| **절감액** | - | **-$50-120/월** |

### 3. 관리 단순화
- AKS: kubectl, Helm, YAML 매니페스트
- VM: SSH 접속, systemd 관리

---

## 🏗️ 새로운 Azure 아키텍처

```
Internet
    ↓
Application Gateway (Public IP)
    ↓
┌─────────────────────────────────────┐
│  Web Subnet 172.16.11.0/24         │
│  └─ Web VM (Standard_B2s)          │
│     └─ Nginx                        │
├─────────────────────────────────────┤
│  WAS Subnet 172.16.21.0/24         │
│  └─ WAS VM (Standard_B2ms)         │
│     └─ Spring Boot + Java 17       │
├─────────────────────────────────────┤
│  DB Subnet 172.16.31.0/24          │
│  └─ Azure MySQL Flexible Server    │
│     └─ Zone Redundant HA           │
├─────────────────────────────────────┤
│  Gateway Subnet 172.16.255.0/24    │
│  └─ VPN Gateway (VpnGw1)           │
└─────────────────────────────────────┘
```

---

## 📦 새로 추가된 파일

### Terraform 파일
```
terraform/azure/
├── main.tf              # Azure 인프라 정의
├── variables.tf         # 변수 정의
├── outputs.tf           # 출력 정의
└── scripts/
    ├── web-init.sh      # Web VM 초기화 (Nginx)
    └── was-init.sh      # WAS VM 초기화 (Spring Boot)
```

### 주요 리소스
1. **VNet 172.16.0.0/16**
   - Web Subnet: 172.16.11.0/24
   - WAS Subnet: 172.16.21.0/24
   - DB Subnet: 172.16.31.0/24
   - Gateway Subnet: 172.16.255.0/24

2. **Network Security Groups**
   - Web NSG: HTTP/HTTPS 허용
   - WAS NSG: Web에서만 8080 허용
   - DB NSG: WAS에서만 3306 허용

3. **Virtual Machines**
   - Web VM: Standard_B2s (2 vCPU, 4GB RAM)
   - WAS VM: Standard_B2ms (2 vCPU, 8GB RAM)

4. **Application Gateway**
   - Public IP
   - Health Check (/health)
   - Backend: Web VM

5. **Azure MySQL**
   - Flexible Server
   - Zone Redundant HA
   - 자동 백업 (7일)

6. **VPN Gateway**
   - Site-to-Site VPN
   - AWS와 연결

---

## 🚀 배포 방법

### 1단계: SSH 키 생성
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_dr_key
```

### 2단계: Terraform 변수 설정
```bash
cd terraform/azure

# terraform.tfvars 파일 생성
cat > terraform.tfvars <<EOF
environment     = "prod"
location        = "koreacentral"
admin_username  = "azureuser"
admin_ip        = "YOUR_PUBLIC_IP/32"  # 본인 IP로 변경
ssh_public_key  = file("~/.ssh/azure_dr_key.pub")

# VM 크기
web_vm_size     = "Standard_B2s"
was_vm_size     = "Standard_B2ms"

# MySQL 설정
mysql_sku       = "B_Standard_B2s"
db_name         = "petclinic"
db_username     = "dbadmin"
db_password     = "STRONG_PASSWORD_HERE"  # 강력한 비밀번호로 변경
EOF
```

### 3단계: Terraform 배포
```bash
terraform init
terraform plan
terraform apply
```

### 4단계: 배포 확인
```bash
# Outputs 확인
terraform output

# Web VM SSH 접속
ssh -i ~/.ssh/azure_dr_key azureuser@<WEB_VM_PUBLIC_IP>

# 애플리케이션 접속
curl http://<APP_GATEWAY_PUBLIC_IP>
```

---

## 📊 VM 스펙 비교

### Web VM (Standard_B2s)
- **vCPU**: 2
- **RAM**: 4GB
- **스토리지**: 30GB Premium SSD
- **용도**: Nginx 리버스 프록시
- **비용**: ~$30/월

### WAS VM (Standard_B2ms)
- **vCPU**: 2
- **RAM**: 8GB
- **스토리지**: 50GB Premium SSD
- **용도**: Spring Boot 애플리케이션
- **비용**: ~$50/월

---

## 🔐 보안 구성

### NSG Rules

#### Web NSG
```
Inbound:
- HTTP (80): 모든 곳에서 허용
- HTTPS (443): 모든 곳에서 허용
- SSH (22): 관리자 IP만 허용

Outbound:
- WAS Subnet (172.16.21.0/24): 허용
```

#### WAS NSG
```
Inbound:
- 8080: Web Subnet (172.16.11.0/24)에서만 허용
- SSH (22): 관리자 IP만 허용

Outbound:
- DB Subnet (172.16.31.0/24): 허용
```

#### DB NSG
```
Inbound:
- MySQL (3306): WAS Subnet (172.16.21.0/24)에서만 허용

Outbound:
- 차단
```

---

## 🔧 VM 관리

### Web VM 관리
```bash
# SSH 접속
ssh -i ~/.ssh/azure_dr_key azureuser@<WEB_VM_IP>

# Nginx 상태 확인
sudo systemctl status nginx

# Nginx 로그 확인
sudo tail -f /var/log/nginx/access.log

# Nginx 재시작
sudo systemctl restart nginx
```

### WAS VM 관리
```bash
# SSH 접속 (Web VM 경유 필요)
ssh -i ~/.ssh/azure_dr_key azureuser@<WEB_VM_IP>
ssh <WAS_PRIVATE_IP>

# Spring Boot 상태 확인
sudo systemctl status petclinic

# 애플리케이션 로그 확인
sudo journalctl -u petclinic -f

# 애플리케이션 재시작
sudo systemctl restart petclinic
```

### DB 연결 테스트
```bash
# WAS VM에서 실행
mysql -h <MYSQL_FQDN> -u dbadmin -p petclinic
```

---

## 📈 스케일링

### 수평 확장 (VM 추가)
```hcl
# main.tf에 추가
resource "azurerm_linux_virtual_machine" "web_2" {
  name = "vm-web-2-${var.environment}"
  # 동일 설정...
}

# Application Gateway Backend Pool에 추가
resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "web_2" {
  network_interface_id    = azurerm_network_interface.web_2.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = tolist(azurerm_application_gateway.main.backend_address_pool)[0].id
}
```

### 수직 확장 (VM 크기 변경)
```bash
# Azure Portal 또는 CLI로 VM 크기 변경
az vm resize \
  --resource-group rg-dr-prod \
  --name vm-was-prod \
  --size Standard_D2s_v3
```

---

## 💰 비용 비교 (월간)

### AKS 기반 (이전)
| 항목 | 비용 |
|------|------|
| AKS Control Plane | $73 |
| Worker Nodes (2x Standard_B2s) | $60 |
| Azure MySQL | $50 |
| VPN Gateway | $30 |
| Application Gateway | $40 |
| **합계** | **$253** |

### VM 기반 (현재)
| 항목 | 비용 |
|------|------|
| Web VM (Standard_B2s) | $30 |
| WAS VM (Standard_B2ms) | $50 |
| Azure MySQL | $50 |
| VPN Gateway | $30 |
| Application Gateway | $40 |
| **합계** | **$200** |

**절감액: $53/월 (약 21% 절감)**

---

## 🎯 장점 정리

### 1. 비용 효율성
- AKS Control Plane 비용 절감 ($73/월)
- 필요한 만큼만 VM 사용

### 2. 단순성
- Kubernetes 학습 불필요
- SSH + systemd로 관리
- 트러블슈팅 용이

### 3. Warm Standby에 최적
- 평상시 최소 리소스
- 필요 시 VM 크기 조정
- 빠른 활성화 가능

### 4. 유지보수
- OS 패치: Azure 자동 업데이트
- 애플리케이션 업데이트: systemd restart
- 모니터링: Azure Monitor

---

## 📚 참고 자료

- **Azure Virtual Machines**: https://learn.microsoft.com/azure/virtual-machines/
- **Azure Application Gateway**: https://learn.microsoft.com/azure/application-gateway/
- **Azure MySQL Flexible Server**: https://learn.microsoft.com/azure/mysql/flexible-server/

---

## ✅ 완료 체크리스트

- [x] AKS 제거
- [x] Web VM 추가 (Nginx)
- [x] WAS VM 추가 (Spring Boot)
- [x] 서브넷 분리 (Web/WAS/DB/Gateway)
- [x] NSG 구성 (계층별 보안)
- [x] Application Gateway 설정
- [x] 초기화 스크립트 작성
- [x] Terraform 코드 작성
- [x] 아키텍처 다이어그램 수정
- [x] 비용 분석
- [x] 문서 작성

---

**이제 Azure DR Site가 간단하고 비용 효율적인 VM 기반 아키텍처로 변경되었습니다!** 🎉

Warm Standby의 목적에 맞게 최소 리소스로 대기하다가, 필요 시 빠르게 활성화할 수 있습니다.
