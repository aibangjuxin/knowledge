#!/usr/bin/env bash
# Argo CD 一键体检脚本
#
# 用法：
#   ./argocd-health.sh              # 全局体检
#   ./argocd-health.sh my-app       # 附带某个 Application 的详情
#   NS=argocd-prod ./argocd-health.sh
#
# 特性：**纯只读**，不修改任何集群资源。
# 退出码：0 = 无异常；1 = 有异常项（见输出中的 ⚠️ 标记）
#
# ---------------------------------------------------------------------------
# 它和同目录其它脚本的分工：
#   argocd-health.sh      ← **运行时**体检（要连集群，看的是活的状态）
#   validate-examples.py  ← **静态**体检（不连集群，看的是配置文件本身）
#   check-doc-links.py    ← 文档链接体检
# ---------------------------------------------------------------------------
set -uo pipefail

NS=${NS:-argocd}
APP=${1:-}
WARN=0

hdr() { printf '\n=== %s ===\n' "$1"; }
warn() { printf '⚠️  %s\n' "$1"; WARN=1; }
ok()   { printf '✅ %s\n' "$1"; }

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found"; exit 2; }
kubectl get ns "$NS" >/dev/null 2>&1 || { echo "namespace '$NS' not found"; exit 2; }

# ---------------------------------------------------------------------------
hdr "组件状态"
kubectl -n "$NS" get pods -o wide 2>/dev/null || warn "无法列出 Pod"

# ---------------------------------------------------------------------------
hdr "副本数一致性（API_SERVER_REPLICAS 必须等于 replicas）"
SRV_REPL=$(kubectl -n "$NS" get deploy argocd-server -o jsonpath='{.spec.replicas}' 2>/dev/null)
SRV_ENV=$(kubectl -n "$NS" get deploy argocd-server \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ARGOCD_API_SERVER_REPLICAS")].value}' 2>/dev/null)
printf 'argocd-server replicas        = %s\n' "${SRV_REPL:-N/A}"
printf 'ARGOCD_API_SERVER_REPLICAS   = %s\n' "${SRV_ENV:-N/A}"
if [ -n "${SRV_REPL:-}" ] && [ -n "${SRV_ENV:-}" ] && [ "$SRV_REPL" != "$SRV_ENV" ]; then
  warn "两者不一致 → 登录会被限流误拒（上游 issue #11387 / #15223）"
elif [ -n "${SRV_REPL:-}" ] && [ "$SRV_REPL" -gt 1 ] 2>/dev/null; then
  ok "一致"
fi

# ---------------------------------------------------------------------------
hdr "dex-server 副本数（HA 下必须为 1）"
DEX_REPL=$(kubectl -n "$NS" get deploy argocd-dex-server -o jsonpath='{.spec.replicas}' 2>/dev/null)
printf 'argocd-dex-server replicas = %s\n' "${DEX_REPL:-N/A}"
if [ "${DEX_REPL:-1}" != "1" ]; then
  warn "dex-server 应保持 1 副本（内存数据库，多副本登录态不一致）"
fi

# ---------------------------------------------------------------------------
hdr "Redis 持久化事实"
REDIS_ARGS=$(kubectl -n "$NS" get deploy argocd-redis \
  -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)
REDIS_VOLS=$(kubectl -n "$NS" get deploy argocd-redis \
  -o jsonpath='{.spec.template.spec.volumes}' 2>/dev/null)
REDIS_MOUNTS=$(kubectl -n "$NS" get deploy argocd-redis \
  -o jsonpath='{.spec.template.spec.containers[0].volumeMounts}' 2>/dev/null)
printf 'args         = %s\n' "${REDIS_ARGS:-N/A}"
printf 'volumes      = %s\n' "${REDIS_VOLS:-<none>}"
printf 'volumeMounts = %s\n' "${REDIS_MOUNTS:-<none>}"
if [ -z "${REDIS_VOLS:-}" ]; then
  ok "无持久卷（Argo CD 内部 Redis 的官方设计，无需持久化）"
fi

# ---------------------------------------------------------------------------
hdr "身份与权限"
ADMIN=$(kubectl -n "$NS" get cm argocd-cm -o jsonpath='{.data.admin\.enabled}' 2>/dev/null)
SCOPES=$(kubectl -n "$NS" get cm argocd-rbac-cm -o jsonpath='{.data.scopes}' 2>/dev/null)
POLDEF=$(kubectl -n "$NS" get cm argocd-rbac-cm -o jsonpath='{.data.policy\.default}' 2>/dev/null)
printf 'admin.enabled = %s\n' "${ADMIN:-<unset → true>}"
printf 'rbac scopes   = %s\n' "${SCOPES:-<unset>}"
printf 'policy.default= %s\n' "${POLDEF:-<unset>}"
if [ -n "${SCOPES:-}" ] && ! printf '%s' "$SCOPES" | grep -q 'groups'; then
  warn "rbac scopes 不含 groups → 组映射不会生效"
fi
if [ "${ADMIN:-}" = "true" ] || [ -z "${ADMIN:-}" ]; then
  warn "内置 admin 仍启用 → 确认这是有意的（禁用前必须先验证组映射）"
fi

# ---------------------------------------------------------------------------
hdr "Application 项目分布（落在 default 的应为空）"
DEF_APPS=$(kubectl -n "$NS" get applications \
  -o jsonpath='{range .items[?(@.spec.project=="default")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
if [ -z "${DEF_APPS:-}" ]; then
  ok "没有 Application 落在 default 项目"
else
  warn "以下 Application 在 default 项目（最宽松，需迁移）："
  printf '%s\n' "$DEF_APPS" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
hdr "AppProject 定义"
kubectl -n "$NS" get appprojects 2>/dev/null || warn "无法列出 AppProject"

# ---------------------------------------------------------------------------
hdr "ApplicationSet 状态"
kubectl -n "$NS" get applicationsets 2>/dev/null || warn "无法列出 ApplicationSet"

# ---------------------------------------------------------------------------
hdr "准入控制器（Gatekeeper 相关）"
kubectl get validatingwebhookconfiguration 2>/dev/null | head -20
GK=$(kubectl get validatingwebhookconfiguration 2>/dev/null \
      | awk '/gatekeeper/ {print $1}')
for w in $GK; do
  FP=$(kubectl get validatingwebhookconfiguration "$w" \
        -o jsonpath='{.webhooks[*].failurePolicy}' 2>/dev/null)
  printf '  %s failurePolicy = %s\n' "$w" "${FP:-N/A}"
done

# ---------------------------------------------------------------------------
if [ -n "$APP" ]; then
  hdr "Application: $APP"
  for f in '.spec.project:project' '.spec.source.targetRevision:revision' \
           '.spec.source.repoURL:repoURL' '.status.sync.status:sync' \
           '.status.health.status:health' \
           '.status.operationState.phase:phase' \
           '.status.operationState.message:message'; do
    path="${f%%:*}"; label="${f##*:}"
    val=$(kubectl -n "$NS" get application "$APP" -o jsonpath="{${path}}" 2>/dev/null)
    printf '%-12s = %s\n' "$label" "${val:-<empty>}"
  done
  echo
  echo "--- 资源健康明细 ---"
  kubectl -n "$NS" get application "$APP" -o jsonpath='{range .status.resources[*]}{.kind}{"/"}{.name}{"  "}{.health.status}{"  "}{.health.message}{"\n"}{end}' 2>/dev/null
fi

# ---------------------------------------------------------------------------
printf '\n========================================\n'
if [ "$WARN" -eq 0 ]; then
  echo "✅ 体检通过，未发现明显异常"
else
  echo "⚠️  发现上面标记的异常项，请按对应专题文档处理"
  echo "    排障手册：argocd-topics/09-troubleshooting.md"
fi
exit "$WARN"
