# SOCI lazy-loading demo (Fargate)

Demonstrates how **Seekable OCI (SOCI)** speeds up Amazon ECS task startup on
AWS Fargate by **lazily loading** a large container image instead of
downloading it in full before the container starts.

- Without SOCI, Fargate downloads the entire image, decompresses it, then starts
  the container.
- With a SOCI index, Fargate starts the container after fetching only the files
  it needs, then streams the rest on demand — so a big image starts in seconds.
- Fargate **auto-detects** the index in the image's ECR repo. **No task
  definition change** is needed; you always reference the normal image.
- The benefit scales with image size, so this demo uses a deliberately large
  (~3 GB) image (a tiny image shows no benefit).

## How it works (the short version)

The SOCI index is a small, separate artifact (~24 MB here) that lives in the
same ECR repo as the 3 GB image. For each large layer it stores a **zTOC** — a
map of which file sits at which byte offset inside the compressed layer. At
launch, the Fargate **SOCI snapshotter** uses the zTOC to fetch just the needed
files via HTTP byte-range requests, mounts each layer as a FUSE filesystem, and
pulls the rest in the background. The image content is unchanged; only *how* it
loads changes (on-demand vs full download).

## Architecture

This matches AWS's reference architecture in
["Under the hood: Lazy Loading Container Images with SOCI and AWS Fargate"](https://aws.amazon.com/blogs/containers/under-the-hood-lazy-loading-container-images-with-seekable-oci-and-aws-fargate/):

- **Index generation** — the **SOCI Index Builder** (CloudFormation: an
  EventBridge rule + two Lambdas). On each ECR image push it validates the image
  and generates + pushes a SOCI index. We deploy it via Terraform in
  `terraform/`, scoped to the `soci-demo` repo.
- **Consumption** — the **Fargate SOCI snapshotter** (Linux platform 1.4.0)
  auto-detects the index and lazy-loads.

## Compute support (important)

SOCI lazy loading is a **Fargate** feature only:

| Compute | Lazy loading? |
|---|---|
| **Fargate** (platform 1.4.0) | Automatic — detects the index and lazy-loads |
| **EC2 (ECS-optimized AMI)** | No — pulls the full image; the snapshotter would have to be installed manually |
| **ECS Managed Instances** | No — runs on an AWS-managed EC2 path, so full image download |

Per the [ECS docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html),
non-Fargate compute downloads the whole image. Keep this demo on Fargate
(`measure.sh` uses `--platform-version 1.4.0`).

## What's here

```
Dockerfile.fat   ~3 GB image (nginx + incompressible blob)
measure.sh       runs a standalone Fargate task, prints pull + startup deltas
terraform/       deploys the SOCI Index Builder (isolated, local state)
```

The `SOCI Demo (manual)` GitHub workflow builds/pushes the image and runs
`measure.sh`. It reuses the existing `nginx-ecs-dev` cluster, subnets, task
security group, and execution role, and creates a dedicated `soci-demo` ECR repo.

## Demo procedure (before / after)

Measure **before** an index exists, enable indexing, then measure again.

### 1. Baseline — no SOCI index
Run the **SOCI Demo (manual)** workflow with `image_tag = fat`, `label = no-soci`.
Note the **image pull window** and **created → RUNNING** time.

Observed on a 3 GB image (no index):

```
[no-soci] image pull window : 86.5s
[no-soci] created -> RUNNING : 97.4s
```

### 2. Enable SOCI indexing (deploy the Index Builder)
```bash
cd terraform
terraform init
terraform apply          # deploys the soci-index-builder CloudFormation stack
```
Local state on purpose — fully isolated from the main app stack (S3 backend).
It creates two Lambdas + an EventBridge rule; existing infrastructure is untouched.

> The Index Builder only indexes images pushed **after** it's deployed, so push a
> new tag (step 3) once the stack is `CREATE_COMPLETE`.

Alternative: generate the index by hand on an EC2/Cloud9 host with containerd +
the SOCI snapshotter (`soci create`/`soci push`, or `soci convert` for v2).

### 3. With SOCI — push a new tag and let the index build
Run the workflow with `image_tag = fat-soci`, `label = with-soci`. The push
triggers the Index Builder Lambda; index generation for a 3 GB image takes
~2 minutes and is asynchronous, so the measurement inside this first run may
still be slow — that's expected.

Confirm the index artifact exists (it's small, untagged):
```bash
aws ecr describe-images --repository-name soci-demo --region us-east-1 \
  --query 'imageDetails[].{tags:imageTags,type:artifactMediaType,bytes:imageSizeInBytes}' \
  --output table
```
You should see an artifact of type `application/vnd.amazon.soci.index.*` (~24 MB)
next to the 3 GB image.

### 4. Measure again and confirm lazy loading
Re-run the workflow with the same `image_tag = fat-soci`. Build skips (tag
exists) and the measure step runs with the index present. Compare:

| Image | SOCI index | Pull window | Created → RUNNING |
|-------|-----------|-------------|-------------------|
| `fat` | none | ~86.5s | ~97.4s |
| `fat-soci` | yes | single-digit seconds (expected) | much faster |

## Verifying lazy loading actually happened

Timing alone can be noisy. The definitive proof is the **ECS Task Metadata
endpoint**, which reports the snapshotter used:

```bash
curl -s $ECS_CONTAINER_METADATA_URI_V4 | jq -r '.Snapshotter'
# soci      -> lazy loaded (SOCI was used)
# overlayfs -> full download (index missing or ignored)
```

## SOCI index v1 vs v2 (read this if the demo shows no speedup)

There are two index formats:
- **v1** — index linked loosely to the image (separate artifact, `Subject`
  field). What the current Index Builder here produces.
- **v2** — index bound to the image via an OCI **image index** for deployment
  consistency and easier replication. See
  ["Improving ECS deployment consistency with SOCI Index Manifest v2"](https://aws.amazon.com/blogs/containers/improving-amazon-ecs-deployment-consistency-with-soci-index-manifest-v2/).

**Critical:** accounts **new to SOCI on Fargate can only use v2** — Fargate will
**not** lazy-load a v1 index and falls back to a full download. Accounts that
previously used SOCI can still use v1.

So if step 4 shows no speedup and `.Snapshotter` reports `overlayfs`, your v1
index is being ignored because this account is new to SOCI. To fix, produce a
**v2** index:
- Update the Index Builder to a v2-capable release, or
- Use `soci convert` (SOCI snapshotter CLI v0.10+). Note v2 **modifies the image
  manifest** (adds an annotation → new image digest), so you must **repush the
  image**; the filesystem layers don't change, so there's no extra layer storage.

A v2 setup shows **three** artifacts in `describe-images`: the image, the SOCI
index (`...soci.index.v2+json`), and an image index (`...oci.image.index.v1+json`).

## Which images get indexed (how the filter works)

The Index Builder does **not** index every image in your account — it's scoped
by the `SociRepositoryImageTagFilters` parameter (set via `repo_filter` in
`terraform/`, default `soci-demo:*`). That value is used in two places:

1. **At deploy time** — a helper Lambda parses the filter into repository ARNs
   and scopes the generator Lambda's IAM so it can only push/pull ECR images in
   the matched repos (least privilege).
2. **At runtime** — it decides whether each pushed image gets indexed.

Runtime flow, per push:

```
docker push soci-demo:fat-soci
        │
        ▼
ECR emits an "ECR Image Action" event (action-type=PUSH, result=SUCCESS)
        │
        ▼
EventBridge rule  ──►  Filtering Lambda
        │
        ▼
builds "repository-name:image-tag" (e.g. "soci-demo:fat-soci")
and matches it against each filter (e.g. "soci-demo:*")
        │
   ┌────┴───────────┐
 match           no match
   │                 │
   ▼                 ▼
invoke Generator   do nothing (image NOT indexed)
   │
   ▼
Generator pulls image, builds the SOCI index, pushes it to the repo
```

Matching rules:

- A filter is `repository:tag`; `*` is a wildcard in either part.
- The event's `repository-name` + `image-tag` are tested against each filter; a
  match on **any** filter triggers indexing.
- Multiple comma-separated filters are allowed.

| Filter | Matches |
|--------|---------|
| `soci-demo:*` | any tag pushed to `soci-demo` (this demo) |
| `*:latest` | the `latest` tag in any repo |
| `prod*:*` | any tag in any repo whose name starts with `prod` |
| `*:*` | everything |

There is also a **size gate**: even for a matched image, the generator only
builds a zTOC for layers above the min-layer-size. If no layer is large enough,
no index is created at all — which is why small images (like the app's ~20 MB
image) produce no index even if they match the filter.

To change scope, edit `repo_filter` in `terraform/` and re-apply.

## Local run (instead of the workflow)

```bash
export AWS_PROFILE=<account-with-the-stack>
export AWS_REGION=us-east-1
REPO=soci-demo ./measure.sh fat no-soci
```

## Clean up

The **Terraform Destroy (manual)** workflow removes the `soci-demo` ECR repo and
task definitions after tearing down the main stack — run it and type `destroy`.

The **SOCI Index Builder** stack is separate (local-state Terraform), so tear it
down on its own:
```bash
cd terraform
terraform destroy
```

Manual cleanup of just the demo resources:
```bash
aws ecr delete-repository --repository-name soci-demo --force --region us-east-1
for arn in $(aws ecs list-task-definitions --family-prefix soci-demo \
    --region us-east-1 --query 'taskDefinitionArns[]' --output text); do
  aws ecs deregister-task-definition --task-definition "$arn" --region us-east-1 >/dev/null
done
```

## Notes

- SOCI benefits large images (AWS cites > 250 MB compressed). Tiny images can be
  slower with SOCI due to index/FUSE overhead.
- The generator used ~1 GB memory for a 3 GB image (near the stack's 1024 MB
  default). Bump the Lambda memory for larger images.
- The demo image exits after ~2 seconds so measurement tasks stop on their own
  and don't accrue cost.
