#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
run-verify.sh: quick verification runner for gcp-infor scripts (Linux)

Usage:
  run-verify.sh [--project PROJECT_ID] [--help]

What it does:
  1) Runs gcp-preflight.sh
  2) Runs gcpfetch-safe (basic + --full)
  3) Optionally runs ../gcp-explore.sh (best-effort)
EOF
}

project_override=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project_override="${2:-}"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"

args=()
if [[ -n "$project_override" ]]; then
  args+=(--project "$project_override")
fi

echo "== 1) Preflight =="
"${here}/gcp-preflight.sh" "${args[@]}"

echo ""
echo "== 2) gcpfetch-safe (basic) =="
"${here}/gcpfetch-safe" "${args[@]}" --no-logo --no-color || true

echo ""
echo "== 3) gcpfetch-safe (--full) =="
"${here}/gcpfetch-safe" "${args[@]}" --no-logo --no-color --full || true

echo ""
echo "== 4) gcp-explore.sh (best-effort) =="
if [[ -x "${root}/gcp-explore.sh" ]]; then
  # This script already handles missing permissions with `|| echo ...`.
  "${root}/gcp-explore.sh" || true
else
  echo "[SKIP] ${root}/gcp-explore.sh not executable"
fi

echo ""
echo "== Done =="

