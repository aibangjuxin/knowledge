#!/usr/bin/env python3
"""
离线预览 ApplicationSet 的展开结果。

**它是什么**：一个模拟器 —— 复刻 `git` 文件生成器 + 模板渲染的行为，
在不连集群的情况下告诉你「这套 GitOps 目录会生成哪些 Application」。

**它不是什么**：
  - 不是 Argo CD controller，不能替代真实验证
  - 不解析 AppProject 约束、不做权限校验

**用法**：
    python3 preview-appset.py                 # 在本目录运行
    python3 preview-appset.py --path <目录>   # 指定 GitOps 仓库根目录

**输出**：组件 × 集群 的 Application 矩阵。
"""

import argparse
import os
import sys

# 与 bootstrap/applicationsets/*.yaml 里的 flatten 列表保持一致
# （与 validate-clusters.py 里的同名常量重复 —— 两边都要改）
REQUIRED_FIELDS = ["component", "cluster", "server", "env", "project", "namespace"]


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


def collect(root):
    """扫描 bootstrap/clusters/*/components/*.yaml，返回 (清单文件, 字段) 列表。"""
    base = os.path.join(root, "bootstrap", "clusters")
    if not os.path.isdir(base):
        sys.exit(f"找不到 {base}")
    items = []
    for cluster in sorted(os.listdir(base)):
        comp_dir = os.path.join(base, cluster, "components")
        if not os.path.isdir(comp_dir):
            continue
        for name in sorted(os.listdir(comp_dir)):
            if not name.endswith((".yaml", ".yml")):
                continue
            path = os.path.join(comp_dir, name)
            items.append((path, parse_flat_yaml(path)))
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=os.path.dirname(os.path.abspath(__file__)))
    args = ap.parse_args()
    root = os.path.abspath(args.path)

    items = collect(root)
    if not items:
        sys.exit("没有找到任何组件启用清单")

    # ---- 校验字段完整性（对应 missingkey=error）--------------------------
    bad = 0
    for path, data in items:
        missing = [f for f in REQUIRED_FIELDS if f not in data]
        if missing:
            print(f"[MISSING] {os.path.relpath(path, root)} 缺字段: {', '.join(missing)}")
            bad += 1
    if bad:
        print(f"\n有 {bad} 个清单文件字段不全 —— Argo CD 的 missingkey=error 会让整个 AppSet 报错。")
        return 1

    # ---- 按组件分组，模拟每个 ApplicationSet 的生成结果 -------------------
    by_component = {}
    for path, data in items:
        by_component.setdefault(data["component"], []).append(data)

    print(f"清单文件: {len(items)} 个   组件: {len(by_component)} 个\n")
    total = 0
    for component in sorted(by_component):
        rows = sorted(by_component[component], key=lambda d: d["cluster"])
        print(f"ApplicationSet/{component}  →  生成 {len(rows)} 个 Application")
        for d in rows:
            total += 1
            print(
                f"    {d['component']}-{d['cluster']:<8} "
                f"project={d['project']:<14} ns={d['namespace']:<14} "
                f"server={d['server']}"
            )
        print()

    # ---- 反向视图：每个集群装了哪些组件 -----------------------------------
    by_cluster = {}
    for _path, data in items:
        by_cluster.setdefault(data["cluster"], []).append(data["component"])

    print("集群视角（组件装在哪些集群）")
    for cluster in sorted(by_cluster):
        comps = sorted(by_cluster[cluster])
        print(f"    {cluster:<8} {len(comps)} 个组件: {', '.join(comps)}")
    print(f"\n合计应生成 {total} 个 Application")
    return 0


if __name__ == "__main__":
    sys.exit(main())
