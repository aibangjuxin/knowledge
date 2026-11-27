#!/usr/bin/env bash
# ===========================================================================
# build.sh —— 构建不可变（immutable）发布镜像
#
# 两种打包策略：
#   A. layered（默认）—— 直接 COPY 源码进镜像层
#      * 优点：简单、构建快、层缓存友好
#      * 缺点：换代码必须重新 build
#
#   B. bundle —— 先把源码打成 zip 塞进镜像，容器启动时再解压执行
#      * 优点：镜像可复用，同一个 runtime 镜像能跑不同版本的代码包
#      * 缺点：多一层解压、启动慢一点
#
# 用法：
#   ./docker/build.sh                        # layered
#   ./docker/build.sh --bundle               # bundle（源码打成 zip）
#   ./docker/build.sh --version 1.2.3        # 指定版本号
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"          # ob/
cd "$ROOT"

VERSION="0.1.0"
MODE="layered"

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle)  MODE="bundle"; shift ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

IMAGE="sms-secret-onboarding:$VERSION"
BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ">>> 构建镜像: $IMAGE (mode=$MODE, buildTime=$BUILD_TIME)"
echo ">>> 构建上下文: $ROOT"

if [ "$MODE" = "bundle" ]; then
  # ---- 策略 B：源码打成 zip，放进 bundle/ 目录 ----
  echo ">>> 打包源码 zip..."
  rm -rf /tmp/sms-bundle && mkdir -p /tmp/sms-bundle/app

  cp -R app/main.py app/common.py app/steps app/config app/requirements.txt /tmp/sms-bundle/app/

  # 写一份版本清单，容器里可以读
  cat > /tmp/sms-bundle/MANIFEST.json <<EOF
{
  "releaseVersion": "$VERSION",
  "buildTime": "$BUILD_TIME",
  "bundledAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

  (cd /tmp/sms-bundle && zip -qr "$ROOT/docker/source.zip" .)
  echo ">>> source.zip: $(ls -lh "$ROOT/docker/source.zip" | awk '{print $5}')"
fi

docker build \
  -f docker/Dockerfile \
  --build-arg "RELEASE_VERSION=$VERSION" \
  --build-arg "BUILD_TIME=$BUILD_TIME" \
  --label "org.opencontainers.image.version=$VERSION" \
  --label "org.opencontainers.image.created=$BUILD_TIME" \
  -t "$IMAGE" \
  "$ROOT"

if [ "$MODE" = "bundle" ]; then
  rm -f "$ROOT/docker/source.zip"
fi

echo
echo "✅ 构建完成: $IMAGE"
docker images "$IMAGE" | head -3
echo
echo "运行："
echo "  $HERE/run.sh --dry-run"
