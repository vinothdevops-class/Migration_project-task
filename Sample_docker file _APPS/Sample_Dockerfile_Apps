# syntax=docker/dockerfile:1.7
# ---------------------------------------------------------------------------
# FinNova order-service
#  - multi-stage: build tools and npm never reach the runtime image
#  - minimal base: distroless Node 22 (no shell, no package manager)
#  - non-root: distroless "nonroot" user, UID 65532
#  - no secrets: DB credentials are fetched from Secrets Manager at runtime via IRSA
# In CI, pin both base images by digest (@sha256:...) and let Renovate/Dependabot bump them.
# ---------------------------------------------------------------------------

ARG NODE_VERSION=22

# ---------- Stage 1: install production dependencies ----------
FROM node:${NODE_VERSION}-bookworm-slim AS deps
WORKDIR /build
ENV NODE_ENV=production
COPY package.json package-lock.json ./
# Reproducible, lockfile-exact install; dev dependencies (eslint) are excluded.
RUN --mount=type=cache,target=/root/.npm \
    npm ci --omit=dev --ignore-scripts --no-audit --no-fund

# ---------- Stage 2: fetch the public RDS CA bundle for TLS verification ----------
FROM debian:bookworm-slim AS certs
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem -o /rds-global-bundle.pem \
 && rm -rf /var/lib/apt/lists/*

# ---------- Stage 3: runtime ----------
FROM gcr.io/distroless/nodejs${NODE_VERSION}-debian12:nonroot AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=8080 \
    DB_CA_PATH=/app/certs/rds-global-bundle.pem

COPY --from=deps  --chown=65532:65532 /build/node_modules ./node_modules
COPY --from=certs --chown=65532:65532 /rds-global-bundle.pem ./certs/rds-global-bundle.pem
COPY --chown=65532:65532 package.json ./
COPY --chown=65532:65532 src ./src

USER 65532:65532
EXPOSE 8080

LABEL org.opencontainers.image.title="finnova-order-service" \
      org.opencontainers.image.source="https://github.com/<org>/finnova-order-management"

# distroless entrypoint is already "node"; exec form so SIGTERM reaches the process for graceful drain.
CMD ["src/server.js"]
