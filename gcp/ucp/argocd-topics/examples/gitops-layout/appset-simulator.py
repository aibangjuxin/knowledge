#!/usr/bin/env python3
"""
精确模拟 ApplicationSet → Application 的展开，并做**交叉校验**。

**它和 preview-appset.py 的区别**
  preview-appset.py   —— 只列矩阵（谁会生成哪些 Application），近似模拟。
  appset-simulator.py —— **真的把 Go template 渲染出来**，拿到每个 Application 的
                        完整 spec（project / source.path / destination / syncPolicy），
                        然后拿这些字段去和 AppProject、磁盘上的目录对账。

**它抓的是 preview 抓不到的错**
  ① Application **重名**：两个 AppSet 生成同一个名字 → Argo CD 里互相覆盖
     （ownerReference 冲突，删一个另一个也完蛋）
  ② destination 不被 AppProject 允许 → 同步被拒
     "not match any of the allowed destinations"
  ③ project 不存在 → 同步被拒 "project not found"
  ④ source.path 渲染出来在磁盘上不存在 → 同步失败
  ⑤ 模板变量没人生成（missingkey=error）→ **整个 AppSet** 报错
  ⑥ prod 和 dev 的同步策略不一致（prod 也在 selfHeal）→ 半夜自动改线上

**它不是什么**
  不连集群、不调用真正的 Go 模板引擎。
  只实现 Argo CD 用得到的模板语法子集（见 render_template 的注释）。

**用法**
    python3 appset-simulator.py
    python3 appset-simulator.py --path <目录>   # 指定 GitOps 仓库根目录
    python3 appset-simulator.py --json          # 机器可读输出
    python3 appset-simulator.py --verbose       # 打印每个 Application 的完整 spec

**退出码**：0 = 通过；1 = 有 ERROR。
"""

import argparse
import glob
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))

def _add_lib_path():
    """找到 examples/lib/（yamlmin.py 所在处）。"""
    here = os.path.dirname(os.path.abspath(__file__))
    for cand in (os.path.join(here, "lib"), os.path.join(here, "..", "lib")):
        if os.path.isdir(cand):
            sys.path.insert(0, os.path.abspath(cand))
            return
    sys.stderr.write("找不到 yamlmin.py —— 请确认 examples/lib/ 目录在位\n")
    sys.exit(2)


_add_lib_path()

from yamlmin import load_all_files, load_file, flatten, select_equal  # noqa: E402

ERRORS = []
WARNINGS = []
NOTES = []

SEVERITY = {
    "prod-selfheal": "warn",
}
IGNORES = []
OVERRIDES = {}


def report(rule, msg):
    """按规则级别输出（可用策略文件调整）。"""
    if any(item.endswith(":" + rule) for item in IGNORES):
        return
    sev = OVERRIDES.get(rule, SEVERITY.get(rule, "warn"))
    line = f"[{rule}] {msg}"
    if sev == "error":
        ERRORS.append(line)
    elif sev == "warn":
        WARNINGS.append(line)
    else:
        NOTES.append(line)


def load_policy(root):
    """读取 appset-simulator.policy.yaml（可选）。"""
    global IGNORES, OVERRIDES
    path = os.path.join(root, "appset-simulator.policy.yaml")
    if not os.path.isfile(path):
        return
    try:
        data = load_file(path) or {}
    except Exception as exc:
        ERRORS.append(f"[{os.path.basename(path)}] 解析失败：{exc}")
        return
    IGNORES = data.get("ignores") or []
    OVERRIDES = data.get("severities") or {}


class TemplateError(Exception):
    """模板渲染失败（缺变量、语法不支持等）。"""


# ---------------------------------------------------------------------------
# Go template 子集
# ---------------------------------------------------------------------------

HELM_ESCAPE = re.compile(r"\$\{\{(.*?)\}\}", re.S)
TEMPLATE = re.compile(r"\{\{(.*?)\}\}", re.S)


def lookup(params, path):
    """按 `a.b.c` 取值。params 既是扁平 dict，也支持嵌套。"""
    if path in params:
        return params[path]
    cur = params
    for part in path.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            raise KeyError(path)
    return cur


def evaluate(expr, params):
    """求值一个模板表达式。"""
    expr = expr.strip()
    if not expr:
        raise TemplateError("空表达式")

    # default "兜底" .foo
    m = re.match(r"^default\s+(.+?)\s+(\.[\w.]+)$", expr, re.S)
    if m:
        raw_default, path = m.group(1).strip(), m.group(2)
        raw_default = raw_default.strip("\"'")
        try:
            value = lookup(params, path[1:])
        except KeyError:
            return raw_default
        return raw_default if value in (None, "") else value

    if expr.startswith("."):
        path = expr[1:]
        try:
            return lookup(params, path)
        except KeyError:
            raise TemplateError(f"缺少变量 {expr}")

    raise TemplateError(f"不支持的模板表达式: {expr!r}")


def render_template(text, params):
    """渲染 Argo CD 用得到的 Go template 子集。

    支持：
      {{.foo}}              取值
      {{.foo.bar}}          嵌套取值
      {{default "x" .foo}}  取值，为空时用默认值
      ${{.foo}}             转义 → ${.foo}（交给 Helm 处理）
    """
    if text is None:
        return None
    text = HELM_ESCAPE.sub(lambda m: "${" + m.group(1) + "}", text)

    def repl(match):
        value = evaluate(match.group(1), params)
        if value is None:
            return ""
        if isinstance(value, bool):
            return "true" if value else "false"
        return str(value)

    return TEMPLATE.sub(repl, text)


# ---------------------------------------------------------------------------
# 生成器
# ---------------------------------------------------------------------------

def git_file_params(root, gen, notes):
    """git 文件生成器：按 glob 找清单文件 → 展平成模板参数。"""
    results = []
    for spec in gen.get("files") or []:
        pattern = spec.get("path", "")
        matches = sorted(glob.glob(os.path.join(root, pattern), recursive=True))
        if not matches:
            notes.append(f"git 生成器的 glob 没匹配到任何文件：{pattern}")
            continue
        flat_keys = spec.get("flatten")
        selector = spec.get("selector")
        for path in matches:
            try:
                data = load_file(path)
            except Exception as exc:
                ERRORS.append(f"[{os.path.relpath(path, root)}] 解析失败：{exc}")
                continue
            if not isinstance(data, dict):
                continue
            if selector:
                try:
                    if not select_equal(data, selector):
                        continue
                except Exception as exc:
                    ERRORS.append(f"[{os.path.relpath(path, root)}] selector 解析失败：{exc}")
                    continue
            params = flatten(data, flat_keys) if flat_keys else flatten(data)
            params.setdefault("_file", os.path.relpath(path, root))
            results.append(params)
    return results


def git_dir_params(root, gen, notes):
    """git 目录生成器：产出 .path.path / .path.basename。"""
    results = []
    for spec in gen.get("directories") or []:
        pattern = spec.get("path", "")
        for path in sorted(glob.glob(os.path.join(root, pattern), recursive=True)):
            if not os.path.isdir(path):
                continue
            rel = os.path.relpath(path, root)
            results.append({"path.path": rel, "path.basename": os.path.basename(rel)})
    return results


def list_params(gen):
    """list 生成器：elements 直接就是参数。"""
    out = []
    for element in gen.get("elements") or []:
        params = dict(element)
        if "path" in params and "path.basename" not in params:
            params["path.basename"] = os.path.basename(str(params["path"]))
        out.append(params)
    return out


def get(obj, *path, default=None):
    cur = obj
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def generate(root, generators, notes):
    """跑一遍生成器，返回参数集合列表。"""
    all_params = []
    for gen in generators:
        if not isinstance(gen, dict):
            continue
        if "git" in gen:
            g = gen["git"]
            if g.get("files"):
                all_params.extend(git_file_params(root, g, notes))
            elif g.get("directories"):
                all_params.extend(git_dir_params(root, g, notes))
            else:
                notes.append("git 生成器既没有 files 也没有 directories —— 未模拟")
        elif "list" in gen:
            all_params.extend(list_params(gen["list"]))
        elif "clusters" in gen:
            notes.append("clusters 生成器依赖**已注册的真实集群**，未模拟"
                         "（用 `argocd cluster list` 确认注册情况）")
        elif "matrix" in gen:
            matrix = gen["matrix"]
            combos = [[]]
            for sub in matrix.get("generators") or []:
                sub_params = generate(root, [sub], notes)
                combos = [c + [p] for c in combos for p in sub_params]
            merged = []
            for combo in combos:
                params = {}
                for part in combo:
                    params.update(part)
                merged.append(params)
            all_params.extend(merged)
        elif "merge" in gen:
            merge = gen["merge"]
            merged = []
            for sub in merge.get("generators") or []:
                for params in generate(root, [sub], notes):
                    item = dict(params)
                    item.update({k: v for k, v in merged[-1].items()
                                 if k not in item} if merged else {})
                    merged.append(item)
            all_params.extend(merged)
        else:
            notes.append(f"未知的生成器类型：{list(gen.keys())}")
    return all_params


# ---------------------------------------------------------------------------
# AppProject 索引
# ---------------------------------------------------------------------------

def load_appprojects(root):
    base = os.path.join(root, "bootstrap", "appprojects")
    projects = {}
    if not os.path.isdir(base):
        return projects
    for name in sorted(os.listdir(base)):
        if not name.endswith((".yaml", ".yml")):
            continue
        path = os.path.join(base, name)
        try:
            doc = load_file(path)
        except Exception as exc:
            ERRORS.append(f"[{name}] 解析失败：{exc}")
            continue
        if not isinstance(doc, dict) or doc.get("kind") != "AppProject":
            continue
        pname = (doc.get("metadata") or {}).get("name", "")
        spec = doc.get("spec") or {}
        projects[pname] = {
            "destinations": spec.get("destinations") or [],
            "file": os.path.relpath(path, root),
        }
    return projects


def destination_allowed(project, server, namespace):
    """Application 的 destination 是否被 AppProject 允许。"""
    if project is None:
        return True, "AppProject 不存在"
    for dest in project["destinations"]:
        dserver = dest.get("server", "")
        dnamespace = dest.get("namespace", "")
        if dserver not in ("*", server):
            continue
        if dnamespace == "*":
            return True, ""
        if dnamespace == namespace:
            return True, ""
        if "*" in dnamespace:
            pattern = "^" + re.escape(dnamespace).replace(r"\*", ".*") + "$"
            if re.match(pattern, namespace or ""):
                return True, ""
    return False, (f"server={server} namespace={namespace} 不在 "
                   f"{project['file']} 的 destinations 里")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=_HERE)
    ap.add_argument("--json", action="store_true", help="输出 JSON")
    ap.add_argument("--verbose", action="store_true", help="打印完整 spec")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    load_policy(root)
    base = os.path.join(root, "bootstrap", "applicationsets")
    if not os.path.isdir(base):
        print(f"找不到 {base}")
        return 2

    projects = load_appprojects(root)
    apps = []
    seen_names = {}
    conflicts = {}

    for fname in sorted(os.listdir(base)):
        if not fname.endswith((".yaml", ".yml")):
            continue
        path = os.path.join(base, fname)
        try:
            docs = load_all_files(path)
        except Exception as exc:
            ERRORS.append(f"[{fname}] 解析失败：{exc}")
            continue
        for doc in docs:
            if not isinstance(doc, dict) or doc.get("kind") != "ApplicationSet":
                continue
            meta = doc.get("metadata") or {}
            spec = doc.get("spec") or {}
            tpl = spec.get("template") or {}
            tpl_spec = tpl.get("spec") or {}
            appset_name = meta.get("name", fname)

            notes = []
            params_list = generate(root, spec.get("generators") or [], notes)
            for msg in notes:
                NOTES.append(f"[{appset_name}] {msg}")

            if not params_list:
                WARNINGS.append(f"[{appset_name}] 一个 Application 都没生成"
                                f"（检查 glob / selector / 文件名）")
                continue

            for params in params_list:
                try:
                    name = render_template(tpl.get("metadata", {}).get("name", ""), params)
                    project = render_template(tpl_spec.get("project", ""), params)
                    src_path = render_template(get(tpl_spec, "source", "path", default=""), params)
                    dest = tpl_spec.get("destination") or {}
                    server = render_template(dest.get("server", ""), params)
                    namespace = render_template(dest.get("namespace", ""), params)
                except TemplateError as exc:
                    ERRORS.append(f"[{appset_name}] 模板渲染失败：{exc}"
                                  f"（missingkey=error → 整个 AppSet 会报错）")
                    continue

                src_file = params.get("_file", "?")
                app = {
                    "appset": appset_name,
                    "name": name,
                    "project": project,
                    "source.path": src_path,
                    "destination.server": server,
                    "destination.namespace": namespace,
                    "file": src_file,
                }
                apps.append(app)

                # ① 名字冲突
                if name in seen_names:
                    conflicts.setdefault(name, (seen_names[name], appset_name))
                else:
                    seen_names[name] = appset_name

                # ② project 存在
                if not project:
                    ERRORS.append(f"[{name}] 没有 project → 落到 default（最宽松）")
                elif project not in projects:
                    ERRORS.append(f"[{name}] project={project} 不存在"
                                  f"（bootstrap/appprojects/ 下没有）→ 同步被拒 "
                                  f"\"project not found\"")

                # ③ destination 被 AppProject 允许
                proj = projects.get(project)
                allowed, why = destination_allowed(proj, server, namespace)
                if not allowed:
                    ERRORS.append(f"[{name}] {why} → 同步被拒 "
                                  f"\"not match any of the allowed destinations\"")

                # ④ source.path 存在
                if src_path and not os.path.isdir(os.path.join(root, src_path)):
                    ERRORS.append(f"[{name}] source.path={src_path} 在磁盘上不存在"
                                  f"（渲染自 {src_file}）→ 同步失败")
                elif src_path and not os.path.isfile(
                        os.path.join(root, src_path, "kustomization.yaml")):
                    ERRORS.append(f"[{name}] source.path={src_path} 里没有 kustomization.yaml")

                # ⑤ 同步策略：prod 不该和 dev 一样
                sync = get(tpl_spec, "syncPolicy", "automated", default={}) or {}
                if namespace.startswith("platform-prod") and sync.get("selfHeal"):
                    report("prod-selfheal",
                           f"[{name}] prod 命名空间却开了 selfHeal=true"
                           f" → 半夜会自动把线上改回去"
                           f"（要人工审批就拆 prod 专用 AppSet）")

    # ---- 输出 ----
    for name, (first, second) in sorted(conflicts.items()):
        ERRORS.append(f"[{name}] Application 名字冲突：{first} 和 {second} 都生成它"
                      f" → Argo CD 里互相覆盖，ownerReference 冲突")

    if args.json:
        print(json.dumps({"apps": apps, "errors": ERRORS,
                          "warnings": WARNINGS, "notes": NOTES},
                         ensure_ascii=False, indent=2))
    else:
        print(f"生成 {len(apps)} 个 Application（来自 {len(seen_names)} 个唯一名字）\n")
        print(f"  {'APPLICATION':<24} {'PROJECT':<14} {'NAMESPACE':<14} SOURCE PATH")
        for app in sorted(apps, key=lambda a: a["name"]):
            print(f"  {app['name']:<24} {app['project']:<14} "
                  f"{app['destination.namespace']:<14} {app['source.path']}")
        if args.verbose:
            print()
            for app in apps:
                print(f"  --- {app['name']} ---")
                print(f"      appset   : {app['appset']}")
                print(f"      来自清单  : {app['file']}")
                print(f"      project   : {app['project']}")
                print(f"      source    : {app['source.path']}")
                print(f"      dest      : {app['destination.server']}"
                      f" / {app['destination.namespace']}")
        print()
        for msg in WARNINGS:
            print(f"[WARN ] {msg}")
        for msg in ERRORS:
            print(f"[ERROR] {msg}")
        for msg in NOTES:
            print(f"[NOTE ] {msg}")

    print()
    if ERRORS:
        print(f"✗ {len(ERRORS)} 个错误，{len(WARNINGS)} 个警告")
        return 1
    print(f"✓ 模拟通过（{len(WARNINGS)} 个警告）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
