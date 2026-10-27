#!/usr/bin/env bash
# =============================================================================
# 90-teardown.sh
# =============================================================================
# 清理本 PoC —— 因为用了独立 namespace,回滚就是删 ns
#
# 用法:
#   bash 90-teardown.sh            # 只删 ns(推荐)
#   bash 90-teardown.sh --purge    # 删 ns + 清掉 cluster 级残留
# =============================================================================
set -euo pipefail

NS=ba000000-lex-intra-call

echo "==> 清理 namespace: ${NS}"
kubectl delete namespace "${NS}" --ignore-not-found --wait=false

echo "==> 等待 namespace 真正删除中(后台继续,不影响后续操作)"
if ! kubectl wait --for=delete "namespace/${NS}" --timeout=180s 2>/dev/null; then
  echo "    (namespace 仍在 terminating,通常 1~3 分钟内完成)"
fi

if [ "${1:-}" = "--purge" ]; then
  echo "==> 检查 cluster 级残留"
  kubectl get gateway -A | grep -E "waypoint-intra" || echo "    (无残留)"
  kubectl get mutatingwebhookconfiguration,validatingwebhookconfiguration 2>/dev/null \
    | grep -i "istio" | head -5 || true
fi

echo "==> 完成。验证:"
echo "    kubectl get ns ${NS}   # 应为 NotFound"
