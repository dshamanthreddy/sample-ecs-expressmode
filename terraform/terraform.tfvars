# Copy to terraform.tfvars and adjust. terraform.tfvars is gitignored.
aws_region        = "us-east-1"
project_name      = "nginx-ecs"
environment       = "dev"
desired_count     = 2
github_repository = "dshamanthreddy/sample-ecs-expressmode"
