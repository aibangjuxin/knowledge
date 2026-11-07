#!/usr/bin/env python3
"""
渲染全部 overlay 并检查**渲染产物** —— 把「Kustomize 能不能 build 出来」和
「build 出来的东西对不对」两件事都自动化。

**它解决什么问题**
  apps/**/overlays/** 里的 overlay 决定了这个组件在某个环境/集群的实际形态。
  现在这些 overlay 从来没有被程序化检查过，靠人肉 `kubectl kustomize` 是查不全的：
    · overlay 引用了不存在的路径 → Argo CD 同步时才报 "no matches for kind"
    · overlay 写成 overlays/dev/dev-01（父子嵌套）→ Kustomize 报 cycle detected
    · Deployment 的 selector 和 pod 模板 labels 对不上 → **K8s 直接拒绝创建**
    · Service 的 selector 和 pod labels 对不上 → 服务永远没有后端
    · 镜像没打 tag / 用 latest → 每次同步都可能拉到不同的镜像
    · prod 环境 replicas=1 → "高可用"名不副实
  这个脚本把上面这些**全部**在提交前抓出来。

**它不是什么**
  不连集群、不验证运行时行为、不替代 Argo CD 的 sync。
  它只看「渲染出来的 YAML」。

**用法**
    python3 render-check.py                    # 检查 apps/ 下所有 kustomization.yaml
    python3 render-check.py --path <目录>      # 指定 GitOps 仓库根目录
    python3 render-check.py --save /tmp/before # 把渲染结果存下来（用于对比）
    python3 render-check.py --compare /tmp/before  # 和之前存的对比（PR 评审用）
    python3 render-check.py --only nginx       # 只检查某个组件

**退出码**：0 = 通过；1 = 有 ERROR。
"""

import argparse
import difflib
import os
import re
import subprocess
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

from yamlmin import load_all  # noqa: E402

ERRORS = []
WARNINGS = []
NOTES = []

SEVERITY = {
    "require-resources": "error",
    "require-probes": "warn",
    "pinned-image": "warn",
    "no-hardcoded-namespace": "warn",
    "prod-replicas": "warn",
    "no-pvc": "info",
    "selector-mismatch": "error",
    "service-selector": "error",
    "duplicate-resource": "error",
    "missing-name": "error",
}

IGNORES = []          # ["<glob>:<rule>", ...]
OVERRIDES = {}        # {"<rule>": "error"/"warn"/"info"/"off"}


def _ignored(relpath, rule):
    for item in IGNORES:
        glob, _, ign_rule = item.partition(":")
        if ign_rule != rule:
            continue
        if fnmatch(relpath, glob) or fnmatch(os.path.basename(relpath), glob):
            return True
    return False


def fnmatch(name, pattern):
    import fnmatch as fm
    return fm.fnmatch(name, pattern)


def report(rule, relpath, msg):
    if _ignored(relpath, rule):
        return
    sev = OVERRIDES.get(rule, SEVERITY.get(rule, "warn"))
    line = f"[{relpath}] {msg}"
    if sev == "error":
        ERRORS.append(line)
    elif sev == "warn":
        WARNINGS.append(line)
    else:
        NOTES.append(line)


# ---------------------------------------------------------------------------
# 渲染
# ---------------------------------------------------------------------------

def find_kustomizations(root):
    """找出所有 kustomization.yaml（base 与 overlay）。"""
    apps = os.path.join(root, "apps")
    if not os.path.isdir(apps):
        return []
    out = []
    for base, dirs, files in os.walk(apps):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if "kustomization.yaml" in files:
            out.append(base)
    return sorted(out)


def render(path):
    """跑 kubectl kustomize，返回 (stdout, stderr, ok)。"""
    if shutil_which("kubectl"):
        cmd = ["kubectl", "kustomize", path]
    elif shutil_which("kustomize"):
        cmd = ["kustomize", "build", path]
    else:
        return "", "找不到 kubectl 或 kustomize", False
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.stdout, proc.stderr, proc.returncode == 0


def shutil_which(cmd):
    from shutil import which
    return which(cmd)


# ---------------------------------------------------------------------------
# 产物检查
# ---------------------------------------------------------------------------

def get(obj, *path, default=None):
    cur = obj
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def check_workload(doc, relpath, ns_hint):
    kind = doc.get("kind")
    spec = doc.get("spec") or {}
    name = get(doc, "metadata", "name", default="?")
    rel = f"{relpath}:{kind}/{name}"

    selector = get(spec, "selector", "matchLabels", default={}) or {}
    pod_labels = get(spec, "template", "metadata", "labels", default={}) or {}
    if kind in ("Deployment", "StatefulSet", "DaemonSet", "Job"):
        if selector and pod_labels:
            missing = {k: v for k, v in selector.items()
                       if pod_labels.get(k) != v}
            if missing:
                report("selector-mismatch", relpath,
                       f"{kind}/{name} 的 selector {selector} 与 pod 模板 labels "
                       f"{pod_labels} 不匹配 → K8s 会拒绝创建（{missing}）")

    # 副本数
    replicas = spec.get("replicas")
    if kind in ("Deployment", "StatefulSet") and ns_hint.startswith("prod"):
        if replicas is not None and int(replicas) < 2:
            report("prod-replicas", relpath,
                   f"{kind}/{name} 在 prod 环境 replicas={replicas}（高可用建议 ≥2）")

    # 容器级检查
    tmpl = get(spec, "template", "spec", default={}) or {}
    for container in tmpl.get("containers") or []:
        cname = container.get("name", "?")
        image = str(container.get("image", ""))
        if not image:
            report("pinned-image", rel, f"容器 {cname} 没有 image")
        elif image.endswith(":latest") or ":" not in image.split("/")[-1]:
            report("pinned-image", rel,
                   f"容器 {cname} 的镜像 {image!r} 没有固定 tag → 每次同步可能拉到不同镜像")
        res = container.get("resources") or {}
        for side in ("requests", "limits"):
            if not res.get(side):
                report("require-resources", rel,
                       f"容器 {cname} 缺 resources.{side}")
        if not container.get("readinessProbe"):
            report("require-probes", rel, f"容器 {cname} 没有 readinessProbe")
        if not container.get("livenessProbe"):
            report("require-probes", rel, f"容器 {cname} 没有 livenessProbe")

    # StatefulSet 持久化
    if kind == "StatefulSet" and not spec.get("volumeClaimTemplates"):
        report("no-pvc", rel,
               f"StatefulSet/{name} 没有 volumeClaimTemplates → 重启即丢数据")


def check_service(doc, relpath, workloads):
    kind = doc.get("kind")
    if kind != "Service":
        return
    spec = doc.get("spec") or {}
    name = get(doc, "metadata", "name", default="?")
    rel = f"{relpath}:Service/{name}"
    selector = spec.get("selector") or {}
    if not selector:
        return
    matched = False
    for wname, wlabels in workloads.items():
        if all(wlabels.get(k) == v for k, v in selector.items()):
            matched = True
            break
    if not matched:
        report("service-selector", rel,
               f"Service/{name} 的 selector {selector} 匹配不到任何工作负载的 "
               f"pod labels {list(workloads.values())} → 服务没有后端")


def check_namespace(doc, relpath, ns_hint):
    ns = get(doc, "metadata", "namespace")
    if ns and ns_hint and ns != ns_hint:
        report("no-hardcoded-namespace", relpath,
               f"资源里硬编码了 namespace={ns}，但这个应用的目标 namespace 是 "
               f"{ns_hint} → Argo CD 会把它 apply 到错误的地方")


def check_products(docs, relpath, ns_hint):
    """对一次渲染的产物做整体检查。"""
    seen = set()
    workloads = {}
    for doc in docs:
        if not isinstance(doc, dict):
            continue
        kind = doc.get("kind")
        name = get(doc, "metadata", "name", default=None)
        if not name:
            report("missing-name", relpath, f"有一个 {kind} 资源没有 metadata.name")
            continue
        key = (kind, name)
        if key in seen:
            report("duplicate-resource", relpath,
                   f"{kind}/{name} 在同一个渲染结果里出现了两次")
        seen.add(key)
        check_namespace(doc, relpath, ns_hint)
        if kind in ("Deployment", "StatefulSet", "DaemonSet"):
            labels = get(doc, "spec", "template", "metadata", "labels", default={}) or {}
            workloads[name] = labels
    for doc in docs:
        if isinstance(doc, dict):
            check_workload(doc, relpath, ns_hint)
    for doc in docs:
        if isinstance(doc, dict):
            check_service(doc, relpath, workloads)


# ---------------------------------------------------------------------------
# 策略文件
# ---------------------------------------------------------------------------

def load_policy(root):
    global IGNORES, OVERRIDES
    path = os.path.join(root, "render-check.policy.yaml")
    if not os.path.isfile(path):
        return
    from yamlmin import load_file
    data = load_file(path) or {}
    IGNORES = data.get("ignores") or []
    for rule, sev in (data.get("severities") or {}).items():
        OVERRIDES[rule] = sev


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def namespace_hint(relpath):
    """从路径猜目标 namespace：overlays/<env>/... → platform-<env>。"""
    parts = relpath.replace("\\", "/").split("/")
    if "overlays" in parts:
        idx = parts.index("overlays")
        if idx + 1 < len(parts):
            env = parts[idx + 1]
            if env in ("cluster", "env"):
                return ""
            return f"platform-{env}"
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=_HERE, help="GitOps 仓库根目录")
    ap.add_argument("--only", help="只检查名字里含这个串的组件")
    ap.add_argument("--save", help="把渲染结果保存到这个目录")
    ap.add_argument("--compare", help="和这个目录里保存的渲染结果对比")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    load_policy(root)

    if not shutil_which("kubectl") and not shutil_which("kustomize"):
        print("找不到 kubectl 或 kustomize —— 无法渲染。")
        print("  macOS: brew install kubectl kustomize")
        print("  Linux: 见 https://kubectl.docs.kubernetes.io/installation/")
        return 2

    kusts = find_kustomizations(root)
    if args.only:
        kusts = [k for k in kusts if args.only in os.path.relpath(k, root)]
    if not kusts:
        print("没找到任何 kustomization.yaml")
        return 0

    total_resources = 0
    built = 0
    for kdir in kusts:
        rel = os.path.relpath(kdir, root)
        out, err, ok = render(kdir)
        if not ok:
            first = (err.strip().splitlines() or ["(无输出)"])[0]
            ERRORS.append(f"[{rel}] 渲染失败：{first}")
            if "cycle" in err.lower():
                ERRORS.append(f"[{rel}] ⭐ 检测到 cycle —— overlay 父子嵌套了"
                              f"（必须是兄弟目录：overlays/env/<env> 与 overlays/cluster/<cluster>）")
            continue
        built += 1
        try:
            docs = [d for d in load_all(out) if isinstance(d, dict)]
        except Exception as exc:
            ERRORS.append(f"[{rel}] 渲染结果不是合法 YAML：{exc}")
            continue
        total_resources += len(docs)
        check_products(docs, rel, namespace_hint(rel))

        if args.save:
            target = os.path.join(args.save, rel + ".yaml")
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8") as fh:
                fh.write(out)

        if args.compare:
            old_path = os.path.join(args.compare, rel + ".yaml")
            if os.path.isfile(old_path):
                with open(old_path, encoding="utf-8") as fh:
                    old = fh.read()
                if old != out:
                    diff = list(difflib.unified_diff(
                        old.splitlines(), out.splitlines(),
                        fromfile=f"before/{rel}", tofile=f"after/{rel}", lineterm=""))
                    if diff:
                        NOTES.append(f"[{rel}] 渲染结果有变化（{len(diff)} 行 diff）")
                        for line in diff[:40]:
                            NOTES.append("    " + line)
            else:
                NOTES.append(f"[{rel}] 新增的 overlay（之前没有渲染快照）")

    print(f"渲染了 {built}/{len(kusts)} 个 kustomization.yaml，"
          f"共 {total_resources} 个资源\n")

    for msg in WARNINGS:
        print(f"[WARN ] {msg}")
    for msg in ERRORS:
        print(f"[ERROR] {msg}")
    if NOTES:
        print()
        for msg in NOTES:
            print(f"[INFO ] {msg}")

    print()
    if ERRORS:
        print(f"✗ {len(ERRORS)} 个错误，{len(WARNINGS)} 个警告")
        return 1
    print(f"✓ 渲染检查通过（{len(WARNINGS)} 个警告）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
