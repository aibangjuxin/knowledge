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
#    --server <url>       集群 API 地址（默认从 cluster.yaml 读）
#    --env <env>          环境名（默认从 cluster.yaml 读）
#    --project <project>  AppProject 名（默认从 cluster.yaml 读）
#    --namespace <ns>     目标 namespace（默认从 cluster.yaml 读）
#    --disable            停用（删除清单文件；集群里的资源因
#                         preserveResourcesOnDeletion=true 而保留，需人工清理）
#    --dry-run            只打印不落盘
#
#  关于 --server/--env/--project/--namespace：
#    正常用法**不用传** —— 四个字段从 bootstrap/clusters/<name>/cluster.yaml 读。
#    传它们是为了「集群目录还不存在」的场景：new-cluster.sh --dry-run 就是
#    这样（它先生成 cluster.yaml 的内容预览，但不落盘）。
#    命令行传的值优先；与 cluster.yaml 里的值不一致时会提醒一下。
#
#  兼容：macOS / Linux（bash 3.2+）
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTERS_DIR="$SCRIPT_DIR/bootstrap/clusters"
APPSETS_DIR="$SCRIPT_DIR/bootstrap/applicationsets"

CLUSTER=""
COMPONENT=""
SERVER_OVERRIDE=""
ENV_OVERRIDE=""
PROJECT_OVERRIDE=""
NAMESPACE_OVERRIDE=""
DISABLE=0
DRY_RUN=0

if [[ -t 1 ]]; then C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RED=$'\033[31m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else C_GRN=""; C_YEL=""; C_RED=""; C_BLD=""; C_RST=""; fi
info() { printf '%s==>%s %s\n' "$C_BLD" "$C_RST" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s  !%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%s  ✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

# usage —— 打印本文件头部的注释块（到第一个非注释行为止）。
# 用 awk 而不是 `sed -n '2,20p'`：以后在头部加选项时，范围不用手动改。
usage() {
  awk 'NR == 1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)   CLUSTER="$2"; shift 2 ;;
    --component) COMPONENT="$2"; shift 2 ;;
    --server)    SERVER_OVERRIDE="$2"; shift 2 ;;
    --env)       ENV_OVERRIDE="$2"; shift 2 ;;
    --project)   PROJECT_OVERRIDE="$2"; shift 2 ;;
    --namespace) NAMESPACE_OVERRIDE="$2"; shift 2 ;;
    --disable)   DISABLE=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) die "未知参数: $1" ;;
  esac
done

[[ -n "$CLUSTER" ]]   || die "缺少 --cluster"
[[ -n "$COMPONENT" ]] || die "缺少 --component"

CLUSTER_DIR="$CLUSTERS_DIR/$CLUSTER"

# 集群目录必须存在 —— 除非是 dry-run **且**调用方把四个字段都传进来了
# （new-cluster.sh --dry-run：集群还没建出来，但字段值已经确定）。
if [[ ! -d "$CLUSTER_DIR" ]]; then
  if [[ $DRY_RUN -eq 1 && -n "$SERVER_OVERRIDE" && -n "$ENV_OVERRIDE" \
        && -n "$PROJECT_OVERRIDE" && -n "$NAMESPACE_OVERRIDE" ]]; then
    warn "集群目录还不存在（$CLUSTER_DIR）—— 按传入的字段值预览"
  else
    die "没有这个集群：$CLUSTER_DIR"
  fi
fi

APPSET_FILE="$APPSETS_DIR/component-$COMPONENT.yaml"
[[ -f "$APPSET_FILE" ]] || die "没有对应的 ApplicationSet：$APPSET_FILE"

# 从 cluster.yaml 里读出那几个必须一致的字段（server/env/project/namespace）
# cluster.yaml 是扁平的 key: value 文件，用 sed 取第一行匹配即可（不依赖 yq）。
read_field() {
  [[ -f "$CLUSTER_DIR/cluster.yaml" ]] || return 0
  sed -n "s/^$1:[[:space:]]*//p" "$CLUSTER_DIR/cluster.yaml" | head -1
}

# 命令行传的值优先；与 cluster.yaml 里的值不一致时提醒一下（大概率是抄错了）。
pick_field() {
  local key="$1" override="$2" from_file
  from_file="$(read_field "$key")"
  if [[ -n "$override" ]]; then
    if [[ -n "$from_file" && "$from_file" != "$override" ]]; then
      warn "$CLUSTER/cluster.yaml 的 $key=$from_file 与传入的 $override 不一致 → 以传入值为准"
    fi
    printf '%s' "$override"
  else
    printf '%s' "$from_file"
  fi
}

SERVER="$(pick_field server "$SERVER_OVERRIDE")"
ENV_NAME="$(pick_field env "$ENV_OVERRIDE")"
PROJECT="$(pick_field project "$PROJECT_OVERRIDE")"
NAMESPACE="$(pick_field namespace "$NAMESPACE_OVERRIDE")"

# 这四个字段缺任何一个，ApplicationSet 都会因为 missingkey=error 而整体报错，
# 所以在写文件之前就拦下来。
for pair in "server:$SERVER" "env:$ENV_NAME" "project:$PROJECT" "namespace:$NAMESPACE"; do
  key="${pair%%:*}"; value="${pair#*:}"
  [[ -n "$value" ]] || die "$CLUSTER 没有 $key 字段（cluster.yaml 里没有，也没用 --$key 传）"
done

MANIFEST="$CLUSTER_DIR/components/$COMPONENT.yaml"

# ---------------------------------------------------------------------------
# 停用
# ---------------------------------------------------------------------------
if [[ $DISABLE -eq 1 ]]; then
  if [[ -f "$MANIFEST" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      printf '    $ rm %s\n' "$MANIFEST"
      ok "将删除 $MANIFEST（--dry-run，没有真的删）"
    else
      rm -f "$MANIFEST"
      ok "已停用 $CLUSTER × $COMPONENT"
    fi
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
    ok "将写入 $MANIFEST（--dry-run，没有真的落盘）"
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
    ok "已写入 $MANIFEST"
  fi
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
        # macOS 的 sed -i 必须带后缀（-i.bak），GNU sed 可以写 -i —— 统一用 -i.bak 再删掉
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
