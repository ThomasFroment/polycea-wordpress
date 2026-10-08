resource "random_password" "rds" {
  length = 16
}

resource "aws_ssm_parameter" "rds_password" {
  name  = "/${var.project_name}/${var.environment}/db-password"
  type  = "SecureString"
  value = random_password.rds.result
}

resource "aws_ssm_parameter" "rds_username" {
  name  = "/${var.project_name}/${var.environment}/db-username"
  type  = "String"
  value = var.project_name_short
}

resource "aws_ssm_parameter" "rds_endpoint" {
  name  = "/${var.project_name}/${var.environment}/db-endpoint"
  type  = "String"
  value = aws_db_instance.this.endpoint
}

resource "aws_ssm_parameter" "rds_name" {
  name  = "/${var.project_name}/${var.environment}/db-name"
  type  = "String"
  value = aws_db_instance.this.db_name
}

resource "aws_db_instance" "this" {
  allocated_storage = 20
  db_name           = "mydb-${local.name_suffix}"
  engine            = "mysql"
  engine_version    = "8.4.11"
  instance_class    = var.rds_instance_type

  username = var.project_name_short
  password = random_password.rds.result

  skip_final_snapshot = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az = var.rds_multi_az
}

resource "aws_db_subnet_group" "this" {
  name       = "rds-subnet-${local.name_suffix}"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_vpc_security_group_ingress_rule" "allow_rds" {
  security_group_id            = aws_security_group.rds.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group" "rds" {
  name   = "rds-sg-${local.name_suffix}"
  vpc_id = aws_vpc.vpc.id
}