# sample-ecs-expressmode

Nginx running on **Amazon ECS (Fargate)** behind an Application Load Balancer.
The container image is built and stored in **Amazon ECR**, and **GitHub Actions**
builds the image and deploys it to ECS on every push to `main`.

## Architecture

```
GitHub push ──► GitHub Actions ──► build image ──► Amazon ECR
                                          │
                                          └──► update ECS service ──► Fargate tasks
Internet ──► ALB (HTTP :80) ──► Target Group ──► Nginx tasks (:80)
```

## Layout

```
app/                     Nginx app + Dockerfile
  Dockerfile
  nginx.conf
  html/index.html
terraform/               Infrastructure (VPC, ECR, ECS, ALB, IAM)
.github/workflows/
  deploy.yml             CI/CD: build → push to ECR → deploy to ECS
```

## What Terraform creates

- VPC with two public subnets across two AZs, internet gateway, routing
- Security groups (ALB open on :80, tasks reachable only from the ALB)
- ECR repository with image scanning and a 10-image lifecycle policy
- ECS Fargate cluster, task definition, and service
- Application Load Balancer, target group (`/health` check), and listener
- IAM: ECS task execution role + a GitHub Actions OIDC role for CI

## Prerequisites

- Terraform >= 1.5, AWS CLI configured with admin-ish credentials for the first apply
- A GitHub OIDC provider in your AWS account. If you don't have one yet:
  ```bash
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
  ```

## Deploy the infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit github_repository, region, etc.
terraform init
terraform apply
```

Note the outputs, especially `github_actions_role_arn` and `ecr_repository_url`.

> First-apply bootstrap: the task definition references `:latest`, which does not
> exist in ECR until the first image is pushed. The ECS service will wait for a
> healthy task. Either let the GitHub Actions workflow push the first image, or
> push one manually:
> ```bash
> aws ecr get-login-password --region us-east-1 \
>   | docker login --username AWS --password-stdin <ecr_repository_url>
> docker build -t <ecr_repository_url>:latest ./app
> docker push <ecr_repository_url>:latest
> ```

## Wire up GitHub Actions

1. In your GitHub repo, add a secret named `AWS_DEPLOY_ROLE_ARN` set to the
   `github_actions_role_arn` Terraform output.
2. Confirm the `env:` values at the top of `.github/workflows/deploy.yml` match
   your `project_name`/`environment` (defaults assume `nginx-ecs` / `dev`).
3. Push to `main` (or run the workflow manually). The pipeline builds the image,
   pushes it to ECR tagged with the commit SHA, registers a new task definition,
   and rolls out the ECS service.

## Access the app

After a successful deploy, open the `alb_dns_name` output in a browser. `/health`
returns `200 ok` for the load balancer health check.

## Clean up

```bash
cd terraform
terraform destroy
```
