#!/opt/homebrew/bin/bash
set -euo pipefail

pid_file="${TMPDIR:-/tmp}/macos-power-keepawake.pid"

usage() {
  cat <<'EOF'
Usage:
  macos_power_keepawake_stop.sh [--pid-file PATH]

Stops the background caffeinate process started by macos_power_keepawake.sh
--background. This only stops the pid recorded in the pid file.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pid-file)
      pid_file="${2:-}"
      [[ -n "$pid_file" ]] || { echo "ERROR: --pid-file cannot be empty" >&2; exit 2; }
      shift 2
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

if [[ ! -f "$pid_file" ]]; then
  echo "No pid file found: $pid_file"
  exit 0
fi

pid="$(tr -d '[:space:]' <"$pid_file")"
if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
  echo "Invalid pid file content: $pid_file" >&2
  exit 1
fi

if kill -0 "$pid" 2>/dev/null; then
  kill "$pid"
  echo "Stopped background caffeinate pid=$pid"
else
  echo "Process already stopped: pid=$pid"
fi

rm -f "$pid_file"
