variable "project_name" {
  description = "The name of the project."
  type        = string
}

variable "role_arn" {
  description = "The ARN of the role to assume."
  type        = string
}

variable "environment" {
  description = "The environment for the resources."
  type        = string
}