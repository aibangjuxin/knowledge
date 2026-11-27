# ===========================================================================
# SMS Secret Manager Onboarding —— 运行镜像
#
# 设计原则（不可变 / Immutable）
#   * 镜像里只放「代码 + 依赖」，不放配置、不放凭据、不放密钥
#   * 配置：运行时 -v 挂载 或 -e 环境变量注入
#   * 凭据：运行时 -v 挂载 ADC 目录（见 docker/README.md「凭据」一节）
#   * 版本信息：build 时打进 OCI label，运行时用 -e RELEASE_VERSION 传业务版本
#
# 构建（推荐用 docker/build.sh）：
#   cd ob && ./docker/build.sh --version 1.2.3
#
# 手动构建：
#   cd ob && docker build -f docker/Dockerfile -t sms-secret-onboarding:0.1.0 .
#
# 运行：
#   docker run --rm \
#     -e TARGET_ENV=prod -e API_NAME=myapi -e RELEASE_VERSION=1.2.3 \
#     -v "$PWD/app/config:/app/config:ro" \
#     -v "$HOME/.config/gcloud-jumpbox:/root/.config/gcloud:ro" \
#     -e GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json \
#     sms-secret-onboarding:1.2.3 run --config-dir /app/config
# ===========================================================================

FROM python:3.11-slim

# 构建参数（build.sh 会传）
ARG RELEASE_VERSION=0.1.0
ARG BUILD_TIME=unknown

LABEL org.opencontainers.image.title="sms-secret-onboarding" \
      org.opencontainers.image.description="Secret Manager onboarding/create pipeline" \
      org.opencontainers.image.version="$RELEASE_VERSION" \
      org.opencontainers.image.created="$BUILD_TIME" \
      org.opencontainers.image.source="git@company.local:infra/sms-secret-onboarding.git"

ENV TZ=Europe/London \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    RELEASE_VERSION="$RELEASE_VERSION" \
    BUILD_TIME="$BUILD_TIME" \
    APP_HOME=/app

# 时区 + 证书链（调用 Google API 需要）
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        tzdata \
        unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR "$APP_HOME"

# ---- 依赖层（利用 Docker layer cache，改代码不会重装依赖）----
COPY app/requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

# ---- 代码层（不可变）----
COPY app/main.py           /app/main.py
COPY app/common.py         /app/common.py
COPY app/steps/            /app/steps/
COPY app/config/           /app/config/

# ---- bundle 模式（可选）：源码 zip，容器启动时解压覆盖 ----
# build.sh --bundle 会把 docker/source.zip 放到构建上下文里
COPY docker/source.zip*   /tmp/source.zip
COPY docker/entrypoint.sh  /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---- 运行时目录 ----
RUN mkdir -p /app/config /run/sms-secret \
    && chmod 700 /run/sms-secret

# 声明挂载点，方便 docker run 时知道该挂什么
VOLUME ["/app/config"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["--help"]
