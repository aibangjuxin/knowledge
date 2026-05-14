#!/bin/bash
set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_result() { echo -e "${CYAN}[RESULT]${NC} $1"; }

#######################################
# Define collections to search
# Modify this array to include the collections you want to search
#######################################
declare -a COLLECTIONS=(
    "teams"
    "apimetadatas"
    "features"
)

#######################################
# Defaults
#######################################
keyword=""
proxy=""
tk=""
project_id=""
output_format="table"  # table, json, or csv

#######################################
# Usage
#######################################
usage() {
    cat <<EOF
Usage: $0 [-k keyword] [-p proxy] [-t token] [-P project_id] [-f format] [-h]

Options:
  -k keyword     Field name to search for (e.g., api_name)
  -p proxy       HTTP proxy (e.g. host:port)
  -t token       Access token (if omitted, uses gcloud auth print-access-token)
  -P project_id  GCP Project ID (default: current gcloud project)
  -f format      Output format: table, json, or csv (default: table)
  -h             Show this help

Example:
  $0 -k "api_name" -P my-project
  $0 -k "api_name" -f json -P my-project

Note:
  - The script will search for documents in the predefined collections that contain the specified keyword field
  - Edit the COLLECTIONS array in the script to customize which collections to search
EOF
    exit 1
}

#######################################
# Args parsing
#######################################
while getopts ":k:p:t:P:f:h" opt; do
    case "$opt" in
        k) keyword="$OPTARG" ;;
        p) proxy="$OPTARG" ;;
        t) tk="$OPTARG" ;;
        P) project_id="$OPTARG" ;;
        f) output_format="$OPTARG" ;;
        h) usage ;;
        :) log_error "Option -$OPTARG requires an argument"; usage ;;
        \?) log_error "Unknown option: -$OPTARG"; usage ;;
    esac
done

# Validate required arguments
if [ -z "$keyword" ]; then
    log_error "Keyword (-k) is required."
    usage
fi

# Validate output format
case "$output_format" in
    table|json|csv) ;;
    *) log_error "Invalid format: $output_format. Use table, json, or csv."; exit 1 ;;
esac

#######################################
# Get Project ID
#######################################
if [ -z "$project_id" ]; then
    if command -v gcloud >/dev/null 2>&1; then
        project_id=$(gcloud config get-value project 2>/dev/null) || true
    fi
    if [ -z "$project_id" ]; then
        log_error "Project ID not provided and could not be detected via gcloud."
        exit 2
    fi
fi

#######################################
# Get Token
#######################################
if [ -z "$tk" ]; then
    if command -v gcloud >/dev/null 2>&1; then
        log_info "No token supplied - fetching via gcloud..."
        tk=$(gcloud auth print-access-token)
    else
        log_error "No token supplied and gcloud not found. Provide -t <token>."
        exit 2
    fi
fi

#######################################
# Check dependencies
#######################################
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed."
    exit 3
fi

#######################################
# Display configuration
#######################################
log_info "Project ID    : ${BLUE}${project_id}${NC}"
log_info "Keyword       : ${BLUE}${keyword}${NC}"
log_info "Collections   : ${BLUE}${COLLECTIONS[*]}${NC}"
log_info "Output Format : ${BLUE}${output_format}${NC}"
[ -n "$proxy" ] && log_info "Proxy         : ${BLUE}${proxy}${NC}"
echo ""

#######################################
# Function to extract field value from Firestore document
# $1: JSON document
# $2: field name to extract
#######################################
extract_field_value() {
    local json="$1"
    local field_name="$2"
    
    # Extract the value of the specified field from Firestore document structure
    # Firestore stores data in a specific format where values are nested under .fields
    local value=$(echo "$json" | jq -r ".fields[\"$field_name\"] |
        if .stringValue then .stringValue
        elif .integerValue then .integerValue
        elif .doubleValue then .doubleValue
        elif .booleanValue then .booleanValue
        elif .timestampValue then .timestampValue
        elif .arrayValue then .arrayValue
        elif .mapValue then .mapValue
        elif .nullValue then null
        else null
        end")
    
    echo "$value"
}

#######################################
# Function to get document ID from document name
# $1: document name (e.g., projects/p/databases/(default)/documents/collection/docid)
#######################################
get_document_id() {
    local name="$1"
    # Extract the document ID from the end of the name path
    echo "$name" | sed 's/.*\/documents\/[^\/]*\///'
}

#######################################
# Main search loop
#######################################
log_info "Searching for documents with field '${keyword}' in collections: ${COLLECTIONS[*]}..."
echo ""

results=()

for collection in "${COLLECTIONS[@]}"; do
    log_info "Processing collection: ${CYAN}${collection}${NC}"
    
    # Fetch all documents from the collection using list documents API
    nextPageToken=""
    tempfile=$(mktemp)
    trap 'rm -f "$tempfile"' RETURN
    
    while :; do
        url="https://firestore.googleapis.com/v1/projects/${project_id}/databases/(default)/documents/${collection}"
        
        curl_args=(-s -G -H "Authorization: Bearer ${tk}")
        [ -n "$nextPageToken" ] && curl_args+=(--data-urlencode "pageToken=${nextPageToken}")
        [ -n "$proxy" ] && curl_args+=(-x "$proxy")
        curl_args+=("${url}")
        
        response=$(curl "${curl_args[@]}")
        
        # Check for API errors
        if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
            error_msg=$(echo "$response" | jq -r '.error.message // .error')
            log_error "API error for collection $collection: $error_msg"
            break
        fi
        
        # Extract documents and append to temp file
        page_docs=$(echo "$response" | jq -c '.documents[]? // empty')
        if [ -n "$page_docs" ]; then
            echo "$page_docs" >> "$tempfile"
        fi
        
        # Get next page token
        nextPageToken=$(echo "$response" | jq -r '.nextPageToken // empty')
        [ -z "$nextPageToken" ] && break
    done
    
    # Process documents from this collection
    if [ -s "$tempfile" ]; then
        while IFS= read -r document; do
            # Check if the document contains the keyword field
            field_exists=$(echo "$document" | jq -r ".fields | has(\"$keyword\")")
            
            if [ "$field_exists" = "true" ]; then
                doc_id=$(get_document_id "$(echo "$document" | jq -r '.name')")
                field_value=$(extract_field_value "$document" "$keyword")
                
                # Store result
                results+=("$collection|$doc_id|$field_value")
                
                log_result "Found in collection '${collection}', document '${doc_id}': $keyword = $field_value"
            fi
        done < "$tempfile"
    fi
    
    rm -f "$tempfile"
    trap - RETURN
done

#######################################
# Output results based on format
#######################################
echo ""
log_info "Search completed. Found ${#results[@]} documents with field '${keyword}'."

if [ ${#results[@]} -gt 0 ]; then
    case "$output_format" in
        table)
            printf "%-20s %-30s %s\n" "Collection" "Document ID" "$keyword"
            printf "%-20s %-30s %s\n" "----------" "-----------" "-------"
            for result in "${results[@]}"; do
                IFS='|' read -r collection doc_id value <<< "$result"
                printf "%-20s %-30s %s\n" "$collection" "$doc_id" "$value"
            done
            ;;
        json)
            echo "["
            for i in "${!results[@]}"; do
                IFS='|' read -r collection doc_id value <<< "${results[$i]}"
                if [ $i -lt $((${#results[@]} - 1)) ]; then
                    echo "  {\"collection\": \"$collection\", \"document_id\": \"$doc_id\", \"$keyword\": $value},"
                else
                    echo "  {\"collection\": \"$collection\", \"document_id\": \"$doc_id\", \"$keyword\": $value}"
                fi
            done
            echo "]"
            ;;
        csv)
            echo "Collection,Document ID,$keyword"
            for result in "${results[@]}"; do
                IFS='|' read -r collection doc_id value <<< "$result"
                # Escape quotes and wrap in quotes for CSV
                value=$(echo "$value" | sed 's/"/""/g')
                echo "\"$collection\",\"$doc_id\",\"$value\""
            done
            ;;
    esac
else
    log_warn "No documents found with field '${keyword}'."
fi