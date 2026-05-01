#!/opt/homebrew/bin/bash
set -euo pipefail

show_full=false

usage() {
  cat <<'EOF'
Usage:
  macos_power_status.sh [--full]

Shows current macOS power settings, scheduled sleep/wake events, and active
sleep assertions. Use --full to include recent sleep/wake log entries.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full)
      show_full=true
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

section() {
  printf '\n== %s ==\n' "$1"
}

section "Host"
sw_vers 2>/dev/null || true
printf 'Hardware: '
sysctl -n hw.model 2>/dev/null || echo "unknown"
printf 'Now: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

section "Current effective settings"
pmset -g || true

section "Custom settings"
pmset -g custom || true

section "Scheduled power events"
pmset -g sched || true

section "Sleep assertions summary"
pmset -g assertions | sed -n '1,120p' || true

if [[ "$show_full" == true ]]; then
  section "Recent sleep/wake log"
  pmset -g log | grep -E " Sleep | Wake | DarkWake | Start | ShutdownCause" | tail -40 || true
fi
