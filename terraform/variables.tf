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
  description = "Port the Nginx container listens on (non-root nginx uses 8080)."
  type        = number
  default     = 8080
}

variable "desired_count" {
  description = "Number of ECS tasks to run."
  type        = number
  default     = 2
}

variable "compute_type" {
  description = "ECS compute model: FARGATE (serverless) or MANAGED_INSTANCES (AWS-managed EC2)."
  type        = string
  default     = "FARGATE"

  validation {
    condition     = contains(["FARGATE", "MANAGED_INSTANCES"], var.compute_type)
    error_message = "compute_type must be either \"FARGATE\" or \"MANAGED_INSTANCES\"."
  }
}

variable "mi_capacity_option" {
  description = "Purchasing option for Managed Instances: ON_DEMAND or SPOT (only used when compute_type = MANAGED_INSTANCES)."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.mi_capacity_option)
    error_message = "mi_capacity_option must be either \"ON_DEMAND\" or \"SPOT\"."
  }
}

variable "mi_vcpu_min" {
  description = "Minimum vCPUs for Managed Instances attribute-based selection."
  type        = number
  default     = 1
}

variable "mi_vcpu_max" {
  description = "Maximum vCPUs for Managed Instances attribute-based selection."
  type        = number
  default     = 4
}

variable "mi_memory_min_mib" {
  description = "Minimum memory (MiB) for Managed Instances attribute-based selection."
  type        = number
  default     = 1024
}

variable "mi_memory_max_mib" {
  description = "Maximum memory (MiB) for Managed Instances attribute-based selection."
  type        = number
  default     = 8192
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
