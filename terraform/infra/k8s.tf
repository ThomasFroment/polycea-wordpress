data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.project_name
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this
  ]
}

resource "kubernetes_storage_class_v1" "this" {
  metadata {
    name = "efs-sc"
  }
  storage_provisioner = "efs.csi.aws.com"
  reclaim_policy      = "Retain"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = aws_efs_file_system.this.id
    directoryPerms   = "700"
    uid              = "1001"
    gid              = "1001"
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
    aws_eks_addon.efs_csi
  ]
}

resource "kubernetes_secret_v1" "rds" {
  metadata {
    name      = "rds-credentials"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    username = aws_db_instance.this.username
    password = aws_db_instance.this.password
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_access_entry.this,
    aws_eks_access_policy_association.this,
  ]
}