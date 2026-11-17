#!/usr/bin/env bash
# approve-tenant-project.sh - Producer 侧审批 Tenant PSC Service Attachment 连接
#
# 设计边界:
#   ACCEPT_MANUAL 模式下, Producer 侧不能可靠枚举所有"待审批"的 Tenant NEG 请求。
#   正确流程是 Tenant 通过工单/流水线提交 project ID, Producer 将其写入 consumer accept list。

set -euo pipefail

if [[ -t 1 ]]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

info() { printf "${BLUE}i${RESET}  %s\n" "$*"; }
ok() { printf "${GREEN}OK${RESET} %s\n" "$*"; }
warn() { printf "${YELLOW}!${RESET}  %s\n" "$*"; }
err() { printf "${RED}ERR${RESET} %s\n" "$*" >&2; }
hdr() { printf "\n${BOLD}%s${RESET}\n" "$*"; }
die() { err "$*"; exit 1; }

PROJECT=""
SA_NAME=""
REGION=""
NON_INTERACTIVE=0
DRY_RUN=0
LIMIT_PER_PROJECT="10"
WAIT_SECONDS=30
MAX_RETRIES=3
TENANT_FILE=""
TENANTS=()

usage() {
  cat <<EOF
用法:
  $0 -p <PRODUCER_PROJECT_ID> [options]

必填:
  -p PROJECT       Producer project ID

Service Attachment 选择:
  -a SA_NAME       指定 service attachment 名称
  -r REGION        指定 region; 和 -a 一起使用时跳过交互选择

Tenant 审批:
  -t PROJECT_ID    要 approve 的 tenant project ID; 可重复传多次
  -f FILE          从文件读取 tenant project ID; 每行一个, # 开头会忽略
  -l LIMIT         每个 tenant 的连接上限, 默认 10

运行控制:
  -n               非交互模式; 必须配合 -a/-r 和 -t/-f 使用
  -d               dry-run, 只打印将要执行的变更
  -w SECONDS       每次校验前等待秒数, 默认 30
  -m RETRIES       校验重试次数, 默认 3
  -h               显示帮助

示例:
  $0 -p master-project
  $0 -p master-project -a api-sa -r asia-east1 -t tenant-a -t tenant-b
  $0 -p master-project -a api-sa -r asia-east1 -f tenants.txt -n -l 20
  $0 -p master-project -a api-sa -r asia-east1 -t tenant-a -d
EOF
}

while getopts ":p:a:r:t:f:l:w:m:ndh" opt; do
  case "$opt" in
    p) PROJECT="$OPTARG" ;;
    a) SA_NAME="$OPTARG" ;;
    r) REGION="$OPTARG" ;;
    t) TENANTS+=("$OPTARG") ;;
    f) TENANT_FILE="$OPTARG" ;;
    l) LIMIT_PER_PROJECT="$OPTARG" ;;
    w) WAIT_SECONDS="$OPTARG" ;;
    m) MAX_RETRIES="$OPTARG" ;;
    n) NON_INTERACTIVE=1 ;;
    d) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    :) die "选项 -$OPTARG 需要参数" ;;
    \?) die "未知选项 -$OPTARG; 使用 -h 查看帮助" ;;
  esac
done

[[ -n "$PROJECT" ]] || { usage; die "必须用 -p 指定 Producer project ID"; }
[[ "$LIMIT_PER_PROJECT" =~ ^[1-9][0-9]*$ ]] || die "-l LIMIT 必须是正整数"
[[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || die "-w SECONDS 必须是非负整数"
[[ "$MAX_RETRIES" =~ ^[0-9]+$ ]] || die "-m RETRIES 必须是非负整数"

for cmd in gcloud jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "缺少依赖: $cmd"
done

if [[ -n "$TENANT_FILE" ]]; then
  [[ -r "$TENANT_FILE" ]] || die "无法读取 tenant 文件: $TENANT_FILE"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && TENANTS+=("$line")
  done < "$TENANT_FILE"
fi

if (( NON_INTERACTIVE == 1 )); then
  [[ -n "$SA_NAME" && -n "$REGION" ]] || die "-n 非交互模式必须指定 -a SA_NAME 和 -r REGION"
  (( ${#TENANTS[@]} > 0 )) || die "-n 非交互模式必须通过 -t 或 -f 显式提供 tenant project"
fi

validate_project_id() {
  local value="$1"
  [[ "$value" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

dedupe_tenants() {
  local tenant
  local unique=()
  local seen=" "
  for tenant in "${TENANTS[@]}"; do
    validate_project_id "$tenant" || die "tenant project ID 格式不合法: $tenant"
    if [[ "$seen" != *" $tenant "* ]]; then
      unique+=("$tenant")
      seen+="$tenant "
    fi
  done
  TENANTS=("${unique[@]}")
}

dedupe_tenants

if ! gcloud projects describe "$PROJECT" >/dev/null 2>&1; then
  die "无法访问 project '$PROJECT'; 检查 gcloud auth 和 compute.viewer 权限"
fi
ok "已连接 Producer project: $PROJECT"

list_service_attachments() {
  gcloud compute service-attachments list \
    --project="$PROJECT" \
    --format="csv[no-heading](region.basename(),name.basename(),connectionPreference)" 2>/dev/null
}

fetch_sa_state() {
  local region="$1" name="$2"
  gcloud compute service-attachments describe "$name" \
    --project="$PROJECT" \
    --region="$region" \
    --format=json 2>/dev/null
}

pick_service_attachment() {
  local raw matches count pick selected
  raw="$(list_service_attachments)"
  [[ -n "$raw" ]] || die "project $PROJECT 下没有 service attachment"

  if [[ -n "$SA_NAME" ]]; then
    if [[ -n "$REGION" ]]; then
      fetch_sa_state "$REGION" "$SA_NAME" >/dev/null || die "找不到 SA: $SA_NAME region=$REGION"
      SELECTED_REGION="$REGION"
      SELECTED_NAME="$SA_NAME"
      info "使用指定 SA: $SELECTED_NAME ($SELECTED_REGION)"
      return 0
    fi

    matches="$(printf '%s\n' "$raw" | awk -F',' -v name="$SA_NAME" '$2 == name')"
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "$count" != "0" ]] || die "找不到 SA: $SA_NAME"
    [[ "$count" == "1" ]] || die "SA_NAME=$SA_NAME 在多个 region 存在; 请加 -r REGION"
    selected="$matches"
    SELECTED_REGION="${selected%%,*}"
    selected="${selected#*,}"
    SELECTED_NAME="${selected%%,*}"
    info "使用指定 SA: $SELECTED_NAME ($SELECTED_REGION)"
    return 0
  fi

  hdr "1. 选择 Service Attachment"
  printf "  %-4s %-42s %-18s %s\n" "#" "NAME" "REGION" "PREFERENCE"
  local index=1
  while IFS=',' read -r row_region row_name row_pref; do
    [[ -n "$REGION" && "$row_region" != "$REGION" ]] && continue
    printf "  %-4s %-42s %-18s %s\n" "$index" "$row_name" "$row_region" "$row_pref"
    index=$((index + 1))
  done <<< "$raw"

  count=$((index - 1))
  (( count > 0 )) || die "region=$REGION 下没有 service attachment"

  read -r -p "$(printf "%b选哪个 SA? [1-%s, q=quit]: %b" "$BOLD" "$count" "$RESET")" pick
  [[ "$pick" == "q" || "$pick" == "Q" ]] && { info "已退出"; exit 0; }
  if ! [[ "$pick" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > count )); then
    die "无效选择: $pick"
  fi

  selected="$(printf '%s\n' "$raw" | awk -F',' -v want_region="$REGION" -v pick="$pick" '
    (want_region == "" || $1 == want_region) {
      idx++
      if (idx == pick) {
        print
        exit
      }
    }')"
  SELECTED_REGION="${selected%%,*}"
  selected="${selected#*,}"
  SELECTED_NAME="${selected%%,*}"
}

print_state_summary() {
  local region="$1" name="$2" json pref limit_total approved_count ep_count
  json="$(fetch_sa_state "$region" "$name")"
  [[ -n "$json" ]] || die "无法 describe SA: $name region=$region"

  pref="$(jq -r '.connectionPreference // "UNKNOWN"' <<< "$json")"
  limit_total="$(jq -r '.propagatedConnectionLimit // "n/a"' <<< "$json")"

  hdr "2. 当前状态"
  printf "SA:              ${BOLD}%s${RESET}\n" "$name"
  printf "Region:          %s\n" "$region"
  printf "Preference:      ${BOLD}%s${RESET}\n" "$pref"
  printf "PropagatedLimit: %s\n" "$limit_total"

  if [[ "$pref" != "ACCEPT_MANUAL" ]]; then
    warn "当前是 $pref 模式; 不需要维护 consumer accept list"
    return 1
  fi

  hdr "3. 已批准 consumerAcceptLists"
  approved_count="$(jq -r '.consumerAcceptLists | length // 0' <<< "$json")"
  if [[ "$approved_count" == "0" ]]; then
    echo "  (空)"
  else
    printf "  %-34s %s\n" "PROJECT_OR_NETWORK" "LIMIT"
    jq -r '.consumerAcceptLists[]? | [.projectOrNetwork, (.limit // "-")] | @tsv' <<< "$json" |
      while IFS=$'\t' read -r project_or_network limit; do
        printf "  %-34s %s\n" "$project_or_network" "$limit"
      done
  fi

  hdr "4. 当前 connectedEndpoints"
  ep_count="$(jq -r '.connectedEndpoints | length // 0' <<< "$json")"
  if [[ "$ep_count" == "0" ]]; then
    echo "  (空)"
  else
    printf "  %-34s %-42s %s\n" "PROJECT_OR_NETWORK" "PSC_NEG" "STATUS"
    jq -r '.connectedEndpoints[]? | [.projectOrNetwork // "-", .pscNetworkEndpointGroup // "-", .pscConnectionStatus // "-"] | @tsv' <<< "$json" |
      while IFS=$'\t' read -r project_or_network neg status; do
        printf "  %-34s %-42s %s\n" "$project_or_network" "$neg" "$status"
      done
  fi
}

build_accept_list_arg() {
  local json="$1" tenant="$2"
  jq -r \
    --arg tenant "$tenant" \
    --argjson limit "$LIMIT_PER_PROJECT" '
      [
        (.consumerAcceptLists[]? | select(.projectOrNetwork != $tenant) |
          "\(.projectOrNetwork)=\((.limit // $limit))"),
        "\($tenant)=\($limit)"
      ] | join(",")
    ' <<< "$json"
}

wait_for_acceptance() {
  local region="$1" sa_name="$2" tenant="$3"
  local attempt status fresh_json

  if (( WAIT_SECONDS > 0 )); then
    info "等待 ${WAIT_SECONDS}s 后校验连接状态"
    sleep "$WAIT_SECONDS"
  fi

  for (( attempt=1; attempt<=MAX_RETRIES; attempt++ )); do
    fresh_json="$(fetch_sa_state "$region" "$sa_name")"
    status="$(jq -r --arg tenant "$tenant" '
      [.connectedEndpoints[]? | select(.projectOrNetwork == $tenant) | .pscConnectionStatus] | first // "NOT_FOUND"
    ' <<< "$fresh_json")"

    case "$status" in
      ACCEPTED)
        ok "$tenant 已 ACCEPTED"
        return 0
        ;;
      PENDING|NOT_FOUND)
        warn "$tenant 状态: $status ($attempt/$MAX_RETRIES)"
        (( attempt == MAX_RETRIES || WAIT_SECONDS == 0 )) || sleep "$WAIT_SECONDS"
        ;;
      REJECTED|CLOSED)
        err "$tenant 状态异常: $status"
        err "检查 consumer-reject-list、Tenant PSC NEG target service、region 是否一致"
        return 1
        ;;
      *)
        warn "$tenant 状态未知: $status ($attempt/$MAX_RETRIES)"
        (( attempt == MAX_RETRIES || WAIT_SECONDS == 0 )) || sleep "$WAIT_SECONDS"
        ;;
    esac
  done

  warn "$tenant 已加入 accept list, 但尚未在 connectedEndpoints 中看到 ACCEPTED"
  warn "这通常表示 Tenant 侧 NEG 尚未创建、未重试连接, 或 GCP 状态传播未完成"
}

do_approve() {
  local region="$1" sa_name="$2" tenant="$3"
  local current_json already_approved new_list_args

  current_json="$(fetch_sa_state "$region" "$sa_name")"
  already_approved="$(jq -r --arg tenant "$tenant" '
    any(.consumerAcceptLists[]?; .projectOrNetwork == $tenant)
  ' <<< "$current_json")"

  if [[ "$already_approved" == "true" ]]; then
    ok "$tenant 已在 accept list 中; 跳过更新"
    wait_for_acceptance "$region" "$sa_name" "$tenant"
    return 0
  fi

  new_list_args="$(build_accept_list_arg "$current_json" "$tenant")"

  hdr "Approve $tenant -> $sa_name"
  info "consumer-accept-list: $new_list_args"
  if (( DRY_RUN == 1 )); then
    warn "dry-run: 未执行 gcloud update"
    return 0
  fi

  if ! gcloud compute service-attachments update "$sa_name" \
      --project="$PROJECT" \
      --region="$region" \
      --consumer-accept-list="$new_list_args"; then
    err "approve $tenant 失败"
    return 1
  fi

  wait_for_acceptance "$region" "$sa_name" "$tenant"
}

collect_interactive_tenants() {
  local tenant
  hdr "5. 输入待审批 Tenant"
  warn "Producer 侧无法可靠自动发现 pending Tenant; 请输入工单/流水线提供的 project ID"
  echo "  空行结束, q 退出"

  while true; do
    read -r -p "$(printf "%btenant project: %b" "$BOLD" "$RESET")" tenant
    [[ -z "$tenant" ]] && break
    [[ "$tenant" == "q" || "$tenant" == "Q" ]] && exit 0
    validate_project_id "$tenant" || { warn "project ID 格式不合法: $tenant"; continue; }
    TENANTS+=("$tenant")
  done
  dedupe_tenants
}

approve_tenants() {
  local region="$1" sa_name="$2" tenant confirm failures=0

  if (( ${#TENANTS[@]} == 0 )); then
    collect_interactive_tenants
  fi

  if (( ${#TENANTS[@]} == 0 )); then
    info "没有 tenant 需要审批"
    return 0
  fi

  hdr "6. 执行审批"
  for tenant in "${TENANTS[@]}"; do
    if (( NON_INTERACTIVE == 0 && DRY_RUN == 0 )); then
      read -r -p "$(printf "确认 approve %b%s%b (limit=%s)? [Y/n]: " "$BOLD" "$tenant" "$RESET" "$LIMIT_PER_PROJECT")" confirm
      confirm="${confirm:-Y}"
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        info "跳过 $tenant"
        continue
      fi
    fi

    if ! do_approve "$region" "$sa_name" "$tenant"; then
      failures=$((failures + 1))
    fi
  done

  (( failures == 0 )) || die "$failures 个 tenant 审批失败"
}

main() {
  pick_service_attachment
  print_state_summary "$SELECTED_REGION" "$SELECTED_NAME" || exit 0
  approve_tenants "$SELECTED_REGION" "$SELECTED_NAME"

  hdr "最终状态"
  print_state_summary "$SELECTED_REGION" "$SELECTED_NAME" || true
}

main "$@"
