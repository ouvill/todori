data "aws_ecr_repository" "server" {
  name = "${local.name}-server"
}
