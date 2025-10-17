#!/usr/bin/env bash
# 查询指定 Ubuntu 版本的 CVE 修复状态
# 适用于 Ubuntu 20.04 / 22.04 / 24.04 / 25.04 等版本

set -e

# 使用方法： ./check_ubuntu_cve_status.sh CVE-2025-8941 noble
# 示例： ./check_ubuntu_cve_status.sh CVE-2025-8941 noble

CVE_ID="$1"
UBUNTU_CODENAME="$2"

if [ -z "$CVE_ID" ] || [ -z "$UBUNTU_CODENAME" ]; then
  echo "Usage: $0 <CVE-ID> <ubuntu-codename>"
  echo "Example: $0 CVE-2025-8941 noble"
  exit 1
fi

# 临时文件
TMPFILE=$(mktemp)

# 下载 Ubuntu 官方 CVE 页面（HTML）
echo "[INFO] Fetching CVE info from ubuntu.com for $CVE_ID ..."
curl -s -L "https://ubuntu.com/security/$CVE_ID" -o "$TMPFILE"

# 检查是否找到页面
if ! grep -q "$CVE_ID" "$TMPFILE"; then
  echo "[ERROR] CVE not found on ubuntu.com"
  rm -f "$TMPFILE"
  exit 1
fi

# 提取目标 Ubuntu 版本行（如 24.04 noble）
echo
echo "========== Security Status for $UBUNTU_CODENAME =========="
grep -A 5 -i "$UBUNTU_CODENAME" "$TMPFILE" | sed 's/<[^>]*>//g' | sed 's/&nbsp;//g' | grep -vE '^\s*$'

echo "=========================================================="

rm -f "$TMPFILE"