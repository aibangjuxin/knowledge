#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
gcp-preflight.sh: verify Linux host prerequisites for gcp-infor scripts

Usage:
  gcp-preflight.sh [--project PROJECT_ID] [--strict] [--help]

Options:
  --project PROJECT_ID  Use this project for checks (does not mutate gcloud config).
  --strict              Fail if optional tools are missing (kubectl/gsutil).
  --help                Show this help.
EOF
}

project_override=""
strict=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project_override="${2:-}"; shift ;;
    --strict) strict=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

need_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "[ERROR] Missing command: $name" >&2
    return 1
  fi
  echo "[OK] $name"
  return 0
}

maybe_cmd() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    echo "[OK] $name"
    return 0
  fi
  if $strict; then
    echo "[ERROR] Missing optional command (strict): $name" >&2
    return 1
  fi
  echo "[WARN] Missing optional command: $name"
  return 0
}

gcloud_cmd() {
  if [[ -n "$project_override" ]]; then
    CLOUDSDK_CORE_PROJECT="$project_override" gcloud "$@"
  else
    gcloud "$@"
  fi
}

echo "== Preflight =="
need_cmd gcloud
maybe_cmd kubectl
maybe_cmd gsutil

echo ""
echo "== Auth =="
active_acct="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1 || true)"
if [[ -z "$active_acct" ]]; then
  echo "[ERROR] No active gcloud account. Run one of:" >&2
  echo "  - gcloud auth login" >&2
  echo "  - gcloud auth activate-service-account --key-file KEY.json" >&2
  exit 1
fi
echo "[OK] Active account: $active_acct"

echo ""
echo "== Project =="
project="$(gcloud_cmd config get-value project 2>/dev/null || true)"
project="${project//[[:space:]]/}"
if [[ -z "$project" ]]; then
  echo "[ERROR] No active project. Fix with one of:" >&2
  echo "  - gcloud config set project PROJECT_ID" >&2
  echo "  - ./assistant/gcp-preflight.sh --project PROJECT_ID" >&2
  exit 1
fi
echo "[OK] Project: $project"

echo ""
echo "== Access Smoke =="
if ! gcloud_cmd projects describe "$project" --format='value(projectNumber)' >/dev/null 2>&1; then
  echo "[WARN] Cannot describe project. Likely missing resourcemanager.projects.get permission." >&2
else
  echo "[OK] projects.describe"
fi

# GKE auth plugin is required in many modern setups.
if command -v kubectl >/dev/null 2>&1; then
  if gcloud_cmd components list 2>/dev/null | grep -q 'gke-gcloud-auth-plugin'; then
    echo "[OK] gke-gcloud-auth-plugin (listed in gcloud components)"
  else
    echo "[WARN] gke-gcloud-auth-plugin not detected. If kubectl auth fails, install it:" >&2
    echo "  - gcloud components install gke-gcloud-auth-plugin" >&2
  fi
fi

echo ""
echo "== Done =="
echo "If you see WARN lines, scripts may still run but will show N/A/0 for some fields."

