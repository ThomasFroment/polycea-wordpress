resource "aws_eks_cluster" "this" {
  name     = "eks-cluster-${local.name_suffix}"
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  }

  tags = {
    Name = "EKSCluster-${local.name_suffix}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

resource "aws_eks_access_entry" "this" {
  count         = var.eks_admin_role_arn != "" ? 1 : 0
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.eks_admin_role_arn
}

resource "aws_eks_access_policy_association" "this" {
  count         = var.eks_admin_role_arn != "" ? 1 : 0
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.eks_admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.this
  ]
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "eks-node-group-${local.name_suffix}"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [aws_subnet.private[0].id, aws_subnet.private[1].id]

  scaling_config {
    desired_size = var.eks_desired_size
    max_size     = var.eks_max_size
    min_size     = var.eks_min_size
  }

  instance_types = var.eks_instance_types

  tags = {
    Name = "EKSNodeGroup-${local.name_suffix}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]

  lifecycle {
    replace_triggered_by = [
      aws_eks_cluster.this,
    ]
  }
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "aws-efs-csi-driver"

  depends_on = [aws_eks_pod_identity_association.efs_csi, aws_eks_node_group.this]

  lifecycle {
    replace_triggered_by = [
      aws_eks_cluster.this,
    ]
  }
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "eks-pod-identity-agent"

  lifecycle {
    replace_triggered_by = [
      aws_eks_cluster.this,
    ]
  }
}