#!/opt/homebrew/bin/bash
set -euo pipefail

command="${1:-}"

usage() {
  cat <<'EOF'
Usage:
  sudo macos_power_schedule.sh repeat --sleep HH:MM --wake HH:MM [--days MTWRFSU] [--dry-run]
  sudo macos_power_schedule.sh cancel-repeat
  sudo macos_power_schedule.sh one-shot-wake --at "YYYY-MM-DD HH:MM" [--dry-run]
  sudo macos_power_schedule.sh sleep-now [--wake-after 8h|480m|28800s] [--dry-run]
  sudo macos_power_schedule.sh cancel-all-onetime
  macos_power_schedule.sh show

Notes:
  - cron cannot wake a sleeping Mac. Use pmset schedule/repeat for wake events.
  - macOS supports only one repeating power-on and one repeating power-off pair.
  - cancel-all-onetime cancels all one-time power events created by pmset.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "This action modifies power schedules. Run with sudo."
  fi
}

normalize_hhmmss() {
  local value="$1"
  if [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "${value}:00"
  elif [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$ ]]; then
    echo "$value"
  else
    die "Invalid time: $value, expected HH:MM or HH:MM:SS"
  fi
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
  elif [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -gt 0 ]]; then
    echo "$value"
  else
    die "Invalid duration: $value"
  fi
}

pmset_datetime_from_iso() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}(:[0-9]{2})?$ ]] || \
    die "Invalid date, expected 'YYYY-MM-DD HH:MM'"

  if [[ "$value" =~ :[0-9]{2}$ && "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    date -j -f '%Y-%m-%d %H:%M:%S' "$value" '+%m/%d/%y %H:%M:%S'
  else
    date -j -f '%Y-%m-%d %H:%M:%S' "${value}:00" '+%m/%d/%y %H:%M:%S'
  fi
}

pmset_datetime_after_seconds() {
  local seconds="$1"
  date -j -v+"${seconds}"S '+%m/%d/%y %H:%M:%S'
}

[[ -n "$command" ]] || { usage; exit 2; }
shift || true

case "$command" in
  show)
    pmset -g sched
    ;;
  repeat)
    days="MTWRFSU"
    sleep_time=""
    wake_time=""
    dry_run=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --days)
          [[ "${2:-}" =~ ^[MTWRFSU]+$ ]] || die "--days must be a subset of MTWRFSU"
          days="$2"
          shift 2
          ;;
        --sleep)
          sleep_time="$(normalize_hhmmss "${2:-}")"
          shift 2
          ;;
        --wake)
          wake_time="$(normalize_hhmmss "${2:-}")"
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
    [[ -n "$sleep_time" ]] || die "--sleep is required"
    [[ -n "$wake_time" ]] || die "--wake is required"
    if [[ "$dry_run" == true ]]; then
      printf 'Would run: pmset repeat sleep %s %s wakeorpoweron %s %s\n' "$days" "$sleep_time" "$days" "$wake_time"
    else
      need_root
      pmset repeat sleep "$days" "$sleep_time" wakeorpoweron "$days" "$wake_time"
      pmset -g sched
    fi
    ;;
  cancel-repeat)
    need_root
    pmset repeat cancel
    pmset -g sched
    ;;
  one-shot-wake)
    at=""
    dry_run=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --at)
          at="$(pmset_datetime_from_iso "${2:-}")"
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
    [[ -n "$at" ]] || die "--at is required"
    if [[ "$dry_run" == true ]]; then
      printf 'Would run: pmset schedule wakeorpoweron %q macos_power_schedule\n' "$at"
    else
      need_root
      pmset schedule wakeorpoweron "$at" "macos_power_schedule"
      pmset -g sched
    fi
    ;;
  sleep-now)
    wake_after=""
    dry_run=false
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --wake-after)
          wake_after="$(parse_duration "${2:-}")"
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
    if [[ -n "$wake_after" ]]; then
      wake_at="$(pmset_datetime_after_seconds "$wake_after")"
      if [[ "$dry_run" == true ]]; then
        printf 'Would run: pmset schedule wakeorpoweron %q macos_power_sleep_now\n' "$wake_at"
      else
        need_root
        pmset schedule wakeorpoweron "$wake_at" "macos_power_sleep_now"
        printf 'Scheduled wakeorpoweron at %s\n' "$wake_at"
      fi
    fi
    if [[ "$dry_run" == true ]]; then
      printf 'Would run: pmset sleepnow\n'
    else
      need_root
      pmset sleepnow
    fi
    ;;
  cancel-all-onetime)
    need_root
    pmset schedule cancelall
    pmset -g sched
    ;;
  -h|--help)
    usage
    ;;
  *)
    die "Unknown command: $command"
    ;;
esac
