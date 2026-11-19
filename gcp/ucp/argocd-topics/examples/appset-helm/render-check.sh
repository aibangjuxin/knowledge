#!/usr/bin/env bash
# 本地验证「Helm 渲染 ApplicationSet」这条链路的转义有没有写对。
#
# 检查点（都是踩过的坑）：
#   ① ApplicationSet 模板里的 {{ }} 必须**原样保留**给 ApplicationSet controller
#   ② chart 自己的变量（{{ $t.xxx }}）必须被 Helm 渲染掉，不能有残留
#   ③ valueFiles 路径拼出来的样子要对
#
# 用法：./render-check.sh
set -euo pipefail
cd "$(dirname "$0")"

command -v helm >/dev/null 2>&1 || {
  echo "✗ 需要 helm：brew install helm" >&2
  exit 1
}

out="$(helm template platform-cp cp-chart)"
fail=0

check() { # check <描述> <期望出现的字符串>
  if grep -qF -- "$2" <<<"$out"; then
    echo "✓ $1"
  else
    echo "✗ $1 —— 没找到：$2"
    fail=1
  fi
}

check "ApplicationSet 名字模板原样保留" '{{ .app.path.basename }}-{{ .cluster.path.basename }}'
check "source.path 模板原样保留" "path: '{{ .app.path.path }}'"
check "destination.server 模板原样保留" "server: '{{ .server }}'"
check "valueFiles 路径模板原样保留" '../../clusters/{{ .cluster.path.basename }}/values.yaml'
check "chart 变量已被 Helm 渲染（不该有残留）" "project: \"tenant-a\""
check "AppProject 已渲染" "kind: AppProject"

if grep -qF '{{ $t.' <<<"$out"; then
  echo "✗ chart 变量没渲染干净（出现了 {{ \$t. ... }}）"
  fail=1
else
  echo "✓ chart 变量渲染干净"
fi

if grep -qF '{{`' <<<"$out"; then
  echo "✗ 反引号没被吃掉（出现了 {{`...`}}）"
  fail=1
else
  echo "✓ 反引号已正确消化"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ 全部通过"
  echo
  echo "渲染结果（ApplicationSet 部分）："
  echo "$out" | awk '/kind: ApplicationSet/,0' | head -60
else
  echo "✗ 有检查没过"
  exit 1
fi
