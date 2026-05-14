#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  apply-urlmap-json.sh <project-id> <region> <urlmap.json> [validate|create|update|upsert]

Examples:
  ./apply-urlmap-json.sh my-project europe-west2 ./urlmap.json validate
  ./apply-urlmap-json.sh my-project europe-west2 ./urlmap.json upsert

Notes:
  - Uses the Compute Engine regional URL Maps REST API.
  - Uses curl with a Bearer token from GOOGLE_OAUTH_ACCESS_TOKEN or gcloud auth print-access-token.
  - Runs a local static validation before calling Google.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

json_field() {
  local file="$1"
  local field="$2"
  python3 - "$file" "$field" <<'PY'
import json
import sys
from pathlib import Path

file_path, field = sys.argv[1], sys.argv[2]
data = json.loads(Path(file_path).read_text(encoding="utf-8"))
value = data.get(field)
if not isinstance(value, str) or not value:
    raise SystemExit(f"missing string field: {field}")
print(value)
PY
}

build_validate_body() {
  local source_json="$1"
  local target_json="$2"
  python3 - "$source_json" "$target_json" <<'PY'
import json
import sys
from pathlib import Path

source_path, target_path = sys.argv[1], sys.argv[2]
resource = json.loads(Path(source_path).read_text(encoding="utf-8"))
Path(target_path).write_text(json.dumps({"resource": resource}), encoding="utf-8")
PY
}

build_update_body() {
  local source_json="$1"
  local fingerprint="$2"
  local target_json="$3"
  python3 - "$source_json" "$fingerprint" "$target_json" <<'PY'
import json
import sys
from pathlib import Path

source_path, fingerprint, target_path = sys.argv[1], sys.argv[2], sys.argv[3]
resource = json.loads(Path(source_path).read_text(encoding="utf-8"))
resource["fingerprint"] = fingerprint
Path(target_path).write_text(json.dumps(resource), encoding="utf-8")
PY
}

http_status() {
  local method="$1"
  local url="$2"
  local body_file="${3:-}"
  local out_file="$4"
  local status

  if [[ -n "$body_file" ]]; then
    status=$(curl -sS -o "$out_file" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      --data @"$body_file" \
      "$url")
  else
    status=$(curl -sS -o "$out_file" -w '%{http_code}' \
      -X "$method" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      "$url")
  fi

  echo "$status"
}

pretty_print() {
  local file="$1"
  python3 -m json.tool "$file"
}

require_cmd curl
require_cmd python3

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

PROJECT_ID="$1"
REGION="$2"
URLMAP_JSON="$3"
MODE="${4:-upsert}"

case "$MODE" in
  validate|create|update|upsert)
    ;;
  *)
    echo "invalid mode: $MODE" >&2
    usage
    exit 2
    ;;
esac

if [[ ! -f "$URLMAP_JSON" ]]; then
  echo "file not found: $URLMAP_JSON" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/validate-urlmap-json.py" "$URLMAP_JSON"

URLMAP_NAME="$(json_field "$URLMAP_JSON" name)"
ACCESS_TOKEN="${GOOGLE_OAUTH_ACCESS_TOKEN:-}"
if [[ -z "$ACCESS_TOKEN" ]]; then
  require_cmd gcloud
  ACCESS_TOKEN="$(gcloud auth print-access-token)"
fi

BASE_URL="https://compute.googleapis.com/compute/v1/projects/${PROJECT_ID}/regions/${REGION}/urlMaps"
RESOURCE_URL="${BASE_URL}/${URLMAP_NAME}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VALIDATE_BODY="${TMP_DIR}/validate-body.json"
VALIDATE_OUT="${TMP_DIR}/validate-response.json"
build_validate_body "$URLMAP_JSON" "$VALIDATE_BODY"

echo "==> Validate with Google API"
VALIDATE_STATUS="$(http_status POST "${RESOURCE_URL}/validate" "$VALIDATE_BODY" "$VALIDATE_OUT")"
pretty_print "$VALIDATE_OUT"
if [[ "$VALIDATE_STATUS" -lt 200 || "$VALIDATE_STATUS" -ge 300 ]]; then
  echo "validate API failed with HTTP ${VALIDATE_STATUS}" >&2
  exit 1
fi

if [[ "$MODE" == "validate" ]]; then
  exit 0
fi

GET_OUT="${TMP_DIR}/get-response.json"
GET_STATUS="$(http_status GET "$RESOURCE_URL" "" "$GET_OUT")"

if [[ "$MODE" == "create" && "$GET_STATUS" -eq 200 ]]; then
  echo "URL map ${URLMAP_NAME} already exists; create mode refuses to overwrite" >&2
  exit 1
fi

if [[ "$MODE" == "update" && "$GET_STATUS" -ne 200 ]]; then
  echo "URL map ${URLMAP_NAME} does not exist; update mode cannot continue" >&2
  exit 1
fi

APPLY_OUT="${TMP_DIR}/apply-response.json"
if [[ "$GET_STATUS" -eq 200 ]]; then
  FINGERPRINT="$(python3 - "$GET_OUT" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(data["fingerprint"])
PY
)"
  UPDATE_BODY="${TMP_DIR}/update-body.json"
  build_update_body "$URLMAP_JSON" "$FINGERPRINT" "$UPDATE_BODY"
  echo "==> Update existing URL map ${URLMAP_NAME}"
  APPLY_STATUS="$(http_status PUT "$RESOURCE_URL" "$UPDATE_BODY" "$APPLY_OUT")"
else
  echo "==> Create URL map ${URLMAP_NAME}"
  APPLY_STATUS="$(http_status POST "$BASE_URL" "$URLMAP_JSON" "$APPLY_OUT")"
fi

pretty_print "$APPLY_OUT"
if [[ "$APPLY_STATUS" -lt 200 || "$APPLY_STATUS" -ge 300 ]]; then
  echo "apply request failed with HTTP ${APPLY_STATUS}" >&2
  exit 1
fi
