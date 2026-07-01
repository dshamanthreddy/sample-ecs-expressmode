output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing images."
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "task_definition_family" {
  description = "Task definition family name."
  value       = aws_ecs_task_definition.app.family
}

output "github_actions_role_arn" {
  description = "IAM role ARN for the GitHub Actions OIDC deploy workflow."
  value       = aws_iam_role.github_actions.arn
}
