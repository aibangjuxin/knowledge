#!/opt/homebrew/bin/bash
# =============================================================================
# verify-poc.sh - UCP PoC 端到端验收脚本
#
# 对应 next-steps-roadmap.md 4.3 节的 8 项检查。
# 全部是对活集群的只读查询，不会创建 / 修改 / 删除任何资源。
#
# 用法:
#   ./verify-poc.sh                 # 默认配置
#   ./verify-poc.sh --team team-a   # 只检查某团队
#   ./verify-poc.sh --help
#
# 环境变量:
#   ARGOCD_NS   Argo CD 所在 namespace, 默认 argocd
#   TEAMS       要检查的团队 namespace 列表, 默认 "team-a team-b"
#   XR_KIND     XR 的 kind, 默认 GKECluster
#   MR_KIND     MR 的 kind, 默认 Cluster
#   PROVIDER    Provider 名, 默认 provider-gcp-container
#   SKIP_CLOUD  设为 1 跳过 gcloud 检查
# =============================================================================

set -uo pipefail

ARGOCD_NS="${ARGOCD_NS:-argocd}"
TEAMS="${TEAMS:-team-a team-b}"
XR_KIND="${XR_KIND:-GKECluster}"
MR_KIND="${MR_KIND:-Cluster}"
PROVIDER="${PROVIDER:-provider-gcp-container}"
SKIP_CLOUD="${SKIP_CLOUD:-0}"

PASS=0; FAIL=0; SKIP=0

if [ -t 1 ]; then
  C_RED=$(printf '\033[31m'); C_GRN=$(printf '\033[32m')
  C_YEL=$(printf '\033[33m'); C_CYN=$(printf '\033[36m'); C_RST=$(printf '\033[0m')
else
  C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_RST=""
fi

ok()   { PASS=$((PASS+1)); printf '%s[PASS]%s %s\n' "$C_GRN" "$C_RST" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RST" "$1"; }
skip() { SKIP=$((SKIP+1)); printf '%s[SKIP]%s %s\n' "$C_YEL" "$C_RST" "$1"; }
info() { printf '%s       %s%s\n' "$C_CYN" "$1" "$C_RST"; }
head1(){ printf '\n%s== %s ==%s\n' "$C_CYN" "$1" "$C_RST"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAMS="$2"; shift 2 ;;
    --help|-h) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '未知参数: %s (--help 看用法)\n' "$1" >&2; exit 2 ;;
  esac
done

head1 "0. 依赖与连通性"
command -v kubectl >/dev/null 2>&1 || { bad "找不到 kubectl"; exit 1; }
ok "kubectl 可用"
if ! kubectl cluster-info >/dev/null 2>&1; then
  bad "连不上集群 (context: $(kubectl config current-context 2>/dev/null || echo unknown))"
  exit 1
fi
ok "集群可达 ($(kubectl config current-context 2>/dev/null))"

head1 "1. Argo CD 组件健康"
POD_OUT=$(kubectl -n "$ARGOCD_NS" get pods --no-headers 2>/dev/null)
if [ -z "$POD_OUT" ]; then
  bad "argocd namespace 下没有 Pod"
else
  ok "argocd namespace 下有 $(printf '%s\n' "$POD_OUT" | grep -c .) 个 Pod"
  NOTREADY=$(printf '%s\n' "$POD_OUT" | awk '$3 != "Running" && $3 != "Completed"' | grep -c . || true)
  if [ "${NOTREADY:-0}" = "0" ]; then
    ok "全部 Pod 处于 Running"
  else
    bad "$NOTREADY 个 Pod 不在 Running"
    printf '%s\n' "$POD_OUT" | awk '$3 != "Running" && $3 != "Completed"' | sed 's/^/       /'
  fi
  for c in repo-server application-controller applicationset-controller; do
    if kubectl -n "$ARGOCD_NS" get deploy "argocd-$c" >/dev/null 2>&1; then
      ok "argocd-$c 已部署"
    else
      bad "argocd-$c 缺失 (Argo CD 3.x install.yaml 含 applicationset-controller, 缺失说明装漏了)"
    fi
  done
fi

head1 "2. Application 状态"
APP_OUT=$(kubectl -n "$ARGOCD_NS" get applications.argoproj.io \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,PROJECT:.spec.project,NS:.spec.destination.namespace \
  --no-headers 2>/dev/null)
if [ -z "$APP_OUT" ]; then
  bad "查不到任何 Application - ApplicationSet 未生成或生成失败"
else
  N=$(printf '%s\n' "$APP_OUT" | grep -c .)
  S=$(printf '%s\n' "$APP_OUT" | awk '$2=="Synced"' | grep -c . || true)
  H=$(printf '%s\n' "$APP_OUT" | awk '$3=="Healthy"' | grep -c . || true)
  info "共 $N 个 Application: Synced=$S Healthy=$H"
  printf '%s\n' "$APP_OUT" | sed 's/^/       /'
  if [ "$N" = "$S" ]; then ok "全部 Application Synced"; else bad "$((N-S)) 个 Application 未同步"; fi
  if [ "$N" = "$H" ]; then ok "全部 Application Healthy"; else bad "$((N-H)) 个 Application 非 Healthy"; fi
fi

head1 "3. 命名一致性 (目录名 = Application namespace = AppProject 允许名单)"
for team in $TEAMS; do
  ALLOWED=$(kubectl -n "$ARGOCD_NS" get appprojects.argoproj.io \
    -o jsonpath="{.items[?(@.metadata.name==\"$team\")].spec.destinations[*].namespace}" 2>/dev/null)
  if [ -z "$ALLOWED" ]; then
    bad "AppProject '$team' 不存在或没有 destinations"
    continue
  fi
  APP_NS=$(printf '%s\n' "$APP_OUT" | awk -v p="$team" '$4==p {print $5}')
  if [ -z "$APP_NS" ]; then
    skip "$team: 没有属于该 project 的 Application"
    continue
  fi
  for ns in $APP_NS; do
    case " $ALLOWED " in
      *" $ns "*) ok "$team/$ns: namespace 在 AppProject 允许名单内" ;;
      *) bad "$team/$ns: AppProject 未放行该 namespace (同步会被拒)" ;;
    esac
  done
done

head1 "4. XR 是否落到目标 namespace"
for team in $TEAMS; do
  XR_OUT=$(kubectl -n "$team" get "$XR_KIND" --no-headers 2>/dev/null)
  if [ -z "$XR_OUT" ]; then
    bad "$team namespace 下没有 $XR_KIND - Git 到 ArgoCD 到 XR 这段没通"
  else
    ok "$team namespace 下有 $(printf '%s\n' "$XR_OUT" | grep -c .) 个 $XR_KIND"
    kubectl -n "$team" get "$XR_KIND" --no-headers -o 'custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status' 2>/dev/null | sed 's/^/       /'
  fi
done

head1 "5. Provider 与 Managed Resource"
if kubectl get provider "$PROVIDER" >/dev/null 2>&1; then
  PH=$(kubectl get provider "$PROVIDER" -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null)
  if [ "$PH" = "True" ]; then
    ok "$PROVIDER Healthy"
  else
    bad "$PROVIDER 状态=$PH (ArgoCD 不装 Provider, 必须由平台侧单独安装)"
  fi
else
  bad "Provider '$PROVIDER' 不存在"
fi
MR_CNT=$(kubectl get managedresources --no-headers 2>/dev/null | grep -c . || true)
if [ "${MR_CNT:-0}" -gt 0 ]; then
  ok "集群里有 $MR_CNT 个 MR (MR 由 Composition 生成, ArgoCD 不应直接同步它们)"
else
  skip "没有 MR - 可能 Composition 未渲染, 或 MRD 未激活 (查 kubectl get mrd 的 state)"
fi

head1 "6. 云上真实集群"
if [ "$SKIP_CLOUD" = "1" ] || ! command -v gcloud >/dev/null 2>&1; then
  skip "跳过 gcloud 检查 (SKIP_CLOUD=1 或未装 gcloud)"
elif ! command -v gcloud >/dev/null 2>&1; then
  skip "未装 gcloud"
else
  CL=$(gcloud container clusters list --format='value(name)' 2>/dev/null)
  if [ -n "$CL" ]; then
    ok "gcloud 可见集群: $(printf '%s' "$CL" | tr '\n' ' ')"
  else
    bad "gcloud 查不到集群 - Provider 权限或目标 Project 可能不对"
  fi
fi

head1 "7. 幂等与资源追踪"
TRACK=$(kubectl -n "$ARGOCD_NS" get cm argocd-cm -o jsonpath='{.data.application\.resourceTrackingMethod}' 2>/dev/null)
if [ "$TRACK" = "annotation" ]; then
  ok "resourceTrackingMethod=annotation (与 Crossplane 的 label 所有权不冲突)"
else
  bad "resourceTrackingMethod=${TRACK:-未设置} - 与 Crossplane 的 label 所有权会冲突, 应设为 annotation"
fi
if kubectl get crd "$XR_KIND".platform.example.org >/dev/null 2>&1; then
  ok "XRD 生成的 CRD 已存在"
else
  skip "未找到 XRD 生成的 CRD ($XR_KIND.platform.example.org)"
fi

head1 "汇总"
printf 'PASS=%s  FAIL=%s  SKIP=%s\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
  printf '%s结论: 未通过 - 见上面 [FAIL] 项. 定位方法见 argocd-admin-guide.md 12 节 与 poc-argocd-git-to-apply-trigger.md 11 节%s\n' "$C_RED" "$C_RST"
  exit 1
fi
printf '%s结论: 全部通过%s\n' "$C_GRN" "$C_RST"
exit 0
