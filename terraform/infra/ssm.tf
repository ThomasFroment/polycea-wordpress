resource "aws_ssm_parameter" "rds_password" {
  name  = "/${aws_db_instance.this.db_name}/${var.environment}/db-password"
  type  = "SecureString"
  value = random_password.rds.result
}