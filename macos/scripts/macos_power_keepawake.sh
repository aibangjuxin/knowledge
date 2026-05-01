#!/opt/homebrew/bin/bash
set -euo pipefail

duration_seconds=""
until_time=""
wait_pid=""
background=false
display=false
disk=true
system=true
user_active=false
reason="macos-power-keepawake"
log_file="${TMPDIR:-/tmp}/macos-power-keepawake.log"
pid_file="${TMPDIR:-/tmp}/macos-power-keepawake.pid"
dry_run=false
command_args=()

usage() {
  cat <<'EOF'
Usage:
  macos_power_keepawake.sh [duration options] [assertion options] [--background]
  macos_power_keepawake.sh --pid PID [assertion options]
  macos_power_keepawake.sh [duration options] -- command [args...]

Duration options:
  --seconds N             Keep awake for N seconds
  --minutes N             Keep awake for N minutes
  --hours N               Keep awake for N hours
  --duration 30m|2h|900s  Keep awake for a compact duration
  --until HH:MM           Keep awake until the next HH:MM today/tomorrow
  --pid PID               Keep awake until PID exits

Assertion options:
  --display               Also prevent display sleep
  --no-disk               Do not prevent disk idle sleep
  --no-system             Do not request AC system sleep prevention
  --user-active           Briefly declare user active; useful for waking display
  --reason TEXT           Label used in process args and log output

Execution options:
  --background            Run caffeinate in background and write a pid file
  --pid-file PATH         Background pid file path
  --log-file PATH         Background log file path
  --dry-run               Print the caffeinate command only

Examples:
  macos_power_keepawake.sh --hours 2 --background
  macos_power_keepawake.sh --until 23:30 --background --reason hermes
  macos_power_keepawake.sh --pid 12345
  macos_power_keepawake.sh --hours 4 -- ./run-hermes.sh
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

is_positive_int() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

parse_duration() {
  local value="$1"
  if [[ "$value" =~ ^([0-9]+)([smhd])$ ]]; then
    local number="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) echo "$number" ;;
      m) echo $((number * 60)) ;;
      h) echo $((number * 3600)) ;;
      d) echo $((number * 86400)) ;;
    esac
  elif is_positive_int "$value"; then
    echo "$value"
  else
    die "Invalid duration: $value"
  fi
}

seconds_until_time() {
  local hhmm="$1"
  [[ "$hhmm" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "Invalid --until time, expected HH:MM"

  local today target now
  today="$(date '+%Y-%m-%d')"
  now="$(date '+%s')"
  target="$(date -j -f '%Y-%m-%d %H:%M:%S' "${today} ${hhmm}:00" '+%s')"
  if [[ "$target" -le "$now" ]]; then
    target="$(date -j -v+1d -f '%Y-%m-%d %H:%M:%S' "${today} ${hhmm}:00" '+%s')"
  fi
  echo $((target - now))
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds)
      is_positive_int "${2:-}" || die "--seconds requires a positive integer"
      duration_seconds="$2"
      shift 2
      ;;
    --minutes)
      is_positive_int "${2:-}" || die "--minutes requires a positive integer"
      duration_seconds=$((2 * 0 + $2 * 60))
      shift 2
      ;;
    --hours)
      is_positive_int "${2:-}" || die "--hours requires a positive integer"
      duration_seconds=$((2 * 0 + $2 * 3600))
      shift 2
      ;;
    --duration)
      duration_seconds="$(parse_duration "${2:-}")"
      shift 2
      ;;
    --until)
      until_time="${2:-}"
      shift 2
      ;;
    --pid)
      is_positive_int "${2:-}" || die "--pid requires a positive PID"
      wait_pid="$2"
      shift 2
      ;;
    --display)
      display=true
      shift
      ;;
    --no-disk)
      disk=false
      shift
      ;;
    --no-system)
      system=false
      shift
      ;;
    --user-active)
      user_active=true
      shift
      ;;
    --reason)
      reason="${2:-}"
      [[ -n "$reason" ]] || die "--reason cannot be empty"
      shift 2
      ;;
    --background)
      background=true
      shift
      ;;
    --pid-file)
      pid_file="${2:-}"
      [[ -n "$pid_file" ]] || die "--pid-file cannot be empty"
      shift 2
      ;;
    --log-file)
      log_file="${2:-}"
      [[ -n "$log_file" ]] || die "--log-file cannot be empty"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --)
      shift
      command_args=("$@")
      break
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

[[ -x /usr/bin/caffeinate ]] || die "/usr/bin/caffeinate not found"

if [[ -n "$until_time" ]]; then
  [[ -z "$duration_seconds" ]] || die "Use only one duration option"
  duration_seconds="$(seconds_until_time "$until_time")"
fi

if [[ -n "$wait_pid" ]]; then
  kill -0 "$wait_pid" 2>/dev/null || die "PID $wait_pid does not exist"
  [[ -z "$duration_seconds" ]] || die "Use either --pid or a duration, not both"
fi

if [[ "${#command_args[@]}" -gt 0 ]]; then
  [[ "$background" == false ]] || die "--background is not supported when wrapping a command"
  [[ -z "$wait_pid" ]] || die "--pid is not supported when wrapping a command"
fi

flags="-i"
[[ "$system" == true ]] && flags="${flags}s"
[[ "$disk" == true ]] && flags="${flags}m"
[[ "$display" == true ]] && flags="${flags}d"
[[ "$user_active" == true ]] && flags="${flags}u"

cmd=(/usr/bin/caffeinate "$flags")
[[ -n "$duration_seconds" ]] && cmd+=(-t "$duration_seconds")
[[ -n "$wait_pid" ]] && cmd+=(-w "$wait_pid")
if [[ "${#command_args[@]}" -gt 0 ]]; then
  cmd+=("${command_args[@]}")
fi

printf 'Reason: %s\n' "$reason"
printf 'Command:'
printf ' %q' "${cmd[@]}"
printf '\n'

if [[ "$dry_run" == true ]]; then
  exit 0
fi

if [[ "$background" == true ]]; then
  mkdir -p "$(dirname "$pid_file")" "$(dirname "$log_file")"
  {
    printf '[%s] starting: ' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf ' %q' "${cmd[@]}"
    printf '\n'
    exec "${cmd[@]}"
  } >>"$log_file" 2>&1 &
  bg_pid=$!
  printf '%s\n' "$bg_pid" >"$pid_file"
  printf 'Started background caffeinate pid=%s\n' "$bg_pid"
  printf 'PID file: %s\n' "$pid_file"
  printf 'Log file: %s\n' "$log_file"
else
  exec "${cmd[@]}"
fi
