terraform {
  required_version = ">= 1.12.0, < 1.13.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.55.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
  }
}

provider "aws" {
  region              = "eu-central-1"
  allowed_account_ids = [var.aws_account_id]
  default_tags {
    tags = {
      Project     = "taskveil"
      Environment = "production"
      ManagedBy   = "OpenTofu"
    }
  }
}

provider "cloudflare" {}
