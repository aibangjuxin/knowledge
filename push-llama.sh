#!/opt/homebrew/bin/bash
# push-llama.sh
# 使用本地 llama-server + gemma-3-1b-it 生成标准化 commit message
# 参考: ocr-llama.py 的临时 server 模式

set -euo pipefail
IFS=$'\n\t'

# ── Config ────────────────────────────────────────────────────────────────────
DEFAULT_REPLACE_FILE="${HOME}/.config/push-replace/replace.txt"
REPLACE_FILE="${REPLACE_FILE:-$DEFAULT_REPLACE_FILE}"
COMMIT_MESSAGE=""
DRY_RUN=0

# llama-server 配置（参考 ocr-llama.py）
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-/opt/homebrew/bin/llama-server}"
MODEL_PATH="${LLAMA_MODEL_PATH:-/Users/lex/.cache/lm-studio/models/lmstudio-community/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf}"
LLAMA_CTX_SIZE="${LLAMA_CTX_SIZE:-8192}"
LLAMA_N_GPU_LAYERS="${LLAMA_N_GPU_LAYERS:-99}"
LLAMA_THREADS="${LLAMA_THREADS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"
LLAMA_SERVER_TIMEOUT=30
LLAMA_HTTP_TIMEOUT=120
LLAMA_PORT=""

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

# ── Helper Functions ───────────────────────────────────────────────────────────
log()   { printf '%b%s%b\n' "$C_BLUE" "$*" "$C_RESET"; }
ok()    { printf '%b%s%b\n' "$C_GREEN" "$*" "$C_RESET"; }
warn()  { printf '%b%s%b\n' "$C_YELLOW" "$*" "$C_RESET"; }
info()  { printf '%b%s%b\n' "$C_CYAN" "$*" "$C_RESET"; }
die()   { printf '%b%s%b\n' "$C_RED" "$*" "$C_RESET" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -m, --message TEXT    Commit message hint (passed to AI as context)
  -r, --replace-file    PATH  Local replace file path (default: $DEFAULT_REPLACE_FILE)
  -n, --dry-run         Show actions without git add/commit/push
  -h, --help            Show this help

Environment variables:
  REPLACE_FILE          Override replace file path
  LLAMA_MODEL_PATH      Path to GGUF model (default: $MODEL_PATH)
  LLAMA_SERVER_BIN      Path to llama-server (default: $LLAMA_SERVER_BIN)
  LLAMA_CTX_SIZE        Context size (default: $LLAMA_CTX_SIZE)
  LLAMA_N_GPU_LAYERS    GPU layers to offload (default: $LLAMA_N_GPU_LAYERS)
EOF
}

# ── llama-server Lifecycle ─────────────────────────────────────────────────────
find_free_port() {
    python3 - <<'PYEOF'
import socket
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind(('127.0.0.1', 0))
    print(s.getsockname()[1])
PYEOF
}

wait_server_ready() {
    local base_url=$1
    local deadline=$(($(date +%s) + LLAMA_SERVER_TIMEOUT))
    local last_err=""
    while [[ $(date +%s) -lt $deadline ]]; do
        if ! kill -0 $LLAMA_PID 2>/dev/null; then
            die "llama-server 进程意外退出"
        fi
        if curl -sf --max-time 2 "${base_url}/health" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    die "llama-server 启动超时"
}

start_llama_server() {
    local port=$1
    info "启动 llama-server (port=${port})..."

    $LLAMA_SERVER_BIN \
        -m "$MODEL_PATH" \
        -c $LLAMA_CTX_SIZE \
        -ngl $LLAMA_N_GPU_LAYERS \
        -t $LLAMA_THREADS \
        --host 127.0.0.1 \
        --port $port \
        --jinja \
        -fa off \
        -fit off \
        --no-webui \
        > /dev/null 2>&1 &

    LLAMA_PID=$!
}

stop_llama_server() {
    if [[ -n "${LLAMA_PID:-}" ]] && kill -0 $LLAMA_PID 2>/dev/null; then
        kill $LLAMA_PID 2>/dev/null || true
        wait $LLAMA_PID 2>/dev/null || true
    fi
}

cleanup() {
    stop_llama_server
    rm -f "$SED_SCRIPT" "$COMMIT_FILE"
}
trap cleanup EXIT

# ── Core Logic ─────────────────────────────────────────────────────────────────
trim_leading_ws() {
    local val="$1"
    printf '%s' "${val#"${val%%[![:space:]]*}"}"
}

esabje_sed_pattern() {
    printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\/]/\\&/g'
}

esabje_sed_replacement() {
    printf '%s' "$1" | sed 's/[\/&]/\\&/g'
}

is_text_file() {
    local mime
    mime=$(file -b --mime "$1" 2>/dev/null || true)
    [[ "$mime" != *"charset=binary"* ]]
}

add_unique() {
    local candidate=$1
    for item in "${CHANGED_FILES[@]:-}"; do
        [[ "$item" == "$candidate" ]] && return 0
    done
    CHANGED_FILES+=("$candidate")
}

# ── Commit Message Helpers ─────────────────────────────────────────────────────
derive_topic_from_files() {
    local files="$1"
    local parts=() seen_dirs=()

    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local dir base top_dir
        dir=$(dirname "$f")
        base=$(basename "$f"); base="${base%.*}"
        top_dir=$(printf '%s' "$dir" | cut -d'/' -f1)

        if [[ "$top_dir" != "." ]]; then
            local already=0 d
            for d in "${seen_dirs[@]:-}"; do [[ "$d" == "$top_dir" ]] && already=1 && break; done
            if [[ $already -eq 0 ]]; then
                seen_dirs+=("$top_dir")
                parts+=("$top_dir")
            fi
        else
            parts+=("$base")
        fi
    done <<< "$files"

    local result="" count=0 p
    for p in "${parts[@]:-}"; do
        [[ $count -ge 3 ]] && break
        [[ -n "$result" ]] && result+=", "
        result+="$p"
        count=$((count + 1))
    done
    printf '%s' "$result"
}

derive_subject_line() {
    local hint="$1" branch="$2" staged_files="$3"
    local title topic file_count first_file first_base
    file_count=$(printf '%s' "$staged_files" | grep -c '.' || echo 0)

    if [[ -n "$hint" ]]; then
        title="$hint"
        if ! printf '%s' "$title" | grep -qiE '^(feat|fix|docs|chore|refactor|style|test|ci|build|perf|revert):'; then
            title="docs: ${title}"
        fi
    else
        topic=$(derive_topic_from_files "$staged_files")
        if [[ $file_count -eq 1 ]]; then
            first_file=$(printf '%s' "$staged_files" | head -1)
            first_base=$(basename "$first_file"); first_base="${first_base%.*}"
            title="docs: update ${first_base}"
        elif [[ -n "$topic" ]]; then
            title="docs: update ${topic}"
        else
            title="chore: sync ${branch}"
        fi
    fi

    [[ ${#title} -gt 72 ]] && title="${title:0:69}..."
    printf '%s' "$title"
}

build_fallback_message() {
    local hint="$1" branch="$2" staged_files="$3" insertions="$4" deletions="$5"
    local title body
    title=$(derive_subject_line "$hint" "$branch" "$staged_files")

    body="Branch: ${branch} Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"$'\n'
    body+="Stats: +${insertions}/-${deletions} lines"$'\n\n'
    body+="Changed files:"$'\n'
    while IFS= read -r f; do
        [[ -n "$f" ]] && body+=" - ${f}"$'\n'
    done <<< "$staged_files"

    printf '%s\n\n%s' "$title" "$body"
}

# ── llama-server API Call ──────────────────────────────────────────────────────
generate_commit_msg_via_llama() {
    local hint="$1" diff_text="$2" staged_files="$3"
    local insertions="$4" deletions="$5" branch="$6"
    local base_url="http://127.0.0.1:${LLAMA_PORT}"

    # 截断 diff 避免小型模型溢出
    local max_diff_chars=2500
    if [[ ${#diff_text} -gt $max_diff_chars ]]; then
        diff_text="${diff_text:0:$max_diff_chars}
... (diff truncated)"
    fi

    # 构建文件列表
    local file_list=""
    while IFS= read -r f; do
        [[ -n "$f" ]] && file_list+=" - ${f}"$'\n'
    done <<< "$staged_files"

    local hint_line=""
    [[ -n "$hint" ]] && hint_line="User summary hint: ${hint}"$'\n'

    # 构建 chat 格式 prompt
    local system_prompt="You are an expert git commit message writer. Write professional, clear commit messages following conventional commits format."
    local user_prompt="${hint_line}Branch: ${branch}
Stats: +${insertions}/-${deletions} lines

Changed files:
${file_list}
Diff summary:
${diff_text:0:1500}

Write a concise commit message body with 2-4 bullet points explaining what changed and why. Focus on the purpose and impact of the changes."

    # 调用 OpenAI 兼容 API
    local payload
    payload=$(python3 - <<PYEOF
import json, sys
data = {
    "model": "gemma-3-1b-it",
    "messages": [
        {"role": "system", "content": "$system_prompt"},
        {"role": "user", "content": """${user_prompt}"""}
    ],
    "temperature": 0.3,
    "max_tokens": 400,
    "stream": False
}
print(json.dumps(data))
PYEOF
)

    local response
    response=$(curl -sf --max-time $LLAMA_HTTP_TIMEOUT \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "${base_url}/v1/chat/completions" 2>/dev/null) || return 1

    local msg
    msg=$(python3 - <<PYEOF
import json, sys
data = json.loads(sys.stdin.read())
print(data.get("choices", [{}])[0].get("message", {}).get("content", "").strip())
PYEOF
) || return 1

    [[ -n "$msg" ]] || return 1
    printf '%s' "$msg"
}

sanitize_ai_body() {
    local body="$1"
    body=$(printf '%s\n' "$body" | sed '/^[[:space:]]*$/N;/^\n$/D')
    body=$(printf '%s\n' "$body" | sed '/^[[:space:]]*git commit message[[:space:]]*$/Id')
    printf '%s' "$body"
}

compose_final_message() {
    local subject="$1" ai_body="$2" branch="$3"
    local staged_files="$4" insertions="$5" deletions="$6"
    local final_body=""

    ai_body=$(sanitize_ai_body "$ai_body")

    if [[ -n "${ai_body//[[:space:]]/}" ]]; then
        final_body="$ai_body"
    else
        final_body="- Branch: ${branch}
- Stats: +${insertions}/-${deletions} lines

Changed files:"
        while IFS= read -r f; do
            [[ -n "$f" ]] && final_body+="
- ${f}"
        done <<< "$staged_files"
    fi

    printf '%s\n\n%s\n' "$subject" "$final_body"
}

# ── Main ───────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message)    [[ $# -ge 2 ]] || die "Missing value for $1"; COMMIT_MESSAGE=$2; shift 2 ;;
        -r|--replace-file) [[ $# -ge 2 ]] || die "Missing value for $1"; REPLACE_FILE=$2; shift 2 ;;
        -n|--dry-run)    DRY_RUN=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)               die "Unknown argument: $1" ;;
    esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Current directory is not a git repository."

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

[[ -f "$REPLACE_FILE" ]] || die "Replace file not found: $REPLACE_FILE"
[[ -n "$(git status --porcelain)" ]] || { warn "No changes detected."; exit 0; }

BRANCH=$(git branch --show-current)
[[ -n "$BRANCH" ]] || die "Unable to detect current branch."

log "${C_BOLD}Repository:${C_RESET} $REPO_ROOT"
log "${C_BOLD}Branch:${C_RESET} $BRANCH"
log "${C_BOLD}Replace file:${C_RESET} $REPLACE_FILE"
log "${C_BOLD}Model:${C_RESET} $(basename "$MODEL_PATH")"

# ── Build sed script from replace file ────────────────────────────────────────
SED_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/push-replace.XXXXXX.sed")
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

# ── Process changed files ─────────────────────────────────────────────────────
CHANGED_FILES=()
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    while IFS= read -r -d '' file; do add_unique "$file"; done < <(git diff --name-only -z --diff-filter=ACMRTUXB HEAD --)
else
    while IFS= read -r -d '' file; do add_unique "$file"; done < <(git ls-files -z)
fi
while IFS= read -r -d '' file; do add_unique "$file"; done < <(git ls-files --others --exclude-standard -z)

if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
    warn "No editable files found."
fi

if [[ ${#CHANGED_FILES[@]} -gt 0 ]]; then
    printf '\n%sFiles to process (%d):%s\n' "$C_BOLD" "${#CHANGED_FILES[@]}" "$C_RESET"
    for file in "${CHANGED_FILES[@]}"; do printf ' - %s\n' "$file"; done
fi

PROCESSED=0; UPDATED=0; SKIPPED=0
for file in "${CHANGED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        warn "Skip missing: $file"; SKIPPED=$((SKIPPED + 1)); continue
    fi
    if ! is_text_file "$file"; then
        warn "Skip binary: $file"; SKIPPED=$((SKIPPED + 1)); continue
    fi
    TMP_FILE=$(mktemp "${TMPDIR:-/tmp}/push-file.XXXXXX")
    sed -f "$SED_SCRIPT" "$file" > "$TMP_FILE"
    if ! cmp -s "$file" "$TMP_FILE"; then
        mv "$TMP_FILE" "$file"
        UPDATED=$((UPDATED + 1)); ok "Updated: $file"
    else
        rm -f "$TMP_FILE"; log "No replacement: $file"
    fi
    PROCESSED=$((PROCESSED + 1))
done

printf '\n%sReplacement summary%s\n' "$C_BOLD" "$C_RESET"
printf ' Rules loaded : %d\n' $RULE_COUNT
printf ' Files checked: %d\n' $PROCESSED
printf ' Files updated: %d\n' $UPDATED
printf ' Files skipped: %d\n' $SKIPPED

[[ $DRY_RUN -eq 1 ]] && { warn "Dry-run. Skipping git add/commit/push."; exit 0; }

git add -A
git diff --cached --quiet && { warn "No staged changes after replacement."; exit 0; }

# ── Collect staged info ────────────────────────────────────────────────────────
STAGED_FILES=$(git diff --cached --name-only)
STAGED_STAT=$(git diff --cached --shortstat 2>/dev/null || echo "0 insertions, 0 deletions")
INSERTIONS=$(printf '%s' "$STAGED_STAT" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)
DELETIONS=$(printf '%s' "$STAGED_STAT" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)
INSERTIONS="${INSERTIONS:-0}"; DELETIONS="${DELETIONS:-0}"

# ── AI commit message via llama-server ────────────────────────────────────────
printf '\n%sGenerating commit message via llama-server...%s\n' "$C_BOLD" "$C_RESET"

USER_HINT="${COMMIT_MESSAGE:-}"
FINAL_MESSAGE=""
SUBJECT_LINE=$(derive_subject_line "$USER_HINT" "$BRANCH" "$STAGED_FILES")
AI_BODY=""

# 验证模型文件
if [[ ! -f "$MODEL_PATH" ]]; then
    warn "Model not found: $MODEL_PATH"
    warn "Using fallback commit message."
else
    # 启动临时 llama-server
    LLAMA_PORT=$(find_free_port)
    start_llama_server $LLAMA_PORT
    wait_server_ready "http://127.0.0.1:${LLAMA_PORT}"

    info "llama-server ready. Querying gemma-3-1b-it..."

    DIFF_TEXT=$(git diff --cached -- 2>/dev/null | head -100 || true)

    if AI_MSG=$(generate_commit_msg_via_llama \
        "$USER_HINT" "$DIFF_TEXT" "$STAGED_FILES" \
        "$INSERTIONS" "$DELETIONS" "$BRANCH"); then
        AI_BODY="$AI_MSG"
        ok "AI body ready."
    else
        warn "llama-server returned empty or invalid response. Using fallback."
    fi

    stop_llama_server
fi

FINAL_MESSAGE=$(compose_final_message \
    "$SUBJECT_LINE" "$AI_BODY" "$BRANCH" \
    "$STAGED_FILES" "$INSERTIONS" "$DELETIONS")

# ── Display and commit ─────────────────────────────────────────────────────────
printf '\n%s--- commit message ---%s\n' "$C_CYAN" "$C_RESET"
printf '%s\n' "$FINAL_MESSAGE"
printf '%s----------------------%s\n' "$C_CYAN" "$C_RESET"

printf '\n%sStaged files%s\n' "$C_BOLD" "$C_RESET"
git diff --cached --name-only | sed 's/^/ - /'

COMMIT_FILE=$(mktemp "${TMPDIR:-/tmp}/commit-msg.XXXXXX")
printf '%s\n' "$FINAL_MESSAGE" > "$COMMIT_FILE"

git commit -F "$COMMIT_FILE"

if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git push
else
    git push -u origin "$BRANCH"
fi

ok "Push completed successfully."