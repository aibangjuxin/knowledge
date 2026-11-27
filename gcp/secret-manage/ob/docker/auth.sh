#!/usr/bin/env bash
# ===========================================================================
# auth.sh —— 在 jumpbox 容器里完成授权，产出 Python SDK 可用的 ADC
#
# 为什么需要这个脚本（实测结论）：
#   gcloud auth login                      → 写 credentials.db   （gcloud CLI 专用）
#   gcloud auth application-default login  → 写 application_default_credentials.json
#                                             （Python SDK / google-auth 读这个）
#
# 所以要让容器里的 Python 脚本能调 GCP API，必须跑 ADC 那条命令。
#
# 用法：
#   ./docker/auth.sh              # 生成 ADC（推荐）
#   ./docker/auth.sh --gcloud     # 只做 gcloud CLI 登录（给 gcloud 命令用）
#   ./docker/auth.sh --both       # 两条都做
# ===========================================================================
set -euo pipefail

IMAGE="${JUMPBOX_IMAGE:-jumpbox:latest}"
PLATFORM="${JUMPBOX_PLATFORM:-linux/amd64}"
CFG="${JUMPBOX_CONFIG_DIR:-$HOME/.config/gcloud-jumpbox}"
GCLOUD_BIN="${GCLOUD_BIN:-/root/google-cloud-sdk/bin/gcloud}"

MODE="${1:---adc}"

mkdir -p "$CFG"

run_gcloud() {
  docker run --rm -it \
    --platform "$PLATFORM" \
    -e CLOUDSDK_CONFIG=/root/.config/gcloud \
    -v "$CFG:/root/.config/gcloud" \
    --entrypoint "$GCLOUD_BIN" \
    "$IMAGE" \
    "$@"
}

case "$MODE" in
  --both)
    run_gcloud auth login --no-launch-browser
    echo
    run_gcloud auth application-default login --no-launch-browser
    ;;
  --gcloud)
    run_gcloud auth login --no-launch-browser
    ;;
  --adc)
    run_gcloud auth application-default login --no-launch-browser
    ;;
  *)
    echo "用法: $0 [--adc|--gcloud|--both]" >&2
    exit 2
    ;;
esac

echo
echo "✅ 完成。凭据目录：$CFG"
ls -la "$CFG" || true
