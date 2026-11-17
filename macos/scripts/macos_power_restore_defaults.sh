#!/opt/homebrew/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  sudo macos_power_restore_defaults.sh [--keep-schedules]

Restores macOS power management defaults. By default it also cancels repeating
and one-time pmset schedules.
EOF
}

keep_schedules=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-schedules)
      keep_schedules=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This action modifies pmset settings. Run with sudo." >&2
  exit 1
fi

if [[ "$keep_schedules" == false ]]; then
  pmset repeat cancel || true
  pmset schedule cancelall || true
fi

pmset restoredefaults

printf '\nCurrent effective settings:\n'
pmset -g

printf '\nScheduled power events:\n'
pmset -g sched || true
