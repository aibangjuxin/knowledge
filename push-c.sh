#!/opt/homebrew/bin/bash
##!/usr/bin/env bash
# -m "<commit message>"

set -euo pipefail
IFS=$'\n\t'

DEFAULT_REPLACE_FILE="${HOME}/.config/push-replace/replace.txt"
REPLACE_FILE="${REPLACE_FILE:-$DEFAULT_REPLACE_FILE}"
COMMIT_MESSAGE=""
DRY_RUN=0

# ── Ollama config ─────────────────────────────────────────────────────────────
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"
ENHANCE_MODEL="${ENHANCE_MODEL:-gemma3:270m}"
OLLAMA_TIMEOUT=20   # seconds to wait for Ollama response
# ─────────────────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -m, --message TEXT        Commit message hint (passed to AI as context)
  -r, --replace-file PATH   Local replace file path (default: $DEFAULT_REPLACE_FILE)
  -n, --dry-run             Show actions without git add/commit/push
  -h, --help                Show this help

Environment variables:
  REPLACE_FILE              Override replace file path
  OLLAMA_HOST               Ollama API base URL (default: http://localhost:11434)
  ENHANCE_MODEL             Model to use for commit message (default: gemma3:270m)

Replace file format:
  old new
  source target

Notes:
  - The replace file should stay outside the repository.
  - If Ollama is unavailable, falls back to a structured timestamp commit message
    that includes changed file list and stats.
EOF
}

log() { printf '%b%s%b\n' "$C_BLUE" "$*" "$C_RESET"; }
ok()  { printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"; }
warn(){ printf '%b%s%b\n' "$C_YELLOW" "$*" "$C_RESET"; }
info(){ printf '%b%s%b\n' "$C_CYAN" "$*" "$C_RESET"; }
die() { printf '%b%s%b\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

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

# ── Commit message helpers ────────────────────────────────────────────────────

# Derive a short topic string from a newline-separated file list.
# Strategy: collect unique top-level dirs + unique basenames (no ext), take up to 3.
derive_topic_from_files() {
  local files="$1"
  local parts=()
  local seen_dirs=()

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local dir
    dir=$(dirname "$f")
    local base
    base=$(basename "$f")
    base="${base%.*}"   # strip extension

    # Collect unique top-level dirs (skip '.')
    local top_dir
    top_dir=$(printf '%s' "$dir" | cut -d'/' -f1)
    if [[ "$top_dir" != "." ]]; then
      local already=0
      local d
      for d in "${seen_dirs[@]:-}"; do [[ "$d" == "$top_dir" ]] && already=1 && break; done
      if [[ $already -eq 0 ]]; then
        seen_dirs+=("$top_dir")
        parts+=("$top_dir")
      fi
    else
      # Root-level file: use basename
      parts+=("$base")
    fi
  done <<< "$files"

  # Take at most 3 parts, join with ', '
  local result=""
  local count=0
  local p
  for p in "${parts[@]:-}"; do
    [[ $count -ge 3 ]] && break
    [[ -n "$result" ]] && result+=", "
    result+="$p"
    count=$((count + 1))
  done
  printf '%s' "$result"
}

# Build a structured fallback commit message (no AI required).
# Includes: conventional commit title derived from file paths + body with stats + file list.
build_fallback_message() {
  local hint="$1"
  local branch="$2"
  local staged_files="$3"   # newline-separated list
  local insertions="$4"
  local deletions="$5"

  local title
  if [[ -n "$hint" ]]; then
    title="${hint}"
    # Ensure it starts with a conventional prefix if not already
    if ! printf '%s' "$title" | grep -qE '^(feat|fix|docs|chore|refactor|style|test|ci|build|perf|revert):'; then
      title="docs: ${title}"
    fi
  else
    # Derive topic from changed files for a meaningful subject line
    local topic
    topic=$(derive_topic_from_files "$staged_files")
    local file_count
    file_count=$(printf '%s' "$staged_files" | grep -c '.' || echo 0)
    if [[ -n "$topic" ]]; then
      if [[ $file_count -eq 1 ]]; then
        # Single file: use full basename (no ext) as subject
        local single_base
        single_base=$(basename "$(printf '%s' "$staged_files" | head -1)")
        single_base="${single_base%.*}"
        title="docs: update ${single_base}"
      else
        title="docs: update ${topic} (${file_count} files)"
      fi
    else
      title="chore: sync ${branch} $(date '+%Y-%m-%d %H:%M')"
    fi
  fi

  # Truncate title to 72 chars
  if [[ ${#title} -gt 72 ]]; then
    title="${title:0:69}..."
  fi

  local body=""
  body+="Branch: ${branch}  Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"$'\n'
  body+="Stats: +${insertions}/-${deletions} lines"$'\n'
  body+=""$'\n'
  body+="Changed files:"$'\n'
  while IFS= read -r f; do
    [[ -n "$f" ]] && body+="  - ${f}"$'\n'
  done <<< "$staged_files"

  printf '%s\n\n%s' "$title" "$body"
}

# ── Ollama helpers ────────────────────────────────────────────────────────────

ollama_is_available() {
  curl -sf --max-time 5 "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1
}

ollama_generate_commit_msg() {
  local hint="$1"
  local diff_text="$2"
  local staged_files="$3"
  local insertions="$4"
  local deletions="$5"
  local branch="$6"

  # Truncate diff to avoid overwhelming small models (~3000 chars)
  local max_diff_chars=3000
  if [[ ${#diff_text} -gt $max_diff_chars ]]; then
    diff_text="${diff_text:0:$max_diff_chars}
... (diff truncated)"
  fi

  # Build file list for prompt
  local file_list=""
  while IFS= read -r f; do
    [[ -n "$f" ]] && file_list+="  - ${f}"$'\n'
  done <<< "$staged_files"

  local hint_line=""
  [[ -n "$hint" ]] && hint_line="User summary: ${hint}"$'\n'

  local prompt
  prompt="You are a git commit message writer. Write a concise, informative git commit message.

Rules:
- Line 1 (subject): conventional commit type + colon + specific description, max 72 chars
  * Types: feat/fix/docs/chore/refactor/style/test/ci/perf/revert
  * MUST reflect actual content changed (files, topic, purpose)
  * NEVER use vague phrases like 'update files', 'sync branch', or the branch name
- Line 2: BLANK (empty line, mandatory)
- Lines 3+: 2-3 bullet points explaining what changed and why
- End with a blank line then 'Changed files:' listing all files
- Output ONLY the commit message, no fences, no explanation

${hint_line}Branch: ${branch}  Stats: +${insertions}/-${deletions} lines
Changed files:
${file_list}
Diff:
${diff_text}"

  local payload
  payload=$(printf '{"model":"%s","prompt":%s,"stream":false,"options":{"temperature":0.3,"num_predict":350}}' \
    "$ENHANCE_MODEL" \
    "$(printf '%s' "$prompt" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null \
      || printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//' | sed 's/^/"/; s/$/"/')")

  local response
  response=$(curl -sf \
    --max-time "$OLLAMA_TIMEOUT" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${OLLAMA_HOST}/api/generate" 2>/dev/null) || return 1

  local msg
  msg=$(printf '%s' "$response" | python3 -c '
import json, sys
data = json.load(sys.stdin)
print(data.get("response", "").strip())
' 2>/dev/null) || return 1

  [[ -n "$msg" ]] || return 1

  # Ensure the AI message also includes the file list at the end
  # (AI might or might not have included it)
  if ! printf '%s' "$msg" | grep -q "Changed files:"; then
    msg="${msg}"$'\n\n'"Changed files:"$'\n'"${file_list}"
  fi

  printf '%s' "$msg"
}

# ─────────────────────────────────────────────────────────────────────────────

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
log "${C_BOLD}Branch:${C_RESET}     $BRANCH"
log "${C_BOLD}Replace file:${C_RESET} $REPLACE_FILE"
log "${C_BOLD}Ollama host:${C_RESET}  $OLLAMA_HOST  (model: $ENHANCE_MODEL)"

SED_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/push-replace.XXXXXX.sed")
cleanup() { rm -f "$SED_SCRIPT"; }
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

# ── Collect staged info for commit message ────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only)
STAGED_STAT=$(git diff --cached --shortstat 2>/dev/null || echo "0 insertions, 0 deletions")
INSERTIONS=$(printf '%s' "$STAGED_STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
DELETIONS=$(printf '%s' "$STAGED_STAT"  | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' || echo 0)
INSERTIONS="${INSERTIONS:-0}"
DELETIONS="${DELETIONS:-0}"
# ─────────────────────────────────────────────────────────────────────────────

# ── AI-powered commit message generation ──────────────────────────────────────
printf '\n%sGenerating commit message...%s\n' "$C_BOLD" "$C_RESET"

USER_HINT="${COMMIT_MESSAGE:-}"
FINAL_MESSAGE=""

if ollama_is_available; then
  info "Ollama reachable → asking ${ENHANCE_MODEL} to summarise the diff..."
  DIFF_TEXT=$(git diff --cached -- 2>/dev/null || true)

  if AI_MSG=$(ollama_generate_commit_msg \
        "$USER_HINT" "$DIFF_TEXT" "$STAGED_FILES" \
        "$INSERTIONS" "$DELETIONS" "$BRANCH"); then
    FINAL_MESSAGE="$AI_MSG"
    ok "AI message ready."
  else
    warn "Ollama returned an empty or invalid response. Using structured fallback."
  fi
else
  warn "Ollama not reachable at ${OLLAMA_HOST}. Using structured fallback."
fi

# Fallback: structured message with file list and stats
if [[ -z "$FINAL_MESSAGE" ]]; then
  FINAL_MESSAGE=$(build_fallback_message \
    "$USER_HINT" "$BRANCH" "$STAGED_FILES" "$INSERTIONS" "$DELETIONS")
fi
# ─────────────────────────────────────────────────────────────────────────────

printf '\n%s--- commit message ---%s\n' "$C_CYAN" "$C_RESET"
printf '%s\n' "$FINAL_MESSAGE"
printf '%s----------------------%s\n' "$C_CYAN" "$C_RESET"

printf '\n%sStaged files%s\n' "$C_BOLD" "$C_RESET"
git diff --cached --name-only | sed 's/^/  - /'

git commit -m "$FINAL_MESSAGE"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin "$BRANCH"
fi

ok "Push completed successfully."
