data "aws_secretsmanager_secret" "runtime" {
  name = local.runtime_secret
}

data "aws_secretsmanager_secret" "migration" {
  name = local.migration_secret
}

data "aws_secretsmanager_secret" "deployment_provider" {
  name = local.provider_secret
}
