# syntax=docker/dockerfile:1.7
# =============================================================================
# cluster-proxy / addon-manager / addon-agent —— 多阶段构建 (Multistage Build)
#
# 上游参考:
#   https://github.com/open-cluster-management-io/cluster-proxy/blob/main/cmd/Dockerfile
#
# 阶段划分 (3 个 stage, 各司其职):
#   [1] proxy-builder : 编译 apiserver-network-proxy 的 4 个二进制 + 下载 kubectl
#                       (与本仓库源码无关, 单独成阶段以获得最稳定的缓存)
#   [2] builder       : 编译本仓库的 cluster-proxy / addon-manager / addon-agent
#   [3] runtime       : 只拷贝最终产物 (无 Go 工具链、无源码、无包管理器残留)
#
# 核心设计点:
#   * --platform=$BUILDPLATFORM
#       构建阶段跑在"构建机原生架构"上, 由 Go 交叉编译 (GOOS/GOARCH) 产出目标架构
#       产物。避免了 QEMU 模拟执行带来的数倍性能损失, 是 buildx 多平台构建的关键。
#   * CGO_ENABLED=0
#       纯静态二进制, 运行阶段不依赖 glibc/musl, 可进一步换用 scratch/distroless。
#   * 依赖层前置
#       先 COPY go.mod/go.sum -> go mod download, 源码改动不会让依赖层失效。
#   * cache mount
#       Go module 缓存与编译缓存挂在 cache mount 上, 不写进镜像层, 跨构建复用。
#   * 下载产物校验
#       proxy tarball 与 kubectl 均做 sha256 校验, 锁定供应链。
#   * 产物裁剪
#       -trimpath (去掉构建机路径) + -ldflags "-s -w" (去掉符号表/调试信息)。
# =============================================================================

# --- 全局 ARG ---------------------------------------------------------------
# BuildKit 自动注入的预定义平台变量。必须在第一个 FROM 之前声明, 才能在
# FROM 的 --platform 中引用 (也可以不声明直接用, 但显式声明可读性更好)。
#   BUILDPLATFORM  : 构建器所在平台, 例如 linux/amd64 (CI runner)
#   TARGETPLATFORM : 目标平台,     例如 linux/arm64 (部署环境)
ARG BUILDPLATFORM
ARG TARGETPLATFORM

# =============================================================================
# Stage 1: proxy-builder
# -----------------------------------------------------------------------------
# 只做两件事:
#   1) 从 GitHub 拉取 apiserver-network-proxy 源码并编译 4 个二进制
#   2) 下载与目标平台匹配的 kubectl
#
# 为什么单独成 stage?
#   这部分内容与 cluster-proxy 自身源码完全无关, 只受
#   APISERVER_NETWORK_PROXY_VERSION / KUBECTL_VERSION 影响。
#   独立出来后, 改一行 Go 业务代码时, 这一层缓存 100% 命中, 不会重复下载和编译。
#
# 为什么不用 `go install sigs.k8s.io/apiserver-network-proxy/cmd/server@v0.36.0`?
#   因为该模块的 go.mod 里带有 replace 指令, Go 规定带 replace 的模块不允许
#   通过 `go install pkg@version` 安装 (会报 "contains one or more replace
#   directives"), 所以只能走源码归档的方式。
# =============================================================================
FROM --platform=$BUILDPLATFORM golang:1.26 AS proxy-builder

# ARG 只在当前 stage 内可见, 且不会被打进最终镜像
ARG TARGETOS=linux                                   # 目标操作系统
ARG TARGETARCH                                       # 目标 CPU 架构 (amd64/arm64)
ARG APISERVER_NETWORK_PROXY_VERSION=0.36.0
ARG KUBECTL_VERSION=v1.30.2
# GitHub 自动生成的源码归档不带官方签名/校验和, 这里锁定 sha256 防止被篡改
# (codeload 归档对同一 tag 是字节稳定的, 已实测校验一致)
ARG APISERVER_NETWORK_PROXY_SHA256=28e7766158efd496cef5d75155b38a8883a59aff8282bef65a5a7e5e6e6f8481

WORKDIR /workspace

# 只关闭 CGO, 目的是产出静态二进制。
# 注意: 这里刻意不在 ENV 里写 GOOS/GOARCH —— 否则 "go mod download" 会按目标
# 平台去拉依赖, 遇到只在其他平台存在的依赖时会出现 go.sum 校验失败。
# GOOS/GOARCH 改在真正执行 go build 的那一条 RUN 里通过 export 指定。
ENV CGO_ENABLED=0

# --- 下载 + 校验 + 解压 + 编译 proxy 的 4 个二进制 ---
# 说明:
#   curl -fsSL : 失败即退出 (-f), 且不输出进度条 (-s), 跟随重定向 (-L)
#   tar xzf    : 去掉原版里的 -v, 避免把文件列表刷进构建日志
#   --strip-components=1: 去掉归档里的顶层目录, 路径更短更可控
#   一次 RUN 内完成下载->编译->落盘, 避免产生多层无意义的中间层
RUN set -eux; \
    curl -fsSL -o /tmp/proxy.tar.gz \
      "https://github.com/kubernetes-sigs/apiserver-network-proxy/archive/refs/tags/v${APISERVER_NETWORK_PROXY_VERSION}.tar.gz"; \
    echo "${APISERVER_NETWORK_PROXY_SHA256}  /tmp/proxy.tar.gz" | sha256sum -c -; \
    mkdir -p /tmp/proxy-src; \
    tar xzf /tmp/proxy.tar.gz -C /tmp/proxy-src --strip-components=1; \
    cd /tmp/proxy-src; \
    go build -trimpath -ldflags="-s -w" -o /workspace/proxy-server       ./cmd/server/; \
    go build -trimpath -ldflags="-s -w" -o /workspace/proxy-agent        ./cmd/agent/; \
    go build -trimpath -ldflags="-s -w" -o /workspace/proxy-test-client ./cmd/test-client/; \
    go build -trimpath -ldflags="-s -w" -o /workspace/proxy-test-server ./cmd/test-server/; \
    rm -f /tmp/proxy.tar.gz

# --- 下载 kubectl 并用官方 sha256 校验 ---
# kubectl 是官方用 Go 静态编译的, 同样不依赖 libc;
# dl.k8s.io 会同时提供 .sha256 文件, 直接拿来用即可。
RUN set -eux; \
    base_url="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${TARGETOS}/${TARGETARCH}"; \
    curl -fsSL -o /workspace/kubectl "${base_url}/kubectl"; \
    curl -fsSL -o /tmp/kubectl.sha256 "${base_url}/kubectl.sha256"; \
    sum="$(awk '{print $1}' /tmp/kubectl.sha256)"; \
    echo "${sum}  /workspace/kubectl" | sha256sum -c -; \
    chmod 0755 /workspace/kubectl

# =============================================================================
# Stage 2: builder
# -----------------------------------------------------------------------------
# 编译本仓库自己的三个二进制。使用与 Stage 1 相同的 golang 镜像, 但分开成两个
# stage, 目的就是让两边的缓存互不干扰。
# =============================================================================
FROM --platform=$BUILDPLATFORM golang:1.26 AS builder

ARG TARGETOS=linux
ARG TARGETARCH
# addon-manager 需要在启动时知道 addon-agent 镜像名, 编译期用 -ldflags -X 注入
ARG ADDON_AGENT_IMAGE_NAME
# 预留: 版本号注入 (需与代码里的变量名一致)
ARG VERSION=dev

WORKDIR /workspace

ENV CGO_ENABLED=0

# --- 第一步: 只拷贝依赖清单, 然后预热依赖 ---
# 这一层只有 go.mod / go.sum 变化时才会失效, 业务代码怎么改都不影响它。
COPY go.mod go.sum ./

# cache mount: Go 模块缓存放在 /go/pkg/mod。
#   * 不会写进镜像层 -> 不污染构建产物
#   * 在 CI 的多次构建之间复用 -> 第二次构建几乎不用再走网络
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    go mod download

# --- 第二步: 拷贝源码 ---
COPY cmd/ cmd/
COPY pkg/ pkg/

# --- 第三步: 编译三个二进制 (合并成一条 RUN) ---
# 关键点:
#   * GOOS/GOARCH 在这里才 export —— 前面 "go mod download" 用的是原生平台
#   * 去掉原版的 -a: -a 会强制重建所有包(含标准库), 编译时间成倍增加, 且
#     现代 Go 已不需要它
#   * -trimpath: 去掉构建机的绝对路径, 产物可复现、不泄露内部路径
#   * -buildvcs=false: 避免容器内缺少 .git 或 git 属主不一致时
#     "error obtaining VCS status" 导致构建失败
#   * -ldflags "-s -w": 去掉符号表和 DWARF 调试信息, 二进制显著变小
#   * 三个二进制放在同一条 RUN 里, 减少镜像层数
RUN --mount=type=cache,target=/go/pkg/mod,sharing=locked \
    --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    set -eux; \
    export GOOS="${TARGETOS}" GOARCH="${TARGETARCH}"; \
    go build -trimpath -buildvcs=false -ldflags="-s -w" \
      -o /workspace/agent cmd/addon-agent/main.go; \
    go build -trimpath -buildvcs=false \
      -ldflags="-s -w -X 'open-cluster-management.io/cluster-proxy/pkg/config.AgentImageName=${ADDON_AGENT_IMAGE_NAME}'" \
      -o /workspace/manager cmd/addon-manager/main.go; \
    go build -trimpath -buildvcs=false -ldflags="-s -w" \
      -o /workspace/cluster-proxy cmd/cluster-proxy/main.go

# =============================================================================
# Stage 3: runtime
# -----------------------------------------------------------------------------
# 最终镜像。这里"只有"运行所需的东西:
#   7 个静态二进制 + CA 根证书。没有任何 Go 工具链、源码、中间产物。
# =============================================================================
FROM alpine:3.21 AS runtime

LABEL org.opencontainers.image.title="cluster-proxy" \
      org.opencontainers.image.description="Open Cluster Management cluster-proxy (multi-stage build demo)" \
      org.opencontainers.image.source="https://github.com/open-cluster-management-io/cluster-proxy" \
      org.opencontainers.image.licenses="Apache-2.0"

WORKDIR /

# CA 根证书: kubectl / proxy-server 访问 Kubernetes APIServer 走 HTTPS,
# 没有 CA bundle 会直接 x509 证书校验失败。
# (alpine 自带 ca-certificates-bundle, 这里显式安装完整包以保证证书是最新的;
#  如果追求极致精简, 可改用 distroless/static, 见文件末尾的备选方案)
RUN apk add --no-cache ca-certificates

# --- 从 proxy-builder 拷贝 proxy 组件 ---
COPY --from=proxy-builder /workspace/proxy-server       /proxy-server
COPY --from=proxy-builder /workspace/proxy-agent        /proxy-agent
COPY --from=proxy-builder /workspace/proxy-test-client  /proxy-test-client
COPY --from=proxy-builder /workspace/proxy-test-server  /proxy-test-server
COPY --from=proxy-builder /workspace/kubectl            /kubectl

# --- 从 builder 拷贝本仓库组件 ---
COPY --from=builder /workspace/agent                    /agent
COPY --from=builder /workspace/manager                  /manager
COPY --from=builder /workspace/cluster-proxy            /cluster-proxy

# 以非 root 身份运行 (65532 是 distroless nonroot 的约定 uid/gid)。
# 用数字 uid 而非用户名, 无需在镜像里创建用户, 也不额外增加镜像层。
# 注意: 数字 uid 在 /etc/passwd 里没有对应条目, 因此容器内 `whoami` 会报错,
#       这是正常现象。
USER 65532:65532

# 本镜像是一个"多用途基础镜像": cluster-proxy / addon-manager / addon-agent
# 三个可执行文件由外部 (K8s Deployment 的 command/args) 指定, 因此这里
# 故意不写 ENTRYPOINT/CMD, 与上游行为保持一致。
#
# --- 构建与运行示例 -------------------------------------------------
#   # 单架构构建
#   docker build -t cluster-proxy:dev .
#
#   # 多架构构建 (buildx), 交叉编译 linux/amd64 + linux/arm64
#   docker buildx build \
#     --platform linux/amd64,linux/arm64 \
#     --build-arg ADDON_AGENT_IMAGE_NAME=quay.io/xxx/addon-agent:latest \
#     -t registry.example.com/cluster-proxy:v1.2.3 \
#     --push .
#
#   # 本地运行
#   docker run --rm -it --entrypoint /bin/sh cluster-proxy:dev
# =============================================================================

# =============================================================================
# 备选方案: 更小的 runtime
# -----------------------------------------------------------------------------
# 本项目所有二进制都是 CGO_ENABLED=0 的静态 Go 程序, 因此 runtime 阶段其实
# 可以换成没有 shell、没有包管理器的极简镜像:
#
#   FROM gcr.io/distroless/static:nonroot AS runtime
#   COPY --from=proxy-builder /workspace/kubectl /kubectl
#   COPY --from=builder       /workspace/manager /manager
#   ...
#   USER nonroot
#
# 代价: 容器内无法 exec 进 shell 调试 (需要 kubectl debug 或临时挂 busybox)。
# 收益: 镜像再小 5-8MB, CVE 数量进一步下降, 攻击面几乎为零。
# =============================================================================
