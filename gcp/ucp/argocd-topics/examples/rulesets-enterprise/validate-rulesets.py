#!/usr/bin/env python3
"""
validate-rulesets.py（企业版）—— 把「企业版规则集」的契约变成可执行断言。

**它和个人版校验器的区别**

个人版（examples/rulesets/validate-rulesets.py）守的是"一个人的仓库别把自己锁死"。
企业版守的是"**一次配置，全组织一起生效**"——这里的每一条 ERROR 都意味着：

    ┌──────────────────────────────────────────────────────────────┐
    │ 某条 ruleset 配错 → 整个组织的仓库同时开始拦人 / 或者同时失效  │
    │ （两种都更糟：一种是全员卡死，一种是全员绕过）                  │
    └──────────────────────────────────────────────────────────────┘

所以企业版多出三类断言：

  ① **能力断言**：你用的 rule type 是不是 Enterprise 才有的？
     → 计划不对就是 ERROR（否则 UI 导入会**静默丢弃**，ruleset 变空壳）
  ② **跨文件一致性断言**：profile ↔ ruleset ↔ policy.yaml 三方的正则/名字必须逐字符一致
  ③ **治理断言**：豁免必须显式列出、生产必须够严、push 必须挡密钥

**断言清单**

  E1  计划声明：profile.org.plan 必须是 enterprise / enterprise-cloud / ghes
  E2  App ID：profile.crCheck.appId 必须是正整数（门禁不能没有来源限定）
  E3  C1 延伸：ruleset 的 check context == policy.yaml 的 checkName == profile 的 checkName
  E4  C2 延伸：CR Check 的 check 必须带 integration_id，且 == profile.crCheck.appId
  E5  正则同源：commit / branch / tag 三个规范在 profile 与 ruleset 中必须逐字符一致
  E6  C3 延伸：policy.yaml 与 profile 声明的 managedBranches 每一条都被 ruleset 覆盖
  E7  scope 正确性：组织级必须有 repository_name + ref_name；仓库级必须没有 repository_name
  E8  branch ruleset 底线：deletion + non_fast_forward（规范类除外）
  E9  生产严格度：reviewer 数 / squash 唯一 / strict / required_signatures
  E10 豁免纪律：bypass_mode=always 必须出现在 profile.bypassAllowlist 里；禁止把 App 列为豁免
  E11 push 门禁：密钥扩展名 / 受限路径 / 文件大小（MB）/ 凭据扫描
  E12 字段白名单：rule parameters 的字段名必须是官方定义过的（抄错 → GitHub 422）
  E13 命名唯一：同名 ruleset 会让 apply 脚本误更新
  E14 merge queue 必须配套 pull_request 规则
  E15 Enterprise-only rule type 与计划匹配

**用法**

    python3 validate-rulesets.py                    # 严格检查本目录
    python3 validate-rulesets.py --strict           # 警告也算失败
    python3 validate-rulesets.py --allow-placeholders   # 只审模板（占位符降级为警告）
    python3 validate-rulesets.py --path <目录>

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

PROFILE_PATH = os.path.join(_HERE, "enterprise-profile.yaml")
POLICY_PATH = os.path.join(
    _HERE, "..", "..", "git-apps", "cr-check", "config", "policy.yaml"
)

ERRORS = []
WARNINGS = []
NOTES = []

# 只有 Enterprise（或 GHEC）才有的 rule type。
# ★ 非 Enterprise 上：API 直接 422；UI 导入**静默丢弃** → ruleset 变空壳。
ENTERPRISE_ONLY_RULES = {
    "commit_message_pattern": "commit message 格式（metadata 规则）",
    "branch_name_pattern": "分支名格式（metadata 规则）",
    "tag_name_pattern": "tag 名格式（metadata 规则）",
    "merge_queue": "合并队列",
    "block_credential_changes": "提交内容里的凭据扫描",
    "required_workflows": "组织级强制工作流",
    "code_scanning_tools": "代码扫描工具要求",
}
# Enterprise 计划名（含自建 GHES）
ENTERPRISE_PLANS = {"enterprise", "enterprise-cloud", "ghes"}

# 官方 REST API 里每种 rule type 的 parameters 字段是固定的。
RULE_PARAMS = {
    "creation": set(),
    "update": set(),
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
    # ★ pull_request.parameters 的必填字段（少一个 → 422）
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
    "tag_name_pattern": {"name", "negate", "operator", "pattern"},
    "file_extension_restriction": {"restricted_file_extensions"},
    "file_path_restriction": {"restricted_file_paths", "ignored_file_paths"},
    "max_file_size": {"max_file_size", "ignored_file_paths"},
    "block_credential_changes": {"credential_types"},
    "merge_queue": {
        "merge_method",
        "min_entries_to_merge",
        "max_entries_to_merge",
        "grouping_strategy",
    },
    "required_workflows": {"required_workflows"},
    "code_scanning_tools": {"analyze", "check"},
}

CONVENTION_RULES = {"branch_name_pattern", "commit_message_pattern", "tag_name_pattern"}

# ★ 只做"加法"的 ruleset：只声明额外必须满足什么（CI、扫描、工作流），
#   本身不构成"分支保护"。
#   → 不要求它们带 pull_request / deletion / non_fast_forward
#     （真正的保护由 01/05/06 这些 ruleset 承担）。
ADDITIVE_RULES = {
    "required_workflows",
    "required_status_checks",
    "required_deployments",
    "code_scanning_tools",
}

# metadata 规则 → profile 里的字段名
PATTERN_BINDING = {
    "commit_message_pattern": "commitMessagePattern",
    "branch_name_pattern": "branchNamePattern",
    "tag_name_pattern": "tagNamePattern",
}


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNINGS.append(msg)


def note(msg):
    NOTES.append(msg)


def rules_of(ruleset, rtype):
    return [r for r in ruleset.get("rules", []) if r.get("type") == rtype]


def is_org_level(ruleset):
    cond = ruleset.get("conditions") or {}
    return "repository_name" in cond


def is_convention_only(ruleset):
    """纯"命名/提交信息规范"的 ruleset —— 不应该要求走 PR。"""
    types = {r.get("type") for r in ruleset.get("rules", [])}
    return bool(types & CONVENTION_RULES) and "pull_request" not in types


def fnmatch_to_regex(pattern):
    """GitHub 用 File::FNM_PATHNAME：`*` 不跨 `/`，`**` 跨层级。"""
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
    if pattern == "~ALL":
        return True
    if pattern == "~DEFAULT_BRANCH":
        return ref == "refs/heads/main"
    return fnmatch_to_regex(pattern).match(ref) is not None


def ruleset_covers(ruleset, ref):
    if ruleset.get("target") not in ("branch", "tag"):
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


def repo_matches(repo, patterns):
    for p in patterns or []:
        if p == "~ALL":
            return True
        if fnmatch_to_regex(p).match(repo):
            return True
    return False


# ---------------------------------------------------------------------------
# 读取
# ---------------------------------------------------------------------------

def load_rulesets(path):
    out = []
    for name in sorted(os.listdir(path)):
        if not name.endswith(".json") or not re.match(r"^\d\d-", name):
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


def load_yaml(path, label):
    if not os.path.exists(path):
        err(f"找不到 {label}：{path}")
        return {}
    try:
        return load_file(path) or {}
    except Exception as exc:  # noqa: BLE001
        err(f"{label} 解析失败：{exc}")
        return {}


# ---------------------------------------------------------------------------
# E1 / E2 / E15：计划与能力
# ---------------------------------------------------------------------------

def check_plan(profile, rulesets, allow_placeholders):
    plan = ((profile.get("org") or {}).get("plan") or "").strip()
    if not plan:
        err("profile.org.plan 没写 —— 必须声明 enterprise / enterprise-cloud / ghes / team / personal")
        return plan
    if plan not in ENTERPRISE_PLANS:
        err(f"profile.org.plan = `{plan}` —— 本目录大量规则依赖 Enterprise 能力。"
            f"计划不对时：API 报 422，UI 导入会**静默丢弃**（ruleset 变空壳 → 什么都不拦）")
    used = set()
    for rs in rulesets:
        for rule in rs.get("rules", []):
            t = rule.get("type")
            if t in ENTERPRISE_ONLY_RULES:
                used.add(t)
    if plan not in ENTERPRISE_PLANS and used:
        err(f"计划 `{plan}` 下使用了 Enterprise-only 规则：{sorted(used)} —— 不会生效")
    elif used:
        note(f"使用了 Enterprise-only 规则：{sorted(used)}（计划 = {plan}）")
    return plan


def check_app_id(profile, allow_placeholders):
    app_id = (profile.get("crCheck") or {}).get("appId")
    if not isinstance(app_id, int) or app_id <= 0:
        msg = (f"profile.crCheck.appId = {app_id!r} —— 必须是 CR Check 这个 GitHub App 的正整数 ID。"
               f"它是 required_status_checks 的 'expected source'，留空 = 同名 check 可伪造 = 门禁形同虚设")
        (warn if allow_placeholders else err)(msg)
        return None
    return app_id


# ---------------------------------------------------------------------------
# E3 / E4 / E5 / E6：跨文件一致性
# ---------------------------------------------------------------------------

def check_check_name_contract(profile, policy, rulesets, app_id, allow_placeholders):
    profile_name = ((profile.get("crCheck") or {}).get("checkName") or "").strip()
    policy_name = (policy.get("checkName") or "").strip()

    if not policy_name:
        err("policy.yaml 里没有 checkName —— 门禁 check 的名字无从谈起")
    elif profile_name and profile_name != policy_name:
        err(f"profile.crCheck.checkName (`{profile_name}`) ≠ policy.yaml 的 checkName "
            f"(`{policy_name}`) —— 两边必须逐字符一致（否则全组织卡死或全组织绕过）")

    wanted = policy_name or profile_name
    if not wanted:
        return

    found = False
    for rs in rulesets:
        for rule in rules_of(rs, "required_status_checks"):
            params = rule.get("parameters") or {}
            for chk in params.get("required_status_checks") or []:
                ctx = chk.get("context")
                if ctx == wanted:
                    found = True
                elif ctx and ctx.startswith("cr/"):
                    err(f"{rs['_file']}: context `{ctx}` 看起来像 CR Check 的 check，"
                        f"但期望的是 `{wanted}` —— 名字必须逐字符一致")
    if not found:
        err(f"没有任何 ruleset 要求 check `{wanted}` —— CR Check 的结论不会被门禁消费")

    # integration_id
    for rs in rulesets:
        for rule in rules_of(rs, "required_status_checks"):
            params = rule.get("parameters") or {}
            for chk in params.get("required_status_checks") or []:
                if chk.get("context") != wanted:
                    continue
                iid = chk.get("integration_id")
                if iid is None:
                    err(f"{rs['_file']}: check `{wanted}` 没有 integration_id —— "
                        f"任何同名 check 都能骗过门禁")
                    continue
                if not isinstance(iid, int) or iid <= 0:
                    err(f"{rs['_file']}: check `{wanted}` 的 integration_id = {iid!r}，必须是正整数")
                    continue
                if app_id and iid != app_id and iid != 123456:
                    # ★ 123456 是占位符 → apply-rulesets.sh 下发时会用
                    #   profile.crCheck.appId 覆盖 → 不算不一致。
                    msg = (f"{rs['_file']}: integration_id = {iid} ≠ profile.crCheck.appId = {app_id} "
                           f"—— 下发时按 profile 覆盖，或直接改 JSON")
                    (warn if allow_placeholders else err)(msg)
                if iid == 123456:
                    warn(f"{rs['_file']}: integration_id 仍是占位符 123456")
                if params.get("strict_required_status_checks_policy") is not True:
                    err(f"{rs['_file']}: 生产分支的 required_status_checks 必须设 "
                        f"strict_required_status_checks_policy = true")


def check_pattern_consistency(profile, rulesets):
    """E5：profile 里的规范正则 ↔ ruleset 里的 metadata 规则，必须逐字符一致。"""
    conv = profile.get("conventions") or {}
    for rtype, field in PATTERN_BINDING.items():
        expected = conv.get(field)
        if expected is None:
            err(f"profile.conventions.{field} 没写 —— 无法校验 {rtype}")
            continue
        try:
            re.compile(expected)
        except re.error as exc:
            err(f"profile.conventions.{field} 不是合法正则：{exc}")
            continue
        for rs in rulesets:
            for rule in rules_of(rs, rtype):
                actual = (rule.get("parameters") or {}).get("pattern")
                if actual != expected:
                    err(f"{rs['_file']}: {rtype} 的 pattern = {actual!r}，"
                        f"与 profile.conventions.{field} = {expected!r} 不一致 —— "
                        f"服务端与本地 hook 会判出两套结果")
                if (rule.get("parameters") or {}).get("operator") != "regex":
                    err(f"{rs['_file']}: {rtype} 的 operator 必须是 \"regex\" —— "
                        f"API 默认不是正则模式")


def check_managed_branches(profile, policy, rulesets):
    """E6：managedBranches ⊆ ruleset 覆盖范围。"""
    managed = list(policy.get("managedBranches") or [])
    managed += list((profile.get("crCheck") or {}).get("managedBranches") or [])
    for branch in sorted(set(managed)):
        ref = branch if branch.startswith("refs/") else f"refs/heads/{branch}"
        if not any(ruleset_covers(rs, ref) for rs in rulesets):
            err(f"managedBranches 里的 `{branch}` 没有任何 ruleset 覆盖 —— "
                f"该分支的 PR 永远等不到 check")


# ---------------------------------------------------------------------------
# E7 / E8 / E9：结构与严格度
# ---------------------------------------------------------------------------

def check_scope_shape(rulesets):
    for rs in rulesets:
        f = rs["_file"]
        cond = rs.get("conditions") or {}
        org_level = "repository_name" in cond
        target = rs.get("target")
        if org_level:
            if target == "branch" and "ref_name" not in cond:
                err(f"{f}: 组织级 ruleset 缺少 ref_name —— 作用范围不明")
            if target == "code_scanning" and "ref_name" in cond:
                warn(f"{f}: code_scanning ruleset 一般不需要 ref_name")
        else:
            if "ref_name" in cond and target in ("branch", "tag"):
                pass
            elif target in ("branch", "tag"):
                err(f"{f}: 仓库级 {target} ruleset 缺少 ref_name —— 不知道管哪些分支")
        # 名称里带 org- 的应当是组织级，反之亦然（防手滑把组织级 JSON 打到仓库端点）
        name = rs.get("name") or ""
        if name.startswith("org-") and not org_level:
            err(f"{f}: 名字叫 `{name}` 却没有 repository_name 条件 —— "
                f"它会被当成仓库级规则下发，作用范围只有 1 个仓库")
        if name.startswith("repo-") and org_level:
            err(f"{f}: 名字叫 `{name}` 却带了 repository_name —— 组织级 + 仓库级重复，会双重计数")


def check_branch_basics(rulesets):
    for rs in rulesets:
        if rs.get("target") != "branch":
            continue
        f = rs["_file"]
        if is_convention_only(rs):
            continue
        types = {r.get("type") for r in rs.get("rules", [])}
        if types and types <= ADDITIVE_RULES:
            # 纯加法 ruleset：只声明"额外要跑什么"，不负责保护分支
            continue
        if not rules_of(rs, "pull_request"):
            err(f"{f}: branch ruleset 缺少 pull_request 规则 —— 等于允许直接 push")
        if not rules_of(rs, "deletion"):
            err(f"{f}: branch ruleset 缺少 deletion 规则 —— 受保护分支可被删除")
        if not rules_of(rs, "non_fast_forward"):
            err(f"{f}: branch ruleset 缺少 non_fast_forward 规则 —— 可被 force push")
        pr = rules_of(rs, "pull_request")
        if pr:
            methods = (pr[0].get("parameters") or {}).get("allowed_merge_methods")
            if methods is None:
                warn(f"{f}: pull_request 没限定 allowed_merge_methods")
            elif len(methods) > 1:
                warn(f"{f}: allowed_merge_methods = {methods} —— 多合并方式会削弱可追溯性")


def prod_tier_of(rs, production_patterns):
    """判断这条 ruleset 是不是"生产级"的。

    返回：
      "prod"      → 直接作用在生产仓库的生产分支上 → 必须最严
      "baseline"  → 组织级基线（~ALL / ~DEFAULT_BRANCH）→ 只提示，不报错
      None        → 与生产无关
    """
    cond = rs.get("conditions") or {}
    includes = (cond.get("ref_name") or {}).get("include") or []
    repo_inc = (cond.get("repository_name") or {}).get("include") or []

    touches_prod_ref = (
        "refs/heads/main" in includes
        or "refs/heads/release/prod" in includes
        or "refs/heads/release/**" in includes
    )
    if not touches_prod_ref:
        return None

    if not repo_inc:
        # 仓库级 ruleset：由 apply 脚本按仓库分层下发
        return "prod"

    # 组织级
    if "~ALL" in repo_inc:
        return "baseline"
    if any(repo_matches("platform-sample", [p]) for p in repo_inc) or \
       any(p in production_patterns for p in repo_inc):
        return "prod"
    return None


def check_prod_strictness(profile, rulesets):
    strictness = profile.get("strictness") or {}
    prod_patterns = ((profile.get("org") or {}).get("repos") or {}).get("production") or []
    want_reviewers = strictness.get("productionMinReviewers", 2)
    want_signed = bool(strictness.get("requireSignedCommits", True))

    for rs in rulesets:
        if rs.get("target") != "branch":
            continue
        f = rs["_file"]
        if is_convention_only(rs):
            continue
        types = {r.get("type") for r in rs.get("rules", [])}
        if "merge_queue" in types:
            # merge queue 是"配套"ruleset：它定义队列怎么合，
            # 真正的严格度由 prod-branch-gate 那条承担（GitHub 取所有命中规则的并集）
            continue
        tier = prod_tier_of(rs, prod_patterns)
        if tier is None:
            continue

        pr = rules_of(rs, "pull_request")
        if not pr:
            err(f"{f}: 覆盖生产分支的 ruleset 没有 pull_request 规则")
            continue
        params = pr[0].get("parameters") or {}
        n = params.get("required_approving_review_count", 0)
        methods = params.get("allowed_merge_methods") or []

        if tier == "baseline":
            if n < want_reviewers:
                warn(f"{f}: 组织级基线只要求 {n} 个 reviewer —— "
                     f"生产仓库靠另一条 ruleset 补齐到 {want_reviewers}")
            if want_signed and not rules_of(rs, "required_signatures"):
                warn(f"{f}: 组织级基线没有 required_signatures")
            continue

        if n < want_reviewers:
            err(f"{f}: 生产分支只有 {n} 个 reviewer —— profile 要求 ≥ {want_reviewers}")
        if methods != ["squash"]:
            err(f"{f}: 生产分支的 allowed_merge_methods = {methods} —— "
                f"必须严格是 [\"squash\"]（线性历史 + 可追溯）")
        if want_signed and not rules_of(rs, "required_signatures"):
            warn(f"{f}: 生产分支没有 required_signatures —— "
                 f"profile.strictness.requireSignedCommits = true")


def check_bypass(profile, rulesets):
    allow = profile.get("bypassAllowlist") or []
    allowed_ids = {a.get("actorId") for a in allow if isinstance(a, dict)}
    if allow:
        note(f"显式豁免名单（bypassAllowlist）：{sorted(str(x) for x in allowed_ids)}")
    for rs in rulesets:
        f = rs["_file"]
        for actor in rs.get("bypass_actors") or []:
            mode = actor.get("bypass_mode", "always")
            atype = actor.get("actor_type")
            aid = actor.get("actor_id")
            if mode == "always":
                if aid not in allowed_ids:
                    err(f"{f}: bypass_actors 里有 bypass_mode = \"always\"（actor {aid}）—— "
                        f"该 actor 可直接 push 受保护分支。"
                        f"★ 若确需豁免（如 Dependabot），把它写进 "
                        f"enterprise-profile.yaml 的 bypassAllowlist")
            if atype == "Integration" and aid not in allowed_ids:
                err(f"{f}: bypass_actors 里出现了 GitHub App（actor_type=Integration）—— "
                    f"★ 绝不能把 CR Check App 放进来：那等于同时给它「发结论」和「跳过规则」两把钥匙")


# ---------------------------------------------------------------------------
# E11 / E12 / E13 / E14：push 门禁与字段白名单
# ---------------------------------------------------------------------------

def check_push_guard(profile, rulesets):
    guard = profile.get("pushGuard") or {}
    want_ext = set(guard.get("restrictedExtensions") or [])
    want_paths = set(guard.get("restrictedPaths") or [])
    want_size = guard.get("maxFileSizeMB")
    want_cred = bool(guard.get("blockCredentialChanges", True))

    push_sets = [rs for rs in rulesets if rs.get("target") == "push"]
    if not push_sets:
        err("没有任何 target=push 的 ruleset —— 密钥 / 大文件 / 凭据可以直接 push 进仓库")
        return
    for rs in push_sets:
        f = rs["_file"]
        exts = set()
        for rule in rules_of(rs, "file_extension_restriction"):
            exts.update((rule.get("parameters") or {}).get("restricted_file_extensions") or [])
        missing = want_ext - exts
        if missing:
            err(f"{f}: push ruleset 少了扩展名限制 {sorted(missing)}")
        paths = set()
        for rule in rules_of(rs, "file_path_restriction"):
            paths.update((rule.get("parameters") or {}).get("restricted_file_paths") or [])
        missing_p = want_paths - paths
        if missing_p:
            err(f"{f}: push ruleset 少了路径限制 {sorted(missing_p)}")
        for rule in rules_of(rs, "max_file_size"):
            size = (rule.get("parameters") or {}).get("max_file_size")
            if not isinstance(size, int) or size <= 0:
                err(f"{f}: max_file_size = {size!r} —— 必须是正整数，单位是 MB")
            elif want_size and size != want_size:
                err(f"{f}: max_file_size = {size} MB ≠ profile.pushGuard.maxFileSizeMB = {want_size}")
        if want_cred and not rules_of(rs, "block_credential_changes"):
            warn(f"{f}: 没有 block_credential_changes —— "
                 f"profile.pushGuard.blockCredentialChanges = true")


def check_rule_params(rulesets):
    for rs in rulesets:
        f = rs["_file"]
        for rule in rs.get("rules", []):
            rtype = rule.get("type")
            if rtype not in RULE_PARAMS:
                err(f"{f}: 未知的 rule type `{rtype}` —— GitHub 会返回 422")
                continue
            params = rule.get("parameters") or {}
            unknown = set(params) - RULE_PARAMS[rtype]
            if unknown:
                err(f"{f}: rule `{rtype}` 里有 API 不存在的字段 {sorted(unknown)} —— GitHub 返回 422")
            if rtype == "pull_request" and "parameters" in rule:
                must = RULE_PARAMS["pull_request.required"]
                missing = must - set(params)
                if missing:
                    err(f"{f}: rule `pull_request` 的 parameters 缺少必填字段 {sorted(missing)} "
                        f"—— GitHub 返回 422（★ parameters 可以整个省略，但不能只写一半）")
            if rtype == "required_status_checks":
                if not params.get("required_status_checks"):
                    err(f"{f}: rule `required_status_checks` 缺少必填字段 'required_status_checks'")
            if rtype in ("branch_name_pattern", "commit_message_pattern", "tag_name_pattern"):
                op = params.get("operator")
                if op not in ("regex", "starts_with", "ends_with", "contains"):
                    err(f"{f}: rule `{rtype}` 的 operator = {op!r} 非法")
                pat = params.get("pattern")
                if op == "regex" and pat:
                    try:
                        re.compile(pat)
                    except re.error as exc:
                        err(f"{f}: rule `{rtype}` 的 pattern 不是合法正则：{exc}")


def check_names_unique(rulesets):
    seen = {}
    for rs in rulesets:
        name = rs.get("name")
        if not name:
            err(f"{rs['_file']}: 缺 name")
            continue
        if name in seen:
            err(f"{rs['_file']} 与 {seen[name]} 同名（{name}）—— apply 脚本会误更新")
        seen[name] = rs["_file"]


def check_merge_queue(rulesets):
    for rs in rulesets:
        if rs.get("target") != "branch":
            continue
        mq = rules_of(rs, "merge_queue")
        if not mq:
            continue
        f = rs["_file"]
        if not rules_of(rs, "pull_request"):
            err(f"{f}: 用了 merge_queue 却没有 pull_request 规则 —— 队列不会建立")
        pr = rules_of(rs, "pull_request")
        if pr:
            n = (pr[0].get("parameters") or {}).get("required_approving_review_count", 0)
            if n < 1:
                err(f"{f}: merge_queue 场景下 required_approving_review_count 必须 ≥ 1")
        params = mq[0].get("parameters") or {}
        lo = params.get("min_entries_to_merge", 1)
        hi = params.get("max_entries_to_merge", 1)
        if isinstance(lo, int) and isinstance(hi, int) and lo > hi:
            err(f"{f}: merge_queue 的 min_entries_to_merge({lo}) > max_entries_to_merge({hi})")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=_HERE, help="ruleset JSON 所在目录")
    ap.add_argument("--profile", default=PROFILE_PATH, help="enterprise-profile.yaml 路径")
    ap.add_argument("--strict", action="store_true", help="警告也算失败")
    ap.add_argument("--allow-placeholders", action="store_true",
                    help="把「占位符未填」类问题降级为警告（只审模板时用）")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"目录不存在：{root}")
        return 2

    rulesets = load_rulesets(root)
    if not rulesets:
        print(f"{root} 里没有找到 ruleset JSON")
        return 1

    profile = load_yaml(os.path.abspath(args.profile), "enterprise-profile.yaml")
    policy = load_yaml(POLICY_PATH, "policy.yaml")

    plan = check_plan(profile, rulesets, args.allow_placeholders)
    app_id = check_app_id(profile, args.allow_placeholders)
    check_check_name_contract(profile, policy, rulesets, app_id, args.allow_placeholders)
    check_pattern_consistency(profile, rulesets)
    check_managed_branches(profile, policy, rulesets)
    check_scope_shape(rulesets)
    check_branch_basics(rulesets)
    check_prod_strictness(profile, rulesets)
    check_bypass(profile, rulesets)
    check_push_guard(profile, rulesets)
    check_rule_params(rulesets)
    check_names_unique(rulesets)
    check_merge_queue(rulesets)

    org = profile.get("org") or {}
    print(f"检查了 {len(rulesets)} 条 ruleset"
          f"（plan={plan!r}，org={org.get('name')!r}，"
          f"checkName={(profile.get('crCheck') or {}).get('checkName')!r}）\n")

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
    print("企业版真正验证门禁是否生效，必须在**测试仓库**上提一个故意不合规的 PR：")
    print("  · 不带 CR 号的 commit → push 时 ref 必须不更新")
    print("  · 不合规 PR → 必须合不了")
    print("  · 合规 PR → 能合")
    print("★ 下发前先用 probe-enterprise-capabilities.sh 确认你们的计划真的支持这些 rule type。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
