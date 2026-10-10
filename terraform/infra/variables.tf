variable "project_name" {
  description = "The name of the project."
  type        = string
}

variable "project_name_short" {
  description = "A short name for the project."
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

variable "eks_admin_role_arn" {
  description = "The ARN of the EKS admin role."
  default     = ""
  sensitive   = true
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

variable "rds_instance_type" {
  description = "The instance type for the RDS."
  default     = "db.t3.micro"
  type        = string
}

variable "rds_multi_az" {
  description = "Whether to create the RDS instance in multiple AZs (true) or a single AZ (false)."
  default     = true
  type        = bool
}

variable "rds_db_name" {
  description = "The name of the RDS database (alphanumeric only)."
  default     = "mydb"
  type        = string
}

variable "rds_username" {
  description = "The username for the RDS database (alphanumeric only)."
  default     = "admin"
  type        = string
}