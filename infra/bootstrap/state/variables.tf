variable "aws_account_id" {
  type = string
}
variable "aws_region" {
  type    = string
  default = "eu-central-1"
}
variable "environment" {
  type = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be staging or production"
  }
}
variable "state_bucket_name" {
  type = string
}
variable "github_repository" {
  type = string
}
