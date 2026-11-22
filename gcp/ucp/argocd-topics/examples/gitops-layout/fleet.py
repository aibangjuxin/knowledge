#!/usr/bin/env python3
# =============================================================================
#  fleet.py —— 集群清单（fleet）视角的两个操作
# -----------------------------------------------------------------------------
#  为什么需要它（这是长期 control plane 才用得上的东西）：
#
#    仓库里已经有一堆脚本了（new-cluster.sh / enable-component.sh /
#    validate-clusters.py / appset-simulator.py），它们管的是"**一个**集群"。
#    但 Argo CD 真正变成长期 control plane 之后，问题会变成：
#
#      ① 集群从 4 个变成 40 个 —— 我想知道每个集群启用了哪些组件
#      ② 集群加进 Git 了，但忘了在 Argo CD 里注册 → Application 报
#         "Unable to connect"，而且**只有跑到那个集群才看得到**
#      ③ 反过来：Argo CD 里注册了一个集群，但 Git 里没有声明它
#         → 有人在控制面里"偷偷"纳管了一个集群，没人知道、没走审批
#      ④ 两边都有，但 server URL 写错了一点点 → 最难查的一类问题
#
#    ①② 是"看"，③④ 是"对账"。本脚本做这两件事。
#
#  用法：
#    python3 fleet.py list              # 集群 × 组件矩阵
#    python3 fleet.py drift             # Git 声明 vs Argo CD 实际注册（对账）
#    python3 fleet.py drift --strict    # 有差异时退出码非 0（可进 CI）
#    python3 fleet.py drift --argocd-ns argocd
#
#  退出码：0 = 正常（list 恒为 0）；drift 在 --strict 且有差异时为 1。
#
#  依赖：只用 Python 标准库（不依赖 PyYAML / kubectl python 库）。
#  兼容：Python 3.8+
# =============================================================================

import argparse
import base64
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CLUSTERS_DIR = os.path.join(HERE, "bootstrap", "clusters")

# Argo CD v2.10+ / v3.x 的 cluster secret 标签
CLUSTER_SECRET_LABEL = "argocd.argoproj.io/secret-type=cluster"


# ─────────────────────────────────────────────────────────────────────────────
# 极简 YAML 读取：只支持 "key: value"（本仓库 cluster.yaml / components/*.yaml
# 就是这种扁平格式）。不引入 PyYAML，保持零依赖。
# ─────────────────────────────────────────────────────────────────────────────
def read_flat_yaml(path):
    """读一个扁平 key: value 文件，返回 dict（忽略 # 注释与空行）。"""
    out = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.split("#", 1)[0].strip()  # 去行内注释
                if not line or ":" not in line:
                    continue
                key, _, value = line.partition(":")
                out[key.strip()] = value.strip().strip("\"'")
    except OSError as exc:
        print("读取失败 %s: %s" % (path, exc), file=sys.stderr)
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Git 侧：声明了什么
# ─────────────────────────────────────────────────────────────────────────────
def git_clusters():
    """读 bootstrap/clusters/*/cluster.yaml → {name: {...}}"""
    clusters = {}
    if not os.path.isdir(CLUSTERS_DIR):
        return clusters
    for entry in sorted(os.listdir(CLUSTERS_DIR)):
        d = os.path.join(CLUSTERS_DIR, entry)
        if not os.path.isdir(d) or entry.startswith("_"):
            continue
        manifest = os.path.join(d, "cluster.yaml")
        if not os.path.isfile(manifest):
            continue
        data = read_flat_yaml(manifest)
        name = data.get("cluster") or entry
        data["_dir"] = d
        data["_components"] = git_components(d)
        clusters[name] = data
    return clusters


def git_components(cluster_dir):
    """读 components/*.yaml → [component, ...]"""
    comp_dir = os.path.join(cluster_dir, "components")
    if not os.path.isdir(comp_dir):
        return []
    out = []
    for name in sorted(os.listdir(comp_dir)):
        if not name.endswith((".yaml", ".yml")):
            continue
        data = read_flat_yaml(os.path.join(comp_dir, name))
        out.append(data.get("component") or os.path.splitext(name)[0])
    return sorted(out)


# ─────────────────────────────────────────────────────────────────────────────
# Argo CD 侧：实际注册了什么
# ─────────────────────────────────────────────────────────────────────────────
def argocd_clusters(namespace, kubeconfig=None):
    """
    从 Argo CD 命名空间里的 cluster secret 读出实际注册的集群。
    读 kubectl 而不是 argocd CLI：不需要登录态，且能覆盖"CLI 看不到但控制面有"的情况。

    返回 (dict, err)：
      err 为 None 时表示读成功；否则是错误原因（字符串）。
    """
    if shutil_which("kubectl") is None:
        return {}, "没装 kubectl"

    # --request-timeout 让 kubectl 在连不上集群时快速失败，而不是干等
    cmd = [
        "kubectl", "-n", namespace,
        "get", "secret", "-l", CLUSTER_SECRET_LABEL,
        "-o", "json", "--request-timeout=8s",
    ]
    if kubeconfig:
        cmd = ["kubectl", "--kubeconfig", kubeconfig] + cmd[1:]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {}, "调用 kubectl 失败: %s" % exc

    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip().splitlines()
        hint = stderr[-1] if stderr else "未知错误"
        return {}, "读不到 Argo CD 命名空间 %s: %s" % (namespace, hint)

    try:
        raw = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError as exc:
        return {}, "解析 kubectl 输出失败: %s" % exc

    out = {}
    for item in raw.get("items", []):
        data = item.get("data", {}) or {}

        def _b64(key):
            v = data.get(key)
            if not v:
                return ""
            try:
                return base64.b64decode(v).decode("utf-8", "replace").strip()
            except Exception:
                return ""

        # secret 的 name 是"生成时的名字"（可能带后缀），
        # 真正的集群名在 data.name 里
        name = _b64("name") or item.get("metadata", {}).get("name", "")
        if not name:
            continue
        out[name] = {
            "secret": item.get("metadata", {}).get("name", ""),
            "server": _b64("server"),
            "project": _b64("project"),
        }
    return out, None


def shutil_which(name):
    for d in os.environ.get("PATH", "").split(os.pathsep):
        candidate = os.path.join(d, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


# ─────────────────────────────────────────────────────────────────────────────
# 子命令：list —— 集群 × 组件矩阵
# ─────────────────────────────────────────────────────────────────────────────
def cmd_list(args):
    clusters = git_clusters()
    if not clusters:
        print("没有找到集群清单（%s）" % CLUSTERS_DIR)
        return 0

    all_components = sorted({c for v in clusters.values() for c in v["_components"]})
    name_w = max([len("集群")] + [len(k) for k in clusters])
    comp_w = max([len(c) for c in all_components] + [4]) + 2

    print("")
    print("集群清单（%d 个）" % len(clusters))
    print("─" * (name_w + 2 + comp_w * len(all_components)))
    header = "  " + "集群".ljust(name_w) + "  "
    header += "".join(c.ljust(comp_w) for c in all_components)
    print(header)
    print("─" * (name_w + 2 + comp_w * len(all_components)))

    for name in sorted(clusters):
        info = clusters[name]
        row = "  " + name.ljust(name_w) + "  "
        for comp in all_components:
            row += ("●" if comp in info["_components"] else "·").ljust(comp_w)
        print(row)

    print("─" * (name_w + 2 + comp_w * len(all_components)))
    print("  ● 已启用   · 未启用")
    print("")
    print("环境分布：", end="")
    envs = {}
    for info in clusters.values():
        envs[info.get("env", "?")] = envs.get(info.get("env", "?"), 0) + 1
    print("  " + "  ".join("%s=%d" % (k, v) for k, v in sorted(envs.items())))
    print("")
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# 子命令：drift —— Git 声明 vs Argo CD 实际
# ─────────────────────────────────────────────────────────────────────────────
def cmd_drift(args):
    git = git_clusters()
    actual, err = argocd_clusters(args.argocd_ns, args.kubeconfig)

    if err:
        print("")
        print("⚠ 无法对账：%s" % err)
        print("  （没有集群访问权限时这是正常的；Git 侧清单仍然有效）")
        print("")
        if args.strict:
            print("✗ --strict 模式下视为失败")
            return 1
        return 0

    only_git = sorted(set(git) - set(actual))
    only_argocd = sorted(set(actual) - set(git))
    server_mismatch = []
    for name in sorted(set(git) & set(actual)):
        want = git[name].get("server", "")
        got = actual[name].get("server", "")
        if want and got and want.rstrip("/") != got.rstrip("/"):
            server_mismatch.append((name, want, got))

    print("")
    print("对账：Git 声明 %d 个集群 / Argo CD 实际注册 %d 个" % (len(git), len(actual)))
    print("─" * 60)

    if only_git:
        print("")
        print("① 只在 Git 声明、Argo CD 未注册（%d 个）" % len(only_git))
        print("   → 该集群的 Application 会报 Unable to connect")
        for name in only_git:
            print("     - %s  (%s)" % (name, git[name].get("server", "")))
        print("   → 修复：在目标集群建 SA，然后在 Argo CD 里 argocd cluster add")

    if only_argocd:
        print("")
        print("② 只在 Argo CD 注册、Git 未声明（%d 个）" % len(only_argocd))
        print("   → ★ 有人在控制面里纳管了 Git 不知道的集群（没走 PR/审批）")
        for name in only_argocd:
            sec = actual[name]
            print("     - %s  (%s, secret=%s, project=%s)"
                  % (name, sec["server"], sec["secret"], sec["project"]))
        print("   → 修复：补 cluster.yaml 并走 PR；确认无用的先从 Argo CD 移除")

    if server_mismatch:
        print("")
        print("③ 两边都有但 server 不一致（%d 个）" % len(server_mismatch))
        print("   → ★ 最难查的一类：应用会连到「看起来对」的地址")
        for name, want, got in server_mismatch:
            print("     - %s" % name)
            print("         Git   : %s" % want)
            print("         ArgoCD: %s" % got)

    if not (only_git or only_argocd or server_mismatch):
        print("")
        print("✓ 完全一致：Git 声明的集群与 Argo CD 实际注册的集群一一对应")

    print("")
    diff = len(only_git) + len(only_argocd) + len(server_mismatch)
    if diff and args.strict:
        print("✗ --strict 模式：发现 %d 处差异" % diff)
        return 1
    if diff:
        print("ℹ 发现 %d 处差异（加 --strict 可让退出码非 0）" % diff)
    return 0


def main():
    ap = argparse.ArgumentParser(
        description="集群清单视角：list 看矩阵，drift 做对账")
    sub = ap.add_subparsers(dest="cmd")

    p_list = sub.add_parser("list", help="集群 × 组件矩阵")
    p_list.set_defaults(func=cmd_list)

    p_drift = sub.add_parser("drift", help="Git 声明 vs Argo CD 实际注册")
    p_drift.add_argument("--argocd-ns", default="argocd",
                         help="Argo CD 所在命名空间（默认 argocd）")
    p_drift.add_argument("--kubeconfig", default=os.environ.get("KUBECONFIG"),
                         help="kubeconfig 路径（默认取环境变量）")
    p_drift.add_argument("--strict", action="store_true",
                         help="有差异时退出码非 0")
    p_drift.set_defaults(func=cmd_drift)

    args = ap.parse_args()
    if not getattr(args, "func", None):
        ap.print_help()
        return 0
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
