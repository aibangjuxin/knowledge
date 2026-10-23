#!/opt/homebrew/bin/bash
# push-llama.sh
# 使用本地 llama-server + gemma-3-1b-it 生成标准化 commit message
# 参考: ocr-llama.py 的临时 server 模式
# when I using bash -x push-llama.sh, I found that the python script is not executed, 
# So I add the python path to the script.

set -euo pipefail
IFS=$'\n\t'

# ── Config ────────────────────────────────────────────────────────────────────
DEFAULT_REPLACE_FILE="${HOME}/.config/push-replace/replace.txt"
REPLACE_FILE="${REPLACE_FILE:-$DEFAULT_REPLACE_FILE}"
COMMIT_MESSAGE=""
DRY_RUN=0
SED_SCRIPT=""
COMMIT_FILE=""

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
PYTHON=/Users/lex/python/openai/bin/python3

find_free_port() {
    $PYTHON - <<'PYEOF'
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

    # 构建 chat 格式 prompt（纯英文，避免编码问题）
    local system_prompt="You are an expert git commit message writer. Write professional, clear commit messages following conventional commits format."
    local user_prompt="${hint_line}Branch: ${branch}
Stats: +${insertions}/-${deletions} lines

Changed files:
${file_list}
Diff summary:
${diff_text:0:1500}

Write a concise commit message body with 2-4 bullet points explaining what changed and why. Focus on the purpose and impact of the changes."

    # 全部由 Python 完成：构建 payload → HTTP POST → 解析响应
    # 避免 curl + 环境变量传递的 ordering 问题，同时打印原始响应到 stderr 方便调试
    local msg
    msg=$(LLAMA_BASE_URL="${base_url}" \
          LLAMA_HINT_LINE="${hint_line}" \
          LLAMA_BRANCH="${branch}" \
          LLAMA_INSERTIONS="${insertions}" \
          LLAMA_DELETIONS="${deletions}" \
          LLAMA_FILE_LIST="${file_list}" \
          LLAMA_DIFF_TEXT="${diff_text:0:1500}" \
          LLAMA_HTTP_TIMEOUT="${LLAMA_HTTP_TIMEOUT}" \
          $PYTHON - <<'PYEOF'
import json, sys, os, urllib.request, urllib.error

base_url       = os.environ['LLAMA_BASE_URL']
hint_line      = os.environ.get('LLAMA_HINT_LINE', '')
branch         = os.environ.get('LLAMA_BRANCH', '')
insertions     = os.environ.get('LLAMA_INSERTIONS', '0')
deletions      = os.environ.get('LLAMA_DELETIONS', '0')
file_list      = os.environ.get('LLAMA_FILE_LIST', '')
diff_text      = os.environ.get('LLAMA_DIFF_TEXT', '')
timeout        = int(os.environ.get('LLAMA_HTTP_TIMEOUT', '120'))

user_prompt = (
    f"{hint_line}Branch: {branch}\n"
    f"Stats: +{insertions}/-{deletions} lines\n\n"
    f"Changed files:\n{file_list}\n"
    f"Diff summary:\n{diff_text}\n\n"
    "Write a concise commit message body with 2-4 bullet points explaining "
    "what changed and why. Focus on the purpose and impact of the changes."
)

payload = json.dumps({
    "model": "gemma-3-1b-it",
    "messages": [
        {"role": "system", "content": "You are an expert git commit message writer. "
                                      "Write professional, clear commit messages "
                                      "following conventional commits format."},
        {"role": "user", "content": user_prompt},
    ],
    "temperature": 0.3,
    "max_tokens": 400,
    "stream": False,
}).encode('utf-8')

url = f"{base_url}/v1/chat/completions"
req = urllib.request.Request(url, data=payload,
                             headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode('utf-8').strip()
except urllib.error.URLError as e:
    print(f"HTTP error: {e}", file=sys.stderr)
    sys.exit(1)

if not raw:
    sys.exit(1)

try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"JSON parse error: {e}", file=sys.stderr)
    sys.exit(1)

# 兼容 OpenAI chat completions 格式
content = (data.get("choices") or [{}])[0].get("message", {}).get("content", "")
if not content:
    # 某些 llama-server 版本直接返回 {"content": "..."}
    content = data.get("content", "")

content = content.strip()
if not content:
    sys.exit(1)
print(content)
PYEOF
) || return 1

    [[ -n "$msg" ]] || return 1
    printf '%s' "$msg"
}

# ── AI Body Sanitizer ──────────────────────────────────────────────────────────
#
# gemma-3-1b-it 在 "write a concise body" 这个指令下的典型输出（实测 24 行）：
#   1  Okay, here's a commit message, following the conventional commit format...
#   3  ```
#   4  feat: Deploy Strategy - Default Node Pool Deployment     ← 自己编的主题行
#   6  This commit updates the `xxx.md` file to reflect...
#   8  *   **Default Deployment...:**  We've implemented...
#  12  ```
#  14  **Explanation of Choices & Why This Works:**
#  16  *   **`feat:` Prefix:**  Using `feat:` is standard...
#  24  Would you like me to refine this further, perhaps by...
#
# 所以 sanitizer 不是「删几行」，而是「按结构提取 bullet 段」。
# 策略：优先取围栏代码块内的内容（那里的 bullet 才是正文）；
# 找不到围栏时，退而取第一组连续的 * / - bullet。

sanitize_ai_body() {
    local raw="$1"

    # 1) 归一化：去掉 Windows 换行、去掉每行行尾空白
    raw="${raw//$'\r'/}"
    local line
    local -a lines=()
    while IFS= read -r line; do
        lines+=("${line%"${line##*[![:space:]]}"}")
    done <<< "$raw"

    local -a out=()
    local i n=${#lines[@]}

    # 2) 定位 markdown 围栏代码块（取第一个有 bullet 的块）
    # 正则放变量：[[ ]] 内联反引号在 bash 3.2 下解析不可靠
    local re_fence_open='^[[:space:]]*`{3}'
    local fence_open=-1 fence_close=-1
    local depth=0
    for ((i = 0; i < n; i++)); do
        if [[ "${lines[i]}" =~ $re_fence_open ]]; then
            if (( depth == 0 )); then
                fence_open=$i
                depth=1
            else
                fence_close=$i
                break
            fi
        fi
    done

    local -a candidates=()
    if (( fence_open >= 0 && fence_close > fence_open )); then
        candidates=( "${lines[@]:$((fence_open+1)):$((fence_close-fence_open-1))}" )
    else
        candidates=( "${lines[@]}" )
    fi

    # 3) 从候选里截取「第一段连续 bullet」—— 即模型真正写的正文
    #    起点：第一个以 * / - / + 开头的行
    #    终点：下一个非 bullet 的非空行（含小标题 / 解释段）
    local in_bullets=0
    for line in "${candidates[@]}"; do
        if [[ "$line" =~ ^[[:space:]]*([-*+])[[:space:]]+ ]]; then
            in_bullets=1
            out+=("$(normalize_bullet "$line")")
        elif (( in_bullets == 1 )); then
            # 允许 bullet 之间的空行与续行（缩进）
            if [[ -z "${line// /}" ]]; then
                out+=("")
            elif [[ "$line" =~ ^[[:space:]]{2,} ]]; then
                out+=("${line#"${line%%[![:space:]]*}"}")
            else
                break   # 遇到新段落 = bullet 段结束
            fi
        elif [[ -z "${line//[[:space:]]/}" ]]; then
            continue  # bullet 之前的空行直接丢
        else
            # bullet 之前遇到实质内容（模型的开场白 / feat: 主题行），跳过它继续找
            continue
        fi
    done

    # 4) 兜底：整段没有 bullet 时，取模型的第一段实质文本并强制转成 bullet
    if [[ ${#out[@]} -eq 0 ]]; then
        # 注意：正则放变量，不要直接写在 [[ =~ ]] 里。
        # bash 3.2（macOS 自带）在 [[ ]] 内解析含 ! 与分组的正则会报语法错。
        local re_fence='^[[:space:]]*```'
        local re_subject='^[[:space:]]*(feat|fix|docs|chore|refactor|style|test|ci|build|perf|revert)(\([a-z0-9/_.-]+\))?(!)?:[[:space:]]'
        local re_meta='(Explanation of Choices|Justification|Why This|Why this|Here is a commit message|here is a commit message)'
        # 开场白模式要宽：模型会写 Okay/ Sure / Certainly / Below 等各种变体，
        # 且不一定在行首（可能带 markdown 强调符号）。
        local re_chat='^[[:space:]]*[*_#>[:space:]]*(okay|ok|sure|certainly|absolutely|below|here|alright|great|excellent|of course|i (h|ha)ve)[[:space:]]'
        local started=0
        for line in "${candidates[@]}"; do
            # 跳过开场白、主题行、围栏、小标题
            [[ -z "${line//[[:space:]]/}" ]] && continue
            [[ "$line" =~ $re_fence ]] && continue
            [[ "$line" =~ $re_subject ]] && continue
            [[ "$line" =~ $re_meta ]] && continue
            [[ "$line" =~ $re_chat ]] && continue
            started=1
            out+=("- $line")
            [[ ${#out[@]} -ge 4 ]] && break
        done
        [[ $started -eq 0 ]] && return 1
    fi

    # 5) 去除常见的 LLM 元评论尾巴（"Would you like me to..."）
    local re_tail='^[[:space:]]*(Would you like|Let me know if|I hope this|Feel free to|If you)'
    local -a clean=()
    for line in "${out[@]}"; do
        [[ "$line" =~ $re_tail ]] && continue
        clean+=("$line")
    done

    # 6) 压缩连续空行 + 限制最多 6 条 bullet
    local -a final=()
    local bullets=0 prev_blank=1
    for line in "${clean[@]}"; do
        if [[ -z "${line//[[:space:]]/}" ]]; then
            [[ $prev_blank -eq 0 ]] && final+=("")
            prev_blank=1
            continue
        fi
        prev_blank=0
        if [[ "$line" =~ ^- ]]; then
            bullets=$((bullets + 1))
            (( bullets > 6 )) && break
        fi
        final+=("$line")
    done
    # 去掉尾部空行
    while [[ ${#final[@]} -gt 0 && -z "${final[-1]// /}" ]]; do
        unset 'final[-1]'
    done

    [[ ${#final[@]} -eq 0 ]] && return 1
    printf '%s\n' "${final[@]}"
}

# 把 * / + / - 开头统一成 "- "
# 注意：模型常输出 "*   **Bold:** text"（星号后多个空格），
# 只剥一个空格会留下 "- *   **..." 双前缀，所以要用 [[:space:]]+ 剥净。
normalize_bullet() {
    local l="$1"
    l="${l#"${l%%[![:space:]]*}"}"                 # 去行首空白
    l="${l#[-+*]}"                                   # 去掉一个列表符号
    l="${l#"${l%%[![:space:]]*}"}"                 # 去符号后的空白
    printf '%s' "- $l"
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