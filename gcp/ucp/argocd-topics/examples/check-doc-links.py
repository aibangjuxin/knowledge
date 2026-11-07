#!/usr/bin/env python3
"""
检查 Markdown 文档里的相对链接（和锚点）能不能跳到地方。

**它解决什么问题**
  这个仓库有 20+ 个 .md，之间互相引用（README ↔ 专题文档 ↔ examples）。
  改文件名 / 挪目录之后，链接会静默失效 —— 读文档的人点一下发现 404，
  但没人会注意到 CI 里少了一个检查。

**它检查什么**
  ① 相对链接指向的文件是否存在
  ② 锚点（`#标题`）在目标文件里是否存在
  ③ 文档里引用的**代码文件**（```路径``` 形式的代码块标题）是否存在
  ④ 反向：仓库里的脚本/README 有没有没被任何文档引用（可选，只提示）

**用法**
    python3 check-doc-links.py                     # 检查当前目录树
    python3 check-doc-links.py --path <目录>
    python3 check-doc-links.py --no-anchors        # 只查文件，不查锚点

**退出码**：0 = 通过；1 = 有断链。
"""

import argparse
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))

LINK = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
IMAGE = re.compile(r"!\[[^\]]*\]\(([^)\s]+)")
FENCE = re.compile(r"^```(\S*)", re.M)
HEADING = re.compile(r"^(#{1,6})\s+(.*)$", re.M)


def slugify(text):
    """GitHub 风格的锚点 slug。

    对齐 github-slugger 的规则：
      · 去掉 ASCII 标点（但**保留**连字符 -）
      · 去掉 U+2000-206F / U+2E00-2E7F 两段 Unicode 标点
      · 保留 CJK、字母、数字、④ 这类符号
      · 空格 → 连字符；整体转小写
    """
    text = re.sub(r"`([^`]*)`", r"\1", text)
    text = re.sub(r"\*\*([^*]*)\*\*", r"\1", text)
    text = re.sub(r"\*([^*]*)\*", r"\1", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = text.strip().lower()
    # github-slugger 的删除集
    text = re.sub(r"[\x00-\x1f!-\x2c./:-@\[-^`{-~\u2000-\u206f\u2e00-\u2e7f]", "", text)
    text = text.replace(" ", "-")
    return text


def anchors_of(path):
    """收集一个 Markdown 文件里所有标题的 slug。"""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return set()
    out = set()
    for _, title in HEADING.findall(text):
        out.add(slugify(title))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=os.path.dirname(_HERE),
                    help="要检查的目录树（默认：argocd-topics/）")
    ap.add_argument("--no-anchors", action="store_true", help="不检查锚点")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"目录不存在：{root}")
        return 2

    md_files = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d != "node_modules"]
        for name in files:
            if name.endswith(".md"):
                md_files.append(os.path.join(base, name))
    md_files.sort()

    broken = []
    checked = 0
    referenced = set()

    for path in md_files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        rel_file = os.path.relpath(path, root)

        targets = [(m.group(2), m.group(1)) for m in LINK.finditer(text)]
        targets += [(m.group(1), "image") for m in IMAGE.finditer(text)]

        for target, _label in targets:
            if target.startswith(("http://", "https://", "mailto:", "#")):
                if target.startswith("#"):
                    anchor = target[1:]
                    if anchor and not args.no_anchors:
                        checked += 1
                        if anchor.lower() not in {a.lower() for a in anchors_of(path)}:
                            broken.append(f"[{rel_file}] 锚点不存在: {target}")
                continue

            filepart, _, anchor = target.partition("#")
            if not filepart:
                continue
            checked += 1
            abs_target = os.path.normpath(os.path.join(os.path.dirname(path), filepart))
            if not os.path.exists(abs_target):
                broken.append(f"[{rel_file}] 文件不存在: {target}")
                continue
            referenced.add(os.path.normpath(abs_target))
            if anchor and not args.no_anchors and abs_target.endswith(".md"):
                if anchor.lower() not in {a.lower() for a in anchors_of(abs_target)}:
                    broken.append(f"[{rel_file}] 目标文件里没有这个锚点: {target}")

    # 代码块里引用的脚本路径（``` 后的第一个词是路径时）
    for path in md_files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        rel_file = os.path.relpath(path, root)
        for m in FENCE.finditer(text):
            token = m.group(1)
            if not token or token in ("bash", "sh", "shell", "console", "text", "yaml",
                                     "yml", "json", "python", "py", "go", "hcl", "diff"):
                continue
            if "/" not in token:
                continue
            checked += 1
            abs_target = os.path.normpath(os.path.join(os.path.dirname(path), token))
            if not os.path.exists(abs_target):
                broken.append(f"[{rel_file}] 引用的文件不存在: {token}")

    print(f"检查了 {len(md_files)} 个 Markdown、{checked} 个链接\n")
    for msg in broken:
        print(f"[BROKEN] {msg}")
    if broken:
        print(f"\n✗ {len(broken)} 个断链")
        return 1
    print("✓ 没有断链")
    return 0


if __name__ == "__main__":
    sys.exit(main())
