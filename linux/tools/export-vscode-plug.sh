#!/usr/bin/env bash
# export-vscode-plug.sh
#
# Export the list of installed VS Code / Cursor / Windsurf / VS Code Insiders
# extensions in formats you can paste elsewhere. Tested on macOS (Bash 3.2 /
# Bash 5.x) and Linux (Bash 4+).
#
# Usage:
#   ./export-vscode-plug.sh                         # names only (one per line)
#   ./export-vscode-plug.sh --with-versions         # name@version, one per line
#   ./export-vscode-plug.sh --csv                   # comma-separated for shell loops
#   ./export-vscode-plug.sh --table                  # aligned table (id, version)
#   ./export-vscode-plug.sh --install-cmd            # `code --install-extension ...` commands
#   ./export-vscode-plug.sh --json                   # raw JSON from extensions/extensions.json
#   ./export-vscode-plug.sh --out FILE               # write to FILE instead of stdout
#   ./export-vscode-plug.sh --editor EDITOR          # pick editor: code|cursor|windsurf|code-insiders|auto
#   ./export-vscode-plug.sh --list-editors           # print detected editors and exit
#
# Notes:
#   - The `code` CLI on macOS may point at Cursor.app (a VS Code fork). Both
#     expose the same `--list-extensions` surface, so this script works for
#     either. The `--json` / `--table` / `--install-cmd` modes read
#     ~/.vscode/extensions/extensions.json (or ~/.cursor / ~/.windsurf /
#     ~/.vscode-insiders) directly to bypass any CLI quirks.
#   - The VS Code family (code, cursor, windsurf, code-insiders) all share the
#     `--list-extensions` CLI and the `extensions/extensions.json` layout.
#     Pass `--editor` to target a specific one; default `auto` finds the first
#     CLI on PATH, falling back to the first extensions.json found.
#   - Run with --help for usage.
#
# Exit codes:
#   0 = success
#   1 = neither a matching CLI nor an extensions.json found
#   2 = bad CLI args or unknown editor

set -euo pipefail

usage() {
  sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# Known editors and their stable identifiers. CLI bin name -> extensions dir.
declare -a EDITOR_ORDER=("code" "code-insiders" "cursor" "windsurf")
declare -A EDITOR_DIR=(
  ["code"]="$HOME/.vscode"
  ["code-insiders"]="$HOME/.vscode-insiders"
  ["cursor"]="$HOME/.cursor"
  ["windsurf"]="$HOME/.windsurf"
)

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for --json / --table / --install-cmd. Install with:" >&2
    echo "  brew install jq          # macOS" >&2
    echo "  apt-get install -y jq     # Debian/Ubuntu" >&2
    echo "  yum install -y jq         # RHEL/Fedora" >&2
    exit 1
  fi
}

# Resolve the editor to actually use. Honors $EDITOR_CHOICE ("auto" if unset).
# Sets globals: CODE_BIN (may be empty), EXT_JSON (may be empty).
resolve_editor() {
  CODE_BIN=""
  EXT_JSON=""
  local choice="${EDITOR_CHOICE:-auto}"

  if [[ "$choice" != "auto" ]]; then
    # Validate the requested editor is known.
    if [[ -z "${EDITOR_DIR[$choice]:-}" ]]; then
      echo "unknown editor: $choice (try one of: ${EDITOR_ORDER[*]} auto)" >&2
      exit 2
    fi
    # Prefer the CLI; fall back to extensions.json for that specific editor.
    local bin
    bin="$(command -v "$choice" 2>/dev/null || true)"
    CODE_BIN="$bin"
    local ej="${EDITOR_DIR[$choice]}/extensions/extensions.json"
    [[ -f "$ej" ]] && EXT_JSON="$ej"
    return 0
  fi

  # auto: walk EDITOR_ORDER, take the first CLI on PATH. Then fall back to
  # the first extensions.json that exists.
  local e
  for e in "${EDITOR_ORDER[@]}"; do
    local bin
    bin="$(command -v "$e" 2>/dev/null || true)"
    if [[ -n "$bin" ]]; then
      CODE_BIN="$bin"
      local ej="${EDITOR_DIR[$e]}/extensions/extensions.json"
      [[ -f "$ej" ]] && EXT_JSON="$ej"
      return 0
    fi
  done
  for e in "${EDITOR_ORDER[@]}"; do
    local ej="${EDITOR_DIR[$e]}/extensions/extensions.json"
    if [[ -f "$ej" ]]; then
      EXT_JSON="$ej"
      return 0
    fi
  done
}

# Print each detected editor (CLI path + extensions.json path) and exit.
list_editors() {
  local e bin ej
  printf '%-16s %-30s %s\n' "editor" "cli" "extensions.json"
  printf '%-16s %-30s %s\n' "------" "---" "---------------"
  for e in "${EDITOR_ORDER[@]}"; do
    bin="$(command -v "$e" 2>/dev/null || true)"
    ej="${EDITOR_DIR[$e]}/extensions/extensions.json"
    [[ -f "$ej" ]] || ej=""
    printf '%-16s %-30s %s\n' "$e" "${bin:-(none)}" "${ej:-(none)}"
  done
}

MODE="names"
OUT=""
EDITOR_CHOICE="auto"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --with-versions) MODE="versions" ;;
    --csv) MODE="csv" ;;
    --table) MODE="table"; require_jq ;;
    --json) MODE="json"; require_jq ;;
    --install-cmd) MODE="install-cmd"; require_jq ;;
    --out) OUT="${2:-}"; shift ;;
    --editor) EDITOR_CHOICE="${2:-}"; shift ;;
    --list-editors) list_editors; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage 2 ;;
  esac
  shift
done

# Honour --editor early so resolution errors surface before any output.
resolve_editor

run() {
  if [[ -n "$OUT" ]]; then
    "$@" > "$OUT"
    echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
  else
    "$@"
  fi
}

# Shared diagnostic for the "found nothing" case.
err_no_source() {
  local editor="$EDITOR_CHOICE"
  echo "no extensions source found (editor=${editor})." >&2
  echo "try: $0 --list-editors  to see what's detected" >&2
  echo " or: $0 --editor code    to force a specific one" >&2
  exit 1
}

case "$MODE" in
  names)
    if [[ -n "$CODE_BIN" ]]; then
      run "$CODE_BIN" --list-extensions
    elif [[ -n "$EXT_JSON" ]]; then
      require_jq
      run jq -r '.[].identifier.id' "$EXT_JSON"
    else
      err_no_source
    fi
    ;;
  versions)
    if [[ -n "$CODE_BIN" ]]; then
      run "$CODE_BIN" --list-extensions --show-versions
    elif [[ -n "$EXT_JSON" ]]; then
      require_jq
      run jq -r '.[] | "\(.identifier.id)@\(.version)"' "$EXT_JSON"
    else
      err_no_source
    fi
    ;;
  csv)
    if [[ -n "$CODE_BIN" ]]; then
      CMD="$CODE_BIN --list-extensions"
      if [[ -n "$OUT" ]]; then
        bash -c "$CMD" | paste -sd ',' - > "$OUT"
        echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
      else
        bash -c "$CMD" | paste -sd ',' -
      fi
    elif [[ -n "$EXT_JSON" ]]; then
      require_jq
      if [[ -n "$OUT" ]]; then
        jq -r '.[].identifier.id' "$EXT_JSON" | paste -sd ',' - > "$OUT"
        echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
      else
        jq -r '.[].identifier.id' "$EXT_JSON" | paste -sd ',' -
      fi
    else
      err_no_source
    fi
    ;;
  json)
    if [[ -n "$EXT_JSON" ]]; then
      run jq '.' "$EXT_JSON"
    elif [[ -n "$CODE_BIN" ]]; then
      # `code` doesn't print JSON; tell the user where to look.
      echo "no extensions.json found for editor=${EDITOR_CHOICE}." >&2
      echo "\`$CODE_BIN --list-extensions\` does not emit JSON." >&2
      exit 1
    else
      err_no_source
    fi
    ;;
  table)
    if [[ -z "$EXT_JSON" ]]; then
      echo "--table requires an extensions.json (editor=${EDITOR_CHOICE})." >&2
      err_no_source
    fi
    run jq -r '
      ["id (publisher.name)","version"],
      ["-------------------","-------"],
      (.[] | [.identifier.id, .version])
      | @tsv
    ' "$EXT_JSON" | column -t -s $'\t'
    ;;
  install-cmd)
    if [[ -z "$EXT_JSON" ]]; then
      echo "--install-cmd requires an extensions.json (editor=${EDITOR_CHOICE})." >&2
      err_no_source
    fi
    run jq -r '.[] | "code --install-extension \(.identifier.id)@\(.version)"' "$EXT_JSON"
    ;;
esac