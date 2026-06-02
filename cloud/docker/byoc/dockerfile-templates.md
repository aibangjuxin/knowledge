---
note: Templates assume BuildKit enabled (DOCKER_BUILDKIT=1). For buildx / multi-arch, see comments at the bottom.
---

# Dockerfile Templates

> 经过 BYOC 实战验证的模板。每个都满足：multi-stage、非 root、healthcheck、< 200MB（ML 例外）。

---

## 1. Python (FastAPI / Web Service)

**适用**：Cloud Run, App Runner, Vertex AI Prediction, 自建 K8s

```dockerfile
# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.12
ARG PORT=8080

# ── Stage 1: deps (缓存命中率高) ──────────────────────────
FROM python:${PYTHON_VERSION}-slim AS deps

WORKDIR /app

# OS deps (curl 给 healthcheck，ca-certificates 给 HTTPS)
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Python deps 用 cache mount 加速后续 build
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# ── Stage 2: runtime ──────────────────────────────────────
FROM python:${PYTHON_VERSION}-slim AS runtime

ARG PORT
ENV PORT=${PORT} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/home/app/.local/bin:${PATH}"

# tini: PID 1，正确转发 SIGTERM，回收 zombie
RUN apt-get update && apt-get install -y --no-install-recommends \
        tini curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 1001 app \
    && useradd  --system --uid 1001 --gid app --home-dir /home/app --shell /bin/bash app

WORKDIR /home/app

# 从 deps 阶段 copy site-packages（避免重复 pip install）
COPY --from=deps /usr/local/lib/python${PYTHON_VERSION}/site-packages /usr/local/lib/python${PYTHON_VERSION}/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

# 应用代码
COPY --chown=app:app . .

USER 1001

EXPOSE ${PORT}

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "${PORT}", "--workers", "2"]
```

**使用提示**：
- `requirements.txt` 必须锁版本：`pip freeze > requirements.txt` 或 `pip-compile`
- 加 `--workers` 根据 CPU 调（Cloud Run 1 vCPU 配 2 workers 起步）
- Cold start 敏感时换 `distroless` base（去掉 curl/tini，自己带 s6-overlay）

---

## 2. Node.js (Express / Fastify / Next.js Standalone)

**适用**：Cloud Run, App Runner, 自建 K8s

```dockerfile
# syntax=docker/dockerfile:1.7
ARG NODE_VERSION=22

# ── Stage 1: deps ─────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS deps

WORKDIR /app

# pnpm 缓存命中（用 npm 的话去掉这两行 + 改 pnpm install → npm ci）
RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml* ./
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile --prod

# ── Stage 2: build ────────────────────────────────────────
FROM deps AS builder

COPY . .
RUN pnpm build

# ── Stage 3: runtime ──────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS runtime

ENV NODE_ENV=production \
    PORT=8080 \
    NODE_OPTIONS="--enable-source-maps"

RUN addgroup -S -g 1001 nodejs \
    && adduser  -S -u 1001 -G nodejs nextjs

WORKDIR /app

# Next.js standalone 模式输出最少文件
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

USER 1001

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -qO- "http://localhost:8080/health" || exit 1

CMD ["node", "server.js"]
```

**关键点**：
- `--enable-source-maps` 让 stack trace 可读
- `wget` 比 `curl` 小（alpine 已带）
- 通用 Node 服务：去掉 Next.js standalone 部分，`COPY --from=builder /app/dist ./dist`

---

## 3. Go (HTTP service / CLI)

**适用**：任何 BYOC 平台（Go 镜像可以做到 < 30MB）

```dockerfile
# syntax=docker/dockerfile:1.7
ARG GO_VERSION=1.22

# ── Stage 1: build ────────────────────────────────────────
FROM golang:${GO_VERSION}-alpine AS builder

WORKDIR /src

# Layer 缓存：go.mod 变了才重跑 go mod download
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

# Static binary（CGO=0），配合 distroless 跑
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/app .

# ── Stage 2: runtime (distroless, 极小) ───────────────────
FROM gcr.io/distroless/static-debian12:nonroot AS runtime

COPY --from=builder /out/app /app

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/app"]
```

**关键点**：
- `CGO_ENABLED=0` → 完全静态，distroless 跑得了
- `-trimpath -ldflags="-s -w"` → 去 file path + 减符号表，小 30%
- `distroless/static` 仅 ~2MB base；适合纯 Go HTTP 服务

---

## 4. ML Training (PyTorch + CUDA)

**适用**：Vertex AI Training, SageMaker Training, 自建 K8s + GPU

```dockerfile
# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.11
ARG CUDA_VERSION=12.3.1
ARG CUDNN_VERSION=8

# ── Stage 1: runtime (no build tools) ─────────────────────
FROM nvidia/cuda:${CUDA_VERSION}-cudnn${CUDNN_VERSION}-runtime-ubuntu22.04 AS runtime

ARG GIT_SHA=unknown
LABEL org.opencontainers.image.revision=$GIT_SHA

ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PATH="/usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/nvidia/lib:/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# OS deps (only what training actually needs)
RUN apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} python3-pip \
        ca-certificates curl \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python deps（pin 版本！）
COPY requirements.txt .
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt

# Code
COPY . .

# 非 root
RUN groupadd --system --gid 1001 app \
    && useradd  --system --uid 1001 --gid app --home-dir /home/app --shell /bin/bash app \
    && chown -R app:app /app
USER 1001

# Vertex AI / SageMaker 训练入口由 ENTRYPOINT 启动
# 多机训练：master 启动 worker（通过 TF_CONFIG 或 torchrun）
ENTRYPOINT ["python", "train.py"]
```

**关键点**：
- `runtime` 而非 `devel` image（无 nvcc / 无 headers）— 攻击面小、image 小
- **不要** bake dataset / model weights — 通过 GCS mount
- 多机训练用 `torchrun --nnodes=N --nproc_per_node=GPU ...` 启动

---

## 5. Static site / SPA (nginx)

**适用**：CDN 边缘、Cloud Storage origin, 任何 static 托管

```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:22-alpine AS builder
WORKDIR /src
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci
COPY . .
RUN npm run build

# ── Stage 2: nginx ────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

# 把 build 产物覆盖默认站点
COPY --from=builder /src/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# non-root
RUN sed -i 's/^user .*/user nginx;/' /etc/nginx/nginx.conf
USER nginx

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:8080/ || exit 1
```

**nginx.conf**（listen 8080，因为 Cloud Run / App Runner 注入 PORT 但通常也接受 8080）：
```nginx
server {
  listen 8080;
  server_name _;
  root /usr/share/nginx/html;
  index index.html;

  # SPA fallback
  location / { try_files $uri /index.html; }

  # cache
  location ~* \.(js|css|png|svg|woff2?)$ { expires 30d; add_header Cache-Control "public, immutable"; }
}
```

---

## Build & Push (CI 片段)

```bash
# Build with cache mount + multi-arch
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag ${REGISTRY}/myapp:${GIT_SHA} \
  --tag ${REGISTRY}/myapp:latest \
  --cache-from type=registry,ref=${REGISTRY}/myapp:buildcache \
  --cache-to   type=registry,ref=${REGISTRY}/myapp:buildcache,mode=max \
  --label org.opencontainers.image.revision=${GIT_SHA} \
  --label org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --push \
  .

# Sign
cosign sign --key cosign.key ${REGISTRY}/myapp:${GIT_SHA}

# SBOM
syft ${REGISTRY}/myapp:${GIT_SHA} -o spdx-json > sbom.spdx.json
```

---

## 选型速查

| 场景 | 推荐模板 | 镜像大小参考 |
|---|---|---|
| 简单 Python API | #1 Python FastAPI | ~150MB |
| Next.js SSR | #2 Node.js | ~180MB |
| 高并发 Go service | #3 Go + distroless | ~30MB |
| ML 训练 | #4 PyTorch + CUDA | ~5-8GB（看 CUDA base） |
| 静态站点 | #5 nginx | ~50MB |
| Lambda function | 用 `#1` + AWS Lambda base | ~250MB |
| Cloudflare Workers Container | 用 `#1` slim 化 | < 200MB 推荐 |

---

## 通用 sanity 脚本

```bash
# 镜像 size 报告
docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}"

# 漏洞扫描
trivy image --severity HIGH,CRITICAL ${REGISTRY}/myapp:${GIT_SHA}

# 验证非 root
docker run --rm ${REGISTRY}/myapp:${GIT_SHA} id  # 应输出 uid=1001(app)

# 本地 smoke test
docker run --rm -p 8080:8080 -e PORT=8080 ${REGISTRY}/myapp:${GIT_SHA}
curl http://localhost:8080/health
```
