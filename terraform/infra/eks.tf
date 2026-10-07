resource "aws_eks_cluster" "EKSCluster" {
  name     = "eks-cluster-${var.project_name}-${var.environment}"
  role_arn = aws_iam_role.EKSClusterRole.arn

  vpc_config {
    subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
  }

  tags = {
    Name = "EKSCluster-${var.project_name}-${var.environment}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
  ]
}

resource "aws_eks_node_group" "EKSNodeGroup" {
  cluster_name    = aws_eks_cluster.EKSCluster.name
  node_group_name = "eks-node-group-${var.project_name}-${var.environment}"
  node_role_arn   = aws_iam_role.EKSNodeGroupRole.arn
  subnet_ids      = [aws_subnet.private[0].id, aws_subnet.private[1].id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = var.eks_instance_types

  tags = {
    Name = "EKSNodeGroup-${var.project_name}-${var.environment}"
  }
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly
  ]
}


