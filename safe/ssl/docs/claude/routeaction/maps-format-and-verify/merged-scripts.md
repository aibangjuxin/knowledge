# Shell Scripts Collection

Generated on: 2026-03-07 15:48:47
Directory: /Users/lex/git/knowledge/ssl/docs/claude/routeaction/maps-format-and-verify

## `verify-urlmap-json.sh`

```bash
#!/usr/bin/env bash
# ============================================================================
# verify-urlmap-json.sh
#
# 本地验证 GLB URL Map JSON 文件的结构完整性、逻辑冲突和最佳实践。
# 支持 validate（纯本地）、create、update、upsert（调用 GCP API）四种模式。
#
# Usage:
#   verify-urlmap-json.sh <project-id> <region> <urlmap.json> [validate|create|update|upsert]
#
# Examples:
#   ./verify-urlmap-json.sh my-project europe-west2 ./urlmaprouteaction.json validate
#   ./verify-urlmap-json.sh my-project europe-west2 ./urlmaprouteaction.json upsert
#
# validate 模式不需要 GCP 权限，只做本地检查。
# create/update/upsert 模式会先做本地检查，然后调用 GCP API。
# ============================================================================

set -euo pipefail

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---- 统计变量 ----
ERRORS=0
WARNINGS=0

pass()  { echo -e "  ${GREEN}✅ PASS${NC}  $1"; }
fail()  { echo -e "  ${RED}❌ FAIL${NC}  $1"; ERRORS=$((ERRORS + 1)); }
warn()  { echo -e "  ${YELLOW}⚠️  WARN${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
info()  { echo -e "  ${BLUE}ℹ️  INFO${NC}  $1"; }
header(){ echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ---- Usage ----
usage() {
  cat <<'EOF'
Usage:
  verify-urlmap-json.sh <project-id> <region> <urlmap.json> [validate|create|update|upsert]

Modes:
  validate  - Local-only checks (no GCP credentials needed)
  create    - Local checks + create URL Map via GCP API
  update    - Local checks + update existing URL Map via GCP API
  upsert    - Local checks + create or update via GCP API (default)

Examples:
  ./verify-urlmap-json.sh my-project europe-west2 ./urlmaprouteaction.json validate
  ./verify-urlmap-json.sh my-project europe-west2 ./urlmaprouteaction.json upsert

Local Checks Include:
  1. JSON syntax validation
  2. Required top-level fields (name, defaultService, hostRules, pathMatchers)
  3. Host duplication detection
  4. hostRule → pathMatcher reference integrity
  5. routeRules priority uniqueness (per pathMatcher)
  6. weightedBackendServices weight sum validation (must equal 100)
  7. urlRewrite field validation (hostRewrite, pathPrefixRewrite)
  8. pathPrefixRewrite trailing slash warning
  9. tests[] coverage check
 10. Quota estimation for large-scale deployments
EOF
}

# ---- 依赖检查 ----
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: missing required command: $1${NC}" >&2
    exit 1
  fi
}

require_cmd python3

# ---- 参数解析 ----
if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage
  exit 2
fi

PROJECT_ID="$1"
REGION="$2"
URLMAP_JSON="$3"
MODE="${4:-upsert}"

case "$MODE" in
  validate|create|update|upsert) ;;
  *)
    echo -e "${RED}ERROR: invalid mode: $MODE${NC}" >&2
    usage
    exit 2
    ;;
esac

if [[ ! -f "$URLMAP_JSON" ]]; then
  echo -e "${RED}ERROR: file not found: $URLMAP_JSON${NC}" >&2
  exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     GLB URL Map JSON Verification Tool                   ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  File:    ${URLMAP_JSON}"
echo -e "  Project: ${PROJECT_ID}"
echo -e "  Region:  ${REGION}"
echo -e "  Mode:    ${MODE}"

# ============================================================================
# Phase 1: 本地验证 (所有模式都执行)
# ============================================================================

header "Phase 1: Local Validation"

# ---- Check 1: JSON 语法 ----
header "Check 1: JSON Syntax"
if python3 -m json.tool "$URLMAP_JSON" > /dev/null 2>&1; then
  pass "JSON syntax is valid"
else
  fail "JSON syntax error — fix before proceeding"
  echo ""
  python3 -m json.tool "$URLMAP_JSON" 2>&1 || true
  echo -e "\n${RED}Aborting: JSON syntax must be fixed first.${NC}"
  exit 1
fi

# ---- Check 2-10: Python 深度验证 ----
VALIDATION_RESULT=$(python3 - "$URLMAP_JSON" <<'PYEOF'
import json
import sys
from pathlib import Path
from collections import Counter

file_path = sys.argv[1]
data = json.loads(Path(file_path).read_text(encoding="utf-8"))

errors = []
warnings = []
infos = []

# ---- Check 2: Required top-level fields ----
required_fields = ["name", "defaultService", "hostRules", "pathMatchers"]
for field in required_fields:
    if field not in data:
        errors.append(f"CHECK2|Missing required top-level field: '{field}'")
    else:
        infos.append(f"CHECK2|Field '{field}' present")

# If critical fields missing, bail out early
if "hostRules" not in data or "pathMatchers" not in data:
    for e in errors:
        print(f"ERROR|{e}")
    for w in warnings:
        print(f"WARN|{w}")
    for i in infos:
        print(f"INFO|{i}")
    sys.exit(0)

# ---- Check 3: Host duplication ----
all_hosts = []
for hr in data.get("hostRules", []):
    all_hosts.extend(hr.get("hosts", []))

host_counts = Counter(all_hosts)
duplicates = {h: c for h, c in host_counts.items() if c > 1}
if duplicates:
    for h, c in duplicates.items():
        errors.append(f"CHECK3|Duplicate host '{h}' appears {c} times in hostRules")
else:
    infos.append(f"CHECK3|No duplicate hosts found ({len(all_hosts)} hosts total)")

# ---- Check 4: hostRule → pathMatcher reference integrity ----
matcher_names = {pm["name"] for pm in data.get("pathMatchers", []) if "name" in pm}
for i, hr in enumerate(data.get("hostRules", [])):
    pm = hr.get("pathMatcher", "")
    hosts = hr.get("hosts", [])
    if pm not in matcher_names:
        errors.append(f"CHECK4|hostRule[{i}] (hosts={hosts}) references pathMatcher '{pm}' which does not exist. Available: {sorted(matcher_names)}")
    else:
        infos.append(f"CHECK4|hostRule[{i}] -> pathMatcher '{pm}' OK")

# Check for orphan pathMatchers (defined but not referenced)
referenced_matchers = {hr.get("pathMatcher", "") for hr in data.get("hostRules", [])}
orphan_matchers = matcher_names - referenced_matchers
for om in orphan_matchers:
    warnings.append(f"CHECK4|pathMatcher '{om}' is defined but not referenced by any hostRule")

# ---- Check 5: routeRules priority uniqueness ----
for pm in data.get("pathMatchers", []):
    pm_name = pm.get("name", "unnamed")
    rules = pm.get("routeRules", [])
    if not rules:
        continue

    priorities = [r.get("priority") for r in rules]
    # Check for missing priorities
    if None in priorities:
        errors.append(f"CHECK5|pathMatcher '{pm_name}' has routeRule(s) without a priority field")
    
    valid_priorities = [p for p in priorities if p is not None]
    priority_counts = Counter(valid_priorities)
    dups = {p: c for p, c in priority_counts.items() if c > 1}
    if dups:
        for p, c in dups.items():
            errors.append(f"CHECK5|pathMatcher '{pm_name}' has duplicate priority {p} ({c} rules)")
    else:
        infos.append(f"CHECK5|pathMatcher '{pm_name}' priorities are unique: {sorted(valid_priorities)}")

# ---- Check 6: weightedBackendServices weight sum ----
for pm in data.get("pathMatchers", []):
    pm_name = pm.get("name", "unnamed")
    for rule in pm.get("routeRules", []):
        priority = rule.get("priority", "?")
        ra = rule.get("routeAction", {})
        wbs = ra.get("weightedBackendServices", [])
        if not wbs:
            warnings.append(f"CHECK6|pathMatcher '{pm_name}' priority {priority} has no weightedBackendServices (uses defaultService)")
            continue
        total_weight = sum(w.get("weight", 0) for w in wbs)
        if total_weight != 100:
            errors.append(f"CHECK6|pathMatcher '{pm_name}' priority {priority} weightedBackendServices weight sum = {total_weight} (must be 100)")
        else:
            infos.append(f"CHECK6|pathMatcher '{pm_name}' priority {priority} weight sum = 100 OK")

        # Check individual weight range
        for j, w in enumerate(wbs):
            weight_val = w.get("weight", 0)
            if weight_val < 0 or weight_val > 100:
                errors.append(f"CHECK6|pathMatcher '{pm_name}' priority {priority} backend[{j}] weight {weight_val} out of range [0-100]")

# ---- Check 7: urlRewrite field validation ----
for pm in data.get("pathMatchers", []):
    pm_name = pm.get("name", "unnamed")

    # Check defaultRouteAction
    dra = pm.get("defaultRouteAction", {})
    if dra:
        rewrite = dra.get("urlRewrite", {})
        if rewrite:
            if "hostRewrite" not in rewrite and "pathPrefixRewrite" not in rewrite:
                warnings.append(f"CHECK7|pathMatcher '{pm_name}' defaultRouteAction.urlRewrite has no hostRewrite or pathPrefixRewrite")
            else:
                infos.append(f"CHECK7|pathMatcher '{pm_name}' defaultRouteAction.urlRewrite fields present")

    # Check routeRules
    for rule in pm.get("routeRules", []):
        priority = rule.get("priority", "?")
        ra = rule.get("routeAction", {})
        rewrite = ra.get("urlRewrite", {})
        if not rewrite:
            warnings.append(f"CHECK7|pathMatcher '{pm_name}' priority {priority} has no urlRewrite (passthrough mode)")
            continue
        if "hostRewrite" not in rewrite:
            warnings.append(f"CHECK7|pathMatcher '{pm_name}' priority {priority} urlRewrite missing hostRewrite")
        if "pathPrefixRewrite" not in rewrite:
            warnings.append(f"CHECK7|pathMatcher '{pm_name}' priority {priority} urlRewrite missing pathPrefixRewrite")

# ---- Check 8: pathPrefixRewrite trailing slash ----
for pm in data.get("pathMatchers", []):
    pm_name = pm.get("name", "unnamed")

    # Check defaultRouteAction
    dra = pm.get("defaultRouteAction", {})
    if dra:
        rewrite = dra.get("urlRewrite", {})
        prefix = rewrite.get("pathPrefixRewrite", "")
        if prefix.endswith("/") and len(prefix) > 1:
            warnings.append(f"CHECK8|pathMatcher '{pm_name}' defaultRouteAction pathPrefixRewrite '{prefix}' has trailing slash — may cause double-slash in URL")

    for rule in pm.get("routeRules", []):
        priority = rule.get("priority", "?")
        ra = rule.get("routeAction", {})
        rewrite = ra.get("urlRewrite", {})
        prefix = rewrite.get("pathPrefixRewrite", "")
        if prefix.endswith("/") and len(prefix) > 1:
            warnings.append(f"CHECK8|pathMatcher '{pm_name}' priority {priority} pathPrefixRewrite '{prefix}' has trailing slash — may cause double-slash in URL")
        elif prefix:
            infos.append(f"CHECK8|pathMatcher '{pm_name}' priority {priority} pathPrefixRewrite '{prefix}' OK (no trailing slash)")

# ---- Check 9: tests[] coverage ----
tests = data.get("tests", [])
if not tests:
    warnings.append("CHECK9|No 'tests' array found — consider adding test cases for validation")
else:
    tested_hosts = {t.get("host", "") for t in tests}
    defined_hosts = set(all_hosts)
    untested = defined_hosts - tested_hosts
    if untested:
        for h in untested:
            warnings.append(f"CHECK9|Host '{h}' defined in hostRules but has no test case in tests[]")
    else:
        infos.append(f"CHECK9|All {len(defined_hosts)} hosts have test coverage")
    infos.append(f"CHECK9|{len(tests)} test case(s) defined")

# ---- Check 10: Quota estimation ----
num_host_rules = len(data.get("hostRules", []))
num_path_matchers = len(data.get("pathMatchers", []))
total_route_rules = sum(len(pm.get("routeRules", [])) for pm in data.get("pathMatchers", []))

# Estimate JSON size
json_size = len(json.dumps(data))

QUOTA_HOST_RULES = 250
QUOTA_PATH_MATCHERS = 250
QUOTA_ROUTE_RULES_PER_MATCHER = 200
QUOTA_URL_MAP_SIZE = 256 * 1024  # 256 KB

infos.append(f"CHECK10|Host Rules: {num_host_rules}/{QUOTA_HOST_RULES}")
infos.append(f"CHECK10|Path Matchers: {num_path_matchers}/{QUOTA_PATH_MATCHERS}")
infos.append(f"CHECK10|Total Route Rules: {total_route_rules}")
infos.append(f"CHECK10|URL Map JSON size: {json_size} bytes / {QUOTA_URL_MAP_SIZE} bytes ({json_size*100//QUOTA_URL_MAP_SIZE}%)")

if num_host_rules > QUOTA_HOST_RULES * 0.8:
    warnings.append(f"CHECK10|Host Rules usage {num_host_rules}/{QUOTA_HOST_RULES} exceeds 80% — consider using wildcard hosts")
if num_path_matchers > QUOTA_PATH_MATCHERS * 0.8:
    warnings.append(f"CHECK10|Path Matchers usage {num_path_matchers}/{QUOTA_PATH_MATCHERS} exceeds 80%")
if json_size > QUOTA_URL_MAP_SIZE * 0.8:
    warnings.append(f"CHECK10|URL Map JSON size {json_size} bytes exceeds 80% of {QUOTA_URL_MAP_SIZE} bytes limit")

# Check per-matcher route rule count
for pm in data.get("pathMatchers", []):
    pm_name = pm.get("name", "unnamed")
    rule_count = len(pm.get("routeRules", []))
    if rule_count > QUOTA_ROUTE_RULES_PER_MATCHER * 0.8:
        warnings.append(f"CHECK10|pathMatcher '{pm_name}' has {rule_count} routeRules — approaching limit of {QUOTA_ROUTE_RULES_PER_MATCHER}")

# ---- Output ----
for e in errors:
    print(f"ERROR|{e}")
for w in warnings:
    print(f"WARN|{w}")
for i in infos:
    print(f"INFO|{i}")
PYEOF
)

# ---- 解析 Python 输出 ----
current_check=""
while IFS='|' read -r level check_id message; do
  # Extract check number for grouping
  new_check=$(echo "$check_id" | grep -oE 'CHECK[0-9]+' || echo "")
  if [[ -n "$new_check" && "$new_check" != "$current_check" ]]; then
    current_check="$new_check"
    case "$current_check" in
      CHECK2)  header "Check 2: Required Top-Level Fields" ;;
      CHECK3)  header "Check 3: Host Duplication Detection" ;;
      CHECK4)  header "Check 4: HostRule → PathMatcher Reference Integrity" ;;
      CHECK5)  header "Check 5: RouteRules Priority Uniqueness" ;;
      CHECK6)  header "Check 6: Weight Sum Validation" ;;
      CHECK7)  header "Check 7: urlRewrite Field Validation" ;;
      CHECK8)  header "Check 8: PathPrefixRewrite Trailing Slash" ;;
      CHECK9)  header "Check 9: Test Coverage" ;;
      CHECK10) header "Check 10: Quota Estimation" ;;
    esac
  fi

  case "$level" in
    ERROR) fail "$message" ;;
    WARN)  warn "$message" ;;
    INFO)  info "$message" ;;
  esac
done <<< "$VALIDATION_RESULT"

# ---- 本地验证汇总 ----
header "Local Validation Summary"
echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo -e "  ${RED}❌ FAILED${NC}: ${ERRORS} error(s), ${WARNINGS} warning(s)"
  echo ""
  if [[ "$MODE" != "validate" ]]; then
    echo -e "  ${RED}Aborting: fix errors before applying to GCP.${NC}"
  fi
  exit 1
else
  echo -e "  ${GREEN}✅ PASSED${NC}: 0 errors, ${WARNINGS} warning(s)"
fi

# ============================================================================
# Phase 2: GCP API 操作 (仅 create/update/upsert 模式)
# ============================================================================
if [[ "$MODE" == "validate" ]]; then
  echo ""
  echo -e "${GREEN}Local validation complete. No GCP API calls made.${NC}"
  exit 0
fi

header "Phase 2: GCP API Operations (mode=$MODE)"

require_cmd curl

# ---- 获取 Access Token ----
URLMAP_NAME=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$URLMAP_JSON")
ACCESS_TOKEN="${GOOGLE_OAUTH_ACCESS_TOKEN:-}"
if [[ -z "$ACCESS_TOKEN" ]]; then
  require_cmd gcloud
  info "Fetching access token via gcloud..."
  ACCESS_TOKEN="$(gcloud auth print-access-token)"
fi

BASE_URL="https://compute.googleapis.com/compute/v1/projects/${PROJECT_ID}/regions/${REGION}/urlMaps"
RESOURCE_URL="${BASE_URL}/${URLMAP_NAME}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---- Step 1: GCP API Validate ----
header "GCP API: Validate"
VALIDATE_BODY="${TMP_DIR}/validate-body.json"
VALIDATE_OUT="${TMP_DIR}/validate-response.json"
python3 -c "
import json,sys
from pathlib import Path
r = json.loads(Path(sys.argv[1]).read_text())
Path(sys.argv[2]).write_text(json.dumps({'resource': r}))
" "$URLMAP_JSON" "$VALIDATE_BODY"

VALIDATE_STATUS=$(curl -sS -o "$VALIDATE_OUT" -w '%{http_code}' \
  -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  --data @"$VALIDATE_BODY" \
  "${RESOURCE_URL}/validate")

if [[ "$VALIDATE_STATUS" -ge 200 && "$VALIDATE_STATUS" -lt 300 ]]; then
  pass "GCP API validation passed (HTTP $VALIDATE_STATUS)"
  python3 -m json.tool "$VALIDATE_OUT" 2>/dev/null || cat "$VALIDATE_OUT"
else
  fail "GCP API validation failed (HTTP $VALIDATE_STATUS)"
  python3 -m json.tool "$VALIDATE_OUT" 2>/dev/null || cat "$VALIDATE_OUT"
  exit 1
fi

# ---- Step 2: GET 检查是否存在 ----
GET_OUT="${TMP_DIR}/get-response.json"
GET_STATUS=$(curl -sS -o "$GET_OUT" -w '%{http_code}' \
  -X GET \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "$RESOURCE_URL")

EXISTS=false
[[ "$GET_STATUS" -eq 200 ]] && EXISTS=true

info "URL Map '${URLMAP_NAME}' exists: ${EXISTS}"

# ---- Mode 检查 ----
if [[ "$MODE" == "create" && "$EXISTS" == "true" ]]; then
  fail "URL Map '${URLMAP_NAME}' already exists; create mode refuses to overwrite"
  exit 1
fi
if [[ "$MODE" == "update" && "$EXISTS" == "false" ]]; then
  fail "URL Map '${URLMAP_NAME}' does not exist; update mode cannot continue"
  exit 1
fi

# ---- Step 3: Create 或 Update ----
APPLY_OUT="${TMP_DIR}/apply-response.json"

if [[ "$EXISTS" == "true" ]]; then
  FINGERPRINT=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['fingerprint'])" "$GET_OUT")
  UPDATE_BODY="${TMP_DIR}/update-body.json"
  python3 -c "
import json,sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text())
d['fingerprint'] = sys.argv[2]
Path(sys.argv[3]).write_text(json.dumps(d))
" "$URLMAP_JSON" "$FINGERPRINT" "$UPDATE_BODY"

  header "GCP API: Update URL Map '${URLMAP_NAME}'"
  APPLY_STATUS=$(curl -sS -o "$APPLY_OUT" -w '%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data @"$UPDATE_BODY" \
    "$RESOURCE_URL")
else
  header "GCP API: Create URL Map '${URLMAP_NAME}'"
  APPLY_STATUS=$(curl -sS -o "$APPLY_OUT" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data @"$URLMAP_JSON" \
    "$BASE_URL")
fi

if [[ "$APPLY_STATUS" -ge 200 && "$APPLY_STATUS" -lt 300 ]]; then
  pass "Apply succeeded (HTTP $APPLY_STATUS)"
else
  fail "Apply failed (HTTP $APPLY_STATUS)"
fi
python3 -m json.tool "$APPLY_OUT" 2>/dev/null || cat "$APPLY_OUT"

echo ""
echo -e "${CYAN}━━━ Done ━━━${NC}"

```

## `apply-urlmap-json.sh`

```bash
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

```

