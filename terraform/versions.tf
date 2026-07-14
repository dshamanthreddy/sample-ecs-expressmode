terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # ECS Managed Instances (managed_instances_provider) requires v6.15+;
      # capacity_option_type (Spot/On-Demand) requires ~v6.24+.
      version = ">= 6.24.0, < 7.0.0"
    }
  }

  # Remote state in S3 so GitHub Actions runners share one source of truth.
  # State bucket is created manually as a bootstrap prerequisite.
  # Native S3 locking (use_lockfile) needs Terraform >= 1.10, so no DynamoDB.
  backend "s3" {
    bucket       = "tf-state-340290106740-nginx-ecs"
    key          = "nginx-ecs/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
