variable "project_name" {
  description = "The name of the project."
  type        = string
}

variable "project_name_short" {
  description = "A short name for the project."
  type        = string
}

variable "environment" {
  description = "The environment for the resources."
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  default     = "eu-west-3"
  type        = string
}

variable "oidc_subject" {
  description = "The OIDC subject for the GitHub Actions workflow."
  type        = string
}