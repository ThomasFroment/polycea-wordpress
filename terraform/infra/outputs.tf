output "eks_cluster_name" {
  description = "The name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "rds_name" {
  description = "The name of the RDS database"
  value       = aws_db_instance.this.db_name
}

output "rds_address" {
  description = "The address of the RDS database"
  value       = aws_db_instance.this.address
}

output "rds_username" {
  description = "The username for the RDS database"
  value       = aws_db_instance.this.username
}

output "rds_password" {
  description = "The password for the RDS database"
  sensitive   = true
  value       = random_password.rds.result
}

output "k8s_namespace" {
  description = "The name of the Kubernetes namespace"
  value       = kubernetes_namespace_v1.this.metadata[0].name
}
