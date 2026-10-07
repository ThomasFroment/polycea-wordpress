terraform {
  required_version = "~> 1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "polycea-wordpress-terraform-tfstate-bucket"
    key          = "terraform.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}