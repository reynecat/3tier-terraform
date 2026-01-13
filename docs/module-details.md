# Infrastructure Module 상세 설명

이 문서는 Terraform으로 구성된 각 모듈의 상세 기술 설명을 제공합니다.

---

## 목차

1. [AWS Modules](#aws-modules)
   - [1.1 VPC Module](#11-vpc-module)
   - [1.2 EKS Module](#12-eks-module)
   - [1.3 RDS Module](#13-rds-module)
   - [1.4 Backup Instance Module](#14-backup-instance-module)
2. [Azure Modules](#azure-modules)
   - [2.1 Network Module](#21-azure-network-module)
   - [2.2 AKS Module](#22-aks-module)
   - [2.3 MySQL Flexible Server Module](#23-mysql-flexible-server-module)
   - [2.4 Application Gateway Module](#24-application-gateway-module)

---

# AWS Modules

## 1.1 VPC Module

### 개요
**경로**: `codes/aws/2. service/modules/vpc`

AWS VPC를 생성하며 Multi-AZ 구성으로 고가용성을 보장합니다.

### 주요 구성 요소

#### CIDR 및 서브넷 설계
```hcl
VPC CIDR: 10.0.0.0/16

Availability Zone A (ap-northeast-2a):
  - Public Subnet:  10.0.1.0/24
  - Web Subnet:     10.0.11.0/24
  - WAS Subnet:     10.0.21.0/24
  - DB Subnet:      10.0.31.0/24

Availability Zone B (ap-northeast-2b):
  - Public Subnet:  10.0.2.0/24
  - Web Subnet:     10.0.12.0/24
  - WAS Subnet:     10.0.22.0/24
  - DB Subnet:      10.0.32.0/24
```

#### 네트워크 계층 분리 이유
- **Public Subnet**: NAT Gateway, Bastion Host (필요시)
- **Web Subnet**: EKS Web Node Group (인터넷 접근 필요)
- **WAS Subnet**: EKS WAS Node Group (격리된 환경)
- **DB Subnet**: RDS MySQL (완전 격리)

### 라우팅 테이블

#### Public Subnet
```hcl
Destination       Target
0.0.0.0/0        → Internet Gateway
10.0.0.0/16      → local
```

#### Private Subnet (Web/WAS)
```hcl
Destination       Target
0.0.0.0/0        → NAT Gateway (각 AZ별)
10.0.0.0/16      → local
```

#### DB Subnet
```hcl
Destination       Target
10.0.0.0/16      → local (인터넷 접근 불가)
```

### NAT Gateway 구성

**Multi-AZ NAT Gateway 배치**:
- AZ-A: NAT Gateway in 10.0.1.0/24
- AZ-B: NAT Gateway in 10.0.2.0/24

**이유**: 단일 NAT Gateway 장애 시에도 다른 AZ의 리소스는 정상 작동

**비용 고려**:
- NAT Gateway: $0.045/hour × 2 = ~$65/month
- 데이터 전송: $0.045/GB

### VPC Endpoints

#### S3 Gateway Endpoint
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.ap-northeast-2.s3"

  route_table_ids = [
    aws_route_table.private_web_a.id,
    aws_route_table.private_web_b.id,
    aws_route_table.private_was_a.id,
    aws_route_table.private_was_b.id,
  ]
}
```

**목적**: S3 접근 시 NAT Gateway를 거치지 않아 비용 절감 및 성능 향상

#### ECR Interface Endpoints (옵션)
Docker 이미지 pull 시 NAT Gateway 비용 절감을 위해 사용 가능:
- `com.amazonaws.ap-northeast-2.ecr.api`
- `com.amazonaws.ap-northeast-2.ecr.dkr`

---

## 1.2 EKS Module

### 개요
**경로**: `codes/aws/2. service/modules/eks`

AWS EKS를 생성하며 별도의 Web/WAS Node Group으로 워크로드를 분리합니다.

### Cluster 구성

#### Control Plane
```hcl
resource "aws_eks_cluster" "main" {
  name     = "blue-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.34"

  vpc_config {
    subnet_ids = [
      # Private subnets only (보안 강화)
      var.web_subnet_ids...,
      var.was_subnet_ids...
    ]

    endpoint_private_access = true   # VPC 내부 접근 허용
    endpoint_public_access  = true   # 외부 kubectl 접근 허용

    public_access_cidrs = [
      "0.0.0.0/0"  # 프로덕션에서는 특정 IP로 제한 권장
    ]
  }
}
```

#### EKS Endpoint 접근 제어 상세

**1. Public + Private 혼합 접근 (현재 설정)**
```hcl
endpoint_private_access = true
endpoint_public_access  = true
public_access_cidrs     = ["0.0.0.0/0"]
```

**접근 경로**:
- **External kubectl** (개발자 로컬): Internet → Public Endpoint → EKS API Server
- **Worker Nodes**: Private Network → Private Endpoint → EKS API Server
- **VPC 내부 리소스**: Private Network → Private Endpoint → EKS API Server

**장점**:
- 외부에서 kubectl 사용 가능 (개발/운영 편의성)
- Worker Node는 Private Endpoint 사용 (보안)
- NAT Gateway 비용 절감 (Node → API Server 통신 시)

**보안 강화 옵션**:
```hcl
public_access_cidrs = [
  "1.2.3.4/32",  # 회사 IP
  "5.6.7.8/32"   # VPN IP
]
```

**2. Private Only 접근 (최고 보안)**
```hcl
endpoint_private_access = true
endpoint_public_access  = false
```

**제약사항**:
- kubectl 사용 시 VPN 또는 Bastion Host 필요
- CI/CD 파이프라인도 VPC 내부에서 실행해야 함

### Node Groups

#### Web Node Group
```hcl
resource "aws_eks_node_group" "web" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "web-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = var.web_subnet_ids  # 10.0.11.0/24, 10.0.12.0/24

  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 2
  }

  # Node Label을 통한 Pod 스케줄링
  labels = {
    role = "web"
    tier = "frontend"
  }

  # Taints를 통한 전용 노드 구성
  taint {
    key    = "dedicated"
    value  = "web"
    effect = "NoSchedule"
  }
}
```

**Web Pod Deployment에서 매칭**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-nginx
spec:
  template:
    spec:
      nodeSelector:
        role: web
      tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "web"
        effect: "NoSchedule"
```

#### WAS Node Group
```hcl
resource "aws_eks_node_group" "was" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "was-nodes"

  subnet_ids = var.was_subnet_ids  # 10.0.21.0/24, 10.0.22.0/24

  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 2
    max_size     = 5
    min_size     = 1
  }

  labels = {
    role = "was"
    tier = "backend"
  }

  taint {
    key    = "dedicated"
    value  = "was"
    effect = "NoSchedule"
  }
}
```

### IAM Roles 및 정책

#### EKS Cluster Role
```hcl
data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}
```

**AmazonEKSClusterPolicy 주요 권한**:
- EC2 네트워크 인터페이스 관리
- Elastic Load Balancer 생성/삭제
- CloudWatch Logs 전송

#### EKS Node Role
```hcl
resource "aws_iam_role" "eks_node" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# 필수 정책 연결
resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"  # Session Manager 접근
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_node.name
}
```

### EKS Add-ons

#### VPC CNI
```hcl
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  addon_version = "v1.18.0-eksbuild.1"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}
```

**VPC CNI 역할**:
- Pod에 VPC IP 주소 직접 할당
- ENI (Elastic Network Interface) 관리
- Security Group for Pods 기능 지원

#### CoreDNS
```hcl
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  # Control Plane이 준비된 후 설치
  depends_on = [
    aws_eks_node_group.web,
    aws_eks_node_group.was
  ]
}
```

#### kube-proxy
```hcl
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}
```

### OIDC Provider (IRSA 지원)

```hcl
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}
```

**IRSA (IAM Roles for Service Accounts) 사용 예시**:

AWS Load Balancer Controller ServiceAccount:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/AWSLoadBalancerControllerRole
```

**작동 원리**:
1. Pod가 ServiceAccount의 token을 사용
2. OIDC Provider가 token 검증
3. AssumeRoleWithWebIdentity로 IAM Role 획득
4. Pod가 AWS API 호출 가능 (Access Key 불필요)

---

## 1.3 RDS Module

### 개요
**경로**: `codes/aws/2. service/modules/rds`

Multi-AZ MySQL RDS를 생성하여 고가용성 데이터베이스를 제공합니다.

### RDS Instance 구성

```hcl
resource "aws_db_instance" "mysql" {
  identifier = "mysql-blue"

  # Engine
  engine               = "mysql"
  engine_version       = "8.0.35"
  instance_class       = "db.t3.medium"

  # Storage
  allocated_storage     = 100
  max_allocated_storage = 500  # Auto-scaling 활성화
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.rds.arn

  # Database
  db_name  = "petclinic"
  username = "admin"
  password = var.db_password  # terraform.tfvars에서 주입

  # High Availability
  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.rds.name

  # Backup
  backup_retention_period = 7
  backup_window           = "03:00-04:00"  # UTC (KST 12:00-13:00)

  # Maintenance
  maintenance_window = "mon:04:00-mon:05:00"

  # Performance Insights
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]
  performance_insights_enabled    = true
  performance_insights_retention_period = 7

  # Security
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Deletion Protection
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "mysql-blue-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = {
    Name = "mysql-blue"
    Backup = "daily"
  }
}
```

### Multi-AZ 동작 방식

**정상 상태**:
```
Primary (AZ-A):  10.0.31.10 (Write/Read)
Standby (AZ-B):  10.0.32.10 (Sync Replication, No Read)
                      ↓
                 동기 복제
```

**Failover 시나리오**:
1. Primary AZ 장애 감지 (60-120초)
2. RDS가 자동으로 Standby를 Primary로 승격
3. DNS 엔드포인트 업데이트 (애플리케이션 재연결 필요 없음)
4. 복구 시간: 일반적으로 1-2분

**Endpoint**:
```
mysql-blue.xxxxxxxxxx.ap-northeast-2.rds.amazonaws.com
```
이 DNS는 항상 현재 Primary를 가리킴

### DB Subnet Group

```hcl
resource "aws_db_subnet_group" "rds" {
  name       = "rds-subnet-group"
  subnet_ids = [
    var.db_subnet_a_id,  # 10.0.31.0/24
    var.db_subnet_b_id   # 10.0.32.0/24
  ]

  tags = {
    Name = "RDS Subnet Group"
  }
}
```

**RDS는 최소 2개의 AZ에 서브넷 필요**

### Security Group

```hcl
resource "aws_security_group" "rds" {
  name_prefix = "rds-sg-"
  vpc_id      = var.vpc_id

  # WAS 서브넷에서만 접근 허용
  ingress {
    description = "MySQL from WAS subnets"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      "10.0.21.0/24",  # WAS Subnet A
      "10.0.22.0/24"   # WAS Subnet B
    ]
  }

  # Backup Instance에서도 접근 허용
  ingress {
    description     = "MySQL from Backup Instance"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.backup_instance_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}
```

**보안 원칙**:
- ✅ WAS Subnet만 접근 가능
- ✅ Backup Instance 접근 가능
- ❌ 외부 인터넷 접근 불가
- ❌ Web Subnet 접근 불가

### Parameter Group

```hcl
resource "aws_db_parameter_group" "mysql" {
  name   = "mysql-custom"
  family = "mysql8.0"

  # Character Set (UTF-8)
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # Slow Query Log
  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"  # 2초 이상 쿼리 로깅
  }

  # Max Connections
  parameter {
    name  = "max_connections"
    value = "500"
  }

  # Binary Log Retention (PITR)
  parameter {
    name  = "binlog_retention_hours"
    value = "168"  # 7 days
  }
}
```

### KMS 암호화

```hcl
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = {
    Name = "rds-encryption-key"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/rds-mysql"
  target_key_id = aws_kms_key.rds.key_id
}
```

**암호화 범위**:
- 데이터베이스 storage
- Automated backups
- Read replicas
- Snapshots

---

## 1.4 Backup Instance Module

### 개요
**경로**: `codes/aws/2. service/modules/backup_instance`

RDS MySQL 데이터를 Azure Blob Storage로 백업하는 EC2 인스턴스입니다.

### EC2 Instance 구성

```hcl
resource "aws_instance" "backup" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.small"

  subnet_id              = var.was_subnet_a_id  # WAS Subnet (RDS 접근 가능)
  vpc_security_group_ids = [aws_security_group.backup.id]

  iam_instance_profile = aws_iam_instance_profile.backup.name

  user_data = templatefile("${path.module}/user_data.sh", {
    rds_endpoint            = var.rds_endpoint
    db_name                 = var.db_name
    db_username             = var.db_username
    db_password             = var.db_password
    azure_storage_account   = var.azure_storage_account_name
    azure_storage_key       = var.azure_storage_account_key
    azure_container         = var.azure_backup_container_name
    backup_schedule_cron    = var.backup_schedule_cron
  })

  tags = {
    Name = "backup-instance"
    Role = "MySQL-to-Azure-Backup"
  }
}
```

### User Data Script

**`user_data.sh` 주요 내용**:

```bash
#!/bin/bash
set -e

# 1. MySQL Client 설치
dnf install -y mysql

# 2. Azure CLI 설치
rpm --import https://packages.microsoft.com/keys/microsoft.asc
dnf install -y azure-cli

# 3. 백업 스크립트 생성
cat > /usr/local/bin/backup-mysql.sh <<'EOF'
#!/bin/bash
DATE=$(date +%Y-%m-%d-%H%M)
BACKUP_FILE="/tmp/mysql-backup-$DATE.sql"

# MySQL Dump
mysqldump -h ${rds_endpoint} \
  -u ${db_username} \
  -p'${db_password}' \
  --single-transaction \
  --routines \
  --triggers \
  --databases ${db_name} \
  > $BACKUP_FILE

# 압축
gzip $BACKUP_FILE

# Azure Blob Storage 업로드
az storage blob upload \
  --account-name ${azure_storage_account} \
  --account-key '${azure_storage_key}' \
  --container-name ${azure_container} \
  --name backups/mysql-backup-$DATE.sql.gz \
  --file $BACKUP_FILE.gz \
  --overwrite

# 로컬 파일 삭제
rm -f $BACKUP_FILE.gz

echo "[$(date)] Backup completed: mysql-backup-$DATE.sql.gz"
EOF

chmod +x /usr/local/bin/backup-mysql.sh

# 4. Cron Job 등록
echo "${backup_schedule_cron} /usr/local/bin/backup-mysql.sh >> /var/log/mysql-backup.log 2>&1" | crontab -

# 5. 즉시 1회 백업 실행
/usr/local/bin/backup-mysql.sh
```

**백업 옵션 설명**:
- `--single-transaction`: InnoDB 테이블에 대해 일관된 백업 (테이블 락 없이)
- `--routines`: Stored Procedures, Functions 포함
- `--triggers`: Triggers 포함
- `--databases`: 특정 데이터베이스만 백업

### Security Group

```hcl
resource "aws_security_group" "backup" {
  name_prefix = "backup-instance-sg-"
  vpc_id      = var.vpc_id

  # Outbound: RDS 접근
  egress {
    description = "MySQL to RDS"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      "10.0.31.0/24",  # DB Subnet A
      "10.0.32.0/24"   # DB Subnet B
    ]
  }

  # Outbound: HTTPS (Azure Blob Storage 업로드)
  egress {
    description = "HTTPS for Azure CLI"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: HTTP (패키지 설치)
  egress {
    description = "HTTP for package installation"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### IAM Role

```hcl
resource "aws_iam_role" "backup" {
  name = "backup-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# SSM Session Manager 접근
resource "aws_iam_role_policy_attachment" "backup_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.backup.name
}

# CloudWatch Logs
resource "aws_iam_role_policy" "backup_cloudwatch" {
  name = "cloudwatch-logs"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}
```

### 백업 모니터링

**CloudWatch Logs Agent 설치** (user_data.sh에 추가):
```bash
# CloudWatch Agent 설치
yum install -y amazon-cloudwatch-agent

# 설정 파일 생성
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [{
          "file_path": "/var/log/mysql-backup.log",
          "log_group_name": "/aws/backup/mysql",
          "log_stream_name": "{instance_id}"
        }]
      }
    }
  }
}
EOF

# Agent 시작
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
```

---

# Azure Modules

## 2.1 Azure Network Module

### 개요
**경로**: `codes/azure/1-always/modules/network` 및 `codes/azure/2-emergency/modules/network`

Azure VNet을 생성하며 AKS, Application Gateway, MySQL을 위한 서브넷을 구성합니다.

### VNet 및 서브넷 설계

```hcl
resource "azurerm_virtual_network" "main" {
  name                = "vnet-dr-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = ["10.1.0.0/16"]

  tags = var.tags
}

# AKS System Node Pool Subnet
resource "azurerm_subnet" "aks_system" {
  name                 = "snet-aks-system"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.0.0/24"]

  # Service Endpoints
  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

# AKS Web Node Pool Subnet
resource "azurerm_subnet" "aks_web" {
  name                 = "snet-aks-web"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]

  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

# AKS WAS Node Pool Subnet
resource "azurerm_subnet" "aks_was" {
  name                 = "snet-aks-was"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.2.0/24"]

  service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
}

# Application Gateway Subnet
resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.10.0/24"]
}

# MySQL Private Endpoint Subnet
resource "azurerm_subnet" "mysql" {
  name                 = "snet-mysql"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.20.0/24"]

  service_endpoints = ["Microsoft.Sql"]

  # Private Endpoint 전용 설정
  private_endpoint_network_policies_enabled = false
}
```

### Network Security Groups

#### AKS NSG
```hcl
resource "azurerm_network_security_group" "aks" {
  name                = "nsg-aks"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Inbound: Application Gateway에서만 허용
  security_rule {
    name                       = "AllowAppGateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "10.1.10.0/24"  # AppGW Subnet
    destination_address_prefix = "*"
  }

  # Inbound: AKS 내부 통신
  security_rule {
    name                       = "AllowAKSInternal"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_address_prefixes    = [
      "10.1.0.0/24",  # System
      "10.1.1.0/24",  # Web
      "10.1.2.0/24"   # WAS
    ]
    destination_address_prefix = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
  }

  # Outbound: MySQL 접근
  security_rule {
    name                       = "AllowMySQL"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "10.1.20.0/24"  # MySQL Subnet
  }
}

# NSG Association
resource "azurerm_subnet_network_security_group_association" "aks_web" {
  subnet_id                 = azurerm_subnet.aks_web.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

resource "azurerm_subnet_network_security_group_association" "aks_was" {
  subnet_id                 = azurerm_subnet.aks_was.id
  network_security_group_id = azurerm_network_security_group.aks.id
}
```

#### Application Gateway NSG
```hcl
resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Inbound: HTTP/HTTPS from Internet
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Inbound: GatewayManager (필수)
  security_rule {
    name                       = "AllowGatewayManager"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }
}
```

### Service Endpoints vs Private Endpoints

**Service Endpoints** (현재 사용):
```hcl
service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
```

**장점**:
- 추가 비용 없음
- 설정 간단
- Azure 백본 네트워크 사용

**단점**:
- 서비스는 여전히 Public IP 유지
- Firewall rules로 접근 제한

**Private Endpoints** (프로덕션 권장):
```hcl
resource "azurerm_private_endpoint" "mysql" {
  name                = "pe-mysql"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.mysql.id

  private_service_connection {
    name                           = "psc-mysql"
    private_connection_resource_id = azurerm_mysql_flexible_server.main.id
    is_manual_connection           = false
    subresource_names              = ["mysqlServer"]
  }
}
```

**장점**:
- MySQL이 완전 Private (Public IP 없음)
- VNet 내부 IP로만 접근
- 최고 수준 보안

**단점**:
- Private Endpoint당 $0.01/hour (~$7/month)
- 추가 DNS 구성 필요

---

## 2.2 AKS Module

### 개요
**경로**: `codes/azure/2-emergency/modules/aks`

Azure Kubernetes Service를 생성하며 Web/WAS 전용 Node Pool을 구성합니다.

### AKS Cluster 구성

```hcl
resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-dr-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "aks-dr-${var.environment}"
  kubernetes_version  = var.kubernetes_version  # 1.34

  # System Node Pool (필수)
  default_node_pool {
    name       = "system"
    node_count = 2
    vm_size    = "Standard_D2s_v3"

    vnet_subnet_id = var.aks_system_subnet_id

    # System pods only
    node_labels = {
      "nodepool-type" = "system"
      "role"          = "system"
    }

    # Only system pods
    only_critical_addons_enabled = true
  }

  # Identity
  identity {
    type = "SystemAssigned"
  }

  # Network Profile
  network_profile {
    network_plugin     = "azure"  # Azure CNI
    network_policy     = "azure"
    load_balancer_sku  = "standard"
    service_cidr       = "10.2.0.0/16"
    dns_service_ip     = "10.2.0.10"
  }

  # API Server 접근 제어
  api_server_access_profile {
    authorized_ip_ranges = [
      "0.0.0.0/0"  # 프로덕션에서는 특정 IP로 제한
    ]
  }

  # Azure AD Integration (옵션)
  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  tags = var.tags
}
```

### Azure CNI vs Kubenet

**Azure CNI** (현재 사용):
- Pod가 VNet IP를 직접 할당받음
- Pod <-> VM 간 라우팅 불필요
- Network Policy 지원
- 단점: IP 주소 많이 소비

**계산 예시**:
```
Node당 최대 Pod 수: 30 (기본값)
Node 2개 = 60개 IP 필요
여유분 포함 = /26 (64 IPs) 권장
```

**Kubenet** (대안):
- Pod가 Node 내부 IP 사용
- NAT 통해 외부 통신
- IP 주소 절약
- 단점: Network Policy 제한적

### User Node Pools

#### Web Node Pool
```hcl
resource "azurerm_kubernetes_cluster_node_pool" "web" {
  name                  = "web"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size

  node_count = var.web_node_count

  # Auto Scaling
  enable_auto_scaling = true
  min_count           = var.web_node_min_count
  max_count           = var.web_node_max_count

  vnet_subnet_id = var.aks_web_subnet_id

  # Availability Zones
  zones = ["1", "2"]

  # Node Labels
  node_labels = {
    "nodepool-type" = "user"
    "role"          = "web"
    "tier"          = "frontend"
  }

  # Node Taints
  node_taints = [
    "dedicated=web:NoSchedule"
  ]

  tags = merge(var.tags, {
    Role = "Web"
  })
}
```

#### WAS Node Pool
```hcl
resource "azurerm_kubernetes_cluster_node_pool" "was" {
  name                  = "was"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size

  node_count = var.was_node_count

  enable_auto_scaling = true
  min_count           = var.was_node_min_count
  max_count           = var.was_node_max_count

  vnet_subnet_id = var.aks_was_subnet_id

  zones = ["1", "2"]

  node_labels = {
    "nodepool-type" = "user"
    "role"          = "was"
    "tier"          = "backend"
  }

  node_taints = [
    "dedicated=was:NoSchedule"
  ]

  tags = merge(var.tags, {
    Role = "WAS"
  })
}
```

### RBAC 및 권한

AKS가 다른 Azure 리소스에 접근하려면 권한 부여 필요:

```hcl
# Network Contributor (LoadBalancer 생성 권한)
resource "azurerm_role_assignment" "aks_network" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}

# AcrPull (Container Registry 이미지 pull 권한)
resource "azurerm_role_assignment" "aks_acr" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.identity[0].principal_id
}
```

---

## 2.3 MySQL Flexible Server Module

### 개요
**경로**: `codes/azure/2-emergency/modules/mysql`

Azure MySQL Flexible Server를 생성하여 고가용성 데이터베이스를 제공합니다.

### MySQL Flexible Server 구성

```hcl
resource "azurerm_mysql_flexible_server" "main" {
  name                = "mysql-dr-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Version
  version = "8.0.21"

  # Authentication
  administrator_login    = var.db_username  # "mysqladmin" (NOT "admin")
  administrator_password = var.db_password

  # SKU
  sku_name = var.mysql_sku  # B_Standard_B2s (Burstable)

  # Storage
  storage {
    size_gb           = var.mysql_storage_gb  # 20
    auto_grow_enabled = true
  }

  # Backup
  backup_retention_days = 7

  # High Availability (Zone-Redundant)
  high_availability {
    mode = "ZoneRedundant"
  }

  # Network
  delegated_subnet_id = var.mysql_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.mysql.id

  tags = var.tags

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.mysql
  ]
}
```

### High Availability 옵션

**ZoneRedundant** (현재 사용):
```
Primary:  Zone 1
Standby:  Zone 2 (자동 동기 복제)
```

**장점**:
- Availability Zone 장애 시 자동 failover
- RPO: 0 (데이터 손실 없음)
- RTO: 60-120초

**비용**:
- 2배 (Primary + Standby 모두 과금)

**SameZone** (대안):
```
Primary:  Zone 1
Standby:  Zone 1 (동일 Zone)
```

**장점**:
- 저렴 (약 1.5배)
- VM 장애 시에는 failover 가능

**단점**:
- Zone 전체 장애 시 failover 불가

### Private DNS Zone

```hcl
resource "azurerm_private_dns_zone" "mysql" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "mysql-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = var.vnet_id
}
```

**작동 원리**:
1. MySQL Flexible Server가 VNet 내부 Private IP 할당
2. Private DNS Zone이 `mysql-dr-blue.mysql.database.azure.com` → `10.1.20.x` 매핑
3. AKS Pod가 DNS 쿼리 시 Private IP 반환

### Firewall Rules

```hcl
# Allow Azure Services
resource "azurerm_mysql_flexible_server_firewall_rule" "azure_services" {
  name                = "AllowAllAzureIPs"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# Allow specific IP (optional)
resource "azurerm_mysql_flexible_server_firewall_rule" "admin" {
  count               = var.admin_ip != "" ? 1 : 0
  name                = "AllowAdminIP"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  start_ip_address    = var.admin_ip
  end_ip_address      = var.admin_ip
}
```

**0.0.0.0 규칙의 의미**:
- Azure 내부 서비스만 접근 가능
- 인터넷에서는 접근 불가
- AKS, App Service, VM 등에서 접근 가능

### MySQL Configuration

```hcl
resource "azurerm_mysql_flexible_server_configuration" "character_set" {
  name                = "character_set_server"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "utf8mb4"
}

resource "azurerm_mysql_flexible_server_configuration" "collation" {
  name                = "collation_server"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "utf8mb4_unicode_ci"
}

resource "azurerm_mysql_flexible_server_configuration" "max_connections" {
  name                = "max_connections"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "500"
}
```

---

## 2.4 Application Gateway Module

### 개요
**경로**: `codes/azure/2-emergency/modules/appgw`

Azure Application Gateway를 생성하여 Layer 7 로드 밸런싱을 제공합니다.

### Application Gateway 구성

```hcl
resource "azurerm_application_gateway" "main" {
  name                = "appgw-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # SKU
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2  # Auto-scaling 시작 용량
  }

  # Auto-scaling
  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }

  # Gateway IP Configuration
  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = var.appgw_subnet_id
  }

  # Frontend IP Configuration (Public)
  frontend_ip_configuration {
    name                 = "appgw-frontend-ip"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Frontend Port
  frontend_port {
    name = "http-port"
    port = 80
  }

  # Backend Address Pool
  backend_address_pool {
    name = "aks-backend-pool"

    # WAS LoadBalancer External IP
    # AKS 배포 후 수동으로 업데이트 필요
    ip_addresses = var.backend_ip_addresses
  }

  # Backend HTTP Settings
  backend_http_settings {
    name                  = "http-settings"
    cookie_based_affinity = "Disabled"
    port                  = var.backend_port  # 8080
    protocol              = "Http"
    request_timeout       = 60

    probe_name = "health-probe"
  }

  # Health Probe
  probe {
    name                = "health-probe"
    protocol            = "Http"
    path                = var.health_probe_path  # "/"
    host                = var.backend_ip_addresses[0]
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3

    match {
      status_code = ["200-399"]
    }
  }

  # HTTP Listener
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "appgw-frontend-ip"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  # Routing Rule
  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "aks-backend-pool"
    backend_http_settings_name = "http-settings"
    priority                   = 100
  }

  # SSL Policy (HTTPS 사용 시)
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"  # TLS 1.2+
  }

  tags = var.tags
}
```

### Public IP

```hcl
resource "azurerm_public_ip" "appgw" {
  name                = "pip-appgw-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}
```

### Backend 업데이트 프로세스

**문제**: AKS WAS LoadBalancer IP는 배포 후에 알 수 있음

**해결 방법 1: Terraform 재실행** (현재 방식):
```bash
# 1. AKS 배포 완료 후 LoadBalancer IP 확인
WAS_LB_IP=$(kubectl get svc -n was was-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. terraform.tfvars 업데이트
echo "backend_ip_addresses = [\"$WAS_LB_IP\"]" >> terraform.tfvars

# 3. Terraform apply
terraform apply -target=module.appgw
```

**해결 방법 2: Azure CLI** (더 빠름):
```bash
WAS_LB_IP=$(kubectl get svc -n was was-service \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

az network application-gateway address-pool update \
  --resource-group rg-dr-blue \
  --gateway-name appgw-blue \
  --name aks-backend-pool \
  --servers $WAS_LB_IP

az network application-gateway probe update \
  --resource-group rg-dr-blue \
  --gateway-name appgw-blue \
  --name health-probe \
  --host $WAS_LB_IP
```

**해결 방법 3: Terraform Data Source** (이상적):
```hcl
# Kubernetes Provider 추가
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
}

# Service 조회
data "kubernetes_service" "was" {
  metadata {
    name      = "was-service"
    namespace = "was"
  }

  depends_on = [
    null_resource.deploy_was
  ]
}

# Application Gateway에서 사용
backend_address_pool {
  name         = "aks-backend-pool"
  ip_addresses = [
    data.kubernetes_service.was.status[0].load_balancer[0].ingress[0].ip
  ]
}
```

### WAF (Web Application Firewall) 활성화

```hcl
sku {
  name     = "WAF_v2"
  tier     = "WAF_v2"
  capacity = 2
}

waf_configuration {
  enabled          = true
  firewall_mode    = "Prevention"
  rule_set_type    = "OWASP"
  rule_set_version = "3.2"

  disabled_rule_group {
    rule_group_name = "REQUEST-942-APPLICATION-ATTACK-SQLI"
    rules           = [942100, 942200]  # False positive 방지
  }
}
```

**비용**:
- Standard_v2: $0.246/hour + $0.008/GB
- WAF_v2: $0.443/hour + $0.008/GB

---

**문서 버전**: v1.0
**최종 수정**: 2026-01-13
**작성자**: I2ST-blue
