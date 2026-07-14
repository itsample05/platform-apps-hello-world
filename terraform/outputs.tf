output "application_url" {
  value = "http://${aws_lb.this.dns_name}"
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "github_repository" {
  value = var.github_repository
}

output "aws_region" {
  value = var.aws_region
}

output "app_name" {
  value = var.app_name
}

output "container_image" {
  value = var.container_image
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ecs_task_family" {
  value = aws_ecs_task_definition.app.family
}
