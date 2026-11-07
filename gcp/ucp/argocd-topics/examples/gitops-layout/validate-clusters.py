#!/usr/bin/env python3
"""
校验 bootstrap/clusters/** 的一致性 —— 「防止手抄漂移」的守门人。

**它解决什么问题**
  clusters/<cluster>/components/<component>.yaml 把 server / env / project /
  namespace 抄了 N 遍（因为 git 文件生成器不暴露文件路径）。
  抄错一个字母的后果：
    · server 写错   → Application 卡 "Unable to connect"
    · project 写错  → 同步被拒 "not match any of the allowed destinations"
    · env 写错      → 渲染到**别的环境**的 overlay（静默生效！最危险）
  这个脚本把这些错误在 **CI / 提交前** 就抓出来。

**它不是什么**
  不是 Argo CD controller，不连集群，不解析 AppProject 的全部语义。

**用法**
    python3 validate-clusters.py                # 在 gitops-layout/ 目录运行
    python3 validate-clusters.py --path <目录>  # 指定 GitOps 仓库根目录

**退出码**：0 = 通过（有 warning 也算通过）；1 = 有 ERROR。
"""

import argparse
import os
import re
import sys

# 与 bootstrap/applicationsets/*.yaml 的 flatten 列表保持一致
REQUIRED_FIELDS = ["component", "cluster", "server", "env", "project", "namespace"]

VALID_ENVS = ["dev", "stg", "prod"]

errors = []
warnings = []


def err(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


# ---------------------------------------------------------------- 解析工具 --

def parse_flat_yaml(path):
    """解析扁平的 key: value 文件（不依赖 PyYAML）。"""
    data = {}
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.split("#", 1)[0].strip()
            if not line or ":" not in line:
                continue
            key, value = line.split(":", 1)
            data[key.strip()] = value.strip().strip("'\"")
    return data


def parse_appsets(root):
    """
    从 bootstrap/applicationsets/*.yaml 里抽出：
      component  → 组件名（由 generator 的 glob 末段决定）
      glob       → 组件清单的匹配模式
      path_tpl   → template.spec.source.path 的模板
    """
    base = os.path.join(root, "bootstrap", "applicationsets")
    appsets = []
    if not os.path.isdir(base):
        return appsets
    for name in sorted(os.listdir(base)):
        if not name.endswith((".yaml", ".yml")):
            continue
        path = os.path.join(base, name)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        # 只取真正生效的 AppSet（_alternatives/ 是备选方案，跳过）
        if "kind: ApplicationSet" not in text:
            continue
        globs = re.findall(r'path:\s*"?([^"\s]*clusters/[^"\s]*/components/[^"\s]+\.yaml)"?', text)
        paths = re.findall(r"path:\s*'([^']*overlays[^']*)'", text)
        if not globs or not paths:
            continue
        glob = globs[0]
        component = os.path.basename(glob)[: -len(".yaml")]
        appsets.append({
            "file": os.path.relpath(path, root),
            "component": component,
            "glob": glob,
            "path_tpl": paths[0],
        })
    return appsets


def _iter_list_block(path, key):
    """
    产出某个 key 下面的列表项（逐行）。

    YAML 里列表项可以与 key **同缩进**：
        destinations:
        - server: 'x'
    所以结束条件是「缩进更浅，且不是列表项」。
    """
    in_block = False
    base_indent = 0
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            indent = len(raw) - len(raw.lstrip())
            if not in_block:
                if stripped.startswith(key + ":"):
                    in_block = True
                    base_indent = indent
                continue
            is_item = stripped.startswith("-")
            if indent < base_indent or (indent == base_indent and not is_item):
                break
            yield indent, stripped


def parse_appproject_destinations(path):
    """取出 destinations 里的 server 列表。"""
    servers = []
    for _, stripped in _iter_list_block(path, "destinations"):
        m = re.match(r"-\s*server:\s*'?([^'\s]+)'?", stripped)
        if m:
            servers.append(m.group(1))
    return servers


def parse_appproject_cluster_whitelist(path):
    """取出 clusterResourceWhitelist 的 (group, kind) 集合。"""
    allowed = set()
    cur_group = None
    for _, stripped in _iter_list_block(path, "clusterResourceWhitelist"):
        m = re.match(r"-\s*group:\s*'?([^'\s]+)'?", stripped)
        if m:
            cur_group = m.group(1)
            continue
        m = re.match(r"kind:\s*'?([^'\s]+)'?", stripped)
        if m and cur_group:
            allowed.add((cur_group, m.group(1)))
    return allowed


def kustomize_resources(path):
    """取出 kustomization.yaml 里 resources: 下列出的条目（忽略注释）。"""
    items = []
    in_block = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if not in_block:
                if stripped.startswith("resources:"):
                    in_block = True
                continue
            if stripped.startswith("-"):
                items.append(stripped.lstrip("- ").strip().strip("'\""))
            else:
                break
    return items


def glob_to_regex(pattern):
    """把 git generator 的 glob（只支持 *）转成正则。"""
    return re.compile("^" + re.escape(pattern).replace("\\*", "[^/]*") + "$")


# ------------------------------------------------------------------ 主流程 --

def collect_clusters(root):
    base = os.path.join(root, "bootstrap", "clusters")
    clusters = {}
    if not os.path.isdir(base):
        sys.exit(f"找不到 {base}")
    for name in sorted(os.listdir(base)):
        d = os.path.join(base, name)
        if not os.path.isdir(d) or name.startswith("_"):
            continue
        meta_path = os.path.join(d, "cluster.yaml")
        meta = {}
        if os.path.isfile(meta_path):
            meta = parse_flat_yaml(meta_path)
        else:
            err(f"[clusters/{name}] 缺少 cluster.yaml（集群元信息）")
        comps = {}
        comp_dir = os.path.join(d, "components")
        if os.path.isdir(comp_dir):
            for cname in sorted(os.listdir(comp_dir)):
                if not cname.endswith((".yaml", ".yml")):
                    continue
                cpath = os.path.join(comp_dir, cname)
                comps[cname[: -len(".yaml")]] = (cpath, parse_flat_yaml(cpath))
        clusters[name] = {"meta": meta, "comps": comps, "dir": d}
    return clusters


def check_cluster(root, name, c):
    meta = c["meta"]
    rel = f"clusters/{name}"

    # ---- 集群身份 ---------------------------------------------------------
    if meta.get("cluster") and meta["cluster"] != name:
        err(f"[{rel}/cluster.yaml] cluster={meta['cluster']} != 目录名 {name}")

    env = meta.get("env")
    if not env:
        err(f"[{rel}/cluster.yaml] 缺少 env")
    else:
        if env not in VALID_ENVS:
            err(f"[{rel}/cluster.yaml] env={env} 不在 {VALID_ENVS} 里")
        if not name.startswith(env + "-"):
            err(f"[{rel}/cluster.yaml] 集群名应以 env 前缀开头：{env}-*（当前 {name}）")

    project = meta.get("project")
    namespace = meta.get("namespace")
    if env and project and project != f"platform-{env}":
        warn(f"[{rel}/cluster.yaml] project={project} 不符合约定 platform-{env}")
    if env and namespace and namespace != f"platform-{env}":
        warn(f"[{rel}/cluster.yaml] namespace={namespace} 不符合约定 platform-{env}")

    # ---- 组件开关 ---------------------------------------------------------
    for comp, (cpath, data) in c["comps"].items():
        crel = os.path.relpath(cpath, root)
        missing = [f for f in REQUIRED_FIELDS if f not in data]
        if missing:
            err(f"[{crel}] 缺字段: {', '.join(missing)}  ← missingkey=error 会让**整个 AppSet**报错")
            continue
        if data["component"] != comp:
            err(f"[{crel}] component={data['component']} != 文件名 {comp}")
        if data["cluster"] != name:
            err(f"[{crel}] cluster={data['cluster']} != 所在目录 {name}")
        for field in ("server", "env", "project", "namespace"):
            if meta.get(field) and data[field] != meta[field]:
                err(f"[{crel}] {field}={data[field]} 与 {rel}/cluster.yaml 的 {meta[field]} 不一致")


def check_appsets(root, clusters, appsets):
    """检查：每个清单文件都有对应的 AppSet；渲染出的 source path 真实存在。"""
    covered = set()
    for a in appsets:
        for name, c in clusters.items():
            comp = a["component"]
            if comp not in c["comps"]:
                continue
            covered.add((name, comp))
            data = c["comps"][comp][1]

            # ---- source path 是否存在 ------------------------------------
            rendered = a["path_tpl"]
            for key in ("component", "cluster", "env"):
                rendered = rendered.replace("{{." + key + "}}", data.get(key, ""))
            abs_path = os.path.join(root, rendered)
            if not os.path.isdir(abs_path):
                err(f"[{a['file']}] {name} 的 source.path 不存在: {rendered}")
            elif not os.path.isfile(os.path.join(abs_path, "kustomization.yaml")):
                err(f"[{a['file']}] {name} 的 source.path 缺少 kustomization.yaml: {rendered}")

            # ---- 集群级 overlay 引用了正确的环境层吗？ ----------------------
            if "{{.cluster}}" in a["path_tpl"]:
                kust = os.path.join(abs_path, "kustomization.yaml")
                if os.path.isfile(kust):
                    env = data.get("env")
                    refs = kustomize_resources(kust)
                    if env and not any(f"env/{env}" in r for r in refs):
                        err(f"[{rendered}/kustomization.yaml] resources 里没有引用环境层 env/{env}"
                            f"（集群 {name} 的 env={env}）")
                    if env and any(f"env/{e}" in r for r in refs
                                   for e in VALID_ENVS if e != env):
                        err(f"[{rendered}/kustomization.yaml] 引用了**其它环境**的环境层"
                            f"（集群 {name} 的 env={env}）")
    # 反向：有没有"开了开关但没有 AppSet"的组件
    for name, c in clusters.items():
        for comp in c["comps"]:
            if (name, comp) not in covered:
                err(f"[clusters/{name}/components/{comp}.yaml] 没有对应的 ApplicationSet"
                    f"（bootstrap/applicationsets/ 下找不到匹配 {comp}.yaml 的 generator）")


def check_destinations(root, clusters):
    """检查：集群的 server 在对应 AppProject 的 destinations 里。"""
    pp_dir = os.path.join(root, "bootstrap", "appprojects")
    cache = {}
    for name, c in clusters.items():
        project = c["meta"].get("project")
        if not project:
            continue
        if project not in cache:
            ppath = os.path.join(pp_dir, f"{project}.yaml")
            if os.path.isfile(ppath):
                cache[project] = (
                    parse_appproject_destinations(ppath),
                    parse_appproject_cluster_whitelist(ppath),
                )
            else:
                cache[project] = (None, None)
        servers, _ = cache[project]
        if servers is None:
            err(f"[clusters/{name}] project={project} 在 bootstrap/appprojects/ 里不存在")
            continue
        server = c["meta"].get("server")
        if server and server not in servers and "*" not in servers:
            err(f"[clusters/{name}] server={server} 不在 AppProject {project} 的 destinations 里"
                f" → 同步会被拒 \"not match any of the allowed destinations\"")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=os.path.dirname(os.path.abspath(__file__)))
    args = ap.parse_args()
    root = os.path.abspath(args.path)

    clusters = collect_clusters(root)
    appsets = parse_appsets(root)

    for name, c in clusters.items():
        check_cluster(root, name, c)
    check_appsets(root, clusters, appsets)
    check_destinations(root, clusters)

    # ---- 输出 ------------------------------------------------------------
    total_comps = sum(len(c["comps"]) for c in clusters.values())
    print(f"集群: {len(clusters)}   组件清单: {total_comps}   ApplicationSet: {len(appsets)}\n")

    for msg in warnings:
        print(f"[WARN ] {msg}")
    for msg in errors:
        print(f"[ERROR] {msg}")

    if errors:
        print(f"\n✗ {len(errors)} 个错误，{len(warnings)} 个警告 —— 不要提交。")
        return 1
    print(f"\n✓ 校验通过（{len(warnings)} 个警告）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
