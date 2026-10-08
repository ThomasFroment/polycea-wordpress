resource "aws_efs_file_system" "efs" {
  creation_token = "efs-${local.name_suffix}"

  tags = {
    Name = "EFS-${local.name_suffix}"
  }
}

resource "aws_efs_mount_target" "efs" {
  count           = 2
  file_system_id  = aws_efs_file_system.efs.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_ssm_parameter" "efs" {
  name  = "/${var.project_name}/${var.environment}/efs-id"
  type  = "String"
  value = aws_efs_file_system.efs.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_nfs_ipv4" {
  security_group_id            = aws_security_group.efs.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

resource "aws_security_group" "efs" {
  name   = "efs-sg-${local.name_suffix}"
  vpc_id = aws_vpc.vpc.id
}