variable "aws_region" {
  description = "Region where the soci-demo ECR repo lives."
  type        = string
  default     = "us-east-1"
}

variable "repo_filter" {
  description = "repo:tag filter for images to auto-index. Scoped to the demo repo only."
  type        = string
  default     = "soci-demo:*"
}

# Official AWS SOCI Index Builder CloudFormation template.
# Pinned to main here for the demo; pin to a release tag for anything real.
data "http" "soci_index_builder" {
  url = "https://raw.githubusercontent.com/awslabs/cfn-ecr-aws-soci-index-builder/main/templates/SociIndexBuilder.yml"
}

# Deploys two Lambdas + an EventBridge rule that, on each image push matching
# repo_filter, generates a SOCI index (v2) and pushes it back into the repo.
# Scoped to soci-demo:* so it never touches the app's nginx-ecs-dev repo.
resource "aws_cloudformation_stack" "soci_index_builder" {
  name          = "soci-index-builder"
  template_body = data.http.soci_index_builder.response_body
  capabilities  = ["CAPABILITY_IAM"]

  parameters = {
    SociRepositoryImageTagFilters = var.repo_filter
    SociIndexVersion              = "V2"
    # AWS-hosted Lambda deployment assets (same-region us-east-1 bucket).
    QSS3BucketName = "aws-quickstart"
    QSS3KeyPrefix  = "cfn-ecr-aws-soci-index-builder/"
  }
}

output "soci_stack_name" {
  description = "Name of the deployed SOCI Index Builder CloudFormation stack."
  value       = aws_cloudformation_stack.soci_index_builder.name
}
