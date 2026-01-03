#!/bin/bash
set -euo pipefail

# --- Configuration & Defaults ---
collection=""
outputFile=""
proxy=""
tk=""
project_id=""
page_size=1000
field_mask=""
format="json"
quiet="false"

# Color definitions
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

log_info() {
  if [ "$quiet" = "false" ]; then
    echo -e "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${GREEN}[INFO]${NC} $1" >&2
  fi
}
log_warn() {
  if [ "$quiet" = "false" ]; then
    echo -e "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${YELLOW}[WARN]${NC} $1" >&2
  fi
}
log_error() {
  echo -e "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ${RED}[ERROR]${NC} $1" >&2
}

usage() {
  cat << EOF
Usage: $0 -c collection [-o output] [-p proxy] [-t token] [-P project_id] [-z page_size] [-M field_mask] [-F format] [-q] [-h]

Options:
  -c collection  Firestore collection (Required)
  -o output      Output file (default: <collection>.json)
  -p proxy       HTTP proxy
  -t token       Access token
  -P project_id  GCP Project ID
  -z page_size   Page size (default 1000)
  -M field_mask  Fields comma sep (e.g. name,createTime)
  -F format      json|pretty|ndjson (default json)
  -q             Quiet
  -h             Help

Env: \$PROJECT_ID, \$ACCESS_TOKEN

Example:
  $0 -c capteams -F ndjson -q
EOF
  exit 1
}

# --- Env Overrides ---
project_id="${PROJECT_ID:-}"
tk="${ACCESS_TOKEN:-}"

# --- Argument Parsing ---
while getopts ":c:o:p:t:P:z:M:F:qh" opt; do
  case "$opt" in
    c) collection="$OPTARG" ;;
    o) outputFile="$OPTARG" ;;
    p) proxy="$OPTARG" ;;
    t) tk="$OPTARG" ;;
    P) project_id="$OPTARG" ;;
    z) page_size="$OPTARG" ;;
    M) field_mask="$OPTARG" ;;
    F) format="$OPTARG" ;;
    q) quiet="true" ;;
    h) usage ;;
    :) log_error "Missing -$OPTARG arg"; usage ;;
    ?) log_error "Unknown -$OPTARG"; usage ;;
  esac
done

# --- Validation & Defaults ---
if [ -z "$collection" ]; then log_error "Collection required"; usage; fi

outputFile="${outputFile:-${collection}.json}"

if [ -z "$project_id" ]; then
  project_id=$(gcloud config get-value project 2>/dev/null || true)
  [ -z "$project_id" ] && log_error "No project_id (flag or gcloud)"; exit 2
fi

page_size="${page_size:-1000}"
page_size=$((page_size > 5000 ? 5000 : page_size))
page_size=$((page_size < 1 ? 1 : page_size))

case "$format" in json|pretty|ndjson) ;; * ) log_error "Bad format $format"; exit 3 ;; esac

if [ -z "$tk" ]; then
  command -v gcloud >/dev/null 2>&1 || { log_error "No gcloud/token"; exit 2; }
  log_info "Fetching token via gcloud..."
  tk=$(gcloud auth print-access-token --project="$project_id")
fi

command -v jq >/dev/null 2>&1 || { log_error "jq required"; exit 3; }

# --- Log ---
log_info "Project: $project_id"
log_info "Collection: $collection"
log_info "Output: $outputFile ($format)"
[ -n "$field_mask" ] && log_info "Fields: $field_mask"
log_info "Page size: $page_size"

# --- Fetch ---
nextPageToken=""
tempfile=$(mktemp)
trap 'rm -f "$tempfile"' EXIT

log_info "Fetching documents..."

count=0
page_num=0
while :; do
  page_num=$((page_num + 1))

  url="https://firestore.googleapis.com/v1/projects/$project_id/databases/(default)/documents/$collection"

  curl_args=( -s -G -H "Authorization: Bearer $tk" --data-urlencode "pageSize=$page_size" "$url" )

  [ -n "$nextPageToken" ] && curl_args+=( --data-urlencode "pageToken=$nextPageToken" )

  if [ -n "$field_mask" ]; then
    IFS=',' read -ra fields <<< "$field_mask"
    for f in "${fields[@]}"; do
      curl_args+=( --data-urlencode "fieldMask.fieldPaths=$f" )
    done
  fi

  [ -n "$proxy" ] && curl_args+=( -x "$proxy" )

  # Retry loop for API errors
  response=""
  for att in 1 2 3; do
    response=$(curl "${curl_args[@]}")
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
      sleep $att
      log_warn "Page $page_num attempt $att error, retrying..."
      [ $att = 3 ] && break
      continue
    fi
    break
  done

  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    log_error "Firestore API Error:"
    echo "$response" | jq -r '.error.message // .error' >&2
    exit 4
  fi

  page_docs=$(echo "$response" | jq -c '.documents[]? // empty')
  page_cnt=$(echo "$page_docs" | wc -l)
  if [ "$page_cnt" -gt 0 ]; then
    echo "$page_docs" >> "$tempfile"
    count=$((count + page_cnt))
    [ $((count % (page_size * 10))) -eq 0 ] && log_info "Fetched $count docs (page $page_num)..."
  fi

  nextPageToken=$(echo "$response" | jq -r '.nextPageToken // empty')
  [ -z "$nextPageToken" ] && break
done

# --- Final Output ---
if [ -s "$tempfile" ]; then
  case "$format" in
    ndjson) cat "$tempfile" > "$outputFile" ;;
    pretty) jq -s . "$tempfile" | jq -S . > "$outputFile" ;;
    *) jq -s . "$tempfile" > "$outputFile" ;;
  esac
  log_info "Success! Total $count docs in $outputFile ($format)"
else
  case "$format" in
    ndjson) > "$outputFile" ;;
    *) echo '[]' > "$outputFile" ;;
  esac
  log_warn "No docs. Empty $format in $outputFile"
fi