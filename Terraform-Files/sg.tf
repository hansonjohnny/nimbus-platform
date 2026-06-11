# ─────────────────────────────────────────
# CONTROL PLANE SECURITY GROUP
# Controls traffic to/from the EKS API server
# ─────────────────────────────────────────
resource "aws_security_group" "eks_cluster_sg" {
  name                   = "${var.project_name}-cluster-sg"
  description            = "Security group for EKS control plane"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = false

  # Your machine/CI-CD → Kubernetes API server (kubectl)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "Allow kubectl access"
  }

  # Control plane → AWS APIs, nodes, OIDC endpoint
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.project_name}-eks-cluster-sg"
    Environment = var.environment
  }
}


# ─────────────────────────────────────────
# WORKER NODES SECURITY GROUP
# Controls traffic to/from your EC2 nodes
# ─────────────────────────────────────────
resource "aws_security_group" "eks_nodes_sg" {
  name                   = "${var.project_name}-nodes-sg"
  description            = "Security group for EKS worker nodes"
  vpc_id                 = aws_vpc.main.id
  revoke_rules_on_delete = false

  # Node-to-node traffic — pods on different nodes talk to each other
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow node-to-node and pod-to-pod traffic"
  }

  # Control plane → nodes on ephemeral ports
  # Used for: health checks, kubectl exec, kubectl logs, port-forward
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
    description     = "Allow control plane to reach nodes"
  }

  # Control plane → nodes HTTPS
  # Required for admission webhooks (ArgoCD, cert-manager etc.)
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster_sg.id]
    description     = "Allow HTTPS from control plane for webhooks"
  }

  # Nodes → ECR (pull images), CloudWatch (logs),
  # AWS APIs, internet via your NAT gateway
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.project_name}-eks-nodes-sg"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# SECURITY GROUP — JENKINS EC2
# ─────────────────────────────────────────
resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins EC2 server"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_ssh_cidr]
    description = "SSH access - my IP only"
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_ssh_cidr] # ← reuse same IP variable
    description = "Jenkins UI - my IP only"
  }
  ingress {
    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"
    cidr_blocks = [
      "192.30.252.0/22",
      "185.199.108.0/22",
      "140.82.112.0/20",
      "143.55.64.0/20"
    ]
    description = "Jenkins - GitHub webhook IPs only"
  }

  ingress {
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.jenkins_ssh_cidr] # ← reuse same IP variable
    description = "SonarQube UI - my IP only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name        = "${var.project_name}-jenkins-sg"
    Environment = var.environment
  }
}