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
