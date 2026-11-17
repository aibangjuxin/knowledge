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
