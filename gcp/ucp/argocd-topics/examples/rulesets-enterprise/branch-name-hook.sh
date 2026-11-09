#!/usr/bin/env bash
# =============================================================================
#  branch-name-hook.sh（企业版）—— L1：本地 pre-push 分支名检查
# -----------------------------------------------------------------------------
#  **为什么企业版需要它**
#  企业版多了 `branch_name_pattern`（组织级 metadata 规则）——
#  这是个人版**根本用不了**的能力（API 直接 422）。
#  但它的失败形态和 commit message 一样难受：
#      push 被拒 → ★ 分支指针不更新 → 开发者以为自己推成功了
#  → 本地 pre-push 先拦一次，秒级反馈。
#
#  ★ 只拦"新建/推送的源分支"，不动目标分支（你往 main 推也拦得住，
#    但那条由 pull_request 规则负责）。
#
#  安装
#      cp examples/rulesets-enterprise/branch-name-hook.sh .githooks/pre-push
#      chmod +x .githooks/pre-push
#      git config core.hooksPath .githooks
#
#  正则来源（单一真相源）
#      1) 环境变量 BRANCH_PATTERN
#      2) examples/rulesets-enterprise/03-org-branch-name-convention.json
#      3) 内置兜底 ^(feature|fix|hotfix|git-apps|codex)/[A-Za-z0-9._-]+$
#
#  退出码：0 = 放行；1 = 拦截
# =============================================================================

set -uo pipefail

# pre-push 的参数：<remote name> <remote url> 之后是一组 <local ref> <local sha> <remote ref> <remote sha>
remote_name="${1:-}"
ZERO_SHA="0000000000000000000000000000000000000000"

while read -r local_ref local_sha remote_ref remote_sha; do
  [[ -z "${local_ref:-}" ]] && continue
  # 删分支 / 推 tag 的场景不参与分支名检查
  [[ "$local_ref" == "refs/heads/"* ]] || continue
  [[ "$local_sha" == "$ZERO_SHA" ]] && continue

  branch="${local_ref#refs/heads/}"

  resolve_pattern() {
    if [[ -n "${BRANCH_PATTERN:-}" ]]; then
      echo "$BRANCH_PATTERN"; return
    fi
    local root candidate
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
    if [[ -n "$root" ]]; then
      for candidate in \
        "$root/examples/rulesets-enterprise/03-org-branch-name-convention.json" \
        "$root/../rulesets-enterprise/03-org-branch-name-convention.json"; do
        if [[ -f "$candidate" ]]; then
          python3 - "$candidate" <<'PY' 2>/dev/null && return
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
for r in d.get("rules", []):
    if r.get("type") == "branch_name_pattern":
        p = (r.get("parameters") or {}).get("pattern")
        if p:
            print(p)
            break
PY
        fi
      done
    fi
    echo '^(feature|fix|hotfix|git-apps|codex)/[A-Za-z0-9._-]+$'
  }

  PATTERN="$(resolve_pattern)"

  if printf '%s' "$branch" | grep -Eq "^${PATTERN}"; then
    continue
  fi

  # ★ 默认分支与 release 分支是"受保护命名空间"，不套用功能分支规范
  case "$branch" in
    main|master|dev|release|release/*|hotfix/*)
      continue ;;
  esac

  cat >&2 <<EOF

✗ 分支名不合规

  你的分支名  : ${branch}
  要求的格式  : feature|fix|hotfix|git-apps|codex/<名字>
  规则来源    : ${PATTERN}

  ✅ 正确示例  : git switch -c feature/CR-123456-fix-login
  ❌ 错误示例  : git switch -c my-temp-branch

  ★ 企业版服务端有 branch_name_pattern（组织级 ruleset），
    不合规的 push **不会被拒绝，而是分支指针不更新**（commit 变 unreachable）。

EOF
  exit 1
done

exit 0
