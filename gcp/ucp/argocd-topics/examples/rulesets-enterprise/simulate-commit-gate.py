#!/usr/bin/env python3
"""
simulate-commit-gate.py（企业版）—— 不连 GitHub 就把"企业版三层门禁"跑一遍。

**它和个人版模拟器的区别**

个人版模拟的是"CI check 路线"（commit 格式由 GitHub Actions 判）。
企业版走的是 **metadata 规则路线**：格式由 GitHub **服务端**在 push 时刻判。

差别不只是"谁判"，而是**失败形态**：

    路线 A（CI check）：PR 上出现一个红叉 → merge 被拒
    路线 B（metadata）：★ push 成功，但**分支指针不更新**（commit 变成 unreachable）

所以企业版模拟器额外把三件事显式画出来：

    ① commit subject 是否合规（commit_message_pattern）
    ② 分支名 / tag 名是否合规（branch_name_pattern / tag_name_pattern）
       ★ 这两条在个人版根本不存在（非 Enterprise 上 API 直接 422）
    ③ squash 合并时 GitHub 实际校验的是"PR 标题 + (#PR号)"

**单一真相源**

正则不是写死的：
    · commit pattern ← 02-org-commit-message-convention.json
    · branch/tag pattern ← enterprise-profile.yaml
改 ruleset / profile，这里立刻跟着变。

**用法**

    python3 simulate-commit-gate.py                       # 跑前两个例子
    python3 simulate-commit-gate.py --all                 # 跑全部内置例子
    python3 simulate-commit-gate.py "CR123456 xxx"
    python3 simulate-commit-gate.py --branch "feature/x" --tag "v1.0.0"

**退出码**：0 = 行为符合预期；1 = 有例子不符合预期（可直接进 CI）
"""

import argparse
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(_HERE), "lib"))

try:
    from yamlmin import load_file
except ImportError:  # pragma: no cover
    print("找不到 yamlmin —— 请在 argocd-topics/ 目录下运行")
    sys.exit(2)

PROFILE_FILE = os.path.join(_HERE, "enterprise-profile.yaml")
COMMIT_RULESET_FILE = os.path.join(_HERE, "02-org-commit-message-convention.json")

# ── 内置例子 ────────────────────────────────────────────────────────────────
EXAMPLES = [
    {
        "name": "例子 A · 正例（格式对 + CR 号真实）",
        "message": "CR123456 release: pfb-gcp-v0.1.0: github app",
        "pr_title": "CR123456 release: pfb-gcp-v0.1.0: github app",
        "branch": "feature/CR-123456",
        "tag": "v0.1.0",
        "expect": "pass",
    },
    {
        "name": "例子 B · 反例（缺 CR 前缀）",
        "message": "release: pfb-gcp-v0.1.0: github app",
        "pr_title": "release: pfb-gcp-v0.1.0: github app",
        "branch": "feature/CR-123456",
        "tag": "v0.1.0",
        "expect": "fail",
    },
    {
        "name": "例子 C · 格式对但 CR 号不存在（★ 只有 L3 能拦）",
        "message": "CR999999 release: pfb-gcp-v0.1.0: github app",
        "pr_title": "CR999999 release: pfb-gcp-v0.1.0: github app",
        "branch": "feature/CR-999999",
        "tag": "v0.1.0",
        "expect": "fail",
    },
    {
        "name": "例子 D · CR 号位数不对（CR12345）",
        "message": "CR12345 release: x",
        "pr_title": "CR12345 release: x",
        "branch": "feature/x",
        "tag": "v0.1.0",
        "expect": "fail",
    },
    {
        "name": "例子 E · 大小写不对（cr123456）",
        "message": "cr123456 release: x",
        "pr_title": "cr123456 release: x",
        "branch": "feature/x",
        "tag": "v0.1.0",
        "expect": "fail",
    },
    {
        "name": "例子 F · ★ 分支名不合规（企业版才有这条规则）",
        "message": "CR123456 release: x",
        "pr_title": "CR123456 release: x",
        "branch": "my-temp-branch",
        "tag": "v0.1.0",
        "expect": "fail",
    },
    {
        "name": "例子 G · ★ tag 名不合规（企业版才有这条规则）",
        "message": "CR123456 release: x",
        "pr_title": "CR123456 release: x",
        "branch": "feature/x",
        "tag": "release-2026",
        "expect": "fail",
    },
]

# ── 假 CR 平台 ──────────────────────────────────────────────────────────────
MOCK_CR = {
    "123456": {
        "status": "implement",
        "approvers": ["bob", "carol"],
        "targetEnv": "prod",
        "validFrom": "2026-01-01T00:00:00+08:00",
        "validTo": "2030-12-31T23:59:59+08:00",
    }
}


def load_json(path):
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def load_commit_pattern():
    data = load_json(COMMIT_RULESET_FILE)
    if data:
        for rule in data.get("rules", []):
            if rule.get("type") == "commit_message_pattern":
                params = rule.get("parameters") or {}
                if params.get("pattern"):
                    return params["pattern"], data.get("name")
    return None, None


def load_profile():
    if not os.path.exists(PROFILE_FILE):
        return {}
    try:
        return load_file(PROFILE_FILE) or {}
    except Exception:  # noqa: BLE001
        return {}


def load_branch_tag_patterns(profile):
    conv = profile.get("conventions") or {}
    return conv.get("branchNamePattern"), conv.get("tagNamePattern")


def compile_pattern(pattern):
    """★ GitHub 用 RE2（Go 正则），不支持负向预查 (?!)。
    本目录的模式不含 lookaround，所以 Python re 与 RE2 等价。"""
    if not pattern:
        return None
    try:
        return re.compile(pattern)
    except re.error as exc:
        print(f"正则编译失败：{exc}")
        return None


def l1_local_hook(subject, rx):
    if rx is None:
        return None, ""
    if rx.match(subject):
        return True, f"subject 匹配 `{rx.pattern}`"
    return False, f"subject 不匹配 `{rx.pattern}`"


def l2_metadata(subject, rx):
    """L2：组织级 metadata 规则。

    ★ 官方语义：
      - push 时：**不是拒绝 push**，而是 ref 不被更新（commit 变 unreachable）
      - squash merge 时：校验的是合并后那个 commit 的 message
    """
    if rx is None:
        return None, ""
    if rx.match(subject):
        return True, "commit message 满足 commit_message_pattern"
    return False, "commit message 不满足 commit_message_pattern → ★ ref 不会被更新（commit 变 unreachable）"


def l2b_branch_name(branch, rx):
    if rx is None or not branch:
        return None, ""
    if rx.match(branch):
        return True, f"分支名匹配 `{rx.pattern}`"
    return False, f"分支名不匹配 `{rx.pattern}` → ★ push 时 ref 不会被更新"


def l2c_tag_name(tag, rx):
    if rx is None or not tag:
        return None, ""
    if rx.match(tag):
        return True, f"tag 名匹配 `{rx.pattern}`"
    return False, f"tag 名不匹配 `{rx.pattern}` → ★ tag 不会被创建"


def l3_app(subject, rx):
    if rx is None:
        return None, "", ""
    if not rx.match(subject):
        return False, "", "subject 里没有 CR 号 → 连查都不用查"
    num = re.search(r"CR([0-9]{6})", subject)
    if not num:
        return False, "", "没解析出 CR 号"
    number = num.group(1)
    cr = MOCK_CR.get(number)
    if cr is None:
        return False, number, f"变更单 {number} 在 CR 平台上不存在"
    if cr["status"] not in ("approved", "implement"):
        return False, number, f"变更单 {number} 状态为 {cr['status']}，不可执行"
    if len(cr["approvers"]) < 2:
        return False, number, f"变更单 {number} 审批人不足"
    return True, number, f"变更单 {number} 合规（{cr['status']}，审批 {', '.join(cr['approvers'])}）"


def run_case(case, rx, brx, trx):
    message = case["message"]
    subject = message.split("\n", 1)[0].strip()
    branch = case.get("branch", "")
    tag = case.get("tag", "")

    l1, l1_msg = l1_local_hook(subject, rx)
    l2, l2_msg = l2_metadata(subject, rx)
    l2b, l2b_msg = l2b_branch_name(branch, brx)
    l2c, l2c_msg = l2c_tag_name(tag, trx)
    l3, number, l3_msg = l3_app(subject, rx)

    pr_title = case.get("pr_title", subject)
    merge_subject = f"{pr_title} (#42)"
    m_ok = bool(rx.match(merge_subject)) if rx else True

    print("=" * 78)
    print(case["name"])
    print("-" * 78)
    print(f"  commit message : {message}")
    print(f"  分支名         : {branch}")
    print(f"  tag 名         : {tag}")
    print(f"  PR 标题        : {pr_title}")
    print(f"  squash 后实际  : {merge_subject}")
    print()
    print(f"  L1 本地 commit-msg hook : {'✅ 通过' if l1 else '❌ 拦截'}   {l1_msg}")
    print(f"  L2 commit_message_pattern: {'✅ 通过' if l2 else '❌ 拦 push'}   {l2_msg}")
    print(f"  L2b branch_name_pattern : {'✅ 通过' if l2b else '❌ 拦 push'}   {l2b_msg}")
    print(f"  L2c tag_name_pattern    : {'✅ 通过' if l2c else '❌ 拦 tag'}   {l2c_msg}")
    print(f"  L3 CR Check (App)       : {'✅ 通过' if l3 else '❌ 拦截'}   {l3_msg}")
    print()
    print(f"  ★ squash merge 实际校验的 message：{merge_subject} → "
          f"{'✅ 合规' if m_ok else '❌ 不合规 → 合并被拒'}")
    if not m_ok:
        print("    → ★ 教训：**PR 标题也必须带 CR 前缀**（squash commit 的 message 默认取 PR 标题）。")

    parts = [p for p in (l1, l2, l2b, l2c, l3) if p is not None]
    overall = all(parts) and m_ok
    print()
    print(f"  总结论：{'✅ 全过，可以合并' if overall else '❌ 合不了'}")
    return overall


def expected(case, actual):
    want = case.get("expect")
    if not want:
        return actual
    return actual == (want == "pass")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("message", nargs="?", help="要检查的 commit message")
    ap.add_argument("--branch", help="分支名（用于 branch_name_pattern）")
    ap.add_argument("--tag", help="tag 名（用于 tag_name_pattern）")
    ap.add_argument("--pr-title", help="PR 标题（用于模拟 squash 后的 commit message）")
    ap.add_argument("--all", action="store_true", help="跑全部内置例子")
    args = ap.parse_args()

    profile = load_profile()
    commit_pattern, ruleset_name = load_commit_pattern()
    if commit_pattern is None:
        print(f"读不到 commit_message_pattern —— 检查 {COMMIT_RULESET_FILE}")
        return 2
    branch_pattern, tag_pattern = load_branch_tag_patterns(profile)

    rx = compile_pattern(commit_pattern)
    brx = compile_pattern(branch_pattern)
    trx = compile_pattern(tag_pattern)
    if rx is None:
        return 2

    print(f"commit 规则来源：{ruleset_name}")
    print(f"commit 模式    ：{commit_pattern}")
    print(f"branch 模式    ：{branch_pattern or '（profile 里没写）'}")
    print(f"tag 模式       ：{tag_pattern or '（profile 里没写）'}")
    print("★ 模拟器用 Python re；GitHub 用 RE2（Go）。本目录模式不含 lookaround，两边等价。")
    print("★ 企业版语义：metadata 规则拦的是 **ref 更新**，不是 push 请求本身。")
    print()

    if args.message:
        ok = run_case({
            "name": "自定义",
            "message": args.message,
            "pr_title": args.pr_title or args.message.split("\n", 1)[0],
            "branch": args.branch or "",
            "tag": args.tag or "",
        }, rx, brx, trx)
        return 0 if ok else 1

    cases = EXAMPLES if args.all else EXAMPLES[:2]
    results = []
    for c in cases:
        ok = run_case(c, rx, brx, trx)
        results.append((c, ok, expected(c, ok)))

    print("=" * 78)
    print("汇总（比对的是行为是否符合预期，不是是否全过）")
    print("-" * 78)
    all_ok = True
    for case, ok, as_expected in results:
        flag = "✅" if as_expected else "❌"
        if not as_expected:
            all_ok = False
        detail = "符合预期" if as_expected else "★ 不符合预期 —— 规则或模拟器有问题"
        print(f"  {flag} {case['name']}  —— {detail}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
