variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix resource names."
  type        = string
  default     = "nginx-ecs"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "container_port" {
  description = "Port the Nginx container listens on."
  type        = number
  default     = 80
}

variable "desired_count" {
  description = "Number of ECS tasks to run."
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "image_tag" {
  description = "Container image tag to deploy. Overridden by CI on each release."
  type        = string
  default     = "latest"
}

variable "github_repository" {
  description = "GitHub repo in 'owner/name' form, used to scope the OIDC deploy role."
  type        = string
  default     = "dshamanthreddy/sample-ecs-expressmode"
}
