#!/usr/bin/env bash
#
# Measure Fargate image-pull and startup time for the SOCI demo image.
# Run it once WITHOUT a SOCI index (baseline) and again WITH one to compare.
#
# Reuses the existing nginx-ecs-dev stack's cluster, public subnets, task
# security group, and task execution role (discovered by name/tag).
#
# Usage:  REPO=soci-demo ./measure.sh <image-tag> <label>
#   e.g.  ./measure.sh fat no-soci
#         ./measure.sh fat with-soci
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER:-nginx-ecs-dev-cluster}"
REPO="${REPO:-soci-demo}"
TAG="${1:-fat}"
LABEL="${2:-run}"
FAMILY="soci-demo"

acct=$(aws sts get-caller-identity --query Account --output text)
image="${acct}.dkr.ecr.${REGION}.amazonaws.com/${REPO}:${TAG}"

# Discover networking + execution role from the existing stack.
subnets=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=tag:Name,Values=nginx-ecs-dev-public-*" \
  --query 'Subnets[].SubnetId' --output text | tr '[:space:]' ',' | sed 's/,$//')
sg=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=nginx-ecs-dev-ecs-tasks-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)
exec_role=$(aws iam get-role --role-name nginx-ecs-dev-ecs-execution \
  --query 'Role.Arn' --output text)

echo "Image:   $image"
echo "Cluster: $CLUSTER"
echo "Subnets: $subnets"
echo "SG:      $sg"

# Register a minimal task definition for the fat image.
td_arn=$(aws ecs register-task-definition --region "$REGION" \
  --family "$FAMILY" \
  --network-mode awsvpc \
  --requires-compatibilities FARGATE \
  --cpu 512 --memory 1024 \
  --execution-role-arn "$exec_role" \
  --container-definitions "[{\"name\":\"app\",\"image\":\"${image}\",\"essential\":true,\"command\":[\"sh\",\"-c\",\"echo started; sleep 2\"]}]" \
  --query 'taskDefinition.taskDefinitionArn' --output text)

# Launch one task on Fargate platform 1.4.0 (required for SOCI).
task_arn=$(aws ecs run-task --region "$REGION" --cluster "$CLUSTER" \
  --task-definition "$td_arn" \
  --launch-type FARGATE --platform-version 1.4.0 \
  --network-configuration "awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${sg}],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)

echo "Task:    $task_arn"
echo "Waiting for task to stop..."
aws ecs wait tasks-stopped --region "$REGION" --cluster "$CLUSTER" --tasks "$task_arn"

# Read the lifecycle timestamps and print the deltas.
read -r created pullStart pullStop started <<<"$(aws ecs describe-tasks \
  --region "$REGION" --cluster "$CLUSTER" --tasks "$task_arn" \
  --query 'tasks[0].[createdAt,pullStartedAt,pullStoppedAt,startedAt]' \
  --output text)"

python3 - "$LABEL" "$created" "$pullStart" "$pullStop" "$started" <<'PY'
import sys, datetime as dt
label, created, pstart, pstop, started = sys.argv[1:6]
def p(x):
    try:
        return dt.datetime.fromisoformat(x)
    except Exception:
        return None
c, ps, pe, st = map(p, (created, pstart, pstop, started))
def delta(a, b):
    return f"{(b - a).total_seconds():.1f}s" if a and b else "n/a"
print("-----------------------------------------")
print(f"[{label}] image pull window : {delta(ps, pe)}")
print(f"[{label}] created -> RUNNING : {delta(c, st)}")
print("-----------------------------------------")
PY
