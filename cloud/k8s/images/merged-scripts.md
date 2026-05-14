# Shell Scripts Collection

Generated on: 2026-03-07 18:43:04
Directory: /Users/lex/git/knowledge/k8s/images

## `verify_pod_image_pull_time_sh.sh`

```bash
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n default my-api-pod-abc123"
}

to_epoch() {
    local ts="$1"
    if [[ -z "${ts}" || "${ts}" == "null" ]]; then
        echo ""
        return 0
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null || true
    else
        date -d "$ts" "+%s" 2>/dev/null || true
    fi
}

pick_event_time() {
    jq -r '(.eventTime // .lastTimestamp // .firstTimestamp // .metadata.creationTimestamp // "")'
}

extract_reported_duration_seconds() {
    local message="$1"
    
    # Try to match patterns like "in 1.234s" or "in 500ms"
    if [[ "$message" =~ in\ ([0-9]+(?:\.[0-9]+)?)s ]]; then
        printf "%.3f" "${BASH_REMATCH[1]}"
        return 0
    fi
    
    if [[ "$message" =~ in\ ([0-9]+(?:\.[0-9]+)?)ms ]]; then
        value="${BASH_REMATCH[1]}"
        awk "BEGIN {printf \"%.3f\", ${value} / 1000}"
        return 0
    fi
    
    echo ""
}

if [[ $# -lt 3 ]]; then
    usage
    exit 1
fi

while getopts "n:" opt; do
    case "$opt" in
        n) NAMESPACE="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

POD_NAME="${1:-}"
if [[ -z "${NAMESPACE:-}" || -z "${POD_NAME}" ]]; then
    usage
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is required" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Pod Image Pull Analysis: ${POD_NAME} (Namespace: ${NAMESPACE})${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

POD_JSON="$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o json 2>/dev/null)" || {
    echo -e "${RED}❌ Error: Pod not found or kubectl access failed${NC}"
    exit 1
}

POD_UID="$(echo "$POD_JSON" | jq -r '.metadata.uid')"
NODE_NAME="$(echo "$POD_JSON" | jq -r '.spec.nodeName // "N/A"')"
POD_START_TIME="$(echo "$POD_JSON" | jq -r '.status.startTime // "N/A"')"

echo -e "${GREEN}Pod UID:${NC} ${POD_UID}"
echo -e "${GREEN}Node Name:${NC} ${NODE_NAME}"
echo -e "${GREEN}Pod Start Time:${NC} ${POD_START_TIME}"

echo -e "\n${YELLOW}📋 Step 1: Container/Image Inventory${NC}"
echo "$POD_JSON" | jq -r '
  [
    (.spec.initContainers[]? | {
      type: "init",
      name: .name,
      image: .image,
      imagePullPolicy: (.imagePullPolicy // "IfNotPresent")
    }),
    (.spec.containers[]? | {
      type: "app",
      name: .name,
      image: .image,
      imagePullPolicy: (.imagePullPolicy // "IfNotPresent")
    })
  ]
  | flatten
  | (["TYPE","CONTAINER","PULL_POLICY","IMAGE"] | @tsv),
    (.[] | [.type, .name, .imagePullPolicy, .image] | @tsv)
' | awk 'BEGIN { FS="\t"; OFS="\t" } { print }'

EVENTS_JSON="$(kubectl get events -n "${NAMESPACE}" -o json 2>/dev/null)"
PULL_EVENTS="$(echo "$EVENTS_JSON" | jq --arg pod_uid "$POD_UID" '
  [
    .items[]
    | select(.involvedObject.uid == $pod_uid)
    | select(.reason == "Pulling" or .reason == "Pulled" or .reason == "Failed")
    | {
        reason: .reason,
        message: (.message // ""),
        time: (.eventTime // .lastTimestamp // .firstTimestamp // .metadata.creationTimestamp // "")
      }
  ]
  | sort_by(.time)
')"

PULL_EVENT_COUNT="$(echo "$PULL_EVENTS" | jq 'length')"
if [[ "$PULL_EVENT_COUNT" -eq 0 ]]; then
    echo -e "\n${RED}❌ No Pulling/Pulled events found for this Pod${NC}"
    echo "Possible reasons:"
    echo "  - image was already cached and events were compacted"
    echo "  - Pod is too old and events expired"
    echo "  - kubectl cannot read events in this namespace"
    exit 1
fi

echo -e "\n${YELLOW}📋 Step 2: Image Pull Events${NC}"
echo "$PULL_EVENTS" | jq -r '.[] | [.time, .reason, .message] | @tsv' | while IFS=$'\t' read -r event_time reason message; do
    echo "  ${event_time} [${reason}] ${message}"
done

declare -A IMAGE_START_TS
declare -A IMAGE_END_TS
declare -A IMAGE_STATUS
declare -A IMAGE_DURATION_FROM_MESSAGE

while IFS= read -r row; do
    reason="$(echo "$row" | jq -r '.reason')"
    message="$(echo "$row" | jq -r '.message')"
    event_time="$(echo "$row" | pick_event_time)"
    image="$(echo "$message" | sed -n 's/.*image "\(.*\)".*/\1/p' | head -1)"

    if [[ -z "$image" ]]; then
        continue
    fi

    if [[ "$reason" == "Pulling" && -z "${IMAGE_START_TS[$image]:-}" ]]; then
        IMAGE_START_TS["$image"]="$event_time"
        IMAGE_STATUS["$image"]="pulling"
    fi

    if [[ "$reason" == "Pulled" ]]; then
        IMAGE_END_TS["$image"]="$event_time"
        IMAGE_STATUS["$image"]="pulled"
        duration_from_message="$(extract_reported_duration_seconds "$message")"
        if [[ -n "$duration_from_message" ]]; then
            IMAGE_DURATION_FROM_MESSAGE["$image"]="$duration_from_message"
        fi
        if echo "$message" | grep -qi "already present on machine"; then
            IMAGE_STATUS["$image"]="cached"
        fi
    fi

    if [[ "$reason" == "Failed" ]]; then
        IMAGE_END_TS["$image"]="$event_time"
        IMAGE_STATUS["$image"]="failed"
    fi
done < <(echo "$PULL_EVENTS" | jq -c '.[]')

echo -e "\n${YELLOW}📊 Step 3: Per-Image Pull Duration${NC}"
printf "%-8s %-22s %-22s %-12s %-10s %s\n" "TYPE" "START" "END" "DURATION(s)" "STATUS" "IMAGE"

EARLIEST_PULL=""
LATEST_PULL=""
SUM_SECONDS="0"

while IFS=$'\t' read -r type container_name image image_pull_policy; do
    start_ts="${IMAGE_START_TS[$image]:-}"
    end_ts="${IMAGE_END_TS[$image]:-}"
    status="${IMAGE_STATUS[$image]:-unknown}"
    duration="${IMAGE_DURATION_FROM_MESSAGE[$image]:-}"

    if [[ -z "$duration" && -n "$start_ts" && -n "$end_ts" ]]; then
        start_epoch="$(to_epoch "$start_ts")"
        end_epoch="$(to_epoch "$end_ts")"
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            duration="$((end_epoch - start_epoch))"
        fi
    fi

    if [[ -z "$duration" && "$status" == "cached" ]]; then
        duration="0"
    fi

    if [[ -n "$start_ts" ]]; then
        if [[ -z "$EARLIEST_PULL" || "$(to_epoch "$start_ts")" -lt "$(to_epoch "$EARLIEST_PULL")" ]]; then
            EARLIEST_PULL="$start_ts"
        fi
    fi

    if [[ -n "$end_ts" ]]; then
        if [[ -z "$LATEST_PULL" || "$(to_epoch "$end_ts")" -gt "$(to_epoch "$LATEST_PULL")" ]]; then
            LATEST_PULL="$end_ts"
        fi
    fi

    if [[ -n "$duration" && "$duration" != "null" ]]; then
        SUM_SECONDS="$(awk "BEGIN {print ${SUM_SECONDS} + ${duration}}")"
    fi

    printf "%-8s %-22s %-22s %-12s %-10s %s\n" \
        "$type" \
        "${start_ts:-N/A}" \
        "${end_ts:-N/A}" \
        "${duration:-N/A}" \
        "$status" \
        "$image"
done < <(echo "$POD_JSON" | jq -r '
  (.spec.initContainers[]? | ["init", .name, .image, (.imagePullPolicy // "IfNotPresent")] | @tsv),
  (.spec.containers[]? | ["app", .name, .image, (.imagePullPolicy // "IfNotPresent")] | @tsv)
')

echo -e "\n${YELLOW}📦 Step 4: Aggregated View${NC}"
echo -e "${GREEN}Sum of per-image durations:${NC} ${SUM_SECONDS} seconds"

if [[ -n "$EARLIEST_PULL" && -n "$LATEST_PULL" ]]; then
    earliest_epoch="$(to_epoch "$EARLIEST_PULL")"
    latest_epoch="$(to_epoch "$LATEST_PULL")"
    if [[ -n "$earliest_epoch" && -n "$latest_epoch" ]]; then
        wall_clock="$((latest_epoch - earliest_epoch))"
        echo -e "${GREEN}Wall-clock pull window:${NC} ${wall_clock} seconds"
        echo -e "${GREEN}Earliest pull event:${NC} ${EARLIEST_PULL}"
        echo -e "${GREEN}Latest pull event:${NC} ${LATEST_PULL}"
    fi
fi

echo -e "\n${YELLOW}🧠 Interpretation${NC}"
echo "  - Sum of per-image durations can overcount if multiple image pulls overlap."
echo "  - Wall-clock pull window is usually closer to the Pod-level deployment delay."
echo "  - If an image is already cached on the node, observed duration may be 0 or there may be no pull event."
echo "  - If the same image is used by multiple containers, the node usually pulls it once and reuses the cache."

```

## `verify_pod_image_pull_time.sh`

```bash
#!/bin/bash

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

usage() {
    echo "Usage: $0 -n <namespace> <pod-name>"
    echo "Example: $0 -n default my-api-pod-abc123"
}

to_epoch() {
    local ts="$1"
    if [[ -z "${ts}" || "${ts}" == "null" ]]; then
        echo ""
        return 0
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" "+%s" 2>/dev/null || true
    else
        date -d "$ts" "+%s" 2>/dev/null || true
    fi
}

pick_event_time() {
    jq -r '(.eventTime // .lastTimestamp // .firstTimestamp // .metadata.creationTimestamp // "")'
}

extract_reported_duration_seconds() {
    local message="$1"
    MESSAGE="$message" python3 - <<'PY'
import os
import re

msg = os.environ.get("MESSAGE", "")
patterns = [
    r'in ([0-9]+(?:\.[0-9]+)?)s',
    r'in ([0-9]+(?:\.[0-9]+)?)ms',
]

for pattern in patterns:
    match = re.search(pattern, msg)
    if not match:
        continue
    value = float(match.group(1))
    if pattern.endswith('ms'):
        value /= 1000.0
    print(f"{value:.3f}")
    raise SystemExit(0)

print("")
PY
}

if [[ $# -lt 3 ]]; then
    usage
    exit 1
fi

while getopts "n:" opt; do
    case "$opt" in
        n) NAMESPACE="$OPTARG" ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND-1))

POD_NAME="${1:-}"
if [[ -z "${NAMESPACE:-}" || -z "${POD_NAME}" ]]; then
    usage
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl is required" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required" >&2
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Pod Image Pull Analysis: ${POD_NAME} (Namespace: ${NAMESPACE})${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

POD_JSON="$(kubectl get pod "${POD_NAME}" -n "${NAMESPACE}" -o json 2>/dev/null)" || {
    echo -e "${RED}❌ Error: Pod not found or kubectl access failed${NC}"
    exit 1
}

POD_UID="$(echo "$POD_JSON" | jq -r '.metadata.uid')"
NODE_NAME="$(echo "$POD_JSON" | jq -r '.spec.nodeName // "N/A"')"
POD_START_TIME="$(echo "$POD_JSON" | jq -r '.status.startTime // "N/A"')"

echo -e "${GREEN}Pod UID:${NC} ${POD_UID}"
echo -e "${GREEN}Node Name:${NC} ${NODE_NAME}"
echo -e "${GREEN}Pod Start Time:${NC} ${POD_START_TIME}"

echo -e "\n${YELLOW}📋 Step 1: Container/Image Inventory${NC}"
echo "$POD_JSON" | jq -r '
  [
    (.spec.initContainers[]? | {
      type: "init",
      name: .name,
      image: .image,
      imagePullPolicy: (.imagePullPolicy // "IfNotPresent")
    }),
    (.spec.containers[]? | {
      type: "app",
      name: .name,
      image: .image,
      imagePullPolicy: (.imagePullPolicy // "IfNotPresent")
    })
  ]
  | flatten
  | (["TYPE","CONTAINER","PULL_POLICY","IMAGE"] | @tsv),
    (.[] | [.type, .name, .imagePullPolicy, .image] | @tsv)
' | awk 'BEGIN { FS="\t"; OFS="\t" } { print }'

EVENTS_JSON="$(kubectl get events -n "${NAMESPACE}" -o json 2>/dev/null)"
PULL_EVENTS="$(echo "$EVENTS_JSON" | jq --arg pod_uid "$POD_UID" '
  [
    .items[]
    | select(.involvedObject.uid == $pod_uid)
    | select(.reason == "Pulling" or .reason == "Pulled" or .reason == "Failed")
    | {
        reason: .reason,
        message: (.message // ""),
        time: (.eventTime // .lastTimestamp // .firstTimestamp // .metadata.creationTimestamp // "")
      }
  ]
  | sort_by(.time)
')"

PULL_EVENT_COUNT="$(echo "$PULL_EVENTS" | jq 'length')"
if [[ "$PULL_EVENT_COUNT" -eq 0 ]]; then
    echo -e "\n${RED}❌ No Pulling/Pulled events found for this Pod${NC}"
    echo "Possible reasons:"
    echo "  - image was already cached and events were compacted"
    echo "  - Pod is too old and events expired"
    echo "  - kubectl cannot read events in this namespace"
    exit 1
fi

echo -e "\n${YELLOW}📋 Step 2: Image Pull Events${NC}"
echo "$PULL_EVENTS" | jq -r '.[] | [.time, .reason, .message] | @tsv' | while IFS=$'\t' read -r event_time reason message; do
    echo "  ${event_time} [${reason}] ${message}"
done

declare -A IMAGE_START_TS
declare -A IMAGE_END_TS
declare -A IMAGE_STATUS
declare -A IMAGE_DURATION_FROM_MESSAGE

while IFS= read -r row; do
    reason="$(echo "$row" | jq -r '.reason')"
    message="$(echo "$row" | jq -r '.message')"
    event_time="$(echo "$row" | pick_event_time)"
    image="$(echo "$message" | sed -n 's/.*image "\(.*\)".*/\1/p' | head -1)"

    if [[ -z "$image" ]]; then
        continue
    fi

    if [[ "$reason" == "Pulling" && -z "${IMAGE_START_TS[$image]:-}" ]]; then
        IMAGE_START_TS["$image"]="$event_time"
        IMAGE_STATUS["$image"]="pulling"
    fi

    if [[ "$reason" == "Pulled" ]]; then
        IMAGE_END_TS["$image"]="$event_time"
        IMAGE_STATUS["$image"]="pulled"
        duration_from_message="$(extract_reported_duration_seconds "$message")"
        if [[ -n "$duration_from_message" ]]; then
            IMAGE_DURATION_FROM_MESSAGE["$image"]="$duration_from_message"
        fi
        if echo "$message" | grep -qi "already present on machine"; then
            IMAGE_STATUS["$image"]="cached"
        fi
    fi

    if [[ "$reason" == "Failed" ]]; then
        IMAGE_END_TS["$image"]="$event_time"
        IMAGE_STATUS["$image"]="failed"
    fi
done < <(echo "$PULL_EVENTS" | jq -c '.[]')

echo -e "\n${YELLOW}📊 Step 3: Per-Image Pull Duration${NC}"
printf "%-8s %-22s %-22s %-12s %-10s %s\n" "TYPE" "START" "END" "DURATION(s)" "STATUS" "IMAGE"

EARLIEST_PULL=""
LATEST_PULL=""
SUM_SECONDS="0"

while IFS=$'\t' read -r type container_name image image_pull_policy; do
    start_ts="${IMAGE_START_TS[$image]:-}"
    end_ts="${IMAGE_END_TS[$image]:-}"
    status="${IMAGE_STATUS[$image]:-unknown}"
    duration="${IMAGE_DURATION_FROM_MESSAGE[$image]:-}"

    if [[ -z "$duration" && -n "$start_ts" && -n "$end_ts" ]]; then
        start_epoch="$(to_epoch "$start_ts")"
        end_epoch="$(to_epoch "$end_ts")"
        if [[ -n "$start_epoch" && -n "$end_epoch" ]]; then
            duration="$((end_epoch - start_epoch))"
        fi
    fi

    if [[ -z "$duration" && "$status" == "cached" ]]; then
        duration="0"
    fi

    if [[ -n "$start_ts" ]]; then
        if [[ -z "$EARLIEST_PULL" || "$(to_epoch "$start_ts")" -lt "$(to_epoch "$EARLIEST_PULL")" ]]; then
            EARLIEST_PULL="$start_ts"
        fi
    fi

    if [[ -n "$end_ts" ]]; then
        if [[ -z "$LATEST_PULL" || "$(to_epoch "$end_ts")" -gt "$(to_epoch "$LATEST_PULL")" ]]; then
            LATEST_PULL="$end_ts"
        fi
    fi

    if [[ -n "$duration" && "$duration" != "null" ]]; then
        SUM_SECONDS="$(awk "BEGIN {print ${SUM_SECONDS} + ${duration}}")"
    fi

    printf "%-8s %-22s %-22s %-12s %-10s %s\n" \
        "$type" \
        "${start_ts:-N/A}" \
        "${end_ts:-N/A}" \
        "${duration:-N/A}" \
        "$status" \
        "$image"
done < <(echo "$POD_JSON" | jq -r '
  (.spec.initContainers[]? | ["init", .name, .image, (.imagePullPolicy // "IfNotPresent")] | @tsv),
  (.spec.containers[]? | ["app", .name, .image, (.imagePullPolicy // "IfNotPresent")] | @tsv)
')

echo -e "\n${YELLOW}📦 Step 4: Aggregated View${NC}"
echo -e "${GREEN}Sum of per-image durations:${NC} ${SUM_SECONDS} seconds"

if [[ -n "$EARLIEST_PULL" && -n "$LATEST_PULL" ]]; then
    earliest_epoch="$(to_epoch "$EARLIEST_PULL")"
    latest_epoch="$(to_epoch "$LATEST_PULL")"
    if [[ -n "$earliest_epoch" && -n "$latest_epoch" ]]; then
        wall_clock="$((latest_epoch - earliest_epoch))"
        echo -e "${GREEN}Wall-clock pull window:${NC} ${wall_clock} seconds"
        echo -e "${GREEN}Earliest pull event:${NC} ${EARLIEST_PULL}"
        echo -e "${GREEN}Latest pull event:${NC} ${LATEST_PULL}"
    fi
fi

echo -e "\n${YELLOW}🧠 Interpretation${NC}"
echo "  - Sum of per-image durations can overcount if multiple image pulls overlap."
echo "  - Wall-clock pull window is usually closer to the Pod-level deployment delay."
echo "  - If an image is already cached on the node, observed duration may be 0 or there may be no pull event."
echo "  - If the same image is used by multiple containers, the node usually pulls it once and reuses the cache."

```

## `images-update.sh`

```bash
#!/bin/bash
# -------------------------------------------------------
# Kubernetes Deployment Image Updater
# Version: 2.1 (keyword-based interactive)
# Author: GPT-5 + User logic preserved
# -------------------------------------------------------

set -euo pipefail

# ======= 通用函数 =======

log() {
  echo -e "🔹 $1"
}

warn() {
  echo -e "⚠️  $1"
}

error() {
  echo -e "❌ $1" >&2
}

usage() {
  echo
  echo "用法: $0 -i <image-keyword> [-n <namespace>]"
  echo
  echo "参数说明:"
  echo "  -i  镜像关键字（用于匹配当前 Deployment 的镜像）"
  echo "  -n  指定命名空间（可选，不填则扫描全部命名空间）"
  echo
  echo "示例:"
  echo "  $0 -i my-service"
  echo "  $0 -i v1.2.3 -n production"
  echo
  exit 1
}

# ======= 参数解析 =======

NAMESPACE=""
IMAGE_KEYWORD=""

while getopts ":i:n:h" opt; do
  case ${opt} in
    i ) IMAGE_KEYWORD=$OPTARG ;;
    n ) NAMESPACE=$OPTARG ;;
    h ) usage ;;
    * ) usage ;;
  esac
done

if [[ -z "${IMAGE_KEYWORD}" ]]; then
  usage
fi

# ======= 环境检查 =======

if ! command -v kubectl &> /dev/null; then
  error "kubectl 未安装，请先安装 kubectl"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  error "无法连接到 Kubernetes 集群，请检查 kubeconfig"
  exit 1
fi

# ======= 获取 Deployment 列表 =======

if [[ -n "$NAMESPACE" ]]; then
  NS_OPT="-n $NAMESPACE"
else
  NS_OPT="--all-namespaces"
fi

log "正在检索 Deployment 信息（关键字: $IMAGE_KEYWORD）..."

DEPLOY_INFO=$(kubectl get deploy $NS_OPT -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"|"}{.image}{"\n"}{end}{end}')

if [[ -z "$DEPLOY_INFO" ]]; then
  error "未找到任何 Deployment"
  exit 1
fi

# ======= 模糊匹配镜像关键字 =======

MATCHED_LINES=$(echo "$DEPLOY_INFO" | grep -i "$IMAGE_KEYWORD" || true)
if [[ -z "$MATCHED_LINES" ]]; then
  error "未找到包含关键字 '$IMAGE_KEYWORD' 的镜像"
  exit 1
fi

echo
log "找到以下匹配的 Deployment 与镜像:"
echo "---------------------------------------------"

MATCHED_NS=()
MATCHED_DEPLOY=()
MATCHED_CONTAINER=()
MATCHED_IMAGE=()

i=0
while IFS='|' read -r ns deploy container image; do
  MATCHED_NS[i]="$ns"
  MATCHED_DEPLOY[i]="$deploy"
  MATCHED_CONTAINER[i]="$container"
  MATCHED_IMAGE[i]="$image"
  printf "%2d) %s/%s (%s): %s\n" "$i" "$ns" "$deploy" "$container" "$image"
  ((i++))
done <<< "$MATCHED_LINES"

if [[ $i -eq 0 ]]; then
  error "未匹配到任何镜像"
  exit 1
fi

echo
read -p "请输入要更新的序号（可输入多个，用空格分隔）: " -a SELECTED_INDICES
if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
  error "未选择任何 Deployment"
  exit 1
fi

# ======= 展示将执行的操作 =======

echo
log "将要执行以下更新操作:"
for idx in "${SELECTED_INDICES[@]}"; do
  echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> ?"
done

# ======= 输入目标镜像 =======

echo
log "请输入完整的目标镜像名称 (包含标签):"
warn "提示: 当前搜索关键字是 '$IMAGE_KEYWORD'"
read -p "目标镜像: " FINAL_IMAGE

if [[ -z "$FINAL_IMAGE" ]]; then
  error "目标镜像不能为空"
  exit 1
fi

# ======= 确认替换计划 =======

echo
log "最终替换计划如下:"
for idx in "${SELECTED_INDICES[@]}"; do
  echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> $FINAL_IMAGE"
done

echo
read -p "确认执行以上更新操作吗？(y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "🚫 已取消操作"
  exit 0
fi

# ======= 执行更新 =======

for idx in "${SELECTED_INDICES[@]}"; do
  ns="${MATCHED_NS[idx]}"
  deploy="${MATCHED_DEPLOY[idx]}"
  container="${MATCHED_CONTAINER[idx]}"
  echo
  log "正在更新: $ns/$deploy ($container)"
  kubectl set image deployment/"$deploy" "$container"="$FINAL_IMAGE" -n "$ns" --record
  log "等待 Rollout 完成..."
  kubectl rollout status deployment/"$deploy" -n "$ns"
done

echo
log "✅ 所有更新操作已完成！"

```

## `k8s-image-replace.sh`

```bash
#!/usr/bin/env bash
# k8s-image-replace.sh
# Replace images in Kubernetes deployments
# Usage: ./k8s-image-replace.sh -i <search-keyword> [-n namespace]
# Note: -i parameter is used to search matching images, actual replacement will prompt for complete target image name

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions
log() { echo -e "${BLUE}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Show help
show_help() {
    cat << EOF
Usage: $0 -i <search-keyword> [-n namespace] [-h]

Parameters:
  -i, --image      Search keyword (required) e.g.: myapp or myapp:v1.2
  -n, --namespace  Specify namespace (optional, default search all namespaces)
  -h, --help       Show help information

Description:
  -i parameter is used to search matching image names, supports partial matching
  During actual replacement, you will be prompted to enter complete target image name (with tag)

Examples:
  $0 -i myapp                    # Search images containing myapp
  $0 -i myapp:v1.2 -n production # Search in production namespace
EOF
}

# Parse arguments
IMAGE=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            IMAGE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown parameter: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check required parameters
if [[ -z "$IMAGE" ]]; then
    error "Search keyword parameter is required"
    show_help
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    error "kubectl not found, please ensure it's installed and in PATH"
    exit 1
fi

# Check kubectl connection
if ! kubectl cluster-info &> /dev/null; then
    error "Unable to connect to Kubernetes cluster"
    exit 1
fi

# Extract image name (without tag)
IMAGE_NAME="${IMAGE%:*}"
IMAGE_TAG="${IMAGE##*:}"

log "Search keyword: $IMAGE"
log "Image name part: $IMAGE_NAME"
if [[ "$IMAGE" == *:* ]]; then
    log "Tag part: $IMAGE_TAG"
fi

# Build kubectl command arguments
if [[ -n "$NAMESPACE" ]]; then
    NS_ARG="-n $NAMESPACE"
    log "Search namespace: $NAMESPACE"
else
    NS_ARG="-A"
    log "Search all namespaces"
fi

echo
log "Searching for matching deployments..."

# Get all deployments and their image information
DEPLOYMENTS=$(kubectl get deployments $NS_ARG -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"="}{.image}{";"}{end}{"\n"}{end}' 2>/dev/null)

if [[ -z "$DEPLOYMENTS" ]]; then
    warn "No deployments found"
    exit 0
fi

# Find matching deployments
MATCHED_NS=()
MATCHED_DEPLOY=()
MATCHED_CONTAINER=()
MATCHED_IMAGE=()

while IFS= read -r line; do
    if [[ -z "$line" ]]; then continue; fi
    
    # Parse line: namespace|deployment|container1=image1;container2=image2;
    ns="${line%%|*}"
    rest="${line#*|}"
    deploy="${rest%%|*}"
    containers="${rest#*|}"
    
    # Parse containers and images
    IFS=';' read -ra container_pairs <<< "$containers"
    for pair in "${container_pairs[@]}"; do
        if [[ -z "$pair" ]]; then continue; fi
        
        container="${pair%%=*}"
        image="${pair#*=}"
        current_image_name="${image%:*}"
        
        # Check if image name matches (supports partial matching)
        if [[ "$current_image_name" == *"$IMAGE_NAME"* ]] || [[ "$IMAGE_NAME" == *"$current_image_name"* ]]; then
            MATCHED_NS+=("$ns")
            MATCHED_DEPLOY+=("$deploy")
            MATCHED_CONTAINER+=("$container")
            MATCHED_IMAGE+=("$image")
        fi
    done
done <<< "$DEPLOYMENTS"

# Display matching results
if [[ ${#MATCHED_NS[@]} -eq 0 ]]; then
    warn "No matching deployments found"
    exit 0
fi

echo
success "Found ${#MATCHED_NS[@]} matching deployment(s):"
echo
printf "%-4s %-20s %-30s %-20s %-40s\n" "No." "Namespace" "Deployment" "Container" "Current Image"
printf "%-4s %-20s %-30s %-20s %-40s\n" "----" "---------" "----------" "---------" "-------------"

for i in "${!MATCHED_NS[@]}"; do
    printf "%-4d %-20s %-30s %-20s %-40s\n" $((i+1)) "${MATCHED_NS[i]}" "${MATCHED_DEPLOY[i]}" "${MATCHED_CONTAINER[i]}" "${MATCHED_IMAGE[i]}"
done

echo
echo "Please select deployments to update:"
echo "  Enter numbers (e.g.: 1,3,5 or 1-3)"
echo "  Enter 'all' to select all"
echo "  Enter 'q' to quit"
echo

read -p "Please select: " selection

case "$selection" in
    q|Q)
        log "User cancelled operation"
        exit 0
        ;;
    all|ALL)
        SELECTED_INDICES=($(seq 0 $((${#MATCHED_NS[@]} - 1))))
        ;;
    *)
        # Parse user input numbers
        SELECTED_INDICES=()
        IFS=',' read -ra selections <<< "$selection"
        for sel in "${selections[@]}"; do
            # Handle range (e.g. 1-3)
            if [[ "$sel" == *-* ]]; then
                start="${sel%-*}"
                end="${sel#*-}"
                for ((j=start; j<=end; j++)); do
                    if [[ $j -ge 1 && $j -le ${#MATCHED_NS[@]} ]]; then
                        SELECTED_INDICES+=($((j-1)))
                    fi
                done
            else
                # Single number
                if [[ "$sel" =~ ^[0-9]+$ ]] && [[ $sel -ge 1 && $sel -le ${#MATCHED_NS[@]} ]]; then
                    SELECTED_INDICES+=($((sel-1)))
                fi
            fi
        done
        ;;
esac

if [[ ${#SELECTED_INDICES[@]} -eq 0 ]]; then
    warn "No deployment selected"
    exit 0
fi

# Display operations to be performed
echo
log "Will perform the following update operations:"
for idx in "${SELECTED_INDICES[@]}"; do
    echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> ?"
done

echo
log "Please enter complete target image name (with tag):"
log "Hint: Current search keyword is: $IMAGE"
echo
read -p "Target image: " FINAL_IMAGE

if [[ -z "$FINAL_IMAGE" ]]; then
    error "Target image cannot be empty"
    exit 1
fi

# Display final replacement plan
echo
log "Final replacement plan:"
for idx in "${SELECTED_INDICES[@]}"; do
    echo "  ${MATCHED_NS[idx]}/${MATCHED_DEPLOY[idx]} (${MATCHED_CONTAINER[idx]}): ${MATCHED_IMAGE[idx]} -> $FINAL_IMAGE"
done

echo
read -p "Confirm execution? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log "User cancelled operation"
    exit 0
fi

# Execute update
echo
log "Starting image update..."

for idx in "${SELECTED_INDICES[@]}"; do
    ns="${MATCHED_NS[idx]}"
    deploy="${MATCHED_DEPLOY[idx]}"
    container="${MATCHED_CONTAINER[idx]}"
    
    log "Updating container $container in $ns/$deploy..."
    
    if kubectl set image deployment/"$deploy" "$container"="$FINAL_IMAGE" -n "$ns" --record; then
        success "✓ $ns/$deploy updated successfully"
        
        # Wait for rollout completion
        log "Waiting for $ns/$deploy rollout to complete..."
        if kubectl rollout status deployment/"$deploy" -n "$ns" --timeout=30s; then
            success "✓ $ns/$deploy rollout completed"
        else
            error "✗ $ns/$deploy rollout timeout or failed"
            warn "To rollback, execute: kubectl rollout undo deployment/$deploy -n $ns"
        fi
    else
        error "✗ $ns/$deploy update failed"
    fi
    echo
done

success "Image update operation completed!"

# Display updated namespace image information
echo
log "Displaying updated image information..."

# Collect all involved namespaces
UPDATED_NAMESPACES=()
for idx in "${SELECTED_INDICES[@]}"; do
    ns="${MATCHED_NS[idx]}"
    # Check if already in the list
    if [[ ! " ${UPDATED_NAMESPACES[*]} " =~ " ${ns} " ]]; then
        UPDATED_NAMESPACES+=("$ns")
    fi
done

# Display all deployment image information for each namespace
for ns in "${UPDATED_NAMESPACES[@]}"; do
    echo
    success "All Deployment image information in namespace '$ns':"
    echo
    
    # Get all deployments and their images in this namespace
    ALL_DEPLOYMENTS=$(kubectl get deployments -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .spec.template.spec.containers[*]}{.name}{"="}{.image}{";"}{end}{"\n"}{end}' 2>/dev/null)
    
    if [[ -z "$ALL_DEPLOYMENTS" ]]; then
        warn "No deployments found in namespace '$ns'"
        continue
    fi
    
    printf "  %-30s %-20s %-50s\n" "Deployment" "Container" "Image"
    printf "  %-30s %-20s %-50s\n" "----------" "---------" "-----"
    
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        
        # Parse line: deployment|container1=image1;container2=image2;
        deploy="${line%%|*}"
        containers="${line#*|}"
        
        # Parse containers and images
        IFS=';' read -ra container_pairs <<< "$containers"
        for pair in "${container_pairs[@]}"; do
            if [[ -z "$pair" ]]; then continue; fi
            
            container="${pair%%=*}"
            image="${pair#*=}"
            
            # Check if just updated
            updated_marker=""
            for idx in "${SELECTED_INDICES[@]}"; do
                if [[ "${MATCHED_NS[idx]}" == "$ns" && "${MATCHED_DEPLOY[idx]}" == "$deploy" && "${MATCHED_CONTAINER[idx]}" == "$container" ]]; then
                    updated_marker=" ✓ (just updated)"
                    break
                fi
            done
            
            printf "  %-30s %-20s %-50s%s\n" "$deploy" "$container" "$image" "$updated_marker"
        done
    done <<< "$ALL_DEPLOYMENTS"
done

echo
log "Image information display completed!"

```

