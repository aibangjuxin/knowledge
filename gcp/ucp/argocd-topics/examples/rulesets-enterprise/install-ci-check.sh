#!/usr/bin/env bash
# =============================================================================
#  install-ci-check.sh（企业版）—— 把可选的 CI 兜底装进**多个**仓库
# -----------------------------------------------------------------------------
#  **企业版 vs 个人版**
#    个人版：装 1 个仓库（--owner + --repo）
#    企业版：★ 一次装一批（按 profile 的仓库分层枚举），
#            或者只装给某一个分层（--tier standard）
#
#  ★ 先想清楚要不要装
#    企业版服务端已经有 commit_message_pattern（组织级 ruleset），
#    CI 只是**体验层**（把"ref 不更新"变成"PR 上一个红叉"）。
#    → 不装也能工作；装了更好用。
#
#  用法
#    ./install-ci-check.sh --tier standard          # 给 standard 层所有仓库装
#    ./install-ci-check.sh --repo my-repo           # 只装一个
#    ./install-ci-check.sh --tier standard --dry-run
#
#  前置
#    gh auth refresh -s workflow      # 没有这个 scope，GitHub 会拒绝创建 .github/workflows/
#
#  退出码：0 = 成功（PR 已开）；1 = 失败
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/workflows/cr-prefix-check.yaml"
PROFILE="$SCRIPT_DIR/enterprise-profile.yaml"

OWNER=""
REPO=""
TIER=""
BRANCH_PREFIX="codex/add-cr-prefix-ci"
TITLE="chore: add cr-prefix CI check"
DRY_RUN=0

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner)   OWNER="$2"; shift 2 ;;
    --repo)    REPO="$2"; shift 2 ;;
    --tier)    TIER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }

[[ -f "$SRC" ]] || fail "找不到 $SRC"
[[ -f "$PROFILE" ]] || fail "找不到 $PROFILE"

profile_get() {
  python3 - "$PROFILE" "$1" <<'PY' 2>/dev/null
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), "..", "lib"))
try:
    from yamlmin import load_file
except ImportError:
    print(""); sys.exit(0)
cur = load_file(sys.argv[1]) or {}
for part in sys.argv[2].split("."):
    if not isinstance(cur, dict) or part not in cur:
        print(""); sys.exit(0)
    cur = cur[part]
print(cur if not isinstance(cur, (list, tuple)) else "\n".join(map(str, cur)))
PY
}

OWNER="${OWNER:-$(profile_get org.name)}"
[[ -n "$OWNER" ]] || fail "profile 里没有 org.name"

if ! gh auth status 2>&1 | grep -q "'workflow'"; then
  echo "⚠️  当前 token 没有 workflow scope —— GitHub 会拒绝创建 .github/workflows/ 下的文件。"
  echo "   请先执行：  gh auth refresh -s workflow"
  exit 1
fi

# ── 决定要装哪些仓库 ───────────────────────────────────────────────────────
if [[ -n "$REPO" ]]; then
  REPOS="$REPO"
else
  [[ -n "$TIER" ]] || fail "必须给 --repo 或 --tier（standard / production / sandbox）"
  case "$TIER" in
    standard)   patterns="$(profile_get org.repos.standard)" ;;
    production) patterns="$(profile_get org.repos.production)" ;;
    sandbox)    patterns="$(profile_get org.repos.sandbox)" ;;
    *) fail "未知 tier：$TIER（standard / production / sandbox）" ;;
  esac
  REPOS="$(gh repo list "$OWNER" --limit 500 --json name --jq '.[].name' 2>/dev/null \
    | while IFS= read -r r; do
        [[ -z "$r" ]] && continue
        while IFS= read -r p; do
          [[ -z "$p" ]] && continue
          case "$r" in $p) echo "$r"; break ;; esac
        done <<< "$patterns"
      done)"
fi

[[ -n "$REPOS" ]] || fail "没有匹配到仓库"

B64="$(base64 < "$SRC" | tr -d '\n')"
FAILED=0

while IFS= read -r r; do
  [[ -z "$r" ]] && continue
  REPO_PATH="repos/$OWNER/$r"
  BRANCH="$BRANCH_PREFIX"
  echo
  echo "▸ $OWNER/$r"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  (dry-run) 会提交 .github/workflows/cr-prefix-check.yaml 到分支 $BRANCH 并开 PR"
    continue
  fi

  BASE_SHA="$(gh api "$REPO_PATH/branches/main" --jq .commit.sha 2>/dev/null)" \
    || { echo "  ⚠️ 读不到 main 的 SHA —— 跳过"; FAILED=1; continue; }

  if ! gh api -X POST "$REPO_PATH/git/refs" \
      --input <(printf '{"ref":"refs/heads/%s","sha":"%s"}' "$BRANCH" "$BASE_SHA") >/dev/null 2>&1; then
    ok "分支已存在：$BRANCH"
  else
    ok "已建分支：$BRANCH"
  fi

  if gh api -X PUT "$REPO_PATH/contents/.github/workflows/cr-prefix-check.yaml" \
       --input <(printf '{"message":"%s","content":"%s","branch":"%s"}' \
                 "$TITLE" "$B64" "$BRANCH") >/dev/null 2>&1; then
    ok "已提交 workflow"
  else
    echo "  （目录不存在，改用 Git Data API 建路径…）"
    BLOB_SHA="$(gh api -X POST "$REPO_PATH/git/blobs" \
        --input <(printf '{"content":"%s","encoding":"base64"}' "$B64") --jq .sha)" || { FAILED=1; continue; }
    TREE_SHA="$(gh api "$REPO_PATH/git/commits/$BASE_SHA" --jq .tree.sha)"
    NEW_TREE="$(gh api -X POST "$REPO_PATH/git/trees" \
        --input <(printf '{"base_tree":"%s","tree":[{"path":".github/workflows/cr-prefix-check.yaml","mode":"100644","type":"blob","sha":"%s"}]}' \
                  "$TREE_SHA" "$BLOB_SHA") --jq .sha)" || { FAILED=1; continue; }
    NEW_COMMIT="$(gh api -X POST "$REPO_PATH/git/commits" \
        --input <(printf '{"message":"%s","tree":"%s","parents":["%s"]}' \
                  "$TITLE" "$NEW_TREE" "$BASE_SHA") --jq .sha)" || { FAILED=1; continue; }
    gh api -X PATCH "$REPO_PATH/git/refs/heads/$BRANCH" \
        --input <(printf '{"sha":"%s","force":true}' "$NEW_COMMIT") >/dev/null || { FAILED=1; continue; }
    ok "已提交 workflow"
  fi

  EXISTING="$(gh api "$REPO_PATH/pulls" --jq "[.[]|select(.head.ref==\"$BRANCH\")]|.[0].number" 2>/dev/null)"
  if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
    ok "PR 已存在：#$EXISTING"
  else
    PR_URL="$(gh api -X POST "$REPO_PATH/pulls" \
      --input <(python3 -c '
import json,sys
print(json.dumps({"title":sys.argv[1],"head":sys.argv[2],"base":"main",
 "body":"可选的 CI 兜底：把 CR 前缀格式校验变成 PR 上的可见红叉。\n\n真正的权威门禁是组织级 ruleset 的 commit_message_pattern。"}))' \
        "$TITLE" "$BRANCH") --jq .html_url)" || { FAILED=1; continue; }
    ok "PR 已开：$PR_URL"
  fi
done <<< "$REPOS"

echo
if [[ $FAILED -ne 0 ]]; then
  echo "⚠️  部分仓库失败（见上）"
  exit 1
fi
ok "全部完成"
echo
echo "下一步："
echo "  1) 合并各仓库的 PR"
echo "  2) 决定是否把 cr-prefix 设成 required_status_checks"
echo "     ★ 企业版通常不需要（metadata 规则已强制），设为 required 只是多一道卡点"
