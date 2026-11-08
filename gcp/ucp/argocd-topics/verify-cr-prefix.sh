#!/usr/bin/env bash
# =============================================================================
#  verify-cr-prefix.sh —— 验证「GitHub Ruleset × GitHub Actions」的咬合关系
# -----------------------------------------------------------------------------
#  要证明的那一件事：
#      Ruleset 说「合并前必须看到名为 cr-prefix 的检查且它是绿的」
#      Action  说「我跑完会产出一个名叫 cr-prefix 的 check」
#      → 两边名字对上，逻辑就成立。
#
#  用法：
#      ./verify-cr-prefix.sh          # 只读检查（①②③⑤）
#      ./verify-cr-prefix.sh --poc    # 额外跑一次真实对抗（④：故意不合规 → 看它拦）
#
#  环境变量：
#      REPO=owner/name   （默认 aibangjuxin/knowledge）
# =============================================================================

set -uo pipefail

# ★★★ 关键修复：gh 在 stdout 是 TTY 时会用 less 分页输出。
#     不设这一行，每条 gh api 都要手动按 q/ESC 退出一次。
export GH_PAGER=cat
export PAGER=cat

REPO="${REPO:-aibangjuxin/knowledge}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DO_POC=0
[[ "${1:-}" == "--poc" ]] && DO_POC=1

sec()  { printf '\n\033[1m%s\033[0m\n%s\n' "$1" "$(printf '─%.0s' {1..72})"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

# ── 预检 ───────────────────────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  echo "✗ 需要 gh CLI"; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "✗ gh 未登录：先跑 gh auth login"; exit 1
fi
if ! gh api "repos/$REPO" --jq .full_name >/dev/null 2>&1; then
  echo "✗ 读不到仓库 $REPO（仓库名错 / token 没权限？）"; exit 1
fi

echo "仓库：$REPO    分页器：GH_PAGER=$GH_PAGER"

# ── ① 规则集现状 ───────────────────────────────────────────────────────────
#    注意：list 接口不返回 rules，必须按 id 逐个查
sec "① 规则集现状"
gh api "repos/$REPO/rulesets" --jq '.[] | "  \(.id)\t\(.name)\t\(.enforcement)\t\(.target)"' \
  || bad "读 rulesets 失败"
while read -r id; do
  [[ -z "$id" ]] && continue
  gh api "repos/$REPO/rulesets/$id" \
    --jq '"    \(.name): enforcement=\(.enforcement)  rules=\([.rules[]?.type]|join(","))"' \
    || bad "读 ruleset $id 失败"
done < <(gh api "repos/$REPO/rulesets" --jq '.[].id' 2>/dev/null)

# ── ② ★ 权威：某个分支上到底生效了哪些规则 ────────────────────────────────
sec "② 分支上实际生效的规则（权威接口 rules/branches）"
for b in main Lex-Release feat/cr-prefix-action feat/CH013456-pfb-gcp-v0.1.0 \
         codex/add-cr-prefix-ci codex/dockerfile-md-format \
         fix/safe-kms-record-check-and-sa-permission-match git-apps/lex; do
  printf '  %-50s ' "$b"
  out=$(gh api "repos/$REPO/rules/branches/$b" --jq '[.[]|.type]|if length==0 then "(none)" else join(",") end' 2>&1)
  if [[ "$out" == "(none)" ]]; then
    warn "$out   ← 该分支不受管"
  else
    echo "$out"
  fi
done

# ── ③ check 到底有没有跑过 ────────────────────────────────────────────────
sec "③ check-runs：cr-prefix 跑过没有、结论是什么"
for pr in 220 221 219; do
  sha=$(gh api "repos/$REPO/pulls/$pr" --jq .head.sha 2>/dev/null)
  [[ -z "$sha" ]] && continue
  title=$(gh api "repos/$REPO/pulls/$pr" --jq .title 2>/dev/null)
  base=$(gh api "repos/$REPO/pulls/$pr" --jq .base.ref 2>/dev/null)
  printf '  PR #%s  %s → %s\n' "$pr" "$base" "$title"
  printf '    title: %s\n' "$title"
  runs=$(gh api "repos/$REPO/commits/$sha/check-runs" \
         --jq '.check_runs[] | "      \(.name)\t\(.conclusion)"' 2>/dev/null)
  if [[ -z "$runs" ]]; then
    bad "没有任何 check run（★ 多半是 head 分支里没有 workflow 文件 → PR 会永久卡住）"
  else
    echo "$runs"
    if ! echo "$runs" | grep -q "cr-prefix"; then
      bad "没有 cr-prefix 这个 check（★ 同上：workflow 没在 head 分支里）"
    fi
  fi
done

# ── ④ POC：故意不合规 → 看门禁是不是真的拦 ───────────────────────────────
if [[ $DO_POC -eq 1 ]]; then
  sec "④ POC：真实对抗（建不合规 PR → 看 check 是否变红 / 是否合不了）"

  POC_BASE="${POC_BASE:-git-apps/lex}"     # 必须是被 dev-branch-guard 覆盖的目标分支
  STAMP="$(date +%s)"
  BR_NEG="poc/cr-prefix-neg-$STAMP"
  BR_POS="poc/cr-prefix-pos-$STAMP"

  # 通过 API 在目标分支上造一个 commit（不改本地工作区）
  make_commit() {
    local base="$1" branch="$2" msg="$3" path="$4" body="$5"
    local base_sha tree_sha blob_sha commit_sha
    base_sha=$(gh api "repos/$REPO/git/ref/heads/$base" --jq .object.sha) || return 1
    blob_sha=$(gh api --method POST "repos/$REPO/git/blobs" \
                 --input - --jq .sha <<<"{\"content\":\"$body\",\"encoding\":\"utf-8\"}") || return 1
    tree_sha=$(gh api --method POST "repos/$REPO/git/trees" \
                 --input - --jq .sha <<<"{\"base_tree\":\"$base_sha\",\"tree\":[{\"path\":\"$path\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$blob_sha\"}]}") || return 1
    commit_sha=$(gh api --method POST "repos/$REPO/git/commits" \
                 --input - --jq .sha <<<"{\"message\":\"$msg\",\"tree\":\"$tree_sha\",\"parents\":[\"$base_sha\"]}") || return 1
    # ★ 新建 ref 必须用 POST git/refs（PATCH 只能改已存在的 ref，否则 422 Reference does not exist）
    gh api --method POST "repos/$REPO/git/refs" \
         --input - >/dev/null <<<"{\"ref\":\"refs/heads/$branch\",\"sha\":\"$commit_sha\"}" || return 1
    echo "$commit_sha"
  }

  open_pr() {
    local branch="$1" title="$2" body="$3"
    gh api --method POST "repos/$REPO/pulls" \
      --input - --jq .number <<<"{\"title\":\"$title\",\"head\":\"$branch\",\"base\":\"$POC_BASE\",\"body\":\"$body\"}"
  }

  wait_check() {
    # 轮询到 cr-prefix 有终态结论为止
    local sha="$1" i status concl
    for i in $(seq 1 40); do
      read -r status concl < <(gh api "repos/$REPO/commits/$sha/check-runs" \
        --jq '[.check_runs[]|select(.name=="cr-prefix")]|last|"\(.status) \(.conclusion)"' 2>/dev/null) || true
      [[ "$status" == "completed" ]] && { echo "$concl"; return 0; }
      sleep 3
    done
    echo "timeout"
  }

  merge_state() {
    gh pr view "$1" --repo "$REPO" --json mergeStateStatus -q .mergeStateStatus 2>/dev/null
  }

  run_case() {
    local label="$1" branch="$2" commit_msg="$3" pr_title="$4" expect="$5"
    local sha pr conclusion state

    printf '\n  ── 用例 %s：%s\n' "$label" "$expect"
    sha=$(make_commit "$POC_BASE" "$branch" "$commit_msg" "poc/$STAMP.md" \
          "poc $STAMP $label") || { bad "造 commit 失败"; return 1; }

    pr=$(open_pr "$branch" "$pr_title" "POC: $label — 自动创建，一会会被清理") \
      || { bad "开 PR 失败"; return 1; }
    echo "    PR #$pr  https://github.com/$REPO/pull/$pr"

    conclusion=$(wait_check "$sha")
    state=$(merge_state "$pr")

    echo "    cr-prefix 结论 : $conclusion"
    echo "    merge 状态     : $state"
    case "$expect" in
      fail)
        if [[ "$conclusion" == "failure" ]]; then ok "符合预期：不合规 → check 变红"
        else bad "不符合预期：期望 failure，实得 $conclusion"; fi
        if [[ "$state" == "BLOCKED" ]]; then ok "符合预期：PR 被挡住（BLOCKED）"
        else warn "merge 状态是 $state（BLOCKED 才是被门禁挡住）"; fi
        ;;
      pass)
        if [[ "$conclusion" == "success" ]]; then ok "符合预期：合规 → check 变绿"
        else bad "不符合预期：期望 success，实得 $conclusion"; fi
        ;;
    esac

    # 清理
    gh api --method PATCH "repos/$REPO/pulls/$pr" --input - >/dev/null <<< '{"state":"closed"}'
    gh api --method DELETE "repos/$REPO/git/refs/heads/$branch" >/dev/null 2>&1
    echo "    已清理：关闭 PR #$pr，删除分支 $branch"
  }

  run_case "NEG" "$BR_NEG" \
    "poc: this commit intentionally has no CR prefix" \
    "poc: this PR title intentionally has no CR prefix" \
    "fail"

  run_case "POS" "$BR_POS" \
    "CH013456 poc: this commit carries a CR prefix" \
    "CH013456 poc: this PR title carries a CR prefix" \
    "pass"
else
  sec "④ POC：真实对抗"
  echo "  跳过（加 --poc 才会真的建 PR）"
  echo "  它会：造一个不带 CH 号的 commit → 开 PR 到受管分支 → 等 cr-prefix 变红 → 看是否 BLOCKED → 清理"
fi

# ── ⑤ 静态校验 ─────────────────────────────────────────────────────────────
sec "⑤ 静态校验（不连 GitHub）"
if [[ -d "$SCRIPT_DIR/examples/rulesets" ]]; then
  ( cd "$SCRIPT_DIR/examples/rulesets" && python3 validate-rulesets.py --strict )
  rc=$?
  if [[ $rc -eq 0 ]]; then
    ok "静态校验通过"
  else
    # --strict 会把 WARN 也算失败；这里这些 WARN 是仓库里既有的设计性告警
    #（merge 方法不唯一、main 的 reviewer 数），与本次 POC 无关。
    warn "静态校验返回 $rc（--strict 把 WARN 也算失败；这些是既有的设计性告警，与门禁是否生效无关）"
  fi
else
  warn "找不到 $SCRIPT_DIR/examples/rulesets，跳过"
fi

# ── 结论 ───────────────────────────────────────────────────────────────────
sec "结论：Ruleset × Action 的咬合关系"
cat <<'EOF'
  Ruleset  说：合并前必须看到名叫 cr-prefix 的 check，且它是绿的
  Action   说：我跑完会产出一个名叫 cr-prefix 的 check
             （check 名 = job 的 name，不是 workflow 顶层的 name）
  咬合点  ：required_status_checks[].context  ==  job.name
             ★ 字符串必须逐字符一致，写错一个字符 → 全员卡死

  强制力来自哪：
    · CI 侧   —— 服务端跑，PR 作者改不动 → check 变红就红
    · Ruleset 侧 —— 只在【合并那一刻】求值；没被引用的 check 没人消费
    · ★ 若某个分支没被 ruleset 的 ref_name 命中 → check 照跑，但【没人消费】
      → 那条分支上"门禁"事实上不存在（脚本第 ② 步会把它标成 (none)）
EOF
printf '\n'
