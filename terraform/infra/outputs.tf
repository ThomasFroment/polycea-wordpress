output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "efs_id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.efs.id
}

output "rds_name" {
  description = "The name of the RDS database"
  value       = aws_db_instance.this.db_name
}

output "rds_endpoint" {
  description = "The endpoint of the RDS database"
  value       = aws_db_instance.this.endpoint
}

output "rds_username" {
  description = "The username for the RDS database"
  value       = var.project_name_short
}