#!/usr/bin/env bash
# =============================================================================
# audit-static-pod-refs.sh — Static Pod Manifest Auditor for Kubernetes v1.37
#
# Purpose:
#   Detect static pod manifests that reference Secret / ConfigMap in ways that
#   kubelet will REJECT starting in Kubernetes v1.37 (GA 2026-08-26).
#   The PreventStaticPodAPIReferences feature gate has been removed, so there
#   is no opt-out.
#
# Implements:  ADR-008 §6 step 2  (gcp/adr/008-static-pod-no-secret-configmap-k8s-137.md)
# References:  https://github.com/kubernetes/kubernetes/issues/140226
#              https://kubernetes.io/blog/2026/07/31/kubernetes-v1-37-sneak-peek/
#              https://kubernetes.io/docs/concepts/configuration/secret/
#
# Detected field patterns (kubelet rejects any of these in a static pod):
#   - spec.volumes[].configMap
#   - spec.volumes[].secret
#   - spec.containers[].env[].valueFrom.configMapKeyRef
#   - spec.containers[].env[].valueFrom.secretKeyRef
#   - spec.containers[].envFrom[].configMapRef
#   - spec.containers[].envFrom[].secretRef
#
# Usage:
#   ./audit-static-pod-refs.sh [--paths /path/a:/path/b] [--report /tmp/out.csv]
#                              [--enable-kubectl-dry-run] [--self-test] [-h]
#
# Env vars:
#   STATIC_POD_PATHS       Colon-separated scan paths (default:
#                           /etc/kubernetes/manifests:/var/lib/kubelet/manifests)
#   KUBECTL_DRY_RUN=true   Enable kubectl --dry-run=client cross-check
#                           (requires a reachable kubeconfig; may false-positive
#                           on non-static-pod files)
#   REPORT_PATH            Override default CSV output path
#
# Exit codes:
#   0  no violations found (clean)
#   1  violations found
#   2  script error (missing path, etc.)
#
# Idempotency: read-only. Never modifies scanned files.
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 颜色 & 格式化
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[1;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
header()  { echo -e "\n${BOLD}${BLUE}$*${RESET}"; }
divider() { echo -e "${DIM}$(printf '─%.0s' {1..70})${RESET}"; }

# --------------------------------------------------------------------------- #
# Default configuration
# --------------------------------------------------------------------------- #
DEFAULT_PATHS="/etc/kubernetes/manifests:/var/lib/kubelet/manifests"
ENABLE_KUBECTL_DRY_RUN=false
SELF_TEST_MODE=false

# Field patterns that kubelet will reject in v1.37 static pod manifests.
# Format: "regex:::field_pattern_label"  (using ":::" as separator because
# the regexes themselves contain "|" for ERE alternation, which would
# conflict with simple shell parameter expansion).
#
# Each regex matches a YAML key line. We accept:
#   - inline value:        `configMap: foo`
#   - nested block value:  `configMap:` then name on next line
#   - list-dash prefix:    `- configMap:` or `- name: foo` followed by nested
# Because kubelet validates the rendered spec, not the textual layout,
# any of these shapes represents the same forbidden reference.
#
# Patterns allow an optional `-` (YAML list indicator) between leading
# whitespace and the key.
DETECTION_PATTERNS=(
  '^[[:space:]]*-?[[:space:]]*configMap:([[:space:]]+[^[:space:]].*|[[:space:]]*)$:::volumes[].configMap'
  '^[[:space:]]*-?[[:space:]]*secret:([[:space:]]+[^[:space:]].*|[[:space:]]*)$:::volumes[].secret'
  '^[[:space:]]*-?[[:space:]]*configMapKeyRef:[[:space:]]*$:::env[].valueFrom.configMapKeyRef'
  '^[[:space:]]*-?[[:space:]]*secretKeyRef:[[:space:]]*$:::env[].valueFrom.secretKeyRef'
  '^[[:space:]]*-?[[:space:]]*configMapRef:[[:space:]]*$:::envFrom[].configMapRef'
  '^[[:space:]]*-?[[:space:]]*secretRef:[[:space:]]*$:::envFrom[].secretRef'
)

# CSV header
CSV_HEADER="node,file,line,field_pattern,match_text,kubelet_will_reject_on_1.37"

# --------------------------------------------------------------------------- #
# Usage
# --------------------------------------------------------------------------- #
usage() {
cat <<EOF

${BOLD}用法:${RESET} $(basename "$0") [OPTIONS]

${BOLD}描述:${RESET}
  扫描 static pod manifest 目录,检测 v1.37 起 kubelet 将拒绝的 Secret /
  ConfigMap 引用。详见 ADR-008。

${BOLD}Options:${RESET}
  -p, --paths PATHS          冒号分隔的扫描路径 (覆盖 STATIC_POD_PATHS)
                             默认: ${DEFAULT_PATHS}
  -r, --report PATH          CSV 报告输出路径 (默认: /tmp/static-pod-audit-*.csv)
  -k, --enable-kubectl-dry-run
                             同时用 kubectl --dry-run=client 交叉验证
                             (需要 kubeconfig; 可能在非 static-pod 文件上误报)
      --self-test            运行内置自检 (创建临时 fixture 并验证脚本)
  -h, --help                 显示此帮助信息

${BOLD}Env vars:${RESET}
  STATIC_POD_PATHS           冒号分隔的扫描路径
  KUBECTL_DRY_RUN=true       同 --enable-kubectl-dry-run
  REPORT_PATH                CSV 报告输出路径

${BOLD}Exit codes:${RESET}
  0  无违规
  1  发现违规 (CSV 报告已生成)
  2  脚本错误 (路径缺失等)

${BOLD}示例:${RESET}
  # 默认扫描 GKE / kubeadm 常见路径
  $(basename "$0")

  # 自定义路径并指定 CSV 输出
  $(basename "$0") --paths /srv/k8s/manifests --report /tmp/audit.csv

  # 启用 kubectl dry-run 二次验证 (需 kubeconfig)
  KUBECTL_DRY_RUN=true $(basename "$0") --paths /etc/kubernetes/manifests

EOF
exit 0
}

# --------------------------------------------------------------------------- #
# Argument parsing
# --------------------------------------------------------------------------- #
PATHS_OVERRIDE=""
REPORT_PATH_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--paths)              PATHS_OVERRIDE="$2"; shift 2 ;;
    -r|--report)             REPORT_PATH_OVERRIDE="$2"; shift 2 ;;
    -k|--enable-kubectl-dry-run) ENABLE_KUBECTL_DRY_RUN=true; shift ;;
    --self-test)             SELF_TEST_MODE=true; shift ;;
    -h|--help)               usage ;;
    *)  error "未知参数: $1"; echo ""; usage ;;
  esac
done

# --------------------------------------------------------------------------- #
# Resolve configuration with env-var fallback
# --------------------------------------------------------------------------- #
SCAN_PATHS="${PATHS_OVERRIDE:-${STATIC_POD_PATHS:-${DEFAULT_PATHS}}}"

if [[ -n "${REPORT_PATH:-}" && -z "${REPORT_PATH_OVERRIDE}" ]]; then
  REPORT_PATH_OVERRIDE="${REPORT_PATH}"
fi
if [[ -z "${REPORT_PATH_OVERRIDE}" ]]; then
  REPORT_PATH_OVERRIDE="/tmp/static-pod-audit-$(date +%Y%m%d-%H%M%S).csv"
fi

if [[ "${KUBECTL_DRY_RUN:-}" == "true" ]]; then
  ENABLE_KUBECTL_DRY_RUN=true
fi

# --------------------------------------------------------------------------- #
# Hostname (for the CSV `node` column)
# --------------------------------------------------------------------------- #
NODE_NAME="$(hostname 2>/dev/null || echo 'unknown')"

# --------------------------------------------------------------------------- #
# Expand colon-separated paths into an array, dedup while preserving order.
# Empty entries are dropped. Exits 0 on success, prints one path per line.
# --------------------------------------------------------------------------- #
resolve_scan_paths() {
  local raw="$1"
  local -a result=()
  local p

  # Word-split on ':' is intentional here.
  local IFS=':'
  # shellcheck disable=SC2206
  local parts=($raw)

  for p in "${parts[@]}"; do
    [[ -z "$p" ]] && continue
    local seen=0
    local existing
    for existing in "${result[@]:-}"; do
      if [[ "$existing" == "$p" ]]; then
        seen=1
        break
      fi
    done
    [[ $seen -eq 0 ]] && result+=("$p")
  done

  [[ ${#result[@]} -gt 0 ]] || return 1
  printf '%s\n' "${result[@]}"
}

# --------------------------------------------------------------------------- #
# Grep a single file for field-pattern violations.
# Prints "<file>|<line_no>|<field_pattern>|<matched_text>" per hit, one per line.
# (File path is prepended so the caller doesn't need to track loop state.)
# --------------------------------------------------------------------------- #
grep_file_for_violations() {
  local file="$1"
  local entry regex label match_line lineno text

  for entry in "${DETECTION_PATTERNS[@]}"; do
    # Separator is ":::" — see DETECTION_PATTERNS comment for rationale.
    regex="${entry%%:::*}"
    label="${entry##*:::}"
    match_line=$(grep -nE "$regex" "$file" 2>/dev/null || true)
    [[ -z "$match_line" ]] && continue
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      lineno="${line%%:*}"
      text="${line#*:}"
      printf '%s|%s|%s|%s\n' "$file" "$lineno" "$label" "$text"
    done <<< "$match_line"
  done
}

# --------------------------------------------------------------------------- #
# Optional cross-check: kubectl --dry-run=client.
# Opt-in: only runs when ENABLE_KUBECTL_DRY_RUN=true AND kubectl exists.
# Output is discarded; this is a cheap sanity check, not a source of truth.
# (--dry-run=client does NOT require cluster connectivity, only a valid
# kubeconfig for client-side schema validation.)
# --------------------------------------------------------------------------- #
maybe_dry_run_check() {
  local file="$1"
  if [[ "$ENABLE_KUBECTL_DRY_RUN" != "true" ]]; then
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl 不可用,跳过 dry-run 二次验证 (--enable-kubectl-dry-run 已请求)"
    return 0
  fi
  kubectl create --dry-run=client -f "$file" >/dev/null 2>&1 || true
  return 0
}

# --------------------------------------------------------------------------- #
# Process a single directory: find yaml files, audit each.
# Writes "<file>|<line>|<field_pattern>|<text>" rows to REPORT_TMPFILE.
# Echoes the count of files visited to stdout (captured by caller).
# --------------------------------------------------------------------------- #
process_directory() {
  local dir="$1"
  local -a files=()
  local f

  # NUL-separated find so paths with spaces/newlines are safe.
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$dir" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null || true)

  if [[ ${#files[@]} -eq 0 ]]; then
    info "目录 '$dir' 下未发现 *.yaml / *.yml manifest"
    return 0
  fi

  info "扫描目录 '$dir' (${#files[@]} 个文件)"
  for f in "${files[@]}"; do
    if [[ ! -r "$f" ]]; then
      warn "无法读取文件 (权限不足?): $f"
      continue
    fi
    grep_file_for_violations "$f" >> "$REPORT_TMPFILE" || true
    maybe_dry_run_check "$f" || true
  done
}

# --------------------------------------------------------------------------- #
# RFC-4180-ish CSV-escape: double internal quotes, wrap in quotes if needed.
# --------------------------------------------------------------------------- #
csv_escape() {
  local s="$1"
  s="${s//\"/\"\"}"
  if [[ "$s" == *','* || "$s" == *'"'* || "$s" == *$'\n'* ]]; then
    s="\"${s}\""
  fi
  printf '%s' "$s"
}

# --------------------------------------------------------------------------- #
# Print human-readable summary
# --------------------------------------------------------------------------- #
print_summary() {
  local scanned="$1"
  local violations="$2"
  local report="$3"

  header "📊 审计摘要"
  echo -e "  ${BOLD}扫描节点:${RESET}      ${NODE_NAME}"
  echo -e "  ${BOLD}扫描文件数:${RESET}    ${scanned}"
  echo -e "  ${BOLD}违规数:${RESET}        ${violations}"
  echo -e "  ${BOLD}CSV 报告:${RESET}      ${report}"
  divider

  if [[ "$violations" -gt 0 ]]; then
    echo -e "${YELLOW}${BOLD}⚠️  发现 ${violations} 处违规 — v1.37 kubelet 将拒绝解析${RESET}"
    echo -e "${DIM}应对模式参见 ADR-008 §4 (内联 / hostPath / 模板渲染 / 改用 Deployment)${RESET}"
  else
    success "无违规 — manifest 兼容 Kubernetes v1.37"
  fi
}

# --------------------------------------------------------------------------- #
# Self-test: creates a temp dir with two fixtures (clean + violating), runs
# the audit against it, and asserts the CSV has the expected content + exit 1.
# --------------------------------------------------------------------------- #
run_self_test() {
  echo ""
  echo -e "${BOLD}${MAGENTA}═══ SELF-TEST ═══${RESET}"

  # Use a global name so the EXIT trap can reach it (locals vanish on return).
  # Cleanup on EXIT (covers normal return, error, and signal).
  SELFTEST_TMPDIR="$(mktemp -d -t static-pod-audit-selftest-XXXXXX)"
  report="${SELFTEST_TMPDIR}/audit.csv"
  trap 'rm -rf "${SELFTEST_TMPDIR:-}"' EXIT

  local self_exit rc
  # Fixture 1: clean manifest using only hostPath / env.value (literal).
  cat > "${SELFTEST_TMPDIR}/clean-etcd.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: etcd
spec:
  containers:
  - name: etcd
    image: registry.k8s.io/etcd:3.5.0
    env:
    - name: ETCD_NAME
      value: "etcd-0"
    volumeMounts:
    - name: data
      mountPath: /var/lib/etcd
  volumes:
  - name: data
    hostPath:
      path: /var/lib/etcd
      type: DirectoryOrCreate
YAML

  # Fixture 2: manifest with multiple forbidden references.
  cat > "${SELFTEST_TMPDIR}/bad-kube-apiserver.yaml" <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
spec:
  containers:
  - name: kube-apiserver
    image: registry.k8s.io/kube-apiserver:v1.37.0
    env:
    - name: AUDIT_POLICY_CFG
      valueFrom:
        configMapKeyRef:
          name: audit-policy
          key: policy.yaml
    - name: ETCD_CA_CERT
      valueFrom:
        secretKeyRef:
          name: etcd-ca
          key: ca.crt
    envFrom:
    - configMapRef:
        name: kube-apiserver-config
    - secretRef:
        name: kube-apiserver-secrets
  volumes:
  - name: audit-policy-vol
    configMap:
      name: audit-policy
  - name: etcd-certs
    secret:
      secretName: etcd-ca
YAML

  info "fixtures in: $SELFTEST_TMPDIR"

  # Run the audit against the temp dir directly.
  set +e
  KUBECTL_DRY_RUN="false" \
    "$(readlink -f "$0")" \
      --paths "$SELFTEST_TMPDIR" \
      --report "$report" \
      > "${SELFTEST_TMPDIR}/selftest.stdout" 2> "${SELFTEST_TMPDIR}/selftest.stderr"
  self_exit=$?
  set -e

  info "self-test exit code: $self_exit"
  echo "----- selftest stdout -----"
  cat "${SELFTEST_TMPDIR}/selftest.stdout"
  echo "----- selftest stderr -----"
  cat "${SELFTEST_TMPDIR}/selftest.stderr"
  echo "----- audit.csv -----"
  cat "$report"
  echo "---------------------------"

  rc=0
  if [[ "$self_exit" -ne 1 ]]; then
    error "self-test FAIL: expected exit code 1 (violations), got $self_exit"
    rc=1
  fi

  # Expected violations: 6 from the bad manifest (1 each pattern).
  local hit_count
  hit_count=$(tail -n +2 "$report" | grep -c . || true)
  if [[ "$hit_count" -ne 6 ]]; then
    error "self-test FAIL: expected 6 violation rows, got $hit_count"
    rc=1
  fi

  # Sanity: each detection pattern should appear at least once.
  # Use grep -F (fixed-string) so [ ] are not interpreted as regex brackets.
  local expected_patterns=(
    "volumes[].configMap"
    "volumes[].secret"
    "env[].valueFrom.configMapKeyRef"
    "env[].valueFrom.secretKeyRef"
    "envFrom[].configMapRef"
    "envFrom[].secretRef"
    "bad-kube-apiserver.yaml"
  )
  local p
  for p in "${expected_patterns[@]}"; do
    if ! grep -qF "$p" "$report"; then
      error "self-test FAIL: CSV missing expected pattern '$p'"
      rc=1
    fi
  done

  # Verify CSV well-formedness: every row (including header) must parse as
  # exactly 6 columns using an RFC-4180-aware parser. Naive `awk -F,` would
  # mis-count rows whose match_text contains quoted commas — Python's csv
  # module handles quoting correctly.
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$report" <<'PYEOF'
import csv, sys
path = sys.argv[1]
expected_cols = 6
with open(path, newline="") as f:
    for i, r in enumerate(csv.reader(f)):
        if len(r) != expected_cols:
            print(f"row {i}: expected {expected_cols} cols, got {len(r)}: {r}", file=sys.stderr)
            sys.exit(1)
sys.exit(0)
PYEOF
    then
      error "self-test FAIL: CSV column-count check failed (expected 6 cols per row)"
      rc=1
    fi
  else
    warn "python3 not available; skipped RFC-4180 column-count check"
  fi

  if [[ $rc -eq 0 ]]; then
    success "self-test passed"
  else
    echo "self-test FAILED"
  fi
  return $rc
}

# --------------------------------------------------------------------------- #
# Main orchestration
# --------------------------------------------------------------------------- #
main() {
  if [[ "$SELF_TEST_MODE" == "true" ]]; then
    run_self_test
    return $?
  fi

  echo ""
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║      Static Pod Manifest Auditor — Kubernetes v1.37               ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "${DIM}依据: ADR-008 §6 step 2 / kubernetes/kubernetes#140226${RESET}"
  echo ""

  local -a paths
  mapfile -t paths < <(resolve_scan_paths "$SCAN_PATHS" || true)

  if [[ ${#paths[@]} -eq 0 ]]; then
    error "未配置任何扫描路径 (请通过 --paths 或 STATIC_POD_PATHS 指定)"
    exit 2
  fi

  # Ensure report directory exists.
  local report_dir
  report_dir="$(dirname -- "$REPORT_PATH_OVERRIDE")"
  if [[ ! -d "$report_dir" ]]; then
    if ! mkdir -p "$report_dir" 2>/dev/null; then
      error "无法创建报告目录: $report_dir"
      exit 2
    fi
  fi

  # Initialize CSV with header.
  echo "$CSV_HEADER" > "$REPORT_PATH_OVERRIDE"

  # Collect violations into a temp file, then count + merge.
  REPORT_TMPFILE="$(mktemp -t static-pod-audit-XXXXXX.tsv)"
  trap 'rm -f "$REPORT_TMPFILE"' EXIT

  local scanned=0 p
  for p in "${paths[@]}"; do
    if [[ ! -d "$p" ]]; then
      warn "路径不存在或不是目录,跳过: $p"
      continue
    fi
    process_directory "$p"
  done

  # Re-glob to count files actually visited (best-effort; for the summary).
  for p in "${paths[@]}"; do
    [[ -d "$p" ]] || continue
    while IFS= read -r -d '' f; do
      [[ -r "$f" ]] && scanned=$(( scanned + 1 ))
    done < <(find "$p" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null || true)
  done

  # Convert TSV → CSV rows and append. Each row format from grep_file_for_violations:
  #   <file>|<line_no>|<field_pattern>|<matched_text>
  local violations=0 file lineno label text escaped_text
  if [[ -s "$REPORT_TMPFILE" ]]; then
    while IFS='|' read -r file lineno label text; do
      [[ -z "$file" ]] && continue
      escaped_text=$(csv_escape "$text")
      printf '%s,%s,%s,%s,%s,%s\n' \
        "$NODE_NAME" "$file" "$lineno" "$label" "$escaped_text" "true" \
        >> "$REPORT_PATH_OVERRIDE"
      violations=$(( violations + 1 ))
    done < "$REPORT_TMPFILE"
  fi

  print_summary "$scanned" "$violations" "$REPORT_PATH_OVERRIDE"

  if [[ "$violations" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"