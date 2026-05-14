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
