# ─────────────────────────────────────────
# EKS CLUSTER — Control Plane
# ─────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster_role.arn

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    # Control plane sits in your private subnets
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.eks_cluster_sg.id]

    # Nodes talk to API server privately inside the VPC
    endpoint_private_access = true

    # You can still reach it from your machine via kubectl
    endpoint_public_access = true
    public_access_cidrs    = var.allowed_cidr_blocks
  }

  tags = {
    Name        = "${var.project_name}-cluster"
    Environment = var.environment
  }

  # Cluster needs the IAM policy attached BEFORE it is created
  # and the log group must exist first
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# ─────────────────────────────────────────
# EKS MANAGED NODE GROUP
# These are the EC2 instances that actually
# run your pods. AWS manages OS patching,
# node provisioning and updates for you.
# ─────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  # Nodes go into private subnets — they never
  # need a public IP. They reach ECR and AWS APIs
  # through your NAT gateway
  subnet_ids = aws_subnet.private[*].id

  instance_types = [var.node_instance_type]

  scaling_config {
    desired_size = 2 # start with 2 nodes
    min_size     = 1 # never go below 1
    max_size     = 3 # can scale up to 3
  }

  update_config {
    # Only take down 1 node at a time during updates
    # so your workloads keep running
    max_unavailable = 1
  }

  # All three policies must be attached to the node role
  # before any node can join the cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only,
  ]

  tags = {
    Name        = "${var.project_name}-node-group"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# TLS CERTIFICATE
# Fetches the fingerprint of the OIDC endpoint
# AWS uses this to verify tokens are genuinely
# coming from your EKS cluster and not forged
# ─────────────────────────────────────────
data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}


# ─────────────────────────────────────────
# OIDC PROVIDER
# Registers your cluster's OIDC endpoint
# with AWS IAM so they can trust each other
# ─────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name        = "${var.project_name}-ebs-csi-addon"
    Environment = var.environment
  }
}