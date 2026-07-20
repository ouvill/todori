terraform {
  backend "s3" {
    key          = "staging/deployment.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
