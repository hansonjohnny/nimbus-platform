# ─────────────────────────────────────────
# ECR REPOSITORIES
# One repository per application service.
# Jenkins builds and pushes images here;
# EKS pulls from here at deploy time.
# ─────────────────────────────────────────

locals {
  services = [
    "auth-service",
    "catalog-service",
    "cart-service",
    "order-service",
    "notification-service",
    "frontend",
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}/${each.key}"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────
# LIFECYCLE POLICY
# Keep the last 10 tagged images per repo
# to avoid unbounded storage growth.
# ─────────────────────────────────────────

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
