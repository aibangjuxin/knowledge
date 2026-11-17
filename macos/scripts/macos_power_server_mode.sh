#!/opt/homebrew/bin/bash
set -euo pipefail

action="${1:-}"
display_sleep=10
backup_dir="${HOME}/.macos_power"
dry_run=false

usage() {
  cat <<'EOF'
Usage:
  sudo macos_power_server_mode.sh enable [--display-sleep MINUTES] [--dry-run]
  sudo macos_power_server_mode.sh show

Enables a Mac mini friendly server mode:
  - system sleep disabled
  - disk sleep disabled
  - display sleep configurable
  - wake for network access enabled
  - TCP keepalive enabled when supported
  - terminal sessions keep the machine awake
  - auto restart after power loss enabled when supported

Use macos_power_restore_defaults.sh to rollback to macOS defaults.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "This action modifies pmset settings. Run with sudo."
  fi
}

supported_setting() {
  local key="$1"
  pmset -g custom 2>/dev/null | awk '{print $1}' | grep -qx "$key"
}

apply_pmset() {
  local key="$1"
  local value="$2"
  if supported_setting "$key"; then
    if [[ "$dry_run" == true ]]; then
      printf 'Would run: pmset -a %s %s\n' "$key" "$value"
    else
      pmset -a "$key" "$value"
    fi
  else
    printf 'Skip unsupported setting: %s\n' "$key"
  fi
}

[[ -n "$action" ]] || { usage; exit 2; }
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --display-sleep)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--display-sleep requires minutes"
      display_sleep="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

case "$action" in
  show)
    pmset -g custom
    ;;
  enable)
    [[ "$dry_run" == true ]] || need_root
    backup_file="${backup_dir}/pmset-custom-$(date '+%Y%m%d-%H%M%S').txt"
    if [[ "$dry_run" == true ]]; then
      printf 'Would save current pmset custom settings to: %s\n' "$backup_file"
    else
      mkdir -p "$backup_dir"
      pmset -g custom >"$backup_file" || true
      printf 'Saved current pmset custom settings to: %s\n' "$backup_file"
    fi

    apply_pmset sleep 0
    apply_pmset disksleep 0
    apply_pmset displaysleep "$display_sleep"
    apply_pmset womp 1
    apply_pmset tcpkeepalive 1
    apply_pmset powernap 1
    apply_pmset ttyskeepawake 1
    apply_pmset autorestart 1
    apply_pmset standby 0
    apply_pmset lowpowermode 0

    if [[ "$dry_run" == false ]]; then
      printf '\nCurrent effective settings:\n'
      pmset -g
    fi
    ;;
  -h|--help)
    usage
    ;;
  *)
    die "Unknown action: $action"
    ;;
esac
