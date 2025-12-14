# =================================================
# Azure DR Site 설정 (유지보수 모드)
# =================================================

# 기본 설정
environment = "prod"
location    = "koreacentral"

# =================================================
# 관리자 접근 설정
# =================================================

# SSH 접속 허용 IP (현재 관리자 IP)
admin_ip = "3.35.64.226/32"

# VM 관리자 계정
admin_username = "azureuser"

# SSH 공개 키
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC1HrbGVbeEE0PsGJ5mrfRVHyx0mywPA57XqiW8Ky08QIt0UsSgjZyoA0rJDb/R5cdjLc/7VCHc9H4Q/RMtccIVHA0fBK9esvH4wxdFtb1acXaFqWQz3Fi9hI8E7E8tv4GHZuf5vThSj8LAxQaDKbB29POFMLNXvnooLSqU5FRJOKPkKVZ4AaeXl6mBPRewaTYlXVIrpkwOY+Khgb0nXsgdHsXeG597U6NUNKM4whDR/ToLJmJG81pQ/+qfVtwd4Yq9QLkZm5ikpIp3IkEXvIbyR1eH5iDxq50JYubQUX/jFs0GkDhGs+u0k9bqZ10Bgmq9tHY8/XNYdqeH3dq5iNXB0P2a7tKnXNYDQIEy04pZUo9nUt5UvNgHX+BdgLQ6/76BlQDHQ55iW/+qbaQ73NGRPoazl9WV9j7Sv9+/5xwBxzgMcEY7Sxt2JZVl638w8U+tI25hMlwi3dbDt/5a2XpV2F6wET90Q9GS/67MKBNzd4IrqfL0lcaDYllxUvV8yp3h4pLmXzi0QKlyuaJoEjyWTAc6S9KBDsNDCVdXwrwOOc+zxU2N6k5zpd+Fz8szHqIkeumWoS2DfLvf86Z5CE6pK/a0p7re9q2WRGDxj/EjVkliEZBwSBciJWL3qXqStRlEXYBKFCof5G39ohpImS9AAxK6Pa3TFev3I/Qnf8/yfQ== ubuntu@ip-192-168-0-59"

# =================================================
# VM 크기 설정
# =================================================

# Web VM (Nginx - 유지보수 페이지)
web_vm_size = "Standard_B2s"  # 2 vCPU, 4GB RAM

# WAS VM (Flask API )
was_vm_size = "Standard_B1s"  

# =================================================
# Application Gateway 설정
# =================================================

# 인스턴스 용량 (최소값으로 비용 절감)
appgw_capacity = 1

# =================================================
# 데이터베이스 설정 (데이터 보존용)
# =================================================

db_name     = "petclinic"
db_username = "mysqladmin"
db_password = "MyNewPassword123!"

# MySQL SKU 

mysql_sku = "B_Standard_B2s"

# =================================================
# VPN 설정 (AWS 연결)
# =================================================

# AWS VPN Connection의 Tunnel 1 IP 주소
aws_vpn_gateway_ip = "3.39.211.139"

# AWS VPC CIDR (VPN 라우팅용)
aws_vpc_cidr = "10.0.0.0/16"

# VPN Pre-Shared Key (AWS와 동일해야 함)
vpn_shared_key = "MySecureVPNKey123456789012345678"
