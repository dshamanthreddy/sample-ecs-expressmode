# sample-ecs-expressmode

Nginx running on **Amazon ECS** behind an Application Load Balancer, with a
choice of **Fargate** or **ECS Managed Instances** compute. The container image
is built and stored in **Amazon ECR**, and **GitHub Actions** runs the entire
lifecycle: Terraform for infrastructure and the build/deploy of the app.

## Architecture

```
Pull request / push to main ─► GitHub Actions: terraform plan (preview only)

Manual "Run workflow" ─► [gated apply] ─► Terraform provisions AWS infra
                                    └────► build image ─► ECR ─► update ECS service

Internet ─► ALB (HTTP :80) ─► Target Group (:8080) ─► Nginx tasks (:8080)
                                                        on Fargate OR Managed Instances
```

## Repository layout

```
app/
  Dockerfile              Multi-stage, non-root Nginx image (serves on :8080)
  nginx.conf              Server config + /health endpoint, gzip_static
  html/index.html         Static content
  .dockerignore
terraform/
  versions.tf             Providers + S3 remote state backend
  providers.tf            AWS provider + default tags
  variables.tf            All inputs (incl. compute_type toggle)
  network.tf              VPC, public subnets, IGW, routing
  security_groups.tf      ALB and task security groups
  ecr.tf                  ECR repository (immutable tags, scan, lifecycle)
  iam.tf                  ECS execution role + GitHub Actions OIDC role
  alb.tf                  ALB, target group (/health), listener
  ecs.tf                  Cluster, task definition, service (compute-aware)
  managed_instances.tf    Managed Instances capacity provider + IAM (opt-in)
  outputs.tf              ALB DNS, ECR URL, names, role ARN
.github/workflows/
  pipeline.yml            plan on push/PR; gated apply + deploy on manual run
  destroy.yml             manual-only terraform destroy (typed confirmation)
```

## Compute options: Fargate vs Managed Instances

Choose the compute model with the `compute_type` variable:

| `compute_type`        | What you get |
|-----------------------|--------------|
| `FARGATE` (default)   | Serverless. No hosts to manage. |
| `MANAGED_INSTANCES`   | AWS provisions, patches, scales, and drains EC2 instances on your behalf, while you keep EC2-level flexibility (instance types, Spot, etc.). |

Example `terraform.tfvars` for Managed Instances:

```hcl
compute_type       = "MANAGED_INSTANCES"
mi_capacity_option = "SPOT"   # or ON_DEMAND
mi_vcpu_min        = 1
mi_vcpu_max        = 4
mi_memory_min_mib  = 1024
mi_memory_max_mib  = 8192
```

Leave `compute_type` unset (or `FARGATE`) and the Managed Instances resources
are not created. Switching types is a single variable change plus an apply.

## What Terraform creates

- VPC with two public subnets across two AZs, internet gateway, routing
- Security groups (ALB open on :80; tasks reachable only from the ALB on :8080)
- ECR repository with image scanning and a lifecycle policy
- ECS Fargate cluster, task definition, and service (with circuit breaker)
- When `compute_type = MANAGED_INSTANCES`: a Managed Instances capacity
  provider, cluster association, ECS infrastructure role, and instance profile
- Application Load Balancer, target group (`/health` check), and HTTP listener
- IAM: ECS task execution role + a GitHub Actions OIDC role

## Best practices baked in

**Container / app**
- Multi-stage Docker build (build stage pre-compresses assets; minimal runtime)
- Runs as a **non-root** user (`nginx-unprivileged`, uid 101) on port 8080
- Pinned base images, OCI labels, `.dockerignore`, container `HEALTHCHECK`

**ECR**
- **Immutable tags** — deploy strictly by git SHA (no `:latest`)
- Scan-on-push and a lifecycle policy to expire old images
- Idempotent push in CI (skips if the commit image already exists)

**ECS**
- **Deployment circuit breaker** with automatic rollback on failed deploys
- Task definition updated out-of-band by CI; Terraform ignores that drift

**CI/CD (GitHub Actions)**
- OIDC federation — **no long-lived AWS keys** in GitHub
- **Plan on push/PR**, gated **apply/deploy** behind a `production` Environment
  with a required reviewer
- **Concurrency guard** shared by apply and destroy so state is never mutated
  by two runs at once
- All actions **pinned to commit SHAs** (supply-chain hardening)

**Terraform**
- **S3 remote state** with native lockfile (`use_lockfile`)
- Multi-platform provider lock file committed for reproducible CI
- Input `validation` blocks on `compute_type` and `mi_capacity_option`

## Bootstrap prerequisites (one-time, manual)

Created by hand in the target account (`340290106740`, `us-east-1`):

1. **GitHub OIDC provider** for `token.actions.githubusercontent.com`.
2. **S3 state bucket** `tf-state-340290106740-nginx-ecs` (versioning enabled).
3. **OIDC bootstrap role** `gha-terraform`, trust scoped to
   `repo:dshamanthreddy/sample-ecs-expressmode:*`, with permissions to manage
   the infrastructure.
4. **GitHub repo secret** `AWS_TF_ROLE_ARN` = the bootstrap role ARN.
5. **GitHub Environment** `production` with a required reviewer (gates apply/deploy).

## Deploy

1. Open a PR or push to `main` → the `plan` job shows what would change.
2. Trigger **Actions → Infra and App Pipeline → Run workflow**.
3. Approve the `production` deployment when prompted.
4. The pipeline applies infrastructure, builds/pushes the image, and rolls out
   the ECS service, waiting for it to stabilize.
5. Open the `alb_dns_name` output in a browser; `/health` returns `200 ok`.

## Tear down

**Actions → Terraform Destroy (manual) → Run workflow**, type `destroy` to
confirm. It runs only on manual trigger and never on push.

## Key variables

| Variable | Default | Purpose |
|---|---|---|
| `aws_region` | `us-east-1` | Deployment region |
| `project_name` / `environment` | `nginx-ecs` / `dev` | Resource name prefix |
| `desired_count` | `2` | Number of tasks |
| `container_port` | `8080` | Non-root Nginx port |
| `compute_type` | `FARGATE` | `FARGATE` or `MANAGED_INSTANCES` |
| `mi_capacity_option` | `ON_DEMAND` | `ON_DEMAND` or `SPOT` (Managed Instances) |
| `mi_vcpu_min` / `mi_vcpu_max` | `1` / `4` | Managed Instances vCPU range |
| `mi_memory_min_mib` / `mi_memory_max_mib` | `1024` / `8192` | Managed Instances memory range |

## Notes

- The public ALB is HTTP on port 80. For production, add an HTTPS (ACM) listener
  and redirect 80 → 443.
- Tasks run in public subnets. For a tighter posture, move them to private
  subnets with a NAT gateway or ECR/S3 VPC endpoints.
- Managed Instances is a recent AWS feature and requires AWS provider v6.15+
  (this repo pins `>= 6.24`).
