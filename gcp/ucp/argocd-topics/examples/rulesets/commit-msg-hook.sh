#!/usr/bin/env bash
# =============================================================================
#  commit-msg-hook.sh —— L1：本地 commit-msg hook（秒级反馈）
# -----------------------------------------------------------------------------
#  **它解决什么问题**
#  GitHub 的 commit_message_pattern 是**服务端**门禁：不合规的 commit 也能 push 进去，
#  只是分支指针不会被更新（commit 变成 unreachable）。开发者要等到 push 才知道，
#  而且要 rebase 改历史，很烦。
#
#  本地 hook 在 `git commit` 的瞬间就拦，代价≈0。
#  ★ 它**不能替代**服务端规则（本地 hook 可以被绕过、可以没有），
#    但它把"发现问题"的时机从 push 提前到了 commit。
#
#  安装（推荐用 core.hooksPath，不要直接改 .git/hooks）：
#      mkdir -p .githooks
#      cp examples/rulesets/commit-msg-hook.sh .githooks/commit-msg
#      chmod +x .githooks/commit-msg
#      git config core.hooksPath .githooks
#
#  ★ 规则必须与 Ruleset 里的 commit_message_pattern **逐字符一致**：
#      Ruleset: ^CR[0-9]{6}(\s|$)
#      本 hook: CR[0-9]{6}   （grep -E 是"包含"语义，所以这里不用 ^）
#
#  退出码：0 = 放行；1 = 拦截。
# =============================================================================

set -uo pipefail

MSG_FILE="${1:-}"
if [[ -z "$MSG_FILE" || ! -f "$MSG_FILE" ]]; then
  echo "commit-msg hook: 用法错误（缺少 commit message 文件参数）" >&2
  exit 1
fi

# 只看第一行（subject）；正文里的 CR 号不参与判定
SUBJECT="$(head -n 1 "$MSG_FILE" | tr -d '\r')"

# ★ 与 Ruleset 的正则保持一致：CR + 恰好 6 位数字，后面必须跟空格或结束
PATTERN='CR[0-9]{6}( |$)'

if printf '%s' "$SUBJECT" | grep -Eq "^${PATTERN}"; then
  exit 0
fi

# 合并提交 / 修复提交时豁免（可选，按需打开）
if [[ "${SKIP_CR_PREFIX:-0}" == "1" ]]; then
  echo "commit-msg hook: 已用 SKIP_CR_PREFIX=1 跳过（服务端 Ruleset 仍会拦）" >&2
  exit 0
fi

cat >&2 <<EOF

✗ commit message 不合规

  你的 subject : ${SUBJECT}
  要求的格式  : CR<6位数字> <任意描述>

  ✅ 正确示例  : git commit -m "CR123456 release: pfb-gcp-v0.1.0: github app"
  ❌ 错误示例  : git commit -m "release: pfb-gcp-v0.1.0: github app"

  提示：
    · CR 号是"变更单编号"，后面接的是这次变更的描述
    · ★ PR 标题也要带同样的前缀 —— squash merge 时 GitHub 校验的是
      "PR 标题 + (#PR号)" 组成的最终 commit message
    · 紧急情况可 SKIP_CR_PREFIX=1 git commit -m "..." 临时跳过本地检查，
      但 ★ GitHub 服务端规则仍然会拦（本地跳过 ≠ 服务端放行）

EOF
exit 1
