# ─────────────────────────────────────────
# POLICY ATTACHMENTS — CLUSTER ROLE POLICIES
# ─────────────────────────────────────────

# Gives the control plane everything it needs to run EKS
# (manage network interfaces, security groups, load balancers)
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─────────────────────────────────────────
# POLICY ATTACHMENTS — NODE ROLE POLICIES
# ─────────────────────────────────────────

# Allows nodes to register with the cluster and report status
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# Allows the VPC CNI plugin to assign IPs from your subnet to pods
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# Allows nodes to pull container images from ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ─────────────────────────────────────────
# POLICY ATTACHMENTS — JENKINS EC2 ROLE
# ─────────────────────────────────────────

resource "aws_iam_role_policy" "jenkins_ecr" {
  name = "${var.project_name}-jenkins-ecr-policy"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "AllowECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_eks_full" {
  name = "${var.project_name}-jenkins-eks-policy"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:AccessKubernetesApi",
          "eks:UpdateClusterConfig"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["sts:AssumeRole"]
        Resource = [
          aws_iam_role.eks_node_role.arn,
          aws_iam_role.eks_cluster_role.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_eks_addons" {
  name = "${var.project_name}-jenkins-eks-addons"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "eks:CreateAddon",
        "eks:DescribeAddon",
        "eks:UpdateAddon",
        "eks:DeleteAddon",
        "eks:ListAddons"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ec2_readonly" {
  role       = aws_iam_role.jenkins_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_role_policy" "jenkins_terraform_state" {
  name = "${var.project_name}-jenkins-terraform-state"
  role = aws_iam_role.jenkins_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::cloud-native-terraform-state",
          "arn:aws:s3:::cloud-native-terraform-state/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:us-east-2:493042495566:table/cloud-native-dynamodb-lock"
      }
    ]
  })
}