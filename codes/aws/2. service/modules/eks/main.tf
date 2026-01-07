# aws/modules/eks/main.tf
# EKS 클러스터 및 노드 그룹 모듈

terraform {
  required_version = ">= 1.14.0"
}

# =================================================
# EKS 삭제 전 Kubernetes 생성 AWS 리소스 정리
# =================================================
# AWS Load Balancer Controller가 생성한 ALB/NLB, Target Group 등을
# EKS 클러스터 삭제 전에 먼저 정리합니다.

resource "null_resource" "cleanup_k8s_resources" {
  triggers = {
    cluster_name = "${var.environment}-eks"
    vpc_id       = var.vpc_id
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    on_failure  = continue
    command     = <<-BASH
      set -e
      echo "=== Starting cleanup of Kubernetes-created AWS resources ==="

      VPC_ID="${self.triggers.vpc_id}"

      # AWS CLI 기본 region 사용 (AWS_DEFAULT_REGION 환경 변수 또는 ~/.aws/config)
      # 기본값으로 ap-northeast-2 사용
      AWS_REGION=$${AWS_DEFAULT_REGION:-ap-northeast-2}

      echo "VPC ID: $VPC_ID"
      echo "Region: $AWS_REGION"

      # 1. VPC 내 모든 Load Balancer 조회 및 삭제
      echo "Step 1: Deleting Load Balancers in VPC $VPC_ID..."
      LB_ARNS=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")

      if [ -n "$LB_ARNS" ]; then
        for lb_arn in $LB_ARNS; do
          echo "  - Deleting Load Balancer: $lb_arn"
          aws elbv2 delete-load-balancer \
            --region "$AWS_REGION" \
            --load-balancer-arn "$lb_arn" 2>/dev/null || true
        done

        # ALB/NLB 삭제 대기
        echo "  - Waiting for Load Balancers to be deleted (30s)..."
        sleep 30
      else
        echo "  - No Load Balancers found"
      fi

      # 2. VPC 내 모든 Target Group 삭제
      echo "Step 2: Deleting Target Groups in VPC $VPC_ID..."
      TG_ARNS=$(aws elbv2 describe-target-groups \
        --region "$AWS_REGION" \
        --query "TargetGroups[?VpcId=='$VPC_ID'].TargetGroupArn" \
        --output text 2>/dev/null || echo "")

      if [ -n "$TG_ARNS" ]; then
        for tg_arn in $TG_ARNS; do
          echo "  - Deleting Target Group: $tg_arn"
          aws elbv2 delete-target-group \
            --region "$AWS_REGION" \
            --target-group-arn "$tg_arn" 2>/dev/null || true
        done
      else
        echo "  - No Target Groups found"
      fi

      # 3. VPC 내 모든 ENI (Elastic Network Interface) 정리
      echo "Step 3: Cleaning up Network Interfaces in VPC $VPC_ID..."

      # 3-1. ELB 관련 ENI 찾기 (Description에 ELB 포함)
      ELB_ENI_IDS=$(aws ec2 describe-network-interfaces \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query "NetworkInterfaces[?contains(Description, 'ELB')].NetworkInterfaceId" \
        --output text 2>/dev/null || echo "")

      if [ -n "$ELB_ENI_IDS" ]; then
        for eni_id in $ELB_ENI_IDS; do
          echo "  - Detaching and deleting ELB ENI: $eni_id"

          # Attachment가 있으면 먼저 detach
          ATTACHMENT_ID=$(aws ec2 describe-network-interfaces \
            --region "$AWS_REGION" \
            --network-interface-ids "$eni_id" \
            --query 'NetworkInterfaces[0].Attachment.AttachmentId' \
            --output text 2>/dev/null || echo "")

          if [ -n "$ATTACHMENT_ID" ] && [ "$ATTACHMENT_ID" != "None" ]; then
            echo "    - Detaching attachment: $ATTACHMENT_ID"
            aws ec2 detach-network-interface \
              --region "$AWS_REGION" \
              --attachment-id "$ATTACHMENT_ID" \
              --force 2>/dev/null || true
            sleep 5
          fi

          # ENI 삭제
          aws ec2 delete-network-interface \
            --region "$AWS_REGION" \
            --network-interface-id "$eni_id" 2>/dev/null || true
        done

        echo "  - Waiting for ELB ENIs to be deleted (15s)..."
        sleep 15
      else
        echo "  - No ELB ENIs found"
      fi

      # 3-2. Available 상태 ENI 삭제
      AVAILABLE_ENI_IDS=$(aws ec2 describe-network-interfaces \
        --region "$AWS_REGION" \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
        --query "NetworkInterfaces[].NetworkInterfaceId" \
        --output text 2>/dev/null || echo "")

      if [ -n "$AVAILABLE_ENI_IDS" ]; then
        for eni_id in $AVAILABLE_ENI_IDS; do
          echo "  - Deleting available ENI: $eni_id"
          aws ec2 delete-network-interface \
            --region "$AWS_REGION" \
            --network-interface-id "$eni_id" 2>/dev/null || true
        done
      else
        echo "  - No available ENIs found"
      fi

      # 4. Lambda ENI 및 기타 ENI 정리 (재시도)
      echo "Step 4: Final ENI cleanup (retry for any remaining ENIs)..."

      for i in {1..3}; do
        REMAINING_ENIS=$(aws ec2 describe-network-interfaces \
          --region "$AWS_REGION" \
          --filters "Name=vpc-id,Values=$VPC_ID" \
          --query "NetworkInterfaces[?Status=='available' || contains(Description, 'ELB') || contains(Description, 'Lambda')].NetworkInterfaceId" \
          --output text 2>/dev/null || echo "")

        if [ -n "$REMAINING_ENIS" ]; then
          echo "  - Retry $i: Found remaining ENIs"
          for eni_id in $REMAINING_ENIS; do
            echo "    - Deleting ENI: $eni_id"
            aws ec2 delete-network-interface \
              --region "$AWS_REGION" \
              --network-interface-id "$eni_id" 2>/dev/null || true
          done
          sleep 10
        else
          echo "  - No remaining ENIs found"
          break
        fi
      done

      # 5. 최종 대기
      echo "Step 5: Final wait for all dependencies to be resolved (30s)..."
      sleep 30

      echo "=== Cleanup completed ==="
    BASH
  }
}

# =================================================
# EKS 클러스터 IAM Role
# =================================================

resource "aws_iam_role" "eks_cluster" {
  name = "${var.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.environment}-eks-cluster-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# =================================================
# EKS 클러스터
# =================================================

resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.web_subnet_ids, var.was_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = {
    Name        = "${var.environment}-eks"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]
}

# =================================================
# EKS 노드 그룹 IAM Role
# =================================================

resource "aws_iam_role" "eks_nodes" {
  name = "${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Name        = "${var.environment}-eks-node-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# =================================================
# EKS 노드 그룹 - Web Tier
# =================================================

resource "aws_eks_node_group" "web" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-web-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.web_subnet_ids

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.web_desired_size
    max_size     = var.web_max_size
    min_size     = var.web_min_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    tier = "web"
  }

  tags = {
    Name        = "${var.environment}-web-nodes"
    Environment = var.environment
    Tier        = "Web"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}

# =================================================
# EKS 노드 그룹 - WAS Tier
# =================================================

resource "aws_eks_node_group" "was" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-was-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.was_subnet_ids

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = var.was_desired_size
    max_size     = var.was_max_size
    min_size     = var.was_min_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    tier = "was"
  }

  tags = {
    Name        = "${var.environment}-was-nodes"
    Environment = var.environment
    Tier        = "WAS"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]
}

# =================================================
# EKS Add-ons
# =================================================

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_node_group.web,
    aws_eks_node_group.was,
  ]
}

# =================================================
# CloudWatch Observability Add-on (Container Insights)
# =================================================
# 이 애드온은 CloudWatch Agent와 Fluent Bit를 자동으로 설치하여
# Container Insights 메트릭과 로그를 수집합니다.
# 수동으로 CloudWatch Agent를 설치할 필요가 없습니다.

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "amazon-cloudwatch-observability"

  depends_on = [
    aws_eks_node_group.web,
    aws_eks_node_group.was,
  ]
}

# CloudWatch Observability 애드온에 필요한 IAM 정책
resource "aws_iam_role_policy_attachment" "cloudwatch_agent_server_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_nodes.name
}
