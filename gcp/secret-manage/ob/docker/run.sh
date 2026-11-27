#!/usr/bin/env bash
# ===========================================================================
# run.sh —— 统一的 docker run 封装
#
# 用法：
#   ./docker/run.sh                          # 用默认配置跑全部步骤
#   ./docker/run.sh --dry-run                # 不调 API
#   ./docker/run.sh --only onboarding         # 只跑一步
#   TARGET_ENV=prod API_NAME=myapi ./docker/run.sh    # 环境变量覆盖
#
# 环境变量：
#   IMAGE                 镜像名（默认 sms-secret-onboarding:latest）
#   TARGET_ENV            → targetEnv
#   API_NAME              → apiName
#   TEAM_NAME             → teamName
#   REGION                → region
#   TICKET_NUM            → ticketNum
#   SECRET_PROJECT_ID     → secretProjectId
#   PROJECT_GCP_SA        → projectGcpSa
#   RELEASE_VERSION       发布版本号（仅日志）
#   RELEASE_BY            发布人（仅日志）
#   JUMPBOX_CONFIG_DIR    凭据目录（默认 $HOME/.config/gcloud-jumpbox）
#   CONFIG_DIR            配置文件目录（默认 <repo>/app/config）
# ===========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

IMAGE="${IMAGE:-sms-secret-onboarding:latest}"
CONFIG_DIR="${CONFIG_DIR:-$ROOT/app/config}"
JUMPBOX_CONFIG_DIR="${JUMPBOX_CONFIG_DIR:-$HOME/.config/gcloud-jumpbox}"
PLATFORM="${PLATFORM:-}"

# ---- 组装 docker run 参数 ----
DOCKER_ARGS=(--rm)

# --platform（Apple Silicon 上 amd64 镜像需要）
if [ -n "$PLATFORM" ]; then
  DOCKER_ARGS+=(--platform "$PLATFORM")
fi

# ---- 凭据挂载（可选）----
# 注意：Python SDK 需要的是 ADC json，不是 gcloud CLI 的 credentials.db。
# 详见 docker/README.md「凭据」一节。
if [ -d "$JUMPBOX_CONFIG_DIR" ]; then
  DOCKER_ARGS+=(-v "$JUMPBOX_CONFIG_DIR:/root/.config/gcloud:ro")

  if [ -f "$JUMPBOX_CONFIG_DIR/application_default_credentials.json" ]; then
    DOCKER_ARGS+=(
      -e GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json
    )
  fi
fi

# ---- 配置挂载 ----
DOCKER_ARGS+=(-v "$CONFIG_DIR:/app/config:ro")

# ---- 环境变量透传 ----
# 只有「在 ENV_TO_CONFIG 映射表里」或「元信息」的变量才透传，避免泄漏宿主环境
PASS_ENV=(
  TARGET_ENV REGION TEAM_NAME API_NAME TICKET_NUM
  SECRET_PROJECT_ID PROJECT_GCP_SA
  IAM_ENABLE UPDATE_SECRET_ACCESS GRANT_GROUP_ACCESSOR
  EIM_APP_ID CHANGE_FILE_NAME TRIGGER_JOB_TIMEOUT SOURCE_VERSION
  JENKINS_PROJECT_NAME
  RELEASE_VERSION RELEASE_BY BUILD_TIME
)

for k in "${PASS_ENV[@]}"; do
  if [ -n "${!k:-}" ]; then
    DOCKER_ARGS+=(-e "$k=${!k}")
  fi
done

# ---- 传给 main.py 的参数 ----
MAIN_ARGS=("$@")
if [ ${#MAIN_ARGS[@]} -eq 0 ]; then
  MAIN_ARGS=(run --config-dir /app/config)
fi

echo ">>> $IMAGE ${MAIN_ARGS[*]}"

exec docker "${DOCKER_ARGS[@]}" "$IMAGE" "${MAIN_ARGS[@]}"
