output "api_base_url" {
  value = "https://${local.api_domain}"
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.server.repository_url
}

output "ecr_repository_name" {
  value = data.aws_ecr_repository.server.name
}

output "lambda_function_name" {
  value = aws_lambda_function.server.function_name
}

output "lambda_alias" {
  value = aws_lambda_alias.live.name
}

output "secret_arns" {
  value = {
    runtime             = data.aws_secretsmanager_secret.runtime.arn
    migration           = data.aws_secretsmanager_secret.migration.arn
    deployment_provider = data.aws_secretsmanager_secret.deployment_provider.arn
  }
}

output "github_deploy_role_arn" {
  value = try(aws_iam_role.github_deploy[0].arn, null)
}
