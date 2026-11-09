#!/usr/bin/env bash
# =============================================================================
#  commit-msg-hook.sh（企业版）—— L1：本地 commit-msg hook（秒级反馈）
# -----------------------------------------------------------------------------
#  **它在企业版里的角色**
#  企业版有了 **metadata 规则**（commit_message_pattern），服务端已经会拦。
#  但服务端拦的失败形态是：
#      push 报错 → ★ 分支指针不更新 → commit 变成 unreachable
#  → 开发者必须 amend / rebase 改历史才能推上去，体验很糟。
#
#  所以本地 hook 在企业版里**不是可有可无**，而是"体验补丁"：
#      把反馈时机从 "push 之后要改历史" 提前到 "commit 之前"。
#
#  ★ 它仍然不是安全边界（可以被 --no-verify 绕过），
#    真正的门禁永远是服务端规则 + CR Check。
#
#  安装
#      mkdir -p .githooks
#      cp examples/rulesets-enterprise/commit-msg-hook.sh .githooks/commit-msg
#      chmod +x .githooks/commit-msg
#      git config core.hooksPath .githooks
#
#  ★ 正则来源（单一真相源，不写死）：
#      1) 环境变量 CR_PATTERN
#      2) 仓库里 examples/rulesets-enterprise/02-org-commit-message-convention.json
#      3) 内置兜底 ^CR[0-9]{6}(\s|$)
#    → 改了服务端 ruleset，hook 自动跟着变。
#
#  退出码：0 = 放行；1 = 拦截
# =============================================================================

set -uo pipefail

MSG_FILE="${1:-}"
if [[ -z "$MSG_FILE" || ! -f "$MSG_FILE" ]]; then
  echo "commit-msg hook: 用法错误（缺少 commit message 文件参数）" >&2
  exit 1
fi

SUBJECT="$(head -n 1 "$MSG_FILE" | tr -d '\r')"

# ── 解析正则（与 ruleset 同源）──────────────────────────────────────────────
resolve_pattern() {
  if [[ -n "${CR_PATTERN:-}" ]]; then
    echo "$CR_PATTERN"; return
  fi
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [[ -n "$root" ]]; then
    local candidate
    for candidate in \
      "$root/examples/rulesets-enterprise/02-org-commit-message-convention.json" \
      "$root/../rulesets-enterprise/02-org-commit-message-convention.json"; do
      if [[ -f "$candidate" ]]; then
        python3 - "$candidate" <<'PY' 2>/dev/null && return
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    d = json.load(fh)
for r in d.get("rules", []):
    if r.get("type") == "commit_message_pattern":
        p = (r.get("parameters") or {}).get("pattern")
        if p:
            print(p)
            break
PY
      fi
    done
  fi
  echo '^CR[0-9]{6}(\s|$)'
}

PATTERN="$(resolve_pattern)"

if printf '%s' "$SUBJECT" | grep -Eq "^${PATTERN}"; then
  exit 0
fi

if [[ "${SKIP_CR_PREFIX:-0}" == "1" ]]; then
  echo "commit-msg hook: 已用 SKIP_CR_PREFIX=1 跳过（★ 服务端 metadata 规则仍会拦）" >&2
  exit 0
fi

cat >&2 <<EOF

✗ commit message 不合规

  你的 subject : ${SUBJECT}
  要求的格式  : CR<6位数字> <任意描述>
  规则来源    : ${PATTERN}

  ✅ 正确示例  : git commit -m "CR123456 release: pfb-gcp-v0.1.0: github app"
  ❌ 错误示例  : git commit -m "release: pfb-gcp-v0.1.0: github app"

  提示：
    · ★ PR 标题也要带同样的前缀 —— squash merge 时 GitHub 校验的是
      "PR 标题 + (#PR号)" 组成的最终 commit message
    · 企业版服务端有 commit_message_pattern（组织级 ruleset），
      不合规的 push **不会被拒绝，而是分支指针不更新**（commit 变 unreachable）
      → 本地先拦住，省得改历史
    · 紧急情况：SKIP_CR_PREFIX=1 git commit -m "..." 临时跳过本地检查，
      但 ★ 服务端规则照样拦

EOF
exit 1
