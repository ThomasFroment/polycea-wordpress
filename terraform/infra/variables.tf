variable "project_name" {
  description = "The name of the project."
  type        = string
}

variable "region" {
  description = "The AWS region to deploy resources in."
  default     = "eu-west-3"
  type        = string
}

variable "environment" {
  description = "The environment for the resources."
  type        = string
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC."
  default     = "10.1.0.0/16"
  type        = string
}

variable "public_subnet_cidr_blocks" {
  description = "The CIDR blocks for the public subnets."
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  type        = list(string)
}

variable "private_subnet_cidr_blocks" {
  description = "The CIDR blocks for the private subnets."
  default     = ["10.1.3.0/24", "10.1.4.0/24"]
  type        = list(string)
}

variable "only_one_nat_gateway" {
  description = "Whether to create only one NAT gateway (true) or two (false)."
  default     = false
  type        = bool
}

variable "eks_instance_types" {
  description = "The instance types for the EKS node group."
  default     = ["t3.small"]
  type        = list(string)
}