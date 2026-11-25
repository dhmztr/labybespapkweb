resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}-db-credentials"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = "unter_user"
    password = random_password.db_password.result
    dbname   = "unter_db"
  })
}

# RDS PostgreSQL 16 (Single-AZ, db.t4g.micro)
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "unter_db"
  username               = "unter_user"
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false
  backup_retention_period = 1
  skip_final_snapshot    = true
  deletion_protection    = false
  backup_window           = "03:00-04:00"
  apply_immediately       = true

}

# ElastiCache Redis (single-node, cache.t4g.micro)
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-redis-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.project_name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.cache.id]
}
