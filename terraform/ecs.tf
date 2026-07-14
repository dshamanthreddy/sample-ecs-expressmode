locals {
  is_fargate = var.compute_type == "FARGATE"
  is_mi      = var.compute_type == "MANAGED_INSTANCES"
}

resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "app" {
  family = "${local.name_prefix}-task"
  # Managed Instances register as EC2 container instances, so tasks use EC2
  # compatibility; Fargate uses FARGATE.
  requires_compatibilities = local.is_fargate ? ["FARGATE"] : ["EC2"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "nginx"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "nginx"
        }
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  # Fargate uses launch_type; Managed Instances use a capacity provider strategy.
  launch_type = local.is_fargate ? "FARGATE" : null

  dynamic "capacity_provider_strategy" {
    for_each = local.is_mi ? [1] : []
    content {
      capacity_provider = aws_ecs_capacity_provider.mi[0].name
      weight            = 1
      base              = 0
    }
  }

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.ecs_tasks.id]
    # Public IP on the task ENI is a Fargate-only setting; for Managed
    # Instances the EC2 host handles image pulls over its own network.
    assign_public_ip = local.is_fargate
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "nginx"
    container_port   = var.container_port
  }

  # If a deployment's tasks never reach a healthy/steady state, ECS aborts it
  # and rolls back to the last known-good task set instead of leaving the
  # service broken.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # CI updates the task definition out-of-band on each deploy, so ignore
  # image/task-definition drift to avoid Terraform reverting deployments.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_cluster_capacity_providers.mi,
  ]
}
