# aws/modules/eks/main.tf
# EKS 클러스터 및 노드 그룹 모듈

terraform {
  required_version = ">= 1.14.0"
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
