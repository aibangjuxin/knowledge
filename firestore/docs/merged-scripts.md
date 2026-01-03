# Shell Scripts Collection

Generated on: 2025-12-30 19:34:14
Directory: /Users/lex/git/knowledge/firestore

## `firestore-get-collection-chatgpt.sh`

```bash
#!/bin/bash
set -euo pipefail

#######################################
# Defaults
#######################################
collection="capteams"
outputFile=""
proxy=""
tk=""
project_id="firestore-gcp-project"
page_size=1000

#######################################
# Usage
#######################################
usage() {
  cat <<EOF
Usage: $0 [-c collection] [-o output] [-p proxy] [-t token] [-P project_id] [-h]

Options:
  -c collection   Firestore collection (default: ${collection})
  -o output       Output file (default: <collection>.json)
  -p proxy        HTTP proxy (e.g. host:port)
  -t token        Access token (if omitted, uses gcloud)
  -P project_id   GCP Project ID (default: ${project_id})
  -h              Show this help

Example:
  $0 -c capteams -p proxy.example.com:3128 -P my-project
EOF
  exit 1
}

#######################################
# Args parsing
#######################################
while getopts ":c:o:p:t:P:h" opt; do
  case "$opt" in
  c) collection="$OPTARG" ;;
  o) outputFile="$OPTARG" ;;
  p) proxy="$OPTARG" ;;
  t) tk="$OPTARG" ;;
  P) project_id="$OPTARG" ;;
  h) usage ;;
  :)
    echo "Missing argument for -$OPTARG" >&2
    usage
    ;;
  \?)
    echo "Unknown option: -$OPTARG" >&2
    usage
    ;;
  esac
done

#######################################
# Output file default logic
#######################################
if [ -z "$outputFile" ]; then
  outputFile="${collection}.json"
fi

#######################################
# Dependency checks
#######################################
command -v jq >/dev/null 2>&1 || {
  echo "Error: jq is required." >&2
  exit 3
}

#######################################
# Token handling
#######################################
if [ -z "$tk" ]; then
  if command -v gcloud >/dev/null 2>&1; then
    echo "No token supplied, fetching via gcloud..."
    tk="$(gcloud auth print-access-token)"
  else
    echo "Error: No token and gcloud not available." >&2
    exit 2
  fi
fi

#######################################
# Info
#######################################
echo "Project     : ${project_id}"
echo "Collection  : ${collection}"
echo "Output file : ${outputFile}"
[ -n "$proxy" ] && echo "Proxy       : ${proxy}"

#######################################
# Fetch loop
#######################################
nextPageToken=""
tempfile="$(mktemp)"
trap 'rm -f "$tempfile"' EXIT

echo "Fetching Firestore documents..."

while :; do
  url="https://firestore.googleapis.com/v1/projects/${project_id}/databases/(default)/documents/${collection}"

  curl_args=(
    -sS
    -G
    -H "Authorization: Bearer ${tk}"
    --data-urlencode "pageSize=${page_size}"
  )

  [ -n "$nextPageToken" ] &&
    curl_args+=(--data-urlencode "pageToken=${nextPageToken}")

  [ -n "$proxy" ] && curl_args+=(-x "$proxy")

  curl_args+=("$url")

  response="$(curl "${curl_args[@]}")"

  # API-level error
  if echo "$response" | jq -e '.error' >/dev/null; then
    echo "Firestore API error:"
    echo "$response" | jq .
    exit 4
  fi

  # Append documents
  echo "$response" | jq -c '.documents[]?' >>"$tempfile" || true

  nextPageToken="$(echo "$response" | jq -r '.nextPageToken // empty')"
  [ -z "$nextPageToken" ] && break
done

#######################################
# Final output
#######################################
if [ -s "$tempfile" ]; then
  jq -s '.' "$tempfile" >"$outputFile"
  echo "Done. Saved to ${outputFile}"
else
  echo "No documents found."
  echo "[]" >"$outputFile"
fi

```

## `firestore-get-collection-claude.sh`

```bash
#!/bin/bash
set -euo pipefail

# 默认值
collection="capteams"
outputFile=""
proxy=""
tk=""
project_id="firestore-gcp-project"

usage() {
  cat <<EOF
Usage: $0 [-c collection] [-o output] [-p proxy] [-t token] [-P project_id] [-h]

Options:
  -c collection  Firestore collection (default: $collection)
  -o output      Output file (default: <collection>.json)
  -p proxy       HTTP proxy (e.g. host:port)
  -t token       Access token (if omitted, uses gcloud auth print-access-token)
  -P project_id  GCP Project ID (default: $project_id)
  -h             Show this help

Example:
  $0 -c capteams -p google-proxy.example.com:3128 -P my-gcp-project
  $0 -c users -o custom-output.json
EOF
  exit 1
}

# 参数解析
while getopts ":c:o:p:t:P:h" opt; do
  case "$opt" in
  c) collection="$OPTARG" ;;
  o) outputFile="$OPTARG" ;;
  p) proxy="$OPTARG" ;;
  t) tk="$OPTARG" ;;
  P) project_id="$OPTARG" ;;
  h) usage ;;
  :)
    echo "Error: Missing argument for -$OPTARG" >&2
    usage
    ;;
  \?)
    echo "Error: Unknown option -$OPTARG" >&2
    usage
    ;;
  esac
done

# 动态生成输出文件名
if [ -z "$outputFile" ]; then
  outputFile="${collection}.json"
fi

# 获取 access token
if [ -z "$tk" ]; then
  if command -v gcloud >/dev/null 2>&1; then
    echo "Fetching access token via gcloud..." >&2
    tk=$(gcloud auth print-access-token) || {
      echo "Error: Failed to get access token from gcloud" >&2
      exit 2
    }
  else
    echo "Error: No token supplied and gcloud not found. Use -t <token>" >&2
    exit 2
  fi
fi

# 检查 jq 依赖
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed" >&2
  exit 3
fi

# 输出配置信息
echo "Configuration:" >&2
echo "  Project ID:  $project_id" >&2
echo "  Collection:  $collection" >&2
echo "  Output file: $outputFile" >&2
[ -n "$proxy" ] && echo "  Proxy:       $proxy" >&2

# 创建临时文件
tempfile=$(mktemp)
trap 'rm -f "$tempfile"' EXIT

echo "Fetching documents from collection '$collection'..." >&2

# 分页获取数据
nextPageToken=""
pageCount=0

while :; do
  ((pageCount++))
  url="https://firestore.googleapis.com/v1/projects/$project_id/databases/(default)/documents/$collection"

  # 构建 curl 参数
  curl_args=(
    -s
    -w "\n%{http_code}"
    -G
    -H "Authorization: Bearer $tk"
  )

  [ -n "$nextPageToken" ] && curl_args+=(--data-urlencode "pageToken=$nextPageToken")
  [ -n "$proxy" ] && curl_args+=(-x "$proxy")

  curl_args+=("$url")

  # 执行请求
  response=$(curl "${curl_args[@]}")

  # 分离 HTTP 状态码和响应体
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  # 检查 HTTP 状态码
  if [ "$http_code" -ne 200 ]; then
    echo "Error: HTTP $http_code received" >&2
    echo "$body" | jq -C '.' >&2 2>/dev/null || echo "$body" >&2
    exit 4
  fi

  # 检查 API 错误
  if echo "$body" | jq -e '.error' >/dev/null 2>&1; then
    echo "Error: Firestore API error" >&2
    echo "$body" | jq -C '.error' >&2
    exit 4
  fi

  # 提取文档并追加到临时文件
  docCount=$(echo "$body" | jq -r '.documents // [] | length')
  if [ "$docCount" -gt 0 ]; then
    echo "$body" | jq -c '.documents[]' >>"$tempfile"
    echo "  Page $pageCount: fetched $docCount document(s)" >&2
  fi

  # 获取下一页 token
  nextPageToken=$(echo "$body" | jq -r '.nextPageToken // empty')

  [ -z "$nextPageToken" ] && break
done

# 生成最终 JSON 文件
if [ -s "$tempfile" ]; then
  totalDocs=$(wc -l <"$tempfile" | tr -d ' ')
  jq -s '.' "$tempfile" >"$outputFile"
  echo "Success: Exported $totalDocs document(s) to $outputFile" >&2
else
  echo "Warning: No documents found in collection '$collection'" >&2
  echo "[]" >"$outputFile"
fi

```

## `firestore-get-collection-grok.sh`

```bash
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
```

## `firestore-get-collection.sh`

```bash
#!/bin/bash
set -euo pipefail

# --- Configuration & Defaults ---
collection=""
outputFile=""
proxy=""
tk=""
project_id=""

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

usage() {
    cat <<EOF
Usage: $0 -c collection [-o output] [-p proxy] [-t token] [-P project_id] [-h]

Options:
  -c collection  Firestore collection (Required)
  -o output      Output file (default: <collection>.json)
  -p proxy       HTTP proxy (e.g. host:port)
  -t token       Access token (if omitted, uses gcloud auth print-access-token)
  -P project_id  GCP Project ID (default: current gcloud project)
  -h             Show this help

Example:
  $0 -c capteams -p google-proxy.example.com:3128
EOF
    exit 1
}

# --- Argument Parsing ---
while getopts ":c:o:p:t:P:h" opt; do
    case "$opt" in
        c) collection="$OPTARG" ;;
        o) outputFile="$OPTARG" ;;
        p) proxy="$OPTARG" ;;
        t) tk="$OPTARG" ;;
        P) project_id="$OPTARG" ;;
        h) usage ;;
        :) log_error "Missing option argument for -$OPTARG"; usage ;;
        \?) log_error "Unknown option: -$OPTARG"; usage ;;
    esac
done

# --- Validation & Dynamic Defaults ---
if [ -z "${collection}" ]; then
    log_error "Collection (-c) is required."
    usage
fi

if [ -z "${outputFile}" ]; then
    outputFile="${collection}.json"
fi

if [ -z "${project_id}" ]; then
    if command -v gcloud >/dev/null 2>&1; then
        project_id=$(gcloud config get-value project 2>/dev/null) || true
    fi
    if [ -z "${project_id}" ]; then
        log_error "Project ID not provided and could not be detected via gcloud."
        exit 2
    fi
fi

if [ -z "${tk}" ]; then
    if command -v gcloud >/dev/null 2>&1; then
        log_info "No token supplied - fetching via gcloud..."
        tk=$(gcloud auth print-access-token)
    else
        log_error "No token supplied and gcloud not found. Provide -t <token>."
        exit 2
    fi
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed."
    exit 3
fi

# --- Execution ---
log_info "Project: ${BLUE}${project_id}${NC}"
log_info "Collection: ${BLUE}${collection}${NC}"
log_info "Output File: ${BLUE}${outputFile}${NC}"
[ -n "$proxy" ] && log_info "Proxy: ${BLUE}${proxy}${NC}"

nextPageToken=""
tempfile=$(mktemp)
trap 'rm -f "$tempfile"' EXIT

log_info "Fetching documents..."

count=0
while :; do
    url="https://firestore.googleapis.com/v1/projects/${project_id}/databases/(default)/documents/${collection}"
    
    curl_args=(-s -G -H "Authorization: Bearer ${tk}")
    [ -n "$nextPageToken" ] && curl_args+=(--data-urlencode "pageToken=${nextPageToken}")
    [ -n "$proxy" ] && curl_args+=(-x "$proxy")
    curl_args+=("${url}")
    
    response=$(curl "${curl_args[@]}")
    
    # Check for API errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        log_error "Firestore API Error:"
        echo "$response" | jq -r '.error.message // .error' >&2
        exit 4
    fi

    # Append documents and update count
    page_docs=$(echo "$response" | jq -c '.documents[]? // empty')
    if [ -n "$page_docs" ]; then
        echo "$page_docs" >> "$tempfile"
        count=$((count + $(echo "$page_docs" | wc -l)))
        log_info "Fetched $count documents..."
    fi

    nextPageToken=$(echo "$response" | jq -r '.nextPageToken // empty')
    [ -z "$nextPageToken" ] || [ "$nextPageToken" == "null" ] && break
done

# --- Finalizing Output ---
if [ -s "$tempfile" ]; then
    jq -s '.' "$tempfile" > "$outputFile"
    log_info "${GREEN}Success!${NC} Total $count documents stored in ${BLUE}${outputFile}${NC}"
else
    log_warn "No documents found in collection ${BLUE}${collection}${NC}."
    echo "[]" > "$outputFile"
    log_info "Empty array stored in ${BLUE}${outputFile}${NC}"
fi
```

