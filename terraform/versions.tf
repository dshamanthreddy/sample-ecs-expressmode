terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
