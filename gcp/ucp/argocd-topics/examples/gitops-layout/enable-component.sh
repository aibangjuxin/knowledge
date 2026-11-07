#!/usr/bin/env bash
# =============================================================================
#  enable-component.sh —— 给已有集群开关组件
# -----------------------------------------------------------------------------
#  「这个集群装不装这个组件」在 GitOps 里 = 一个文件的有无。
#  这个脚本负责把那件事做对，包括**集群级组件**（gatekeeper / gateway）需要
#  的那份每集群一份的 overlay。
#
#  用法：
#    ./enable-component.sh --cluster dev-01 --component redis      # 启用
#    ./enable-component.sh --cluster dev-01 --component redis --disable  # 停用
#    ./enable-component.sh --cluster dev-01 --component gateway --dry-run
#
#  选项：
#    --cluster <name>     集群目录名（bootstrap/clusters/<name>）
#    --component <name>   组件名（要能对上 bootstrap/applicationsets/component-<name>.yaml）
#    --disable            停用（删除清单文件；集群里的资源因
#                         preserveResourcesOnDeletion=true 而保留，需人工清理）
#    --dry-run            只打印不落盘
#
#  兼容：macOS / Linux（bash 3.2+）
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="$SCRIPT_DIR/bootstrap/clusters"
APPSETS_DIR="$SCRIPT_DIR/bootstrap/applicationsets"

CLUSTER=""
COMPONENT=""
DISABLE=0
DRY_RUN=0

if [[ -t 1 ]]; then C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else C_GRN=""; C_YEL=""; C_RED=""; C_BLD=""; C_RST=""; fi
info() { printf '%s==>%s %s\n' "$C_BLD" "$C_RST" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)   CLUSTER="$2"; shift 2 ;;
    --component) COMPONENT="$2"; shift 2 ;;
    --disable)   DISABLE=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
done

[[ -n "$CLUSTER" ]]   || die "缺少 --cluster"
[[ -n "$COMPONENT" ]] || die "缺少 --component"

CLUSTER_DIR="$CLUSTERS_DIR/$CLUSTER"
[[ -d "$CLUSTER_DIR" ]] || die "没有这个集群：$CLUSTER_DIR"
[[ -f "$CLUSTER_DIR/cluster.yaml" ]] || die "$CLUSTER 缺 cluster.yaml"

APPSET_FILE="$APPSETS_DIR/component-$COMPONENT.yaml"
[[ -f "$APPSET_FILE" ]] || die "没有对应的 ApplicationSet：$APPSET_FILE"

# 从 cluster.yaml 里读出那几个必须一致的字段（server/env/project/namespace）
read_field() {
  sed -n "s/^$1:[[:space:]]*//p" "$CLUSTER_DIR/cluster.yaml" | head -1
}
SERVER="$(read_field server)"
ENV_NAME="$(read_field env)"
PROJECT="$(read_field project)"
NAMESPACE="$(read_field namespace)"

for pair in "server:$SERVER" "env:$ENV_NAME" "project:$PROJECT" "namespace:$NAMESPACE"; do
  key="${pair%%:*}"; value="${pair#*:}"
  [[ -n "$value" ]] || die "$CLUSTER/cluster.yaml 里没有 $key 字段"
done

MANIFEST="$CLUSTER_DIR/components/$COMPONENT.yaml"

# ---------------------------------------------------------------------------
# 停用
# ---------------------------------------------------------------------------
if [[ $DISABLE -eq 1 ]]; then
  if [[ -f "$MANIFEST" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '    $ rm %s\n' "$MANIFEST"
    else
      rm -f "$MANIFEST"
    fi
    ok "已停用 $CLUSTER × $COMPONENT"
    echo "  注意：集群里的资源不会自动删除（preserveResourcesOnDeletion=true）"
    echo "        需要人工清理：kubectl --context $CLUSTER -n $NAMESPACE delete ... "
  else
    warn "$CLUSTER 本来就没启用 $COMPONENT"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# 启用
# ---------------------------------------------------------------------------
info "启用 $CLUSTER × $COMPONENT"

if [[ -f "$MANIFEST" ]]; then
  warn "清单已存在：$MANIFEST（不覆盖，需要的话请手工改）"
else
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    $ cat > %s\n' "$MANIFEST"
  else
    cat > "$MANIFEST" <<EOF
# 组件启用清单：$CLUSTER × $COMPONENT
#
# ⭐ 这个文件的存在 = 该集群启用该组件。

component: $COMPONENT
cluster: $CLUSTER
server: $SERVER
env: $ENV_NAME
project: $PROJECT
namespace: $NAMESPACE
EOF
  fi
  ok "已写入 $MANIFEST"
fi

# ---------------------------------------------------------------------------
# 集群级组件：每集群还要有一份 overlay
# ---------------------------------------------------------------------------
# ⭐ 判定方式：**source.path 里**出现 {{.cluster}} 才是集群级组件。
#    （不能用整文件 grep —— 模板的 metadata.name 里也有 {{.cluster}}，
#      那是所有组件都有的。）
IS_CLUSTER_SCOPED=0
while IFS= read -r line; do
  case "$line" in \#*) continue ;; esac
  if [[ "$line" == *"path:"* && "$line" == *"{{.cluster}}"* ]]; then
    IS_CLUSTER_SCOPED=1
    break
  fi
done < "$APPSET_FILE"

if [[ $IS_CLUSTER_SCOPED -eq 1 ]]; then
  OVERLAY_DIR="$SCRIPT_DIR/apps/$COMPONENT/overlays/cluster/$CLUSTER"
  info "这是**集群级**组件 → 每个集群都要有一份 overlay"

  if [[ -d "$OVERLAY_DIR" ]]; then
    ok "overlay 已存在：apps/$COMPONENT/overlays/cluster/$CLUSTER"
  else
    # 找一个同环境的兄弟集群的 overlay 当模板，复制并把集群名换掉
    SOURCE_OVERLAY=""
    for sibling in "$SCRIPT_DIR/apps/$COMPONENT/overlays/cluster/$ENV_NAME"-*; do
      if [[ -d "$sibling" && "$sibling" != "$OVERLAY_DIR" ]]; then
        SOURCE_OVERLAY="$sibling"
        break
      fi
    done

    if [[ -z "$SOURCE_OVERLAY" ]]; then
      warn "找不到同环境的模板 overlay，需要手工创建："
      warn "  apps/$COMPONENT/overlays/cluster/$CLUSTER/kustomization.yaml"
      warn "  （结构参考 apps/$COMPONENT/overlays/env/$ENV_NAME/）"
    else
      SIBLING="$(basename "$SOURCE_OVERLAY")"
      if [[ $DRY_RUN -eq 1 ]]; then
        printf '    $ cp -r %s %s   # 并把 %s 换成 %s\n' \
          "$SOURCE_OVERLAY" "$OVERLAY_DIR" "$SIBLING" "$CLUSTER"
      else
        mkdir -p "$(dirname "$OVERLAY_DIR")"
        cp -r "$SOURCE_OVERLAY" "$OVERLAY_DIR"
        # 把兄弟集群的名字换成新集群（域名、豁免名单里的集群名等）
        find "$OVERLAY_DIR" -type f -name '*.yaml' -exec \
          sed -i.bak "s/$SIBLING/$CLUSTER/g" {} \; -exec rm -f {}.bak \;
        ok "已从 $SIBLING 复制出 $OVERLAY_DIR"
        echo "  ⚠️ 请检查复制过来的内容：集群相关的值（域名、豁免名单）可能需要改"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 自检
# ---------------------------------------------------------------------------
if [[ $DRY_RUN -eq 0 ]]; then
  ( cd "$SCRIPT_DIR" && python3 validate-clusters.py >/dev/null ) \
    && ok "validate-clusters.py 通过" \
    || warn "validate-clusters.py 没通过，看看上面的输出"
fi
