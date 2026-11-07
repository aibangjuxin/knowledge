#!/usr/bin/env bash
# =============================================================================
#  new-cluster.sh —— 新增一个集群的脚手架
# -----------------------------------------------------------------------------
#  加一个集群要手工做 4 件事，每件都容易抄错：
#    ① 建 bootstrap/clusters/<name>/cluster.yaml
#    ② 建 bootstrap/clusters/<name>/components/<component>.yaml（每个组件一份）
#    ③ 在 bootstrap/appprojects/platform-<env>.yaml 的 destinations 里加这个集群
#    ④ 注册 Argo CD Cluster Secret（这个脚本只**生成** YAML，不 apply）
#
#  这个脚本把 ①②③ 自动化 —— 字段全部从一个地方填，其它地方自动保持一致。
#  ④ 仍然需要你手动执行（Cluster Secret 含凭据，不该进 Git）。
#
#  用法：
#    ./new-cluster.sh --name dev-03 --env dev \
#        --project acme-platform-dev \
#        --server https://dev-03.k8s.example.com \
#        --component nginx --component api
#
#  常用选项：
#    --name <cluster>       集群名，必须是 <env>-<后缀>（如 dev-03）
#    --env <dev|stg|prod>   环境
#    --project <gcp-project>  GCP Project（只写进 cluster.yaml，不参与 AppSet）
#    --region <region>      GCP region（可选）
#    --vpc <vpc>            VPC 名（可选）
#    --server <url>         Kubernetes API 地址（必须与 Cluster Secret 一致）
#    --namespace <ns>       目标 namespace（默认 platform-<env>）
#    --component <name>     启用一个组件（可重复）
#    --secret-namespace <ns> Cluster Secret 放哪个 namespace（默认 argocd）
#    --dry-run              只打印要做什么，不落盘
#
#  兼容：macOS / Linux（bash 3.2+）
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="$SCRIPT_DIR/bootstrap/clusters"
PROJECTS_DIR="$SCRIPT_DIR/bootstrap/appprojects"

CLUSTER=""
ENV_NAME=""
GCP_PROJECT=""
GCP_REGION=""
VPC=""
SERVER=""
NAMESPACE=""
SECRET_NS="argocd"
COMPONENTS=()
DRY_RUN=0

if [[ -t 1 ]]; then C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else C_GRN=""; C_YEL=""; C_RED=""; C_BLD=""; C_RST=""; fi
info() { printf '%s==>%s %s\n' "$C_BLD" "$C_RST" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
run()  { if [[ $DRY_RUN -eq 1 ]]; then printf '    $ %s\n' "$*"; else "$@"; fi; }

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)      CLUSTER="$2"; shift 2 ;;
    --env)       ENV_NAME="$2"; shift 2 ;;
    --project)   GCP_PROJECT="$2"; shift 2 ;;
    --region)    GCP_REGION="$2"; shift 2 ;;
    --vpc)       VPC="$2"; shift 2 ;;
    --server)    SERVER="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --component) COMPONENTS+=("$2"); shift 2 ;;
    --secret-namespace) SECRET_NS="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "未知参数: $1（-h 看用法）" ;;
  esac
done

# ---------------------------------------------------------------------------
# 参数校验
# ---------------------------------------------------------------------------
[[ -n "$CLUSTER" ]]  || die "缺少 --name"
[[ -n "$ENV_NAME" ]] || die "缺少 --env"
[[ -n "$SERVER" ]]   || die "缺少 --server（必须与 Argo CD Cluster Secret 里的 server 一致）"
[[ -n "$GCP_PROJECT" ]] || die "缺少 --project（GCP project）"

case "$ENV_NAME" in
  dev|stg|prod) ;;
  *) die "--env 只能是 dev / stg / prod（当前 $ENV_NAME）" ;;
esac

if [[ "$CLUSTER" != "$ENV_NAME"-* ]]; then
  die "集群名必须以环境开头：$ENV_NAME-*（当前 $CLUSTER）"
fi

NAMESPACE="${NAMESPACE:-platform-$ENV_NAME}"
APPPROJECT="platform-$ENV_NAME"

if [[ -d "$CLUSTERS_DIR/$CLUSTER" ]]; then
  die "$CLUSTERS_DIR/$CLUSTER 已存在"
fi

# ---------------------------------------------------------------------------
# ① cluster.yaml
# ---------------------------------------------------------------------------
info "① 生成 bootstrap/clusters/$CLUSTER/cluster.yaml"

cluster_yaml() {
cat <<EOF
# 集群元信息：$CLUSTER
#
# ⚠️ 不是 Argo CD 资源，不会被 apply。仅作为 Git 里的集群事实来源。
#
# 本集群：$GCP_PROJECT project${GCP_REGION:+ / $GCP_REGION}${VPC:+ / $VPC}

cluster: $CLUSTER
server: $SERVER
env: $ENV_NAME
project: $APPPROJECT
namespace: $NAMESPACE

# ---- 以下字段仅供人/工具参考，不参与 ApplicationSet 展开 ----------------
gcpProject: $GCP_PROJECT
${GCP_REGION:+gcpRegion: $GCP_REGION}
${VPC:+vpc: $VPC}
argocdClusterSecret: $CLUSTER
workloadIdentityServiceAccount: sa-argocd@$GCP_PROJECT.iam.gserviceaccount.com
EOF
}

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$CLUSTERS_DIR/$CLUSTER/components"
  cluster_yaml > "$CLUSTERS_DIR/$CLUSTER/cluster.yaml"
else
  cluster_yaml | sed 's/^/    /'
fi
ok "cluster.yaml"

# ---------------------------------------------------------------------------
# ② components/*.yaml
# ---------------------------------------------------------------------------
info "② 生成组件启用清单"

if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
  warn "没指定 --component → 这个集群暂时不装任何组件（后面用 enable-component.sh 补）"
fi

for comp in "${COMPONENTS[@]}"; do
  # 委托给 enable-component.sh —— 它还负责集群级组件（gatekeeper/gateway）
  # 需要的「每集群一份的 overlay」
  if [[ $DRY_RUN -eq 1 ]]; then
    bash "$SCRIPT_DIR/enable-component.sh" --cluster "$CLUSTER" --component "$comp" --dry-run
  else
    bash "$SCRIPT_DIR/enable-component.sh" --cluster "$CLUSTER" --component "$comp"
  fi
done

# ---------------------------------------------------------------------------
# ③ AppProject destinations
# ---------------------------------------------------------------------------
info "③ 把集群加进 AppProject $APPPROJECT 的 destinations"

PROJECT_FILE="$PROJECTS_DIR/$APPPROJECT.yaml"
[[ -f "$PROJECT_FILE" ]] || die "找不到 $PROJECT_FILE"

if grep -qF "$SERVER" "$PROJECT_FILE"; then
  warn "$SERVER 已经在 $APPPROJECT 的 destinations 里了，跳过"
else
  # 用 awk 在 destinations 块后面插入一条，保留原有注释和格式
  if [[ $DRY_RUN -eq 0 ]]; then
    tmp="$(mktemp)"
    awk -v srv="$SERVER" -v ns="$NAMESPACE" '
      !done && /^[[:space:]]*destinations:[[:space:]]*$/ {
        print
        match($0, /^[[:space:]]*/)
        ind = substr($0, 1, RLENGTH)
        printf "%s- server: \x27%s\x27\n", ind, srv
        printf "%s  namespace: \x27%s\x27\n", ind, ns
        done = 1
        next
      }
      { print }
    ' "$PROJECT_FILE" > "$tmp" && mv "$tmp" "$PROJECT_FILE"
    ok "已加入 $PROJECT_FILE"
  else
    printf "    $ 在 %s 的 destinations 里插入 server=%s namespace=%s\n" \
      "$PROJECT_FILE" "$SERVER" "$NAMESPACE"
  fi
fi

# ---------------------------------------------------------------------------
# ④ Cluster Secret（只生成，不 apply）
# ---------------------------------------------------------------------------
info "④ Cluster Secret（需要你手动执行 —— 凭据不进 Git）"

cat <<EOF

  # 1) 在**目标集群**里造一个给 Argo CD 用的 ServiceAccount
  kubectl --context <目标集群> create sa argocd -n kube-system --dry-run=client -o yaml | kubectl --context <目标集群> apply -f -
  kubectl --context <目标集群> create clusterrolebinding argocd \\
      --clusterrole=cluster-admin --serviceaccount=kube-system:argocd

  # 2) 生成 token（GKE 上建议改用 Workload Identity，别用长期 token）
  TOKEN=\$(kubectl --context <目标集群> create token argocd -n kube-system --duration=8760h)

  # 3) 在 Argo CD 里注册集群
  argocd cluster add $CLUSTER \\
      --name $CLUSTER \\
      --server $SERVER \\
      --bearer-token "\$TOKEN" \\
      --insecure \\
      --project $APPPROJECT

  # 4) 确认
  argocd cluster list

EOF

# ---------------------------------------------------------------------------
# ⑤ 自检
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
  info "⑤ 自检"
  ( cd "$SCRIPT_DIR" && python3 validate-clusters.py ) || die "validate-clusters.py 没通过"
  ( cd "$SCRIPT_DIR" && python3 appset-simulator.py | tail -20 ) || true
  ok "全部通过"
fi

cat <<EOF

下一步：
  1. git add bootstrap/clusters/$CLUSTER bootstrap/appprojects/$APPPROJECT.yaml
  2. 提交后根应用会自动同步 → AppSet 生成新的 Application
  3. 执行上面的第 ④ 步注册集群（否则 Application 会报 "Unable to connect"）
EOF
