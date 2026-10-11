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

data "aws_iam_policy_document" "efs_csi_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "efs_csi" {
  name               = "EKS_EFS_CSI_PodIdentityRole-${local.name_suffix}"
  assume_role_policy = data.aws_iam_policy_document.efs_csi_assume_role.json
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role       = aws_iam_role.efs_csi.name
}

resource "aws_eks_pod_identity_association" "efs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "efs-csi-controller-sa"
  role_arn        = aws_iam_role.efs_csi.arn

  depends_on = [aws_eks_addon.pod_identity]
}