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