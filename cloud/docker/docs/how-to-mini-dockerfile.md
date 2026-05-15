# 如何构建最小 Docker 镜像 — 全面指南

> 文档版本: v1.0
> 更新日期: 2026-05-15
> 目标读者: 基础设施工程师 / Platform Team / DevOps

---

## 1. 原则先行：为什么最小镜像重要？

| 收益           | 说明                                      |
| ------------ | --------------------------------------- |
| **安全攻击面小**  | 更少的系统包 → 更少的 CVE 漏洞                    |
| **构建速度快**   | 镜像小 → 拉取（pull）快 → CI/CD 等待时间短           |
| **启动时间短**   | 容器启动时无需解压/加载大镜像层，冷启动更快              |
| **存储成本低**   | 大量容器节点时，节省的是成吨的磁盘和网络带宽             |
| **缓存效率高**   | 层数少 + 层内容干净 → Docker 缓存命中率更高            |

一条经验法则：**每多 1MB 镜像体积，每一次 pull、push、deploy 都在付成本。**

---

## 2. 构建最小镜像的核心手法

### 2.1 多阶段构建（Multistage Build）

多阶段构建是构建最小镜像的**基石**。Docker 17.05+ 支持。

**核心思想：** 用一个 Dockerfile 写多个 `FROM` 阶段，把"构建依赖"（编译器、构建工具、源码）全部留在前面的阶段，只把最终运行的二进制/产物复制到最后一个阶段。

```
┌─────────────────────────────────┐
│ Stage 1: Builder                │  ← 包含编译器、Maven/Gradle、源码
│  (yum/apt/node/python/go... )   │
│  产出: app binary / jar         │
└──────────────┬──────────────────┘
               │ COPY --from=builder
               ▼
┌─────────────────────────────────┐
│ Stage 2: Runtime (最小镜像)       │  ← 只有一个 JRE/Python Runtime
│  产出: 最终推送的镜像             │    没有任何构建工具
└─────────────────────────────────┘
```

**效果实测（来自你已有的 knowledge）：**

| 项目    | 优化前    | 优化后     | 缩减率   |
| ----- | ------- | -------- | ------ |
| Python | 588 MB | 47.7 MB | −91.9% |
| Next.js | ~800 MB | 130–160 MB | −80%  |

### 2.2 层优化（Layer Optimization）

Dockerfile 中每条指令产生一层。优化原则：

**① 合理排序——让变化频率最低的指令放在最前面**

```dockerfile
# ✅ 好：依赖层不变时不重新安装
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --prod
COPY . .

# ❌ 差：任何代码改动都会导致依赖重新安装
COPY . .
RUN pnpm install --prod
```

**② 合并 RUN，减少层数**

```dockerfile
# ✅ 好：合并相关命令，用 && \ 减少层
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ❌ 差：每个 RUN 都是一层
RUN apt-get update
RUN apt-get install -y curl wget
RUN apt-get clean
```

**③ 使用 BuildKit 并行构建（自动生效）**

Docker Buildx / BuildKit 会自动并行执行不相关的指令，无需额外配置。

### 2.3 .dockerignore

在 Dockerfile 同级目录下创建 `.dockerignore`，排除一切非产物的文件：

```gitignore
# 版本控制
.git
.gitignore

# 开发依赖
node_modules
__pycache__
*.pyc
*.pyo
*.test
*.coverage

# 构建产物（不应该在 context 中）
dist
build
target/*.jar
*.log

# IDE
.idea/
.vscode/
*.swp

# 文档（生产镜像不需要）
*.md
LICENSE
README.md

# 其他
.env*
docker-compose*.yml
Dockerfile
```

> **作用：** 减少构建上下文（build context）大小，避免把 node_modules / target 目录传给 Docker daemon。context 传得越小，CI 构建越快。

---

## 3. 最小基础镜像对比

### 3.1 镜像家族总览

| 基础镜像                  | 典型体积    | 包含内容                        | 适用场景              |
| ---------------------- | -------- | --------------------------- | ----------------- |
| `scratch`              | **0 KB**  | **什么都没有** — 空镜像，只放二进制    | Go/Rust 等静态编译语言  |
| `gcr.io/distroless/static` | **~650 KB** | 极简 + ca-certificates + glibc | 纯静态语言，无 libc 依赖   |
| `cgr.dev/chainguard/static` | **~1 MB** | 同上，基于 Wolfi，比 Distroless 更小 | 追求最小 + 快速 CVE 修复  |
| `alpine`               | **~2–5 MB** | apk 包管理器 + musl libc        | 需 shell 和 apk 的场景  |
| `eclipse-temurin:17-jre-focal` | **~180 MB** | JRE only (非完整 OS)           | Java 生产运行            |
| `eclipse-temurin:17-jre-alpine` | **~100 MB** | JRE + musl                     | 轻量 Java                |
| `gcr.io/distroless/java17-debian11` | **~50–80 MB** | JRE + glibc，无 shell            | Java 生产（安全优先）       |
| `cgr.dev/chainguard/java` | **~30–50 MB** | 基于 Wolfi 的 Java 运行时         | Java 生产（最小体积 + 安全）  |
| `ubuntu` / `debian`     | **70–80 MB+** | 完整 OS + apt                   | 不推荐用于生产镜像          |
| `python:3.12-slim`      | **~150 MB** | Python + 精简 Debian            | Python 需要 shell 时     |
| `node:22-alpine`        | **~50 MB**  | Node.js + musl                 | Node.js 生产            |

### 3.2 scratch vs distroless vs chainguard 深度对比

#### `FROM scratch` — 只适用于静态二进制

Go 编译为静态二进制后，唯一的选择：

```dockerfile
# 编译阶段（在你的 CI 中）
# CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o app main.go

# 运行阶段
FROM scratch
COPY app /app
COPY certs /etc/ssl/certs/ca-certificates.crt   # 如果需要 TLS
EXPOSE 8080
ENTRYPOINT ["/app"]
```

**限制：**
- 无法运行 shell 脚本
- 无法 `docker exec` 进入调试
- 没有 `curl`、`wget`、`apk` 等任何工具
- 如果 Go 程序需要 DNS（`/etc/resolv.conf`），需要显式 COPY

#### Distroless — Google 出品，平衡体积与可用性

Google 用 Bazel 构建，只包含运行时必要依赖，无 shell、无包管理器：

```dockerfile
# Java
FROM gcr.io/distroless/java17-debian11
COPY app.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]

# Python (如果有)
FROM gcr.io/distroless/python3-debian11
COPY app.py /app/app.py
CMD ["/app/app.py"]
```

**限制：**
- 无法运行 shell，调试困难（生产问题排查靠日志和探针）
- 可用 `:debug` 标签临时进入（包含 busybox）

#### Chainguard（Wolfi）— Distroless 的进化版

Wolfi 是 Chainguard 用 apk 构建的"类 Alpine"发行版，比 Alpine 更安全（签名包、无遗留漏洞）：

| 特性       | Alpine       | Distroless    | Chainguard Wolfi |
| -------- | ------------ | ------------ | ----------------- |
| 包管理器    | apk          | ❌ 无          | apk（签名包）         |
| C 库       | musl         | glibc        | glibc              |
| CVE 修复速度 | 依赖社区       | Google 维护    | **最快**（自动化重建）    |
| 可调试性    | 可 shell      | `:debug` 可选  | 可 shell           |
| 体积       | ~2–5 MB      | ~2–5 MB      | ~1–5 MB            |

```dockerfile
# Chainguard 提供最新版本 + 自动 CVE 修复
FROM cgr.dev/chainguard/wolfi-base AS builder
FROM cgr.dev/chainguard/wolfi-base AS runtime

# 或者语言镜像
FROM cgr.dev/chainguard/go:latest     # Go
FROM cgr.dev/chainguard/python:latest # Python
FROM cgr.dev/chainguard/java:latest   # Java (基于 Wolfi)
FROM cgr.dev/chainguard/nginx:latest  # Nginx
```

---

## 4. 各语言最优 Dockerfile 模板

### 4.1 Go（静态编译）— 极致最小

```dockerfile
# =============================================
# Stage 1: Build
# =============================================
FROM golang:1.23-alpine AS builder

WORKDIR /app

# 先复制 go.mod（利用缓存）
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO_ENABLED=0 静态编译，不依赖任何 C 库
# -w -s 去除调试信息和符号表，体积最小
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o app .

# =============================================
# Stage 2: Scratch（零体积基础镜像）
# =============================================
FROM scratch AS runtime

# 如果需要 HTTPS CA 证书（大多数 Go 程序需要）
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /app/app /app/

EXPOSE 8080
ENTRYPOINT ["/app"]
```

**产物对比：**
- 普通镜像（`golang:1.23`）：800 MB+
- 优化后（scratch）：**~5–10 MB**

### 4.2 Java（基于 Maven + Distroless）

```dockerfile
# =============================================
# Stage 1: Builder
# =============================================
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# 先复制 pom.xml，利用 Docker 缓存
COPY pom.xml .
RUN mvn dependency:go-offline

COPY src ./src
RUN mvn package -DskipTests

# =============================================
# Stage 2: Runtime（Distroless，无 shell）
# =============================================
FROM gcr.io/distroless/java17-debian11 AS runtime

ENV JAVA_HOME=/opt/java/openjdk

COPY --from=builder /build/target/*.jar /app/app.jar

WORKDIR /app
USER nonroot

ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 4.3 Java（Chainguard，最新 CVE 修复）

```dockerfile
FROM cgr.dev/chainguard/maven:latest AS builder

WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn package -DskipTests

FROM cgr.dev/chainguard/java17-runtime AS runtime
COPY --from=builder /build/target/*.jar /app/app.jar
WORKDIR /app
ENTRYPOINT ["java", "-jar", "app.jar"]
```

### 4.4 Node.js / Next.js（pnpm + Alpine）

```dockerfile
# =============================================
# Stage 1: Base — 只拉一次
# =============================================
FROM node:22-alpine AS base
RUN apk add --no-cache libc6-compat
RUN corepack enable && corepack prepare pnpm@latest --activate

# =============================================
# Stage 2: Deps — 缓存依赖层
# =============================================
FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN pnpm install --frozen-lockfile --prod

# =============================================
# Stage 3: Builder
# =============================================
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm build

# =============================================
# Stage 4: Runner — 最终生产镜像
# =============================================
FROM base AS runner
WORKDIR /app

RUN addgroup -S -g 1001 nodejs && \
    adduser -S -u 1001 nextjs

# Next.js standalone 模式：只复制必要文件
COPY --from=builder /app/next.config.mjs .*
COPY --from=builder /app/package.json ./
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER nextjs
EXPOSE 3000
ENV PORT=3000 NODE_ENV=production

CMD ["node", "server.js"]
```

### 4.5 Python（多阶段 + 极简 Runtime）

```dockerfile
# =============================================
# Stage 1: Builder
# =============================================
FROM python:3.12-slim AS builder

WORKDIR /app

# 利用缓存：先装依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN pip install --no-cache-dir -e .

# =============================================
# Stage 2: Runtime（Debian slim，无编译工具）
# =============================================
FROM python:3.12-slim AS runtime

WORKDIR /app

# 只复制 Python 运行时和已安装的包
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY . .

# 非 root 运行
USER nobody

CMD ["python", "app.py"]
```

> **如果追求更小：** 用 `FROM cgr.dev/chainguard/python:latest` 替代 python:slim，体积更小且 CVE 自动修复。

---

## 5. Docker Buildx — 进阶工具链

Docker Buildx 是 Docker 19.03+ 内置的构建插件，基于 BuildKit 引擎，**解锁了普通 `docker build` 没有的所有高级特性**。

### 5.1 Buildx 核心能力

| 能力           | 说明                                       |
| ------------ | ---------------------------------------- |
| **多架构构建**   | 单次构建生成 amd64、arm64、ppc64le 等多平台镜像     |
| **并行构建**    | 自动并行执行不相关的构建阶段                      |
| **缓存挂载**    | `RUN --mount=type=cache` 加速依赖下载（apt/pip/maven） |
| **远程缓存**    | `--cache-from` / `--cache-to` 复用上一次构建缓存   |
| **Secrets**   | `--mount=type=secret` 安全注入 npm token 等密钥   |
| **`--link`**  | 利用前一次构建结果做增量构建，节省 CPU                   |

### 5.2 创建多架构构建器

```bash
# 创建支持多架构的 builder 实例
docker buildx create --name multi-builder --use

# 初始化并验证
docker buildx inspect multi-builder --bootstrap
```

### 5.3 多架构构建 + 推送

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag your-registry.com/yourapp:latest \
  --push \
  .
```

这会在一次命令中同时为 x86 和 ARM 架构构建，并推送到镜像仓库。

### 5.4 利用远程缓存加速 CI

```bash
docker buildx build \
  --platform linux/amd64 \
  --cache-from type=registry,ref=your-registry.com/yourapp:build-cache \
  --cache-to type=registry,ref=your-registry.com/yourapp:build-cache,mode=max \
  --tag your-registry.com/yourapp:latest \
  --push \
  .
```

| 参数                        | 作用                         |
| ------------------------- | -------------------------- |
| `--cache-from`             | 从上次推送的缓存镜像拉取层            |
| `--cache-to=type=registry` | 构建完成后将新缓存推送回仓库           |
| `mode=max`                | 缓存所有层（默认 only 层最后一次被使用）    |

### 5.5 GitHub Actions 中使用 Buildx

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    platforms: linux/amd64,linux/arm64
    cache-from: type=registry,ref=yourapp:build-cache
    cache-to: type=registry,ref=yourapp:build-cache,mode=max
    push: true
    tags: yourapp:latest
```

### 5.6 BuildKit 缓存挂载（Cache Mounts）— 加速依赖安装

BuildKit 支持在 RUN 指令中挂载持久缓存，避免每次构建都重新下载依赖：

```dockerfile
# Maven 缓存
RUN --mount=type=cache,target=/root/.m2 \
    mvn dependency:go-offline

# apt 缓存
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# pip 缓存
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt
```

> **注意：** 这些缓存**不进入镜像层**，只存在于构建时的临时存储中，镜像本身不会变大，且构建速度大幅提升。

### 5.7 `--link` 模式：真正的增量构建

普通构建中，即使只改了一行代码，COPY 产物也会重建。`--link` 模式可以基于上一次构建的产物做增量复制：

```bash
docker buildx build --link -t yourapp:v2 .
```

配合 `.dockerignore` 使用效果最佳。

---

## 6. 全面优化检查清单

### 6.1 Dockerfile 自检

- [ ] 多阶段构建？最后一个阶段没有编译器/构建工具
- [ ] 基础镜像是最小镜像（alpine / distroless / scratch）而非 ubuntu/debian
- [ ] `.dockerignore` 已配置，排除 `node_modules`、`target`、`.git` 等
- [ ] 依赖层（`COPY package.json` / `COPY pom.xml`）在源码层之前
- [ ] `RUN` 指令已合并（减少层数）
- [ ] 使用 `--no-install-recommends`（apt）避免安装不需要的推荐包
- [ ] `apt-get clean` 和 `rm -rf /var/lib/apt/lists/*` 已在同一 RUN 中
- [ ] 应用以非 root 用户运行（`USER`）
- [ ] 使用 `EXPOSE` 声明端口
- [ ] `ENTRYPOINT` 使用 exec 格式 `["cmd", "arg"]` 而非 shell 格式

### 6.2 镜像体积自检

```bash
# 查看镜像各层大小
docker history your-image:tag

# 查看最终镜像大小
docker images your-image:tag

# 扫描 CVE（前提是使用 Distroless / Chainguard）
docker scout cves your-image:tag
```

### 6.3 CI/CD 自检

- [ ] Buildx 构建器已配置多架构
- [ ] 缓存策略（`--cache-from` / `--cache-to`）已启用
- [ ] 构建缓存已推送至镜像仓库（`mode=max` 覆盖所有层）
- [ ] 使用 `docker/build-push-action` v5+ 的 GitHub Actions

---

## 7. 技术选型决策树

```
你的语言 / 运行时？
│
├─ Go / Rust（静态编译）
│   └─ ▶ FROM scratch（0 KB）或 distroless/static
│
├─ Java（需要 JRE）
│   ├─ 追求极致安全 + 最小体积
│   │   └─ ▶ gcr.io/distroless/java17-debian11
│   │              或 cgr.dev/chainguard/java17-runtime
│   └─ 需要 shell / 调试
│       └─ ▶ eclipse-temurin:17-jre-alpine
│
├─ Node.js / Python（需要 Runtime）
│   ├─ 追求最小
│   │   └─ ▶ cgr.dev/chainguard/{python,node}-latest
│   └─ 需要 shell（调试 / 脚本）
│       └─ ▶ node:22-alpine / python:3.12-alpine
│
└─ 需要完整 OS / apt
    └─ ▶ ubuntu:24.04-slim 或 debian:bookworm-slim
        （仅用于本地开发，不推荐生产）
```

---

## 8. 参考链接

| 资源                                | 说明             |
| --------------------------------- | -------------- |
| [Docker Buildx 官方文档](https://docs.docker.com/build/buildx/) | Buildx 完整指南    |
| [BuildKit 缓存文档](https://docs.docker.com/build/cache/) | 层缓存 + 远程缓存机制  |
| [Google Distroless](https://github.com/distroless) | 官方仓库 + 各语言镜像  |
| [Chainguard Images](https://github.com/chainguard-images) | Wolfi 系镜像，CVE 修复最快 |
| [Multi-stage Builds 官方文档](https://docs.docker.com/build/building/multi-stage/) | Docker 官方多阶段构建指南 |
| [Dockerfile 最佳实践](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/) | 官方 Dockerfile 规范 |
| [your knowledge: multistage-build-analysis.md](https://github.com/chainguard-images) | 你已有的 Java Multistage 分析 |
