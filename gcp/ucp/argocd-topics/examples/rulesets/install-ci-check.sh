#!/usr/bin/env bash
# =============================================================================
#  install-ci-check.sh —— 把 commit message 校验的 GitHub Actions 装进仓库
# -----------------------------------------------------------------------------
#  **为什么需要它**
#  GitHub 的 `commit_message_pattern`（metadata 规则）只在 **Enterprise 组织**可用。
#  个人账号 / 非组织 / 非 Enterprise 计划上：
#      · API：422 Invalid rule 'commit_message_pattern'
#      · UI 导入：**静默丢弃** → ruleset 建出来了，但 `rules: []` → 什么都不拦
#  → 所以格式校验改由 **CI**（GitHub Actions）做，再通过 `required_status_checks` 强制。
#    这个能力**仓库级、所有计划都有**。
#
#  **前置：token 需要 workflow scope**
#      gh auth refresh -s workflow
#    （没有这个 scope，GitHub 会拒绝创建 .github/workflows/ 下的文件）
#
#  用法
#      ./install-ci-check.sh --owner <org> --repo <repo>
#      ./install-ci-check.sh --owner <org> --repo <repo> --title "CR100001 chore: xxx"
#
#  退出码：0 = 成功（PR 已开）；1 = 失败
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/workflows/cr-prefix-check.yaml"
REPO=""
OWNER=""
TITLE="CR100001 chore: add cr-prefix CI check"
BRANCH="codex/add-cr-prefix-ci"

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo)  REPO="$2";  shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✓ $*"; }

[[ -n "$OWNER" && -n "$REPO" ]] || fail "必须给 --owner 和 --repo"
[[ -f "$SRC" ]] || fail "找不到 $SRC"

# ── 0. 检查 token 有没有 workflow scope ─────────────────────────────────────
if ! gh auth status 2>&1 | grep -q "'workflow'"; then
  echo "⚠️  当前 token 没有 workflow scope —— GitHub 会拒绝创建 .github/workflows/ 下的文件。"
  echo "   请先执行：  gh auth refresh -s workflow"
  exit 1
fi

REPO_PATH="repos/$OWNER/$REPO"

# ── 1. 建分支 ───────────────────────────────────────────────────────────────
BASE_SHA="$(gh api "$REPO_PATH/branches/main" --jq .commit.sha)" || fail "读不到 main 的 SHA"
if gh api "$REPO_PATH/git/refs/heads/$BRANCH" >/dev/null 2>&1; then
  ok "分支已存在：$BRANCH"
else
  gh api -X POST "$REPO_PATH/git/refs" \
      --input <(printf '{"ref":"refs/heads/%s","sha":"%s"}' "$BRANCH" "$BASE_SHA") >/dev/null \
    || fail "建分支失败"
  ok "已建分支：$BRANCH"
fi

# ── 2. 提交 workflow 文件 ───────────────────────────────────────────────────
# 用 Contents API；它不会自动创建多级目录 → 先建 .github/workflows 目录树
# （用 Git Data API 建 tree，再回写 ref）
B64="$(base64 < "$SRC" | tr -d '\n')"

if gh api -X PUT "$REPO_PATH/contents/.github/workflows/cr-prefix-check.yaml" \
     --input <(printf '{"message":"%s","content":"%s","branch":"%s"}' \
               "$TITLE" "$B64" "$BRANCH") >/dev/null 2>&1; then
  ok "已提交 .github/workflows/cr-prefix-check.yaml"
else
  # 目录不存在 → 用 Git Data API 建整条路径
  echo "  （目录不存在，改用 Git Data API 建路径…）"
  BLOB_SHA="$(gh api -X POST "$REPO_PATH/git/blobs" \
      --input <(printf '{"content":"%s","encoding":"base64"}' "$B64") --jq .sha)"
  TREE_SHA="$(gh api "$REPO_PATH/git/commits/$BASE_SHA" --jq .tree.sha)"
  NEW_TREE="$(gh api -X POST "$REPO_PATH/git/trees" \
      --input <(printf '{"base_tree":"%s","tree":[{"path":".github/workflows/cr-prefix-check.yaml","mode":"100644","type":"blob","sha":"%s"}]}' \
                "$TREE_SHA" "$BLOB_SHA") --jq .sha)" || fail "建 tree 失败"
  NEW_COMMIT="$(gh api -X POST "$REPO_PATH/git/commits" \
      --input <(printf '{"message":"%s","tree":"%s","parents":["%s"]}' \
                "$TITLE" "$NEW_TREE" "$BASE_SHA") --jq .sha)" || fail "建 commit 失败"
  gh api -X PATCH "$REPO_PATH/git/refs/heads/$BRANCH" \
      --input <(printf '{"sha":"%s","force":true}' "$NEW_COMMIT") >/dev/null || fail "更新分支失败"
  ok "已提交 .github/workflows/cr-prefix-check.yaml"
fi

# ── 3. 开 PR ────────────────────────────────────────────────────────────────
EXISTING="$(gh api "$REPO_PATH/pulls" --jq "[.[]|select(.head.ref==\"$BRANCH\")]|.[0].number" 2>/dev/null)"
if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
  ok "PR 已存在：#$EXISTING"
  PR_URL="$(gh api "$REPO_PATH/pulls/$EXISTING" --jq .html_url)"
else
  PR_URL="$(gh api -X POST "$REPO_PATH/pulls" \
      --input <(python3 -c '
import json,sys
title=sys.argv[1]; head=sys.argv[2]; base=sys.argv[3]
body = """用 GitHub Actions 校验 commit message / PR 标题格式。

**为什么用 CI 而不是 Ruleset 的 `commit_message_pattern`**：
metadata 规则只在 Enterprise 组织可用；个人账号上 API 直接 422，
UI 导入还会**静默丢弃**（ruleset 建出来但 `rules` 是空的 → 什么都不拦）。

这个 workflow 产生的 status check 名字是 `cr-prefix`，
已被 `main-branch-guard` / `dev-branch-guard` 两条 ruleset 引用。

合并后打开强制（★ PUT 是全量替换，必须带完整 payload）：

```bash
cd examples/rulesets
./apply-rulesets.sh --owner <owner> --repo <repo> \\
    --enforcement active --only main-branch-guard
```
"""
print(json.dumps({"title":title,"head":head,"base":base,"body":body}))' \
      "$TITLE" "$BRANCH" "main") \
      --jq .html_url)" || fail "开 PR 失败"
  ok "PR 已开：$PR_URL"
fi

cat <<EOF

下一步：
  1) 合并 PR（合并后 `cr-prefix` 这个 check 才会出现在 PR 上）
  2) 打开强制：
       cd examples/rulesets
       ./apply-rulesets.sh --owner $OWNER --repo $REPO \\
           --enforcement active --only main-branch-guard
       ./apply-rulesets.sh --owner $OWNER --repo $REPO \\
           --enforcement active --only dev-branch-guard
  3) 验证：
       gh api repos/$OWNER/$REPO/rules/branches/main | jq -r '.[].type'
EOF
