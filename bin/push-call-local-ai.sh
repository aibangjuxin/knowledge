#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

DEFAULT_REPLACE_FILE="${HOME}/.config/push-replace/replace.txt"
REPLACE_FILE="${REPLACE_FILE:-$DEFAULT_REPLACE_FILE}"
COMMIT_MESSAGE=""
DRY_RUN=0

OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
ENHANCE_MODEL="${ENHANCE_MODEL:-gemma3:270m}"
PYTHON_BIN="${PYTHON_BIN:-/Users/lex/python/openai/bin/python3}"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
else
  C_RESET=""
  C_BOLD=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -m, --message TEXT        Commit message
  -r, --replace-file PATH   Local replace file path (default: $DEFAULT_REPLACE_FILE)
  -n, --dry-run             Show actions without git add/commit/push
  -h, --help                Show this help

AI defaults:
  OLLAMA_HOST=${OLLAMA_HOST}
  ENHANCE_MODEL=${ENHANCE_MODEL}
  PYTHON_BIN=${PYTHON_BIN}

Replace file format:
  old new
  source target

Notes:
  - The replace file should stay outside the repository.
  - You can also override the replace file with REPLACE_FILE=/path/to/replace.txt
  - If -m is not provided, the script will try to generate a short commit message using local Ollama.
EOF
}

log() {
  printf '%b%s%b\n' "$C_BLUE" "$*" "$C_RESET"
}

ok() {
  printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"
}

warn() {
  printf '%b%s%b\n' "$C_YELLOW" "$*" "$C_RESET"
}

die() {
  printf '%b%s%b\n' "$C_RED" "$*" "$C_RESET" >&2
  exit 1
}

trim_leading_ws() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  printf '%s' "$value"
}

esabje_sed_pattern() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\/]/\\&/g'
}

esabje_sed_replacement() {
  printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

is_text_file() {
  local file=$1
  local mime
  mime=$(file -b --mime "$file" 2>/dev/null || true)
  [[ "$mime" != *"charset=binary"* ]]
}

add_unique() {
  local candidate=$1
  local item
  for item in "${CHANGED_FILES[@]:-}"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  CHANGED_FILES+=("$candidate")
}

generate_ai_commit_message() {
  local repo_root=$1
  local branch=$2
  local tmp_input
  tmp_input=$(mktemp "${TMPDIR:-/tmp}/push-ai-input.XXXXXX")

  {
    echo "Repository: $repo_root"
    echo "Branch: $branch"
    echo
    echo "[staged files]"
    git diff --cached --name-status
    echo
    echo "[staged stat]"
    git diff --cached --stat
    echo
    echo "[staged diff excerpt]"
    git diff --cached --unified=0 --no-color | head -c 12000
  } > "$tmp_input"

  local result
  if ! result=$(
    OLLAMA_HOST="$OLLAMA_HOST" \
    ENHANCE_MODEL="$ENHANCE_MODEL" \
    INPUT_FILE="$tmp_input" \
    "$PYTHON_BIN" - <<'PY'
import json
import os
import sys
import urllib.request
import urllib.error

host = os.environ.get("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
model = os.environ.get("ENHANCE_MODEL", "gemma3:270m")
input_file = os.environ["INPUT_FILE"]

with open(input_file, "r", encoding="utf-8") as f:
    changes = f.read()

prompt = f"""You are a git commit assistant.
Read the staged changes and output exactly one concise commit message.

Requirements:
- Output only one line
- No quotes
- Prefer conventional commit style
- Max 72 characters
- Use present tense
- Be specific but short

Staged changes:
{changes}
"""

payload = {
    "model": model,
    "prompt": prompt,
    "stream": False,
    "options": {
        "temperature": 0.1,
        "top_p": 0.85,
        "num_predict": 80,
        "num_ctx": 2048
    }
}

req = urllib.request.Request(
    host + "/api/generate",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"},
    method="POST",
)

try:
    with urllib.request.urlopen(req, timeout=45) as resp:
        data = json.loads(resp.read().decode("utf-8"))
except Exception:
    sys.exit(1)

text = (data.get("response") or "").strip()
lines = [line.strip() for line in text.splitlines() if line.strip()]
if not lines:
    sys.exit(1)

message = lines[0]
message = " ".join(message.split())
message = message.strip("\"'`")
print(message)
PY
  ); then
    rm -f "$tmp_input"
    return 1
  fi

  rm -f "$tmp_input"
  printf '%s' "$result"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      COMMIT_MESSAGE=$2
      shift 2
      ;;
    -r|--replace-file)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      REPLACE_FILE=$2
      shift 2
      ;;
    -n|--dry-run)
      DRY_RUN=1
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

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Current directory is not a git repository."

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

[[ -f "$REPLACE_FILE" ]] || die "Replace file not found: $REPLACE_FILE"
[[ -n "$(git status --porcelain)" ]] || {
  warn "No changes detected."
  exit 0
}

BRANCH=$(git branch --show-current)
[[ -n "$BRANCH" ]] || die "Unable to detect current branch."

log "${C_BOLD}Repository:${C_RESET} $REPO_ROOT"
log "${C_BOLD}Branch:${C_RESET} $BRANCH"
log "${C_BOLD}Replace file:${C_RESET} $REPLACE_FILE"
log "${C_BOLD}AI host:${C_RESET} $OLLAMA_HOST"
log "${C_BOLD}AI model:${C_RESET} $ENHANCE_MODEL"

SED_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/push-replace.XXXXXX.sed")
cleanup() {
  rm -f "$SED_SCRIPT"
}
trap cleanup EXIT

RULE_COUNT=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "${line#\#}" != "$line" ]] && continue

  old=${line%%[[:space:]]*}
  new=${line#"$old"}
  new=$(trim_leading_ws "$new")

  [[ -n "$old" ]] || continue

  printf 's/%s/%s/g\n' \
    "$(esabje_sed_pattern "$old")" \
    "$(esabje_sed_replacement "$new")" >> "$SED_SCRIPT"
  RULE_COUNT=$((RULE_COUNT + 1))
done < "$REPLACE_FILE"

[[ $RULE_COUNT -gt 0 ]] || die "Replace file is empty or contains no valid rules."

CHANGED_FILES=()
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  while IFS= read -r -d '' file; do
    add_unique "$file"
  done < <(git diff --name-only -z --diff-filter=ACMRTUXB HEAD --)
else
  while IFS= read -r -d '' file; do
    add_unique "$file"
  done < <(git ls-files -z)
fi

while IFS= read -r -d '' file; do
  add_unique "$file"
done < <(git ls-files --others --exclude-standard -z)

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  warn "No editable files found. Continuing with git add/commit for deletions or mode-only changes."
fi

if [[ ${#CHANGED_FILES[@]} -gt 0 ]]; then
  printf '\n%sFiles to process (%d):%s\n' "$C_BOLD" "${#CHANGED_FILES[@]}" "$C_RESET"
  for file in "${CHANGED_FILES[@]}"; do
    printf '  - %s\n' "$file"
  done
fi

PROCESSED=0
UPDATED=0
SKIPPED=0

for file in "${CHANGED_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    warn "Skip missing file: $file"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if ! is_text_file "$file"; then
    warn "Skip binary file: $file"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  TMP_FILE=$(mktemp "${TMPDIR:-/tmp}/push-file.XXXXXX")
  sed -f "$SED_SCRIPT" "$file" > "$TMP_FILE"

  if ! cmp -s "$file" "$TMP_FILE"; then
    mv "$TMP_FILE" "$file"
    UPDATED=$((UPDATED + 1))
    ok "Updated: $file"
  else
    rm -f "$TMP_FILE"
    log "No replacement needed: $file"
  fi

  PROCESSED=$((PROCESSED + 1))
done

printf '\n%sReplacement summary%s\n' "$C_BOLD" "$C_RESET"
printf '  Rules loaded : %d\n' "$RULE_COUNT"
printf '  Files checked: %d\n' "$PROCESSED"
printf '  Files updated: %d\n' "$UPDATED"
printf '  Files skipped: %d\n' "$SKIPPED"

if [[ $DRY_RUN -eq 1 ]]; then
  warn "Dry-run enabled. Skipping git add/commit/push."
  exit 0
fi

git add -A

if git diff --cached --quiet; then
  warn "No staged changes after replacement."
  exit 0
fi

if [[ -z "$COMMIT_MESSAGE" ]]; then
  log "Generating commit message with local AI..."
  if AI_COMMIT_MESSAGE=$(generate_ai_commit_message "$REPO_ROOT" "$BRANCH"); then
    if [[ -n "$AI_COMMIT_MESSAGE" ]]; then
      COMMIT_MESSAGE="$AI_COMMIT_MESSAGE"
      ok "AI commit message: $COMMIT_MESSAGE"
    fi
  fi
fi

if [[ -z "$COMMIT_MESSAGE" ]]; then
  COMMIT_MESSAGE="chore: sync ${BRANCH} $(date '+%Y-%m-%d %H:%M:%S %Z')"
  warn "Falling back to default commit message."
fi

printf '\n%sStaged files%s\n' "$C_BOLD" "$C_RESET"
git diff --cached --name-only | sed 's/^/  - /'

log "Commit message: $COMMIT_MESSAGE"
git commit -m "$COMMIT_MESSAGE"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin "$BRANCH"
fi

ok "Push completed successfully."
