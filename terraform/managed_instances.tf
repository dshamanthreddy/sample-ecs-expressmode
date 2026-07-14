# ---------------------------------------------------------------------------
# Amazon ECS Managed Instances
# Only created when compute_type = "MANAGED_INSTANCES". AWS provisions,
# patches, scales, and drains the EC2 instances on your behalf while you keep
# EC2-level flexibility (instance types, GPUs, etc.).
#
# Requires two IAM roles:
#   - infrastructure role: lets ECS manage instances on your behalf
#   - instance profile: permissions for the ECS agent on each instance
#     (its role name must be prefixed "ecsInstanceRole" to satisfy the
#     infrastructure role's PassRole condition).
# ---------------------------------------------------------------------------

# AWS-managed policy for the infrastructure role (resolved by name so a wrong
# value fails at plan time rather than apply time).
data "aws_iam_policy" "mi_infrastructure" {
  count = local.is_mi ? 1 : 0
  name  = "AmazonECSInfrastructureRolePolicyForManagedInstances"
}

resource "aws_iam_role" "ecs_infrastructure" {
  count = local.is_mi ? 1 : 0
  name  = "${local.name_prefix}-ecs-infra"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  count      = local.is_mi ? 1 : 0
  role       = aws_iam_role.ecs_infrastructure[0].name
  policy_arn = data.aws_iam_policy.mi_infrastructure[0].arn
}

# Instance profile role - name must start with "ecsInstanceRole".
resource "aws_iam_role" "ecs_mi_instance" {
  count = local.is_mi ? 1 : 0
  name  = "ecsInstanceRole-${local.name_prefix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_mi_instance_ecs" {
  count      = local.is_mi ? 1 : 0
  role       = aws_iam_role.ecs_mi_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_mi_instance_ssm" {
  count      = local.is_mi ? 1 : 0
  role       = aws_iam_role.ecs_mi_instance[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_mi_instance" {
  count = local.is_mi ? 1 : 0
  name  = "ecsInstanceRole-${local.name_prefix}"
  role  = aws_iam_role.ecs_mi_instance[0].name
}

# Managed Instances capacity provider.
resource "aws_ecs_capacity_provider" "mi" {
  count   = local.is_mi ? 1 : 0
  name    = "${local.name_prefix}-mi"
  cluster = aws_ecs_cluster.main.name

  managed_instances_provider {
    infrastructure_role_arn = aws_iam_role.ecs_infrastructure[0].arn
    propagate_tags          = "CAPACITY_PROVIDER"

    instance_launch_template {
      ec2_instance_profile_arn = aws_iam_instance_profile.ecs_mi_instance[0].arn
      capacity_option_type     = var.mi_capacity_option
      monitoring               = "BASIC"

      network_configuration {
        subnets         = aws_subnet.public[*].id
        security_groups = [aws_security_group.ecs_tasks.id]
      }

      storage_configuration {
        storage_size_gib = 30
      }

      # Attribute-based instance selection; ECS picks the most cost-effective
      # instances that satisfy these requirements.
      instance_requirements {
        vcpu_count {
          min = var.mi_vcpu_min
          max = var.mi_vcpu_max
        }
        memory_mib {
          min = var.mi_memory_min_mib
          max = var.mi_memory_max_mib
        }
        instance_generations = ["current"]
      }
    }
  }
}

# Associate the capacity provider with the cluster and make it the default.
resource "aws_ecs_cluster_capacity_providers" "mi" {
  count              = local.is_mi ? 1 : 0
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = [aws_ecs_capacity_provider.mi[0].name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.mi[0].name
    weight            = 1
    base              = 0
  }
}
