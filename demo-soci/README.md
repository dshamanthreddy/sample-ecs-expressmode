# SOCI lazy-loading demo (Fargate)

Demonstrates how **Seekable OCI (SOCI)** speeds up Amazon ECS task startup on
Fargate by lazily loading large container images instead of downloading them in
full before the container starts.

- With SOCI, Fargate starts the container after pulling only a few seconds of
  data, streaming the rest in the background.
- Fargate **auto-detects** a SOCI index in the image's ECR repo — **no task
  definition change** is needed.
- The benefit scales with image size, so this demo uses a deliberately large
  (~3 GB) image.

Requirements: Fargate **Linux platform 1.4.0**, X86_64/ARM64, and the SOCI
index stored in the **same ECR repo** as the image (use **SOCI Index Manifest
v2**).

## What's here

```
Dockerfile.fat   ~3 GB image (nginx + random blob)
measure.sh       runs a standalone Fargate task, prints pull + startup deltas
```

The `SOCI Demo (manual)` GitHub workflow builds/pushes the image and runs
`measure.sh`. It reuses the existing `nginx-ecs-dev` cluster, subnets, task
security group, and execution role, and creates a dedicated `soci-demo` ECR
repo.

## Demo procedure (before / after)

The trick is to measure **before** an index exists, then enable indexing and
measure again.

### 1. Baseline — no SOCI index
Run the **SOCI Demo (manual)** workflow with:
- `image_tag = fat`
- `label = no-soci`

Note the reported **image pull window** and **created → RUNNING** time (tens of
seconds for a 3 GB image).

### 2. Enable SOCI indexing
Deploy AWS's **SOCI Index Builder** solution once
(`cfn-ecr-aws-soci-index-builder`). It runs a Lambda on ECR push events that
generates and pushes a SOCI index automatically. See:
https://aws.amazon.com/blogs/containers/ (search "SOCI Index Builder").

Alternatively, generate the index by hand on an EC2/Cloud9 host that has
containerd + the SOCI snapshotter (the "SOCI toolbox"): `soci create <image>`
then `soci push` to the `soci-demo` repo.

### 3. With SOCI — re-push and measure
Re-run the workflow with:
- `image_tag = fat-soci` (a new tag so the Index Builder generates an index for it)
- `label = with-soci`

Confirm an index artifact now exists in the repo:
```bash
aws ecr describe-images --repository-name soci-demo \
  --query 'imageDetails[].{tag:imageTags,type:artifactMediaType}' --output table
```

The **image pull window** should drop to a few seconds and the task should reach
RUNNING much faster.

### 4. Present it

| Image | Index | Pull window | Created → RUNNING |
|-------|-------|-------------|-------------------|
| 3 GB  | none      | ~40–60s | slow |
| 3 GB  | SOCI v2   | ~3–5s   | fast |

Run a few trials each; first-pull vs cache and placement add noise.

## Local run (instead of the workflow)

```bash
export AWS_PROFILE=<account-with-the-stack>
export AWS_REGION=us-east-1
REPO=soci-demo ./measure.sh fat no-soci
```

## Clean up

```bash
aws ecr delete-repository --repository-name soci-demo --force --region us-east-1
aws ecs deregister-task-definition --task-definition soci-demo:<revision> --region us-east-1
```

## Notes

- SOCI's auto-detect behavior is a **Fargate** feature; it does not demo the
  same way on the Managed Instances compute path.
- The demo image exits after a couple of seconds so measurement tasks stop on
  their own and don't accrue cost.
