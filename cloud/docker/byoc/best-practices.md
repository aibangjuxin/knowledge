# BYOC Best Practices

> **面向生产环境**的 BYOC 工程实践清单。按"必做 → 强烈建议 → 进阶"分层。

---

## 1. 镜像设计 (Image Design)

### 1.1 必做 ✅

| 项目 | 做法 | 理由 |
|---|---|---|
| **基础镜像** | `distroless` / `alpine` / `debian-slim` | 攻击面小、pull 快、digest 稳定 |
| **非 root 用户** | 创建专用 user + `USER <uid>` | 容器逃逸后不是 root |
| **Pin 基础镜像 digest** | `FROM alpine:3.19@sha256:...` | 避免上游 rebuild 引入 breaking change |
| **健康检查** | `HEALTHCHECK CMD ...`（如有 process manager） | K8s 派平台可读；Vertex AI prediction 需要 `/health` |
| **SIGTERM 处理** | Python `signal.signal` / Go default / Node 自定义 | 平台缩容时优雅退出，不杀一半请求 |
| **多阶段构建** | builder + runtime 两阶段 | runtime 镜像不携带 build 工具链 |

### 1.2 强烈建议 🟡

- **tini / dumb-init**：作为 PID 1，正确转发信号、回收 zombie
- **`.dockerignore` 全面**：屏蔽 `.git`、`__pycache__`、`node_modules`、`.env`、`*.md`
- **明确 `ENTRYPOINT` + `CMD` 分离**：
  - `ENTRYPOINT` = 不可变的执行入口（如 `python`）
  - `CMD` = 平台 / 用户可覆盖的默认参数
- **labels 写元数据**：
  ```dockerfile
  LABEL org.opencontainers.image.source="https://github.com/.../myapp" \
        org.opencontainers.image.revision="${GIT_SHA}" \
        org.opencontainers.image.created="${BUILD_DATE}"
  ```

---

## 2. 体积优化 (Size)

### 2.1 直接收益

> **镜像每减 100MB → 冷启动减少 1-3s，egress 费用降低。**

### 2.2 必做 ✅

- **同一 RUN 层清理**：
  ```dockerfile
  RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates \
      && rm -rf /var/lib/apt/lists/*
  ```
- **移除不必要的包**：docs、locales、man pages、dev headers
- **精简 Python 安装**：用 `pip install --no-cache-dir`，multi-stage 拷贝 `site-packages`

### 2.2 强烈建议 🟡

- **BuildKit cache mounts**（v2 语法）：
  ```dockerfile
  # syntax=docker/dockerfile:1.7
  RUN --mount=type=cache,target=/root/.cache/pip \
      pip install -r requirements.txt
  ```
  缓存命中跨 build，比 `--mount=type=bind` 快
- **Multi-arch builds**（amd64 + arm64）：GCP Tau T2D / AWS Graviton 可降费 20-40%
- **`slim` / `alpine` 选型**：
  - 兼容性要求高 → `debian-slim`
  - 极致体积 / Python 简单依赖 → `alpine`（注意 musl libc 兼容）
  - 不需要 shell / package manager → `distroless`

---

## 3. 安全 (Security)

### 3.1 必做 ✅

| 项目 | 工具 / 做法 |
|---|---|
| **漏洞扫描** | `trivy image`, `grype`, `snyk container`；接 CI 失败门禁 |
| **不 bake secrets** | 镜像内禁止 token、key；运行时通过 Secret Manager / Vault / env 注入 |
| **只读 root FS** | `RUN chmod -R a-w /app` 后 `USER app`（如业务允许） |
| **最小 capability** | 除非必要不 `CAP_NET_RAW` 等 |
| **`:latest` 禁止** | 永远用 immutable tag（version / digest） |

### 3.2 强烈建议 🟡

- **Cosign 签名 + 验证**：
  ```bash
  cosign sign --key cosign.key myregistry/myapp:v1.2.3
  # 平台侧：cosign verify --key cosign.pub ... 或 policy controller
  ```
- **SBOM 生成**：
  ```bash
  syft myregistry/myapp:v1.2.3 -o spdx-json > sbom.spdx.json
  ```
- **OPA/Gatekeeper 限制**：禁止 root user、强制只读 FS、强制有 HEALTHCHECK

### 3.3 进阶 🚀

- **Distroless + static binary**：Go 应用可做到 < 20MB 镜像
- **Rootless container**（如 `docker:dind-rootless`）：容器内无 root 权限

---

## 4. 可复现性 (Reproducibility)

> **同一 image digest → 同一行为。** 这条没满足就别上生产。

### 4.1 必做 ✅

- **Pin 所有依赖**：`requirements.txt` 锁版本（`pip freeze`）、`package-lock.json`、`go.sum`
- **Build 时注入版本**：
  ```dockerfile
  ARG GIT_SHA=unknown
  ARG BUILD_DATE=unknown
  LABEL org.opencontainers.image.revision=$GIT_SHA
  ```
- **CI 中固化 base digest**：避免 base 升级偷偷改变 image

---

## 5. Registry (注册表)

### 5.1 必做 ✅

| 项目 | 说明 |
|---|---|
| **私有 registry + auth** | 不暴露公网（除非要分发第三方） |
| **Lifecycle policy** | 清理 untagged > 30d、tagged > 90d 的旧 image |
| **Vulnerability scanning on push** | ECR / Artifact Registry / ACR / GCR 都内置 |
| **同 region 拉取** | 减少冷启动时间 + 跨 region egress 费用 |

### 5.2 强烈建议 🟡

- **Geo-replication**：多 region 部署时，registry 自动同步
- **VPC-SC / Private endpoint**：registry 不走公网
- **Separate registries per env**：dev/staging/prod 物理隔离（防止误部署）

---

## 6. 可观测 (Observability)

### 6.1 必做 ✅

- **结构化日志到 stdout/stderr**：JSON 行，便于平台采集
- **不要写日志到文件**：容器是 ephemeral 的，文件丢失
- **Trace propagation**：HTTP `traceparent` header 透传（W3C Trace Context）

### 6.2 强烈建议 🟡

- **OpenTelemetry SDK**：自动埋点 + 上报到 Cloud Trace / X-Ray / Jaeger
- **Prometheus metrics endpoint**（如业务适用）：`/metrics` 暴露给平台抓取
- **业务 metric 命名规范**：`myapp_request_duration_seconds_bucket{status="200"}`

---

## 7. CI/CD 集成

### 7.1 必做 ✅

- **Build 一次，promote 多次**：
  ```
  CI build → image:v1.2.3-abc123 → deploy to dev → deploy to staging → deploy to prod
  ```
  prod 永远用通过 staging 的**同一个 digest**
- **Tag 含 git SHA**：可追溯到具体 commit
- **Build cache**：CI runner 用 registry cache 或 BuildKit 远程缓存

### 7.2 强烈建议 🟡

- **Image promotion workflow**：
  ```bash
  # 伪代码
  deploy.sh myapp:v1.2.3-abc123 staging   # 自动跑 smoke test
  # 测试通过
  deploy.sh myapp:v1.2.3-abc123 prod      # 同一 digest
  ```
- **SBOM 跟 image 一起发布**：regulatory / 安全审计用
- **Re-build on base image update**：dependabot / renovate 监控 base digest 变化

---

## 8. 平台合约 (Platform Contract) — 关键

每个平台有**隐式合约**，违反就跑不起来或起不来。

### 通用合约

| 要求 | 适用 |
|---|---|
| 监听 `$PORT` | Cloud Run, App Runner |
| HTTP/1.1 或 HTTP/2 | Cloud Run, App Runner, SageMaker, Vertex AI Prediction |
| 非 root + UID >= 1000 | 部分平台强制 |
| Read-only root FS 可选 | K8s-based 平台支持 |
| 启动后 < 平台超时（一般 4 分钟） | Cloud Run, App Runner |
| 支持 graceful shutdown（SIGTERM） | 所有生产平台 |

### 平台特例 → 见 [`platforms.md`](./platforms.md)

---

## 9. 反模式 (Anti-patterns)

| ❌ 错误做法 | ✅ 正确做法 |
|---|---|
| `FROM ubuntu:latest` | `FROM ubuntu:24.04@sha256:...` |
| 镜像内 `pip install xxx` 装运行时依赖 | multi-stage build 装到最终镜像 |
| `USER root` 跑应用 | 创建 `app` user + `USER 1001` |
| `CMD ["python", "app.py"]` 用 shell form | `CMD ["python", "app.py"]` exec form（PID 1 信号） |
| 镜像内 bake `.env` | 运行时 mount secret / env |
| 用 `:latest` 部署 prod | 固定 `v1.2.3@sha256:...` |
| 一个 image 跑多服务（API + worker） | 拆 image，按服务部署 |
| Dockerfile 不进 git | 跟代码同 repo，code review 必经 |

---

## 10. 验证清单 (Pre-prod gate)

每次 BYOC 上线前，确认：

- [ ] Image digest 已记录，跨环境用同一 digest
- [ ] Vulnerability scan 0 个 High/Critical
- [ ] 镜像大小 < 500MB（ML 除外，但 < 2GB 是合理上限）
- [ ] 非 root user
- [ ] HEALTHCHECK 定义
- [ ] SIGTERM 处理（实测 30s 内退出）
- [ ] 日志输出 JSON 到 stdout
- [ ] 已 SBOM + cosign 签名
- [ ] 平台合约已满足（PORT、health、predict 端点）
- [ ] 本地用同一 image 跑过端到端 smoke test
- [ ] Rollback 路径明确（旧 digest / 旧 tag）
