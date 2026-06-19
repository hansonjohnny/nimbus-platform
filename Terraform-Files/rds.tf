# ─────────────────────────────────────────
# RDS — PostgreSQL 16
# One shared cluster; each service owns its
# own schema (auth, catalog, cart, orders).
# Credentials are stored in Secrets Manager
# and injected via External Secrets Operator.
# ─────────────────────────────────────────

# ── Subnet group (private subnets only) ───
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-db-subnet-group"
    Environment = var.environment
  }
}

# ── Random master password ─────────────────
resource "random_password" "db" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:?"
}

# ── Secrets Manager — store master password ─
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}/${var.environment}/db-password"
  description             = "Master password for the ${var.project_name} RDS PostgreSQL instance"
  recovery_window_in_days = 0 # 0 = immediate deletion (safe for dev); increase for prod

  tags = {
    Name        = "${var.project_name}-db-password"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

# ── RDS instance ───────────────────────────
resource "aws_db_instance" "main" {
  identifier        = "${var.project_name}-postgres"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # ── Availability ──────────────────────────
  multi_az            = true # standby replica in second AZ
  publicly_accessible = false

  # ── Backup / protection ───────────────────
  backup_retention_period = 7
  skip_final_snapshot     = true  # set false for production
  deletion_protection     = false # set true for production

  # ── Observability ─────────────────────────
  performance_insights_enabled = true

  tags = {
    Name        = "${var.project_name}-postgres"
    Environment = var.environment
  }
}
