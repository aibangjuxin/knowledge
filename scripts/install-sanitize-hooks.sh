#!/usr/bin/env bash
# install-sanitize-hooks.sh — 安装内部标识符闸门钩子
#
# 装两个钩子：
#   .git/hooks/pre-commit  → 提交前扫描暂存区
#   .git/hooks/pre-push    → 推送前扫描待推送的提交
#
# 钩子位于 .git/hooks/，不随仓库提交，也不会泄露任何代号。
# 钩子本体不含代号，只调用仓库里的 scripts/sanitize-check.sh，
# 由后者读取本机 .git/sanitize-denylist.txt。
#
# 用法： bash scripts/install-sanitize-hooks.sh

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "不在 git 仓库内" >&2; exit 1; }
cd "$ROOT" || exit 1

HOOKS="$ROOT/.git/hooks"
CHECK="$ROOT/scripts/sanitize-check.sh"

if [ ! -f "$CHECK" ]; then
  echo "找不到 $CHECK，无法安装。" >&2
  exit 1
fi

mkdir -p "$HOOKS"
chmod +x "$CHECK"

cat > "$HOOKS/pre-commit" <<'HOOK'
#!/bin/sh
# pre-commit — 内部标识符闸门（由 scripts/install-sanitize-hooks.sh 生成）
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
if [ ! -x "$ROOT/scripts/sanitize-check.sh" ]; then
  echo "ℹ️  sanitize-check: 检查脚本缺失，本次提交跳过。" >&2
  exit 0
fi
exec "$ROOT/scripts/sanitize-check.sh" --staged
HOOK

cat > "$HOOKS/pre-push" <<'HOOK'
#!/bin/sh
# pre-push — 内部标识符闸门（由 scripts/install-sanitize-hooks.sh 生成）
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
if [ ! -x "$ROOT/scripts/sanitize-check.sh" ]; then
  echo "ℹ️  sanitize-check: 检查脚本缺失，本次推送跳过。" >&2
  exit 0
fi
exec "$ROOT/scripts/sanitize-check.sh" --push
HOOK

chmod +x "$HOOKS/pre-commit" "$HOOKS/pre-push"

echo "✅ 已安装："
echo "   $HOOKS/pre-commit"
echo "   $HOOKS/pre-push"
echo ""
if [ -f "$ROOT/.git/sanitize-denylist.txt" ]; then
  n="$(grep -cvE '^[[:space:]]*(#|$)' "$ROOT/.git/sanitize-denylist.txt" 2>/dev/null || echo 0)"
  echo "📋 本机清单：.git/sanitize-denylist.txt（$n 条规则）"
else
  echo "⚠️  未找到 .git/sanitize-denylist.txt —— 闸门会放行一切。"
  echo "   在本机创建该文件即可启用（每行一个代号，勿提交）。"
fi
