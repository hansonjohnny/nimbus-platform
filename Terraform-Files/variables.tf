variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
  default     = "nimbus-retail"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "iam_admin_user" {
  description = "IAM admin username"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = <<EOT
CIDRs allowed to reach the Kubernetes API server (kubectl).
"0.0.0.0/0" = open to all (fine for dev).
Your IP only = more secure: ["YOUR.IP.HERE/32"]
EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.32"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "c7i-flex.large"
}

variable "jenkins_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "m7i-flex.large"
}

variable "jenkins_ssh_cidr" {
  description = "CIDR block allowed to SSH into Jenkins — restrict to your IP e.g. 105.x.x.x/32"
  type        = string
  default     = "0.0.0.0/0"
}


