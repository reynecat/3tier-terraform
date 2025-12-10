# =================================================
# Azure DR Site 설정
# =================================================

# 기본 설정
environment = "prod"
location    = "koreacentral"

# =================================================
# 관리자 접근 설정
# =================================================

# SSH 접속 허용 IP (현재 관리자 IP)
admin_ip = "43.201.1.235/32"

# VM 관리자 계정
admin_username = "azureuser"

# SSH 공개 키
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC1HrbGVbeEE0PsGJ5mrfRVHyx0mywPA57XqiW8Ky08QIt0UsSgjZyoA0rJDb/R5cdjLc/7VCHc9H4Q/RMtccIVHA0fBK9esvH4wxdFtb1acXaFqWQz3Fi9hI8E7E8tv4GHZuf5vThSj8LAxQaDKbB29POFMLNXvnooLSqU5FRJOKPkKVZ4AaeXl6mBPRewaTYlXVIrpkwOY+Khgb0nXsgdHsXeG597U6NUNKM4whDR/ToLJmJG81pQ/+qfVtwd4Yq9QLkZm5ikpIp3IkEXvIbyR1eH5iDxq50JYubQUX/jFs0GkDhGs+u0k9bqZ10Bgmq9tHY8/XNYdqeH3dq5iNXB0P2a7tKnXNYDQIEy04pZUo9nUt5UvNgHX+BdgLQ6/76BlQDHQ55iW/+qbaQ73NGRPoazl9WV9j7Sv9+/5xwBxzgMcEY7Sxt2JZVl638w8U+tI25hMlwi3dbDt/5a2XpV2F6wET90Q9GS/67MKBNzd4IrqfL0lcaDYllxUvV8yp3h4pLmXzi0QKlyuaJoEjyWTAc6S9KBDsNDCVdXwrwOOc+zxU2N6k5zpd+Fz8szHqIkeumWoS2DfLvf86Z5CE6pK/a0p7re9q2WRGDxj/EjVkliEZBwSBciJWL3qXqStRlEXYBKFCof5G39ohpImS9AAxK6Pa3TFev3I/Qnf8/yfQ== ubuntu@ip-192-168-0-59"

# =================================================
# VM 크기 설정
# =================================================

# Web VM (Nginx) - 최소 사양
web_vm_size = "Standard_B2s"  # 2 vCPU, 4GB RAM

# WAS VM (Spring Boot) - 중간 사양
was_vm_size = "Standard_B2ms" # 2 vCPU, 8GB RAM

# =================================================
# Application Gateway 설정
# =================================================

# 인스턴스 용량 (최소값으로 비용 절감)
appgw_capacity = 1

# =================================================
# 데이터베이스 설정
# =================================================

db_name     = "petclinic"
db_username = "mysqladmin"
db_password = "MyNewPassword123!"

# MySQL SKU (Burstable 시리즈로 비용 절감)
mysql_sku = "B_Standard_B2s"

# =================================================
# VPN 설정 (AWS 연결)
# =================================================

# ⚠️ IMPORTANT: AWS 배포 완료 후 반드시 업데이트 필요
# AWS VPN Connection의 Tunnel 1 IP 주소를 입력하세요
# 
# 확인 방법:
# cd aws
# terraform output vpn_connection_tunnel1_address
#
# 현재 임시값 사용 중 - AWS 배포 후 교체 필요
aws_vpn_gateway_ip = "43.203.11.112"  # terraform output vpn_connection_tunnel1_address

# AWS VPC CIDR (VPN 라우팅용)
aws_vpc_cidr = "10.0.0.0/16"

# VPN Pre-Shared Key (AWS와 동일해야 함)
# ⚠️ 보안: aws/terraform.tfvars의 vpn_shared_key와 일치해야 합니다
vpn_shared_key = "MySecureVPNKey123456789012345678"

# =================================================
# 네트워크 설정
# =================================================

# Azure VNet CIDR는 variables.tf에 기본값으로 정의됨
# 필요시 여기서 오버라이드 가능
# azure_vnet_cidr = "172.16.0.0/16"

# =================================================
# 태그 및 메타데이터
# =================================================

# 추가 태그 (선택사항)
# tags = {
#   Project     = "Multi-Cloud-DR"
#   Team        = "SRE"
#   Owner       = "your-email@example.com"
#   CostCenter  = "Engineering"
# }

# =================================================
# 배포 전 체크리스트
# =================================================
#
# [ ] SSH 공개 키가 올바른지 확인
# [ ] admin_ip가 현재 공인 IP인지 확인
# [ ] db_password가 강력한지 확인 (최소 12자, 특수문자 포함)
# [ ] AWS 배포 완료 후 aws_vpn_gateway_ip 업데이트
# [ ] vpn_shared_key가 AWS와 일치하는지 확인
# [ ] Azure CLI 로그인 확인: az login
# [ ] 적절한 Azure 구독 선택: az account set --subscription <SUBSCRIPTION_ID>
#
# =================================================
