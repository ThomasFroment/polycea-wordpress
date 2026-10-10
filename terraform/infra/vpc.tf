resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC-${local.name_suffix}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "IGW-${local.name_suffix}"
  }
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "PublicSubnet-${count.index == 0 ? "A" : "B"}-${local.name_suffix}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "PrivateSubnet-${count.index == 0 ? "A" : "B"}-${local.name_suffix}"
  }
}

resource "aws_eip" "nat" {
  count      = var.only_one_nat_gateway ? 1 : 2
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name = "EIP-${count.index == 0 ? "A" : "B"}-${local.name_suffix}"
  }
}

resource "aws_nat_gateway" "nat" {
  count         = var.only_one_nat_gateway ? 1 : 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name = "NAT-${count.index == 0 ? "A" : "B"}-${local.name_suffix}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "PublicRT-${local.name_suffix}"
  }
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[var.only_one_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = "PrivateRT-${count.index == 0 ? "A" : "B"}-${local.name_suffix}"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}