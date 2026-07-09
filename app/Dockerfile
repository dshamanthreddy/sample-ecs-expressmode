# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1 - build/prepare static assets
# For a non-trivial app this is where a real build tool (npm, hugo, vite...)
# would run. Here we pre-compress assets so Nginx can serve them via
# gzip_static, cutting bandwidth and per-request CPU.
# ---------------------------------------------------------------------------
FROM alpine:3.20 AS builder

WORKDIR /site
COPY html/ ./

RUN apk add --no-cache gzip \
 && find . -type f \( -name '*.html' -o -name '*.css' -o -name '*.js' -o -name '*.svg' \) \
      -exec gzip -9 -k {} \;

# ---------------------------------------------------------------------------
# Stage 2 - runtime
# nginx-unprivileged runs as a non-root user (uid 101) and listens on 8080
# by default, so no privileged-port capability is needed.
# ---------------------------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

LABEL org.opencontainers.image.title="nginx-ecs" \
      org.opencontainers.image.description="Static Nginx site on ECS Fargate" \
      org.opencontainers.image.source="https://github.com/dshamanthreddy/sample-ecs-expressmode"

# Server config (listens on 8080, exposes /health). Owned by root, world
# readable - nginx only needs to read it.
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Static content + pre-compressed variants, owned by the runtime user.
COPY --chown=101:101 --from=builder /site/ /usr/share/nginx/html/

# Run as the unprivileged user (explicit; the base image also sets this).
USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://localhost:8080/health || exit 1

# Base image already provides: CMD ["nginx", "-g", "daemon off;"]
