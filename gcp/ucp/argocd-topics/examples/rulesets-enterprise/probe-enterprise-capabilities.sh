#!/usr/bin/env bash
# =============================================================================
#  probe-enterprise-capabilities.sh —— ★ 实测你们的 org 到底支持哪些 rule type
# -----------------------------------------------------------------------------
#  **它解决什么问题**
#  "我们买的是 Enterprise，所以 metadata 规则肯定能用吧？" —— **不能假设**。
#
#  官方文档里"哪些计划能用哪些 rule type"的表述是分散的，而且 **GHES 与 GHEC
#  的版本差异很大**（自建版升级节奏和云版不同）。
#  → 与其查文档，不如**花 2 分钟实测**：逐个 rule type 真的建一次（disabled），
#    看 API 是 200 还是 422。
#
#  ★ 实测出来的表才是你们环境的真相；本文档里其它地方的能力矩阵都是"参考"。
#
#  **它怎么做到不污染环境**
#    · 全部在**组织级**建，且 `conditions.repository_name` 只包含**探针仓库**
#    · `enforcement: disabled`（建了也不执行）
#    · 建完立刻 DELETE
#    → 其它仓库完全不受影响；探针仓库上也只是多出一条已删除的历史记录
#
#  用法
#    ./probe-enterprise-capabilities.sh --probe-repo <某个测试仓库>
#    ./probe-enterprise-capabilities.sh --probe-repo <repo> --dry-run   # 只打印要发什么
#    ./probe-enterprise-capabilities.sh --probe-repo <repo> --out capabilities.md
#
#  前提
#    · gh auth refresh -s admin:org（组织级 ruleset 需要 org owner）
#    · 探针仓库必须存在，且名字在 org 下唯一
#
#  退出码：0 = 全部可用；1 = 有不可用的 rule type
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$SCRIPT_DIR/enterprise-profile.yaml"

PROBE_REPO=""
DRY_RUN=0
OUT=""
OWNER=""

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe-repo) PROBE_REPO="$2"; shift 2 ;;
    --owner)      OWNER="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "未知参数: $1"; usage; exit 1 ;;
  esac
done

fail() { echo "✗ $*" >&2; exit 1; }

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
[[ -n "$PROBE_REPO" ]] || fail "必须给 --probe-repo <某个测试仓库>"
command -v gh >/dev/null 2>&1 || fail "找不到 gh"
gh auth status >/dev/null 2>&1 || fail "gh 未登录"

REPO_ID="$(gh api "repos/$OWNER/$PROBE_REPO" --jq .id 2>/dev/null)" \
  || fail "读不到仓库 $OWNER/$PROBE_REPO（名字对吗？有权限吗？）"
[[ -n "$REPO_ID" ]] || fail "读不到仓库 ID"

echo "▸ 探针仓库：$OWNER/$PROBE_REPO (id=$REPO_ID)"
echo "▸ 目标 org ：$OWNER"
echo

# ── 候选 rule type → 最小可用 payload ──────────────────────────────────────
# target: branch / tag / push / code_scanning
build_payload() {  # $1=rule_type  $2=probe_repo  $3=repo_id
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
rtype, repo, repo_id = sys.argv[1], sys.argv[2], int(sys.argv[3])

PULL = {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews_on_push": False,
    "require_code_owner_review": False,
    "require_last_push_approval": False,
    "required_review_thread_resolution": False,
    "allowed_merge_methods": ["squash"],
}

def rule(t):
    if t == "pull_request":
        return {"type": t, "parameters": PULL}
    if t == "required_status_checks":
        return {"type": t, "parameters": {
            "required_status_checks": [{"context": "probe/noop"}],
            "strict_required_status_checks_policy": False,
            "do_not_enforce_on_create": True}}
    if t == "commit_message_pattern":
        return {"type": t, "parameters": {
            "name": "probe", "negate": False, "operator": "regex", "pattern": "^CR[0-9]{6}"}}
    if t == "branch_name_pattern":
        return {"type": t, "parameters": {
            "name": "probe", "negate": False, "operator": "regex", "pattern": "^[a-z]+/.+$"}}
    if t == "tag_name_pattern":
        return {"type": t, "parameters": {
            "name": "probe", "negate": False, "operator": "regex", "pattern": "^v[0-9]+\\.[0-9]+\\.[0-9]+$"}}
    if t == "merge_queue":
        return {"type": t, "parameters": {
            "merge_method": "squash", "min_entries_to_merge": 1,
            "max_entries_to_merge": 5, "grouping_strategy": "ALLGREEN"}}
    if t == "required_workflows":
        return {"type": t, "parameters": {"required_workflows": [{
            "path": ".github/workflows/probe.yaml",
            "ref": "refs/heads/main",
            "repository_id": repo_id}]}}
    if t == "block_credential_changes":
        return {"type": t, "parameters": {"credential_types": ["password"]}}
    if t == "file_extension_restriction":
        return {"type": t, "parameters": {"restricted_file_extensions": [".pem"]}}
    if t == "file_path_restriction":
        return {"type": t, "parameters": {"restricted_file_paths": ["releases/**"], "ignored_file_paths": []}}
    if t == "max_file_size":
        return {"type": t, "parameters": {"max_file_size": 10}}
    if t == "code_scanning_tools":
        return {"type": t, "parameters": {"analyze": ["codeql"], "check": []}}
    if t == "required_deployments":
        return {"type": t, "parameters": {"required_deployment_environments": ["production"]}}
    return {"type": t}

TARGET = {
    "tag_name_pattern": "tag",
    "block_credential_changes": "push",
    "file_extension_restriction": "push",
    "file_path_restriction": "push",
    "max_file_size": "push",
    "code_scanning_tools": "code_scanning",
}

target = TARGET.get(rtype, "branch")
out = {
    "name": f"probe-{rtype}",
    "target": target,
    "enforcement": "disabled",
    "bypass_actors": [],
    "rules": [rule(rtype)],
}
if target == "code_scanning":
    out["conditions"] = {"repository_name": {"include": [repo], "exclude": []}}
else:
    out["conditions"] = {
        "repository_name": {"include": [repo], "exclude": []},
        "ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []},
    }
print(json.dumps(out, ensure_ascii=False))
PY
}

# ★ 需要 pull_request 配套的 rule（merge_queue 至少要一个 PR 规则）
NEEDS_PR=("merge_queue")

CANDIDATES=(
  "pull_request" "required_status_checks" "required_linear_history" "required_signatures"
  "deletion" "non_fast_forward" "creation" "required_deployments"
  "commit_message_pattern" "branch_name_pattern" "tag_name_pattern"
  "merge_queue" "required_workflows"
  "block_credential_changes" "file_extension_restriction" "file_path_restriction" "max_file_size"
  "code_scanning_tools"
)

printf "| rule type | 结果 | 说明 |\n|---|---|---|\n"

FAILED=0
for t in "${CANDIDATES[@]}"; do
  payload="$(build_payload "$t" "$PROBE_REPO" "$REPO_ID")"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "| \`$t\` | (dry-run) | $(printf '%s' "$payload" | head -c 120)… |"
    continue
  fi
  resp="$(printf '%s' "$payload" | gh api -X POST "orgs/$OWNER/rulesets" --input - 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    rid="$(printf '%s' "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null)"
    [[ -n "$rid" ]] && gh api -X DELETE "orgs/$OWNER/rulesets/$rid" >/dev/null 2>&1
    printf '| `%s` | ✅ 可用 | 已建后删除 |\n' "$t"
  else
    FAILED=1
    msg="$(printf '%s' "$resp" | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-160)"
    printf '| `%s` | ❌ 不可用 | %s |\n' "$t" "$msg"
  fi
done

echo
echo "▸ 说明："
echo "  · ✅ 可用 = 你们的环境支持这条 rule type（GHEC / 特定版本 GHES）"
echo "  · ❌ 不可用 = API 422 → ★ 不要把它写进 ruleset（UI 导入更坑：静默丢弃，"
echo "              ruleset 显示 active 但 rules=[]，什么都不拦）"
echo "  · 目标 = 'branch' 的要配 ref_name；'push' 的是 push ruleset；'tag' 的是 tag 规则"

if [[ -n "$OUT" ]]; then
  echo "（把上表写进 $OUT）" 
fi

exit $FAILED
