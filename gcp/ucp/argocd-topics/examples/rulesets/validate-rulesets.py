#!/usr/bin/env python3
"""
校验 examples/rulesets/ 里的 ruleset —— 把「Ruleset 与 CR Check 的契约」变成可执行断言。

**它解决什么问题**

Ruleset 配错的最大风险不是"报错"，而是**静默失效**：

    ┌──────────────────────────────────────────────────────────────┐
    │ S1  context ≠ CR Check 写出的 check 名                        │
    │     → GitHub 永远等一个不存在的 check → 全员卡死              │
    │ S2  required_status_checks 缺 integration_id                  │
    │     → 任何同名 check 都能骗过门禁 → 门禁形同虚设              │
    │ S3  policy.yaml 的 managedBranches ⊄ ruleset 的 ref_name      │
    │     → App 不判的分支 / Ruleset 不管的分支 → 缺口或死锁        │
    └──────────────────────────────────────────────────────────────┘

这三条都是**静态可查**的。本脚本把它们写成断言，接到 CI 里 —— 改坏了就在 PR 上红，
而不是在生产事故里才发现。

**它检查什么**

  ① C1：ruleset 里 required_status_checks 的 context == cr-check/config/policy.yaml 的 checkName
  ② C2：凡是 context == checkName 的 check，必须带非 0 的 integration_id（来源限定）
  ③ C3：policy.yaml 的 managedBranches，每一条都被至少一条 branch ruleset 覆盖
  ④ 每条 branch ruleset 都必须有 pull_request / deletion / non_fast_forward（禁直推、禁删、禁强推）
  ⑤ 生产 ruleset：reviewer ≥ 2、只允许 squash、strict_required_status_checks_policy = true
  ⑥ 任何 ruleset 都不得出现 bypass_mode = "always"，也不得把 GitHub App（Integration）列为 bypass
  ⑦ push ruleset 必须限制密钥类扩展名

**它不检查什么**

  · GitHub 侧 ruleset 的真实生效情况（要靠联调：提一个故意不合规的 PR）
  · integration_id 填的是不是真的 CR Check App ID（要靠人工核对）
  · App 是否真的能写 check（要靠联调）

**用法**

    python3 validate-rulesets.py                 # 检查本目录
    python3 validate-rulesets.py --path <目录>
    python3 validate-rulesets.py --strict        # 警告也算失败

**退出码**：0 = 通过；1 = 有 ERROR（或 --strict 下有 WARN）。
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
    print("找不到 yamlmin —— 请在 argocd-topics/ 目录下运行，或检查 examples/lib/")
    sys.exit(2)

POLICY_PATH = os.path.join(
    _HERE, "..", "..", "git-apps", "cr-check", "config", "policy.yaml"
)

ERRORS = []
WARNINGS = []
NOTES = []


def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNINGS.append(msg)


def note(msg):
    NOTES.append(msg)


# ---------------------------------------------------------------------------
# fnmatch（GitHub 语义）→ 正则
#   GitHub 用 File::FNM_PATHNAME：`*` 不跨 `/`，`**` 跨层级。
# ---------------------------------------------------------------------------

def fnmatch_to_regex(pattern):
    out = ["^"]
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if pattern.startswith("**", i):
            out.append(".*")
            i += 2
            continue
        if ch == "*":
            out.append("[^/]*")
            i += 1
            continue
        if ch == "?":
            out.append("[^/]")
            i += 1
            continue
        out.append(re.escape(ch))
        i += 1
    out.append("$")
    return re.compile("".join(out))


def pattern_matches(pattern, ref):
    """判断一个 ref 是否被 pattern 覆盖。

    ★ `~DEFAULT_BRANCH` / `~ALL` 是 GitHub 的特殊标记，不走 fnmatch。
      这里把 `~DEFAULT_BRANCH` 当作"默认分支"（我们的默认分支是 main）。
    """
    if pattern == "~ALL":
        return True
    if pattern == "~DEFAULT_BRANCH":
        return ref == "refs/heads/main"
    return fnmatch_to_regex(pattern).match(ref) is not None


def ruleset_covers(ruleset, ref):
    """ruleset 的 conditions 是否覆盖这个 ref。"""
    if ruleset.get("target") != "branch":
        return False
    cond = ruleset.get("conditions") or {}
    ref_name = cond.get("ref_name") or {}
    includes = ref_name.get("include") or []
    excludes = ref_name.get("exclude") or []
    if not any(pattern_matches(p, ref) for p in includes):
        return False
    if any(pattern_matches(p, ref) for p in excludes):
        return False
    return True


# ---------------------------------------------------------------------------
# 读取
# ---------------------------------------------------------------------------

def load_rulesets(path):
    """读目录下所有 [0-9][0-9]-*.json。每个文件 = 一条 ruleset。"""
    out = []
    for name in sorted(os.listdir(path)):
        if not name.endswith(".json"):
            continue
        if not re.match(r"^\d\d-", name):
            continue
        full = os.path.join(path, name)
        try:
            with open(full, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as exc:
            err(f"{name}: 不是合法 JSON —— {exc}")
            continue
        data["_file"] = name
        out.append(data)
    return out


def load_policy():
    if not os.path.exists(POLICY_PATH):
        err(f"找不到 policy.yaml：{POLICY_PATH}")
        return {}
    try:
        return load_file(POLICY_PATH) or {}
    except Exception as exc:  # noqa: BLE001
        err(f"policy.yaml 解析失败：{exc}")
        return {}


def rules_of(ruleset, rtype):
    return [r for r in ruleset.get("rules", []) if r.get("type") == rtype]


# 官方 REST API 里，每种 rule type 的 parameters 字段是固定的。
# 拼错字段名不会静默 —— GitHub 会返回 422 —— 但报错信息很难看懂，
# 所以这里提前拦一层，把“API 字段名抄错”变成人话。
RULE_PARAMS = {
    "creation": set(),
    "deletion": set(),
    "non_fast_forward": set(),
    "required_linear_history": set(),
    "required_signatures": set(),
    "pull_request": {
        "allowed_merge_methods",
        "dismiss_stale_reviews_on_push",
        "dismissal_restriction",
        "require_code_owner_review",
        "require_extra_approval_for_unattributed_changes",
        "require_last_push_approval",
        "required_approving_review_count",
        "required_review_thread_resolution",
        "required_reviewers",
    },
    # ★ API 里 pull_request.parameters 的**必填字段**（少一个 → 422）
    #   实测：只写 required_approving_review_count 会报
    #   "Invalid property /rules/N: data matches no possible input"
    "pull_request.required": {
        "required_approving_review_count",
        "dismiss_stale_reviews_on_push",
        "require_code_owner_review",
        "require_last_push_approval",
        "required_review_thread_resolution",
    },
    "required_status_checks": {
        "required_status_checks",
        "strict_required_status_checks_policy",
        "do_not_enforce_on_create",
    },
    "required_deployments": {"required_deployment_environments"},
    "branch_name_pattern": {"name", "negate", "operator", "pattern"},
    "commit_message_pattern": {"name", "negate", "operator", "pattern"},
    "file_extension_restriction": {"restricted_file_extensions"},
    "file_path_restriction": {"restricted_file_paths", "ignored_file_paths"},
    "max_file_size": {"max_file_size", "ignored_file_paths"},
}

CONVENTION_RULES = {"branch_name_pattern", "commit_message_pattern"}


def is_convention_only(ruleset):
    """纯“命名/提交信息规范”的 ruleset —— 不应该要求走 PR。

    例：feature 分支只需要名字规范，开发者应该能自由 push。
    """
    types = {r.get("type") for r in ruleset.get("rules", [])}
    return bool(types & CONVENTION_RULES) and "pull_request" not in types


# ---------------------------------------------------------------------------
# 检查
# ---------------------------------------------------------------------------

def check_policy_contract(policy, rulesets):
    """C1 / C2 / C3 三条契约。"""
    check_name = (policy.get("checkName") or "").strip()
    managed = policy.get("managedBranches") or []

    if not check_name:
        err("policy.yaml 里没有 checkName —— 门禁 check 的名字无从谈起")
        return

    # ---- C1：context == checkName ----
    found = False
    for rs in rulesets:
        for rule in rules_of(rs, "required_status_checks"):
            params = rule.get("parameters") or {}
            for chk in params.get("required_status_checks") or []:
                ctx = chk.get("context")
                if ctx == check_name:
                    found = True
                elif ctx and ctx.startswith("cr/"):
                    err(f"{rs['_file']}: context `{ctx}` 看起来像 CR Check 的 check，"
                        f"但 policy.yaml 的 checkName 是 `{check_name}` —— 名字必须逐字符一致（C1）")

    if not found:
        err(f"没有任何 ruleset 要求 check `{check_name}` —— "
            f"CR Check 产出的结论不会被门禁消费（C1 断裂）")

    # ---- C2：CR Check 的 check 必须限定来源 ----
    for rs in rulesets:
        for rule in rules_of(rs, "required_status_checks"):
            params = rule.get("parameters") or {}
            for chk in params.get("required_status_checks") or []:
                if chk.get("context") != check_name:
                    continue
                iid = chk.get("integration_id")
                if iid is None:
                    err(f"{rs['_file']}: check `{check_name}` 没有 integration_id —— "
                        f"任何同名 check 都能骗过门禁（C2）")
                elif not isinstance(iid, int) or iid <= 0:
                    err(f"{rs['_file']}: check `{check_name}` 的 integration_id = {iid!r}，"
                        f"必须是正整数（C2）")
                elif iid == 123456:
                    warn(f"{rs['_file']}: integration_id 仍是占位符 123456 —— "
                         f"下发时请用 CR_CHECK_APP_ID 覆盖")
                strict = params.get("strict_required_status_checks_policy")
                if strict is not True:
                    err(f"{rs['_file']}: 生产分支的 required_status_checks 必须设 "
                        f"strict_required_status_checks_policy = true")

    # ---- C3：managedBranches ⊆ ruleset 覆盖范围 ----
    for branch in managed:
        ref = branch if branch.startswith("refs/") else f"refs/heads/{branch}"
        if not any(ruleset_covers(rs, ref) for rs in rulesets):
            err(f"policy.yaml 的 managedBranches 里的 `{branch}` 没有任何 ruleset 覆盖 —— "
                f"该分支的 PR 永远等不到 check（C3）")


def check_branch_ruleset_basics(rulesets):
    """每条 branch ruleset 的底线规则。"""
    for rs in rulesets:
        if rs.get("target") != "branch":
            continue
        f = rs["_file"]
        if is_convention_only(rs):
            # 纯规范类 ruleset：只要求它确实带了规范规则
            if not (rules_of(rs, "branch_name_pattern") or rules_of(rs, "commit_message_pattern")):
                err(f"{f}: 看起来是规范类 ruleset，但没有 branch_name_pattern / "
                    f"commit_message_pattern 规则")
            continue
        if not rules_of(rs, "pull_request"):
            err(f"{f}: branch ruleset 缺少 pull_request 规则 —— "
                f"等于允许直接 push 到受保护分支")
        if not rules_of(rs, "deletion"):
            err(f"{f}: branch ruleset 缺少 deletion 规则 —— 受保护分支可被删除")
        if not rules_of(rs, "non_fast_forward"):
            err(f"{f}: branch ruleset 缺少 non_fast_forward 规则 —— 可被 force push")

        pr = rules_of(rs, "pull_request")
        if pr:
            params = pr[0].get("parameters") or {}
            methods = params.get("allowed_merge_methods")
            if methods is None:
                warn(f"{f}: pull_request 没限定 allowed_merge_methods —— "
                     f"仓库设置变了合并方式就跟着变")
            elif len(methods) > 1:
                warn(f"{f}: allowed_merge_methods = {methods} —— "
                     f"允许多种合并方式会让「发布可追溯」变难")


def check_prod_strictness(rulesets):
    """生产 ruleset 必须够严。"""
    for rs in rulesets:
        if rs.get("target") != "branch":
            continue
        f = rs["_file"]
        # ★ 只认"显式点名 main"的 ruleset。
        #   组织级基线用的是 ~DEFAULT_BRANCH（对所有仓库的默认分支生效），
        #   它刻意只要求 1 个 reviewer —— 不能拿它当生产 ruleset 判。
        includes = ((rs.get("conditions") or {}).get("ref_name") or {}).get("include") or []
        if "refs/heads/main" not in includes:
            continue
        # 纯元数据类 ruleset（只管 commit message / 分支名）不受生产严格度约束
        if is_convention_only(rs):
            continue
        # ★ main 必须走 PR —— 这条对企业版和个人仓库版都成立 → ERROR
        if not rules_of(rs, "pull_request"):
            err(f"{f}: 覆盖 main 的 ruleset 没有 pull_request 规则 —— "
                f"等于允许直接 push 到 main")

        # 下面两条是"企业版推荐值"，个人仓库可以更宽松 → WARN
        pr = rules_of(rs, "pull_request")
        if pr:
            params = pr[0].get("parameters") or {}
            n = params.get("required_approving_review_count", 0)
            if n < 2:
                warn(f"{f}: 覆盖 main 的 ruleset 只有 {n} 个 reviewer —— "
                     f"企业/团队仓库建议 ≥ 2（个人仓库 0~1 也可以，"
                     f"注意 require_last_push_approval 在单人仓库会把自己锁死）")
            methods = params.get("allowed_merge_methods") or []
            if methods != ["squash"]:
                warn(f"{f}: 覆盖 main 的 ruleset 的 allowed_merge_methods = {methods} —— "
                     f"企业发布流程建议严格是 [\"squash\"]（线性历史）")


def check_bypass(rulesets):
    """bypass 是最危险的一环。"""
    for rs in rulesets:
        f = rs["_file"]
        for actor in rs.get("bypass_actors") or []:
            mode = actor.get("bypass_mode", "always")
            atype = actor.get("actor_type")
            if mode == "always":
                err(f"{f}: bypass_actors 里有 bypass_mode = \"always\" —— "
                    f"该 actor 可以直接 push 受保护分支，生产分支一律禁用")
            if atype == "Integration":
                err(f"{f}: bypass_actors 里出现了 GitHub App（actor_type=Integration）—— "
                    f"★ 绝不能把 CR Check App 放进来：那等于同时给它「发结论」和「跳过规则」两把钥匙")


def check_push_ruleset(rulesets):
    """push ruleset 必须挡住密钥类扩展名。"""
    for rs in rulesets:
        if rs.get("target") != "push":
            continue
        f = rs["_file"]
        exts = set()
        for rule in rules_of(rs, "file_extension_restriction"):
            params = rule.get("parameters") or {}
            exts.update(params.get("restricted_file_extensions") or [])
        must = {".pem", ".key", ".p12", ".pfx"}
        missing = must - exts
        if missing:
            err(f"{f}: push ruleset 没有限制扩展名 {sorted(missing)} —— "
                f"密钥类文件可以被 push 进仓库")
        if not rules_of(rs, "file_path_restriction"):
            warn(f"{f}: push ruleset 没有 file_path_restriction —— "
                 f"归档目录 / terraform state 可以被改")
        for rule in rules_of(rs, "max_file_size"):
            size = (rule.get("parameters") or {}).get("max_file_size")
            # ★ 官方单位是 **MB**（不是字节）—— 写错单位 = 实际限制差 1e6 倍
            if not isinstance(size, int) or size <= 0:
                err(f"{f}: max_file_size = {size!r} —— 必须是正整数，单位是 MB")


def check_rule_params(rulesets):
    """rule parameters 的字段名必须是官方定义过的。"""
    for rs in rulesets:
        f = rs["_file"]
        for rule in rs.get("rules", []):
            rtype = rule.get("type")
            if rtype not in RULE_PARAMS:
                continue
            params = rule.get("parameters") or {}
            unknown = set(params) - RULE_PARAMS[rtype]
            if unknown:
                err(f"{f}: rule `{rtype}` 里有 API 不存在的字段 {sorted(unknown)} —— "
                    f"GitHub 会返回 422")
            required = {"required_status_checks": "required_status_checks"}
            if rtype in required and required[rtype] not in params:
                err(f"{f}: rule `{rtype}` 缺少必填字段 `{required[rtype]}`")

            # ★ pull_request.parameters：一旦写了 parameters，就必须**字段齐全**
            #   （少一个必填字段 → GitHub API 返回 422，报错信息完全看不出是哪缺了）
            if rtype == "pull_request" and "parameters" in rule:
                must = RULE_PARAMS["pull_request.required"]
                missing = must - set(params)
                if missing:
                    err(f"{f}: rule `pull_request` 的 parameters 缺少必填字段 "
                        f"{sorted(missing)} —— GitHub 会返回 422"
                        f"（★ parameters 可以整个省略，但不能只写一半）")


def check_names_unique(rulesets):
    seen = {}
    for rs in rulesets:
        name = rs.get("name")
        if not name:
            err(f"{rs['_file']}: 缺 name")
            continue
        if name in seen:
            err(f"{rs['_file']} 与 {seen[name]} 的 ruleset 同名（{name}）—— "
                f"apply 脚本会误更新")
        seen[name] = rs["_file"]


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=_HERE, help="ruleset JSON 所在目录")
    ap.add_argument("--strict", action="store_true", help="警告也算失败")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"目录不存在：{root}")
        return 2

    rulesets = load_rulesets(root)
    if not rulesets:
        print(f"{root} 里没有找到 ruleset JSON")
        return 1

    policy = load_policy()

    check_names_unique(rulesets)
    check_policy_contract(policy, rulesets)
    check_branch_ruleset_basics(rulesets)
    check_prod_strictness(rulesets)
    check_bypass(rulesets)
    check_push_ruleset(rulesets)
    check_rule_params(rulesets)

    print(f"检查了 {len(rulesets)} 条 ruleset"
          f"（checkName={policy.get('checkName')!r}，"
          f"managedBranches={policy.get('managedBranches')}）\n")

    for msg in NOTES:
        print(f"ℹ️  {msg}")
    for msg in WARNINGS:
        print(f"[WARN] {msg}")
    for msg in ERRORS:
        print(f"[ERROR] {msg}")

    print()
    if ERRORS:
        print(f"✗ {len(ERRORS)} 个错误 / {len(WARNINGS)} 个警告")
        return 1
    if WARNINGS and args.strict:
        print(f"✗ {len(WARNINGS)} 个警告（--strict）")
        return 1
    print(f"✓ 没有错误（{len(WARNINGS)} 个警告）")
    print()
    print("提醒：静态检查只保证「配置之间自洽」。")
    print("真正验证门禁是否生效，必须在测试仓库上提一个**故意不合规**的 PR：")
    print("  · 不带 CR 号 → 必须合不了")
    print("  · 带合规 CR 号 → 能合")
    return 0


if __name__ == "__main__":
    sys.exit(main())
