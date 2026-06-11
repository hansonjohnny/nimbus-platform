# ─────────────────────────────────────────
# CLUSTER ROLE
# Assumed by the EKS control plane itself
# ─────────────────────────────────────────
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-eks-cluster-role"
    Environment = var.environment
  }
}


# ─────────────────────────────────────────
# NODE ROLE
# Assumed by your EC2 worker nodes
# ─────────────────────────────────────────
resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-eks-node-role"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# JENKINS IAM ROLE
# Assumed by the EC2 instance running Jenkins
# ─────────────────────────────────────────
resource "aws_iam_role" "jenkins_ec2" {
  name        = "${var.project_name}-jenkins-role"
  description = "Role assumed by Jenkins EC2 instance"

  # Trust policy — only EC2 instances can assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.project_name}-jenkins-ec2-role"
    Environment = var.environment
  }
}

resource "aws_iam_instance_profile" "jenkins_ec2" {
  name = "${var.project_name}-jenkins-instance-profile"
  role = aws_iam_role.jenkins_ec2.name

  tags = {
    Name        = "${var.project_name}-jenkins-instance-profile"
    Environment = var.environment
  }
}
