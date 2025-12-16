# aws/s3-vpc-endpoint.tf
# S3 VPC Endpoint 설정 (Azure VM에서 S3 접근용)

# =================================================
# S3 Gateway Endpoint
# =================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  
  route_table_ids = [
    module.vpc.private_route_table_id
  ]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      }
    ]
  })
  
  tags = {
    Name = "s3-endpoint-${var.environment}"
  }
}

# =================================================
# S3 Bucket Policy (외부 접근 허용)
# =================================================

resource "aws_s3_bucket_policy" "backup_external_access" {
  bucket = aws_s3_bucket.backup.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAzureVMAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.azure_vm_s3_access.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      }
    ]
  })
}

# =================================================
# IAM User for Azure VM (S3 Access)
# =================================================

resource "aws_iam_user" "azure_vm_s3_access" {
  name = "azure-vm-s3-access-${var.environment}"
  path = "/service-accounts/"
  
  tags = {
    Name        = "azure-vm-s3-access"
    Environment = var.environment
    Purpose     = "Azure VM S3 백업 동기화"
  }
}

resource "aws_iam_access_key" "azure_vm" {
  user = aws_iam_user.azure_vm_s3_access.name
}

resource "aws_iam_user_policy" "azure_vm_s3" {
  name = "s3-backup-access"
  user = aws_iam_user.azure_vm_s3_access.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
      }
    ]
  })
}

# =================================================
# Outputs
# =================================================

output "s3_vpc_endpoint_id" {
  description = "S3 VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "azure_vm_aws_access_key_id" {
  description = "Azure VM용 AWS Access Key ID"
  value       = aws_iam_access_key.azure_vm.id
  sensitive   = true
}

output "azure_vm_aws_secret_access_key" {
  description = "Azure VM용 AWS Secret Access Key"
  value       = aws_iam_access_key.azure_vm.secret
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 백업 버킷 이름"
  value       = aws_s3_bucket.backup.id
}
