tree
```bash
find . -print | sed -e 's;[^/]*/;|____;g;s;____|; |;g'
进阶版（排除隐藏文件/目录，如 .git 或 node_modules）：
find . -maxdepth 3 -not -path '*/.*' | sed -e 's;[^/]*/;|____;g;s;____|; |;g'

alias tree="find . -print | sed -e 's;[^/]*/;|____;g' -e 's;____|; |;g'"
```

./gh-weekly-dashboard.sh
```bash
#!/bin/zsh
# ============================================================================
# gh-weekly-dashboard.sh — GitHub Weekly Activity Dashboard (beautified v2)
# ============================================================================
# Generates a colorful, Unicode-boxed dashboard for the last 7 days of
# activity on any GitHub repository. Output goes to stdout (terminal-direct).
#
# Usage:
#   ./gh-weekly-dashboard.sh                           # auto-detect current repo
#   ./gh-weekly-dashboard.sh owner/repo                # specific repo
#   ./gh-weekly-dashboard.sh owner/repo md             # filter by file extension
#
# Prerequisites:
#   - gh (GitHub CLI) authenticated with repo scope
#   - jq
#
# Author: project Lead (with architect-gcp design assist)
# Date:   2026-09-26
# ============================================================================

# ---- ANSI color codes (zsh requires $'...' to interpret escape sequences) ----
BOLD_CYAN=$'\033[1;36m'
BOLD_YELLOW=$'\033[1;33m'
BOLD_GREEN=$'\033[1;32m'
BOLD_RED=$'\033[1;31m'
BOLD_MAGENTA=$'\033[1;35m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# ---- Unicode box drawing ----
BOX_TL="╭"; BOX_TR="╮"; BOX_BL="╰"; BOX_BR="╯"
BOX_H="─"; BOX_V="│"
TITLE_TL="╔"; TITLE_TR="╗"; TITLE_BL="╚"; TITLE_BR="╝"
TITLE_H="═"; TITLE_V="║"

# ---- Parse arguments ----
REPO="${1:-}"
FILE_EXT="${2:-}"   # optional: filter by file extension (md / yaml / etc.)

if [ -z "$REPO" ]; then
    # Auto-detect from current directory
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    if [ -z "$REPO" ]; then
        echo "${BOLD_RED}❌ Error: please specify a repo, e.g. ./gh-weekly-dashboard.sh owner/repo${RESET}"
        exit 1
    fi
fi

# ---- Compute "since" timestamp (7 days ago, UTC) ----
if [[ "$OSTYPE" == "darwin"* ]]; then
    SINCE_DATE=$(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ')
else
    SINCE_DATE=$(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ')
fi

# ---- Print title box ----
TODAY=$(date -u '+%Y-%m-%d')
WEEK_AGO=$(date -u -v-7d '+%m-%d' 2>/dev/null || date -u -d '7 days ago' '+%m-%d')

echo "${BOLD_CYAN}${TITLE_TL}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_TR}${RESET}"
echo "${BOLD_CYAN}${TITLE_V}${RESET} 📊 GitHub Weekly Dashboard : ${BOLD_YELLOW}$REPO${RESET}"
echo "${BOLD_CYAN}${TITLE_V}${RESET} ⏳ Period: ${DIM}${WEEK_AGO} → ${TODAY}${RESET} ${DIM}(last 7 days, UTC)${RESET}"
echo "${BOLD_CYAN}${TITLE_BL}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_H}${TITLE_BR}${RESET}"
echo ""

# ---- Fetch commits ----
COMMITS_JSON=$(gh api "repos/$REPO/commits?since=$SINCE_DATE&per_page=100" \
    --jq '[.[] | {date: (.commit.committer.date | split("T")[0]),
                  author: (.author.login // .commit.author.email // "unknown"),
                  message: (.commit.message | split("\n")[0])}]' 2>/dev/null)

if [ -z "$COMMITS_JSON" ]; then
    printf "%s❌ Failed to fetch data. Please check gh login status and repo permissions.%s\n" \
        "${BOLD_RED}" "${RESET}"
    exit 2
fi

TOTAL_COMMITS=$(echo "$COMMITS_JSON" | jq 'length')

# ---- Optional: file-extension filter hint ----
if [ -n "$FILE_EXT" ]; then
    echo "${DIM}💡 Note: file-extension filter is metadata-only (full per-file fetch requires N extra API calls)${RESET}"
    echo ""
fi

# ---- Fetch PRs ----
PRS_JSON=$(gh api "repos/$REPO/pulls?state=all&per_page=100" \
    --jq '[.[] | select(.created_at >= "'"$SINCE_DATE"'" or .merged_at >= "'"$SINCE_DATE"'" or .closed_at >= "'"$SINCE_DATE"'") | {state: .state, merged: (.merged_at != null)}]' 2>/dev/null)
PRS_OPENED=$(echo "$PRS_JSON" | jq 'length')
PRS_MERGED=$(echo "$PRS_JSON" | jq '[.[] | select(.merged == true)] | length')

# ---- Fetch Issues (excluding PRs) ----
ISSUES_JSON=$(gh api "repos/$REPO/issues?state=all&per_page=100&since=$SINCE_DATE" \
    --jq '[.[] | select(.pull_request == null) | {state: .state}]' 2>/dev/null)
ISSUES_OPENED=$(echo "$ISSUES_JSON" | jq 'length')
ISSUES_CLOSED=$(echo "$ISSUES_JSON" | jq '[.[] | select(.state == "closed")] | length')

ACTIVE_CONTRIBUTORS=$(echo "$COMMITS_JSON" | jq -r '[.author] | unique | length')

# ---- Compute ratios (guard against divide-by-zero) ----
if [ "$PRS_OPENED" -gt 0 ] 2>/dev/null; then
    PR_MERGE_RATE=$(echo "scale=0; $PRS_MERGED * 100 / $PRS_OPENED" | bc 2>/dev/null || echo "0")
else
    PR_MERGE_RATE="0"
fi
if [ "$ISSUES_OPENED" -gt 0 ] 2>/dev/null; then
    ISSUE_CLOSE_RATE=$(echo "scale=0; $ISSUES_CLOSED * 100 / $ISSUES_OPENED" | bc 2>/dev/null || echo "0")
else
    ISSUE_CLOSE_RATE="0"
fi

# ---- Block 1: Core Metrics ----
echo "${BOLD_CYAN}${BOX_TL}${BOX_H} ${BOLD_YELLOW}📈 Core Metrics${RESET}${BOLD_CYAN} ${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${RESET}"
echo "${BOLD_CYAN}${BOX_V}${RESET} Total commits          : ${BOLD_YELLOW}$TOTAL_COMMITS${RESET}"
echo "${BOLD_CYAN}${BOX_V}${RESET} PRs opened / merged    : ${BOLD_YELLOW}$PRS_OPENED${RESET} / ${BOLD_GREEN}$PRS_MERGED${RESET} ${DIM}(${PR_MERGE_RATE}% merge rate)${RESET}"
echo "${BOLD_CYAN}${BOX_V}${RESET} Issues opened / closed : ${BOLD_YELLOW}$ISSUES_OPENED${RESET} / ${BOLD_GREEN}$ISSUES_CLOSED${RESET} ${DIM}(${ISSUE_CLOSE_RATE}% close rate)${RESET}"
echo "${BOLD_CYAN}${BOX_V}${RESET} Active contributors    : ${BOLD_YELLOW}$ACTIVE_CONTRIBUTORS${RESET}"
echo "${BOLD_CYAN}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${RESET}"
echo ""

# ---- Block 2: Daily Activity ----
echo "${BOLD_CYAN}${BOX_TL}${BOX_H} ${BOLD_YELLOW}📅 Daily Activity${RESET}${BOLD_CYAN} ${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${RESET}"

echo "$COMMITS_JSON" | jq -r '
    group_by(.date) |
    map({date: .[0].date, count: length}) |
    sort_by(.date) |
    .[] | "\(.date)|\(.count)"
' | while IFS='|' read -r commit_date count; do
    count=$(echo "$count" | tr -d ' ')

    weekday=$(date -j -f '%Y-%m-%d' "$commit_date" '+%a' 2>/dev/null \
           || date -d "$commit_date" '+%a' 2>/dev/null \
           || echo "?")

    bar=""
    for ((i = 0; i < count; i++)); do
        bar="${bar}█"
    done
    while [ ${#bar} -lt 20 ]; do
        bar="${bar} "
    done

    if [ "$count" -ge 10 ]; then
        level="${BOLD_GREEN}🟢 peak    ${RESET}"
    elif [ "$count" -ge 8 ]; then
        level="${BOLD_GREEN}🟢 active  ${RESET}"
    elif [ "$count" -ge 3 ]; then
        level="${BOLD_YELLOW}🟡 normal  ${RESET}"
    elif [ "$count" -ge 1 ]; then
        level="${BOLD_RED}🔴 quiet   ${RESET}"
    else
        level="${DIM}⚪ off-day  ${RESET}"
    fi

    printf "${BOLD_CYAN}${BOX_V}${RESET} %s %s ${BOLD_YELLOW}%2s${RESET} ${BOLD_CYAN}${BOX_V}${RESET} %s ${BOLD_CYAN}${BOX_V}${RESET} %s\n" \
        "$weekday" "$commit_date" "$count" "$bar" "$level"
done

echo "${BOLD_CYAN}${BOX_V}${RESET} ${DIM}Chart key: ▁ 1-2  ▃ 3-4  ▅ 5-6  ▇ 7-9  █ 10+${RESET}"
echo "${BOLD_CYAN}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${RESET}"
echo ""

# ---- Block 3: Top Contributors ----
echo "${BOLD_CYAN}${BOX_TL}${BOX_H} ${BOLD_YELLOW}👥 Top Contributors${RESET}${BOLD_CYAN} ${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${RESET}"

RANK=0
echo "$COMMITS_JSON" | jq -r '
    group_by(.author) |
    map({author: .[0].author, count: length}) |
    sort_by(.count) | reverse |
    .[0:5] | .[] | "\(.author)|\(.count)"
' | while IFS='|' read -r author c; do
    RANK=$((RANK + 1))
    c=$(echo "$c" | tr -d ' ')

    bar=""
    for ((i = 0; i < c; i++)); do
        bar="${bar}█"
    done
    while [ ${#bar} -lt 20 ]; do
        bar="${bar} "
    done

    pct=$(echo "scale=0; $c * 100 / $TOTAL_COMMITS" | bc 2>/dev/null || echo "0")
    medal=""
    [ "$RANK" -eq 1 ] && medal=" 🏆"
    printf "${BOLD_CYAN}${BOX_V}${RESET} ${BOLD_YELLOW}%d.${RESET} %-12s ${BOLD_CYAN}${BOX_V}${RESET} ${BOLD_GREEN}%s${RESET} ${BOLD_YELLOW}%2d${RESET} commits ${DIM}(%s%%)${RESET}${medal}\n" \
        "$RANK" "$author" "$bar" "$c" "$pct"
done

echo "${BOLD_CYAN}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${RESET}"
echo ""

# ---- Block 4: Commit Message Hot Words ----
echo "${BOLD_CYAN}${BOX_TL}${BOX_H} ${BOLD_YELLOW}💬 Commit Message Hot Words (top 10)${RESET}${BOLD_CYAN} ${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${RESET}"

echo "$COMMITS_JSON" | jq -r '
    .[].message | split(" ")[0] | ascii_downcase
' | sort | uniq -c | sort -rn | head -10 | while read -r count word; do
    word=$(echo "$word" | tr -d '\r')
    bar=""
    for ((i = 0; i < count; i++)); do
        bar="${bar}█"
    done
    printf "${BOLD_CYAN}${BOX_V}${RESET} %-12s ${BOLD_CYAN}${BOX_V}${RESET} ${BOLD_MAGENTA}%s${RESET} ${BOLD_YELLOW}%2d${RESET}\n" "$word" "$bar" "$count"
done

echo "${BOLD_CYAN}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${RESET}"
echo ""

echo "${DIM}💡 Tip: filter by file extension:${RESET} ${BOLD_YELLOW}./gh-weekly-dashboard.sh owner/repo md${RESET}"
printf "%s💡 Tip: strip colors for CI / email:%s %s./gh-weekly-dashboard.sh owner/repo | sed 's/\\x1b\\[[0-9;]*m//g'%s\n" \
    "${DIM}" "${RESET}" "${BOLD_YELLOW}" "${RESET}"
echo ""%
```