data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "helm_oidc" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      values   = ["sts.amazonaws.com"]
      variable = "token.actions.githubusercontent.com:aud"
    }

    condition {
      test     = "StringLike"
      values   = ["repo:ThomasFroment@97841826/polycea-wordpress@1407865294:*"]
      variable = "token.actions.githubusercontent.com:sub"
    }
  }
}

resource "aws_iam_role" "helm_oidc" {
  name               = "github-oidc-role-helm-${var.project_name_short}"
  assume_role_policy = data.aws_iam_policy_document.helm_oidc.json
}

data "aws_iam_policy_document" "helm_oidc_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = [aws_eks_cluster.this.arn]
  }
}

resource "aws_iam_role_policy" "helm_oidc" {
  name   = "EKSDescribeCluster"
  role   = aws_iam_role.helm_oidc.id
  policy = data.aws_iam_policy_document.helm_oidc_permissions.json
}

resource "aws_eks_access_entry" "helm_oidc" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.helm_oidc.arn
}

resource "aws_eks_access_policy_association" "helm_oidc" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.helm_oidc.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [kubernetes_namespace_v1.this.metadata[0].name]
  }

  depends_on = [aws_eks_access_entry.helm_oidc]
}