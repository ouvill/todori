data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-lambda-runtime"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
  statement {
    sid       = "ReadRuntimeSecretOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.runtime.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "runtime-boundary"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

data "aws_iam_policy_document" "github_deploy_assume" {
  count = var.enable_github_deploy_role ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.deploy_oidc_sub]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count              = var.enable_github_deploy_role ? 1 : 0
  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_deploy_assume[0].json
  tags               = local.tags
}

data "aws_iam_policy_document" "github_deploy" {
  count = var.enable_github_deploy_role ? 1 : 0
  statement {
    sid = "PushAndInspectServerImages"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImageScanFindings", "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = [data.aws_ecr_repository.server.arn]
  }
  statement {
    sid       = "AuthenticateToEcr"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "PublishAndMoveServerAlias"
    actions = [
      "lambda:GetAlias", "lambda:GetFunction", "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion", "lambda:UpdateAlias", "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
    ]
    resources = [
      aws_lambda_function.server.arn,
      "${aws_lambda_function.server.arn}:*",
    ]
  }
  statement {
    sid     = "ReadDeploymentSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.runtime.arn,
      data.aws_secretsmanager_secret.migration.arn,
      data.aws_secretsmanager_secret.deployment_provider.arn,
    ]
  }
  statement {
    sid       = "DownloadPinnedParametersExtension"
    actions   = ["lambda:GetLayerVersion"]
    resources = ["arn:aws:lambda:${var.aws_region}:187925254637:layer:AWS-Parameters-and-Secrets-Lambda-Extension:*"]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  count  = var.enable_github_deploy_role ? 1 : 0
  name   = "staging-deploy-boundary"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
