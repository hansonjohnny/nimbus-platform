# ─────────────────────────────────────────
# ELASTICACHE — Redis 7
# Used by catalog-service (product cache)
# and cart-service (session / cart storage).
# ─────────────────────────────────────────

# ── Subnet group (private subnets only) ───
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.project_name}-redis-subnet-group"
    Environment = var.environment
  }
}

# ── ElastiCache cluster ────────────────────
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.1"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  tags = {
    Name        = "${var.project_name}-redis"
    Environment = var.environment
    UsedBy      = "catalog-service cart-service"
  }
}
