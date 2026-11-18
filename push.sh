#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

DEFAULT_REPLACE_FILE="${HOME}/.config/push-replace/replace.txt"
REPLACE_FILE="${REPLACE_FILE:-$DEFAULT_REPLACE_FILE}"
COMMIT_MESSAGE=""
DRY_RUN=0

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

Replace file format:
  old new
  source target

Notes:
  - The replace file should stay outside the repository.
  - You can also override the replace file with REPLACE_FILE=/path/to/replace.txt
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

add_unique() {
  local candidate=$1
  local item
  for item in "${CHANGED_FILES[@]:-}"; do
    [[ "$item" == "$candidate" ]] && return 0
  done
  CHANGED_FILES+=("$candidate")
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

# 内部标识符闸门 / 自动替换（依赖本机 .git/sanitize-denylist.txt）
SANITIZE_CHECK="$REPO_ROOT/scripts/sanitize-check.sh"
SANITIZE_REPLACE="$REPO_ROOT/scripts/sanitize-replace.sh"

[[ -f "$REPLACE_FILE" ]] || warn "Replace file not found: $REPLACE_FILE (仅用清单规则替换)"
[[ -n "$(git status --porcelain)" ]] || {
  warn "No changes detected."
  exit 0
}

BRANCH=$(git branch --show-current)
[[ -n "$BRANCH" ]] || die "Unable to detect current branch."

log "${C_BOLD}Repository:${C_RESET} $REPO_ROOT"
log "${C_BOLD}Branch:${C_RESET} $BRANCH"
log "${C_BOLD}Replace file:${C_RESET} $REPLACE_FILE"

# ── 用内部标识符清单做定向替换 ────────────────────────────────────────────────
# 规则来源：.git/sanitize-denylist.txt（唯一事实来源）+ $REPLACE_FILE（本机补充）
# 替换边界与 sanitize-check.sh 的 HARD 判定一致，避免改坏 base64 / 证书 / JAR
RULE_COUNT=0
if [[ -x "$SANITIZE_REPLACE" ]]; then
  RULE_COUNT=$(SANITIZE_EXTRA_RULES="$REPLACE_FILE" bash "$SANITIZE_REPLACE" --list-rules 2>/dev/null \
    | tail -n +2 | grep -c . || echo 0)
else
  warn "找不到 $SANITIZE_REPLACE，跳过自动替换（闸门仍会拦截）。"
fi

[[ $RULE_COUNT -gt 0 ]] || warn "没有可用的替换规则，请检查 .git/sanitize-denylist.txt。"

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

if [[ ${#CHANGED_FILES[@]} -gt 0 && -x "$SANITIZE_REPLACE" ]]; then
  FILE_LIST="$(mktemp "${TMPDIR:-/tmp}/push-files.XXXXXX")"
  printf '%s\n' "${CHANGED_FILES[@]}" >"$FILE_LIST"
  REPLACE_LOG="$(SANITIZE_EXTRA_RULES="$REPLACE_FILE" bash "$SANITIZE_REPLACE" --files-from "$FILE_LIST" 2>&1)"
  printf '%s\n' "$REPLACE_LOG"
  UPDATED=$(printf '%s\n' "$REPLACE_LOG" | grep -c '已替换' || true)
  SKIPPED=$(printf '%s\n' "$REPLACE_LOG" | grep -c '跳过' || true)
  rm -f "$FILE_LIST"
  PROCESSED=${#CHANGED_FILES[@]}
elif [[ ${#CHANGED_FILES[@]} -gt 0 ]]; then
  warn "未执行内容替换。"
fi

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
  COMMIT_MESSAGE="chore: sync ${BRANCH} $(date '+%Y-%m-%d %H:%M:%S %Z')"
fi

printf '\n%sStaged files%s\n' "$C_BOLD" "$C_RESET"
git diff --cached --name-only | sed 's/^/  - /'

log "Commit message: $COMMIT_MESSAGE"
# commit message 也可能带上代号（AI / diff 带进来的）—— 提交前统一脱敏
if [[ -x "$SANITIZE_REPLACE" ]]; then
  COMMIT_MESSAGE="$(printf '%s\n' "$COMMIT_MESSAGE" \
    | SANITIZE_EXTRA_RULES="$REPLACE_FILE" bash "$SANITIZE_REPLACE" --stdin 2>/dev/null)"
fi

# 提交前再跑一次闸门（不依赖钩子是否装好）
if [[ -x "$SANITIZE_CHECK" ]]; then
  bash "$SANITIZE_CHECK" --staged || die "内部标识符闸门拦截了本次提交，请按提示处理后再试。"
fi

git commit -m "$COMMIT_MESSAGE"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  git push
else
  git push -u origin "$BRANCH"
fi

ok "Push completed successfully."
