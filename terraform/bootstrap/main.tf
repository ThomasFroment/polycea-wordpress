terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3"

  assume_role {
    role_arn     = var.role_arn
    session_name = "${var.project_name}-${var.environment}-terraform"
  }

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

resource "aws_s3_bucket" "terraformState" {
  bucket        = "${var.project_name}-tfstate-bucket"
  force_destroy = true

  tags = {
    Name = "Terraform State Bucket"
  }
}