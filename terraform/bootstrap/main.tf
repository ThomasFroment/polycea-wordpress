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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket        = "${var.project_name}-terraform-tfstate-bucket"
  force_destroy = true

  tags = {
    Name = "Terraform State Bucket"
  }
}

resource "aws_iam_openid_connect_provider" "terraform_oidc" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]
}

data "aws_iam_policy_document" "terraform_oidc" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.terraform_oidc.arn]
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

resource "aws_iam_role" "terraform_oidc" {
  name               = "github-oidc-role-terraform-${var.project_name_short}"
  assume_role_policy = data.aws_iam_policy_document.terraform_oidc.json
}

resource "aws_iam_role_policy_attachment" "terraform_oidc" {
  role       = aws_iam_role.terraform_oidc.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}