#!/usr/bin/env bash
# export-vscode-plug.sh
#
# Export the list of installed VS Code / Cursor extensions in formats you can
# paste elsewhere. Tested on macOS (Bash 3.2 / Bash 5.x) and Linux (Bash 4+).
#
# Usage:
#   ./export-vscode-plug.sh                  # names only (one per line)
#   ./export-vscode-plug.sh --with-versions  # name@version, one per line
#   ./export-vscode-plug.sh --csv            # comma-separated for shell loops
#   ./export-vscode-plug.sh --table          # markdown table (name, publisher, version)
#   ./export-vscode-plug.sh --install-cmd    # `code --install-extension ...` commands
#   ./export-vscode-plug.sh --json           # raw JSON from extensions/extensions.json
#   ./export-vscode-plug.sh --out FILE       # write to FILE instead of stdout
#
# Notes:
#   - The `code` CLI on macOS may point at Cursor.app (a VS Code fork). Both
#     expose the same `--list-extensions` surface, so this script works for
#     either. The `--json` variant reads ~/.vscode/extensions/extensions.json
#     directly to bypass any CLI quirks.
#   - Run with --help for usage.
#
# Exit codes:
#   0 = success
#   1 = neither `code` nor an extensions.json found
#   2 = bad CLI args

set -euo pipefail

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for --json / --table / --install-cmd. Install with:" >&2
    echo "  brew install jq          # macOS" >&2
    echo "  apt-get install -y jq    # Debian/Ubuntu" >&2
    echo "  yum install -y jq        # RHEL/Fedora" >&2
    exit 1
  fi
}

MODE="names"
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --with-versions) MODE="versions" ;;
    --csv) MODE="csv" ;;
    --table) MODE="table"; require_jq ;;
    --json) MODE="json" ;;
    --install-cmd) MODE="install-cmd"; require_jq ;;
    --out) OUT="${2:-}"; shift ;;
    *) echo "unknown arg: $1" >&2; usage 2 ;;
  esac
  shift
done

# Where does `code` resolve to?
CODE_BIN="$(command -v code 2>/dev/null || true)"
EXT_JSON=""
[[ -f "$HOME/.vscode/extensions/extensions.json" ]] && EXT_JSON="$HOME/.vscode/extensions/extensions.json"
[[ -z "$EXT_JSON" && -f "$HOME/.cursor/extensions/extensions.json" ]] && EXT_JSON="$HOME/.cursor/extensions/extensions.json"

run() {
  if [[ -n "$OUT" ]]; then
    "$@" > "$OUT"
    echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
  else
    "$@"
  fi
}

case "$MODE" in
  names)
    if [[ -n "$CODE_BIN" ]]; then
      run "$CODE_BIN" --list-extensions
    elif [[ -n "$EXT_JSON" ]]; then
      # shellcheck disable=SC2016
      jq -r '.[].identifier.id' "$EXT_JSON"
    else
      echo "no `code` CLI and no extensions.json found" >&2; exit 1
    fi
    ;;
  versions)
    if [[ -n "$CODE_BIN" ]]; then
      run "$CODE_BIN" --list-extensions --show-versions
    elif [[ -n "$EXT_JSON" ]]; then
      jq -r '.[] | "\(.identifier.id)@\(.version)"' "$EXT_JSON"
    else
      echo "no `code` CLI and no extensions.json found" >&2; exit 1
    fi
    ;;
  csv)
    if [[ -n "$CODE_BIN" ]]; then
      CMD="$CODE_BIN --list-extensions"
    else
      CMD="jq -r '.[].identifier.id' $EXT_JSON"
    fi
    if [[ -n "$OUT" ]]; then
      bash -c "$CMD" | paste -sd ',' - > "$OUT"
      echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
    else
      bash -c "$CMD" | paste -sd ',' -
    fi
    ;;
  json)
    require_jq
    if [[ -n "$EXT_JSON" ]]; then
      run jq '.' "$EXT_JSON"
    elif [[ -n "$CODE_BIN" ]]; then
      # `code` doesn't print JSON; offer the file path so the user knows where to look
      echo "no extensions.json found; \`code --list-extensions\` doesn't emit JSON" >&2
      exit 1
    else
      echo "no `code` CLI and no extensions.json found" >&2; exit 1
    fi
    ;;
  table)
    require_jq
    run jq -r '
      ["id (publisher.name)","version"],
      ["-------------------","-------"],
      (.[] | [.identifier.id, .version])
      | @tsv
    ' "$EXT_JSON" | column -t -s $'\t'
    ;;
  install-cmd)
    require_jq
    run jq -r '.[] | "code --install-extension \(.identifier.id)@\(.version)"' "$EXT_JSON"
    ;;
esac