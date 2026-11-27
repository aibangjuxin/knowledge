#!/usr/bin/env bash
# ===========================================================================
# entrypoint.sh —— 容器入口
#
# 职责：
#   1. 如果镜像里有 source.zip（bundle 模式），解压到 APP_HOME 覆盖源码
#   2. 打印运行时环境（版本、ADC 状态等）
#   3. exec python3 /app/main.py "$@"
#
# 用 exec 是为了让 python 成为 PID 1，能正确收到 docker stop 的 SIGTERM。
# ===========================================================================
set -euo pipefail

APP_HOME="${APP_HOME:-/app}"
ZIP_PATH="${BUNDLE_ZIP:-/tmp/source.zip}"

# ---- 1. bundle 解压 ----
if [ -f "$ZIP_PATH" ]; then
  echo ">>> 检测到 bundle: $ZIP_PATH"
  STAGE="${APP_HOME}.bundle"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  unzip -q -o "$ZIP_PATH" -d "$STAGE"

  # bundle 内有两种布局：
  #   a) app/xxx  → 解到 $STAGE/app，把 app/ 的内容铺到 $APP_HOME
  #   b) xxx      → 直接铺到 $APP_HOME
  if [ -d "$STAGE/app" ]; then
    cp -R "$STAGE/app/." "$APP_HOME/"
  else
    cp -R "$STAGE/." "$APP_HOME/"
  fi

  if [ -f "$STAGE/MANIFEST.json" ]; then
    echo ">>> bundle manifest:"
    cat "$STAGE/MANIFEST.json"
    echo
  fi
  rm -rf "$STAGE"
  echo ">>> bundle 已展开到 $APP_HOME"
  echo
fi

# 兜底：如果 main.py 不在 APP_HOME，找一下 bundle 解压后的位置
if [ ! -f "$APP_HOME/main.py" ]; then
  FOUND="$(find "$APP_HOME" -maxdepth 3 -name main.py -type f 2>/dev/null | head -1)"
  if [ -n "$FOUND" ]; then
    echo ">>> main.py 实际位置: $FOUND"
    APP_HOME="$(dirname "$FOUND")"
  fi
fi

# ---- 2. 打印运行时环境 ----
echo "=========================================================="
echo " SMS Secret Onboarding"
echo " releaseVersion : ${RELEASE_VERSION:-unknown}"
echo " buildTime      : ${BUILD_TIME:-unknown}"
echo " appHome        : $APP_HOME"
echo " python         : $(python3 --version 2>&1)"
echo "=========================================================="
echo

# ---- 3. 交给 main.py ----
cd "$APP_HOME"
exec python3 "$APP_HOME/main.py" "$@"
