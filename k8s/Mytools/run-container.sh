#!/bin/bash

# Kali Linux 容器启动脚本
# 自动挂载配置目录并启动容器

set -e

# 配置变量
CONTAINER_NAME="kali-tools"
IMAGE_NAME="my-kali-tools"
HOST_CONFIG_DIR="$(pwd)/host-config"  # 宿主机配置目录
CONTAINER_CONFIG_DIR="/opt/share"      # 容器内挂载点

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    log_error "Docker 未运行，请先启动 Docker"
    exit 1
fi

# 创建宿主机配置目录结构
log_info "创建宿主机配置目录..."
mkdir -p "$HOST_CONFIG_DIR"/{tools,scripts,projects,notes,logs,wordlists,backups}
mkdir -p "$HOST_CONFIG_DIR"/.ssh
mkdir -p "$HOST_CONFIG_DIR"/.kube

# 复制配置模板（如果不存在）
if [ ! -f "$HOST_CONFIG_DIR/mount-config.sh" ]; then
    log_info "复制配置模板..."
    cp mount-config-template.sh "$HOST_CONFIG_DIR/mount-config.sh"
    chmod +x "$HOST_CONFIG_DIR/mount-config.sh"
    log_success "配置模板已复制，请编辑 $HOST_CONFIG_DIR/mount-config.sh"
fi

if [ ! -f "$HOST_CONFIG_DIR/custom.sh" ]; then
    cp example-custom.sh "$HOST_CONFIG_DIR/custom.sh"
    chmod +x "$HOST_CONFIG_DIR/custom.sh"
    log_success "自定义配置模板已复制"
fi

if [ ! -f "$HOST_CONFIG_DIR/.zshrc.custom" ]; then
    cp example-.zshrc.custom "$HOST_CONFIG_DIR/.zshrc.custom"
    log_success "自定义 .zshrc 模板已复制"
fi

# 停止并删除现有容器（如果存在）
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log_info "停止现有容器..."
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# 构建镜像（如果不存在）
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}:latest$"; then
    log_info "构建 Docker 镜像..."
    docker build -t "$IMAGE_NAME" .
    log_success "镜像构建完成"
fi

# 准备挂载参数
MOUNT_ARGS=(
    -v "$(pwd):/workspace"                    # 工作目录
    -v "$HOST_CONFIG_DIR:$CONTAINER_CONFIG_DIR"  # 配置目录
)

# 如果存在 .kube 配置，挂载它
if [ -d "$HOME/.kube" ]; then
    MOUNT_ARGS+=(-v "$HOME/.kube:/root/.kube:ro")
    log_info "挂载 Kubernetes 配置"
fi

# 如果存在 .ssh 配置，挂载它
if [ -d "$HOME/.ssh" ]; then
    MOUNT_ARGS+=(-v "$HOME/.ssh:/root/.ssh-host:ro")
    log_info "挂载 SSH 配置"
fi

# 启动容器
log_info "启动容器..."
docker run -it --rm \
    --name "$CONTAINER_NAME" \
    --hostname "kali-security" \
    "${MOUNT_ARGS[@]}" \
    -e "PROXY_HOST=192.168.31.198" \
    -e "PROXY_PORT=7221" \
    -e "GIT_USER_NAME=Your Name" \
    -e "GIT_USER_EMAIL=your.email@example.com" \
    "$IMAGE_NAME"

log_success "容器已退出"