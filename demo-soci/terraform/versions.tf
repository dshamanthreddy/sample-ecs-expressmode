terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
  }

  # Local state on purpose: this demo helper is isolated from the main app
  # stack (which uses the S3 backend). Apply/destroy it independently.
}

provider "aws" {
  region = var.aws_region
}
