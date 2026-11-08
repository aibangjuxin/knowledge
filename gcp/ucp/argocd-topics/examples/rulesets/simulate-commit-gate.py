#!/usr/bin/env python3
"""
simulate-commit-gate.py —— **不连 GitHub** 就能模拟"commit message 门禁"会怎么判。

**它解决什么问题**

想在真仓库上试 Ruleset 之前，先看清楚三层判定各自会怎么表现：

    L1  本地 commit-msg hook   → 你 `git commit` 的瞬间就报错（秒级反馈）
    L2  GitHub Ruleset         → `git push` 时 ref 不被更新 / merge 被拦
    L3  CR Check (GitHub App)  → PR 上出现一个红叉：CR 号查无此人 / 未批准

**它怎么保证和真实配置一致**

正则不是写死的 —— 它从
[`07-commit-message-cr-prefix-protected.json`](./07-commit-message-cr-prefix-protected.json)
的 `commit_message_pattern` 规则里**读出来**。
改了 ruleset JSON，这里立刻跟着变（单一真相源）。

**它模拟的 L3**

用一个内置的假 CR 平台：

    CR 123456  → 存在 / implement / 2 位审批人  → 合规
    其它编号   → 查无此人                       → 不合规

**用法**

    python3 simulate-commit-gate.py                    # 跑内置的两个例子
    python3 simulate-commit-gate.py --all              # 跑全部内置例子
    python3 simulate-commit-gate.py "CR123456 release: pfb-gcp-v0.1.0: github app"
    python3 simulate-commit-gate.py --file /tmp/msg.txt
    python3 simulate-commit-gate.py --pr-title "CR123456 release: pfb-gcp-v0.1.0"

**退出码**：0 = 全部通过；1 = 有例子没过（适合做 CI 门禁）。
"""

import argparse
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))

RULESET_FILE = os.path.join(_HERE, "07-commit-message-cr-prefix-protected.json")
WORKFLOW_FILE = os.path.join(_HERE, "workflows", "cr-prefix-check.yaml")

# ── 内置例子 ────────────────────────────────────────────────────────────────
EXAMPLES = [
    {
        "name": "例子 A · 正例",
        "message": "CR123456 release: pfb-gcp-v0.1.0: github app",
        "pr_title": "CR123456 release: pfb-gcp-v0.1.0: github app",
        "expect": "pass",
    },
    {
        "name": "例子 B · 反例（缺 CR 前缀）",
        "message": "release: pfb-gcp-v0.1.0: github app",
        "pr_title": "release: pfb-gcp-v0.1.0: github app",
        "expect": "fail",
    },
    {
        "name": "例子 C · 格式对但 CR 号不存在（★ 只有 L3 能拦住）",
        "message": "CR999999 release: pfb-gcp-v0.1.0: github app",
        "pr_title": "CR999999 release: pfb-gcp-v0.1.0: github app",
        "expect": "fail",
    },
    {
        "name": "例子 D · CR 号位数不对（CR12345，只有 5 位）",
        "message": "CR12345 release: pfb-gcp-v0.1.0: github app",
        "pr_title": "CR12345 release: pfb-gcp-v0.1.0: github app",
        "expect": "fail",
    },
    {
        "name": "例子 E · 大小写不对（cr123456）",
        "message": "cr123456 release: pfb-gcp-v0.1.0: github app",
        "pr_title": "cr123456 release: pfb-gcp-v0.1.0: github app",
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


def load_pattern(path):
    """读出"CR 前缀"的正则。

    优先从 ruleset JSON 的 commit_message_pattern 读（Enterprise 路线）；
    没有就从 **CI workflow** 里读（通用路线 —— 个人账号只有这条路）。
    ★ 两条路线共用同一个正则 → 不会出现"CI 拦一套、Ruleset 拦另一套"。
    """
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
            for rule in data.get("rules", []):
                if rule.get("type") != "commit_message_pattern":
                    continue
                params = rule.get("parameters") or {}
                if params.get("pattern"):
                    return params["pattern"], data.get("name")
        except (OSError, ValueError):
            pass

    if os.path.exists(WORKFLOW_FILE):
        with open(WORKFLOW_FILE, encoding="utf-8") as fh:
            text = fh.read()
        # 从 grep -Eq '...' 里抠出正则（CI 路线的事实来源）
        m = re.search(r"grep -Eq\s+'([^']+)'", text)
        if m:
            return m.group(1), "workflows/cr-prefix-check.yaml"

    print("读不到 CR 前缀正则（既没有 metadata 规则，也没有 CI workflow）")
    return None, None


def compile_pattern(pattern):
    """编译 ruleset 的正则。

    ★ GitHub 用 **RE2**（Go 正则），不支持负向预查 `(?!)`。
      Python 的 `re` 语法更宽（支持 lookaround），但我们这个模式不含这些特性，
      所以两边等价。若你以后改了模式用了 lookahead，这里要同步改。
    """
    try:
        return re.compile(pattern)
    except re.error as exc:
        print(f"正则编译失败：{exc}")
        return None


def layer1_local_hook(subject, rx):
    """L1：本地 commit-msg hook 的判定。"""
    if rx is None:
        return None, ""
    if rx.match(subject):
        return True, f"subject 匹配 `{rx.pattern}`"
    return False, f"subject 不匹配 `{rx.pattern}`"


def layer2_ruleset(subject, rx):
    """L2：GitHub Ruleset 的 commit_message_pattern 判定。

    ★ 官方语义（Important considerations）：
      - push 时：不是拒绝 push，而是 **ref 不被更新**（commit 变成 unreachable）
      - squash merge 时：校验的是 **合并后那个 commit 的 message**（默认 = PR 标题 + (#PR)）
    """
    if rx is None:
        return None, ""
    if rx.match(subject):
        return True, "commit message 满足模式"
    return False, "commit message 不满足模式 → ref 不会被更新 / merge 被拦"


def layer3_app(subject, rx):
    """L3：CR Check App 的判定（模拟）。"""
    if rx is None:
        return None, "", ""
    m = rx.match(subject)
    if not m:
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


def run_case(case, rx):
    message = case["message"]
    subject = message.split("\n", 1)[0].strip()

    l1, l1_msg = layer1_local_hook(subject, rx)
    l2, l2_msg = layer2_ruleset(subject, rx)
    l3, number, l3_msg = layer3_app(subject, rx)

    # squash merge 时 GitHub 实际校验的是"合并后的 commit message"
    pr_title = case.get("pr_title", subject)
    merge_subject = f"{pr_title} (#42)"
    m_ok = bool(rx.match(merge_subject))

    print("=" * 78)
    print(f"{case['name']}")
    print("-" * 78)
    print(f"  commit message : {message}")
    print(f"  PR 标题        : {pr_title}")
    print(f"  squash 后实际  : {merge_subject}")
    print()
    print(f"  L1 本地 commit-msg hook : {'✅ 通过' if l1 else '❌ 拦截'}   {l1_msg}")
    print(f"  L2 GitHub Ruleset       : {'✅ 通过' if l2 else '❌ 拦截'}   {l2_msg}")
    print(f"  L3 CR Check (App)       : {'✅ 通过' if l3 else '❌ 拦截'}   {l3_msg}")
    print()
    print(f"  ★ squash merge 实际校验的 message：{merge_subject} → "
          f"{'✅ 合规' if m_ok else '❌ 不合规 → 合并被拦'}")
    if not m_ok:
        print("    → ★ 教训：**PR 标题也必须带 CR 前缀**，"
              "因为 squash commit 的 message 默认取 PR 标题。")

    overall = l1 and l2 and l3 and m_ok
    print()
    print(f"  总结论：{'✅ 三层全过，可以合并' if overall else '❌ 合不了'}")
    return overall


def expected(case, actual):
    """内置例子带 `expect` 字段 —— 比对的是"行为是否符合预期"，不是"是否全过"。"""
    want = case.get("expect")
    if not want:
        return actual
    return actual == (want == "pass")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("message", nargs="?", help="要检查的 commit message")
    ap.add_argument("--file", help="从文件读 commit message")
    ap.add_argument("--pr-title", help="PR 标题（用于模拟 squash 后的 commit message）")
    ap.add_argument("--all", action="store_true", help="跑全部内置例子")
    args = ap.parse_args()

    pattern, ruleset_name = load_pattern(RULESET_FILE)
    if pattern is None:
        print(f"读不到 commit_message_pattern 规则 —— 检查 {RULESET_FILE}")
        return 2
    rx = compile_pattern(pattern)
    if rx is None:
        return 2

    print(f"规则来源：{ruleset_name}")
    print(f"模式    ：{pattern}")
    print(f"★ 模拟器用 Python re 编译；GitHub 用 RE2（Go）。本模式不含 lookaround，两边等价。")
    print()

    if args.file:
        with open(args.file, encoding="utf-8") as fh:
            msg = fh.read()
        ok = run_case({"name": "自定义", "message": msg,
                       "pr_title": args.pr_title or msg.split("\n", 1)[0]}, rx)
        return 0 if ok else 1

    if args.message:
        ok = run_case({"name": "自定义", "message": args.message,
                       "pr_title": args.pr_title or args.message.split("\n", 1)[0]}, rx)
        return 0 if ok else 1

    cases = EXAMPLES if args.all else EXAMPLES[:2]
    results = []
    for c in cases:
        ok = run_case(c, rx)
        as_expected = expected(c, ok)
        results.append((c, ok, as_expected))

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
