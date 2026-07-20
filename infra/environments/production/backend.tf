terraform {
  backend "s3" {
    key          = "production/deployment.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
