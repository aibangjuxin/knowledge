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
  ④ 反向：仓库里的 .md / .sh / .py 有没有**没被任何文档提到**（只提示）

**它不检查什么**
  · 外部链接（http/https/mailto）能不能打开 —— 需要联网，不属于静态检查

**用法**
    python3 check-doc-links.py                     # 检查当前目录树
    python3 check-doc-links.py --path <目录>
    python3 check-doc-links.py --no-anchors        # 只查文件，不查锚点
    python3 check-doc-links.py --no-orphans        # 不做 ④ 反向检查

**退出码**：0 = 通过；1 = 有断链。
  ⚠️ ④ 反向检查**不会**影响退出码 —— 它只是提示（文件没人引用不等于错）。
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

# 代码块的语言标记：这些词后面跟的不是文件路径，而是语言名
FENCE_LANGUAGES = {
    "bash", "sh", "shell", "console", "text",
    "yaml", "yml", "json",
    "python", "py", "go", "hcl", "diff",
}

# 正文里出现的「像文件名的东西」—— 用于 ④ 反向检查。
# 例：`` `check-doc-links.py` ``、"./ci-check.sh"、"[README](README.md)"
FILE_NAME = re.compile(r"[\w][\w./-]*\.(?:md|sh|py)\b")

# ④ 反向检查关心的文件类型
ORPHAN_SUFFIXES = (".md", ".sh", ".py")
SKIP_DIRS = {".git", "node_modules", "__pycache__"}


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


def loose(text):
    """去掉符号（emoji、全角标点等）后的宽松形式。

    GitHub 对标题里的 emoji 怎么处理在不同版本/渲染器上不一致
    （有的保留、有的变成连字符）。比较锚点时先用宽松形式匹配，
    避免把「只是 emoji 写法不同」误报成断链。
    """
    return re.sub(r"[^\w\u4e00-\u9fff]+", "", text.lower())


def anchors_of_text(text):
    """从一个 Markdown **文本**里抽出所有标题的 slug。"""
    return {slugify(title) for _, title in HEADING.findall(text)}


def anchor_index(text):
    """返回 (精确 slug 集合, 宽松 slug 集合)。

    两个集合的用途：
      · 精确集合 —— 正常比对
      · 宽松集合 —— 吸收 GitHub 对 emoji / 全角标点的处理差异
    """
    anchors = anchors_of_text(text)
    return anchors, {loose(a) for a in anchors}


def anchor_index_file(path):
    """读文件并返回 (精确 slug 集合, 宽松 slug 集合)；读不了就返回两个空集。"""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return set(), set()
    return anchor_index(text)


def link_targets(text):
    """抽出文本里所有链接目标（普通链接 + 图片）。

    普通链接的正则里用 (?<!!) 排除了图片，所以两边要各抽一遍。
    """
    targets = [m.group(2) for m in LINK.finditer(text)]
    targets += [m.group(1) for m in IMAGE.finditer(text)]
    return targets


def find_markdown_files(root):
    """找出目录下所有 .md（跳过隐藏目录、node_modules、__pycache__）。"""
    md_files = []
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs
                   if not d.startswith(".") and d not in SKIP_DIRS]
        for name in files:
            if name.endswith(".md"):
                md_files.append(os.path.join(base, name))
    return sorted(md_files)


def find_orphans(root, referenced_paths, mentioned_names):
    """④ 反向检查：找出**没被任何文档提到**的文件。

    判定一个文件“被提到过”的方式有两种（满足其一即可）：
      ① 精确：它的路径出现在某个文档的链接目标或代码块标题里
      ② 按文件名：某个文档的正文里出现过同名文件
         （例：正文写 `` `check-doc-links.py` `` 也算提到过）

    返回没被提到的文件列表（相对 root 的路径）。
    ⚠️ 这只是提示：文件没人引用 ≠ 有错，所以不影响退出码。
    """
    orphans = []
    entry_readme = os.path.normpath(os.path.join(root, "README.md"))
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs
                   if not d.startswith(".") and d not in SKIP_DIRS]
        for name in sorted(files):
            if not name.endswith(ORPHAN_SUFFIXES):
                continue
            path = os.path.normpath(os.path.join(base, name))
            # 被扫描目录自己的 README 是入口，没有人会“引用”它
            if path == entry_readme:
                continue
            if path in referenced_paths:
                continue
            if name in mentioned_names:
                continue
            orphans.append(os.path.relpath(path, root))
    return orphans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=os.path.dirname(_HERE),
                    help="要检查的目录树（默认：argocd-topics/）")
    ap.add_argument("--no-anchors", action="store_true", help="不检查锚点")
    ap.add_argument("--no-orphans", action="store_true",
                    help="不做 ④ 反向检查（不提示没被任何文档提到的文件）")
    args = ap.parse_args()

    root = os.path.abspath(args.path)
    if not os.path.isdir(root):
        print(f"目录不存在：{root}")
        return 2

    md_files = find_markdown_files(root)

    broken = []
    checked = 0
    # ④ 反向检查用的两个集合：
    #   referenced_paths —— 被链接 / 代码块**精确指向**的绝对路径
    #   mentioned_names —— 正文里出现过的**文件名**（basename）
    referenced_paths = set()
    mentioned_names = set()

    for path in md_files:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        rel_file = os.path.relpath(path, root)

        # 本文件的标题索引：只解析一次（同一个文件里可能有几十个 #锚点 链接）
        anchors, loose_anchors = anchor_index(text)

        # ---- ① 普通链接 / 图片 ----
        for target in link_targets(text):
            # 外链、邮件链接不用管
            if target.startswith(("http://", "https://", "mailto:")):
                continue

            # 纯锚点链接（同一个文件内跳转）
            if target.startswith("#"):
                anchor = target[1:]
                if anchor and not args.no_anchors:
                    checked += 1
                    if anchor not in anchors and loose(anchor) not in loose_anchors:
                        broken.append(f"[{rel_file}] 锚点不存在: {target}")
                continue

            # 文件链接：可能带 #锚点 后缀
            filepart, _, anchor = target.partition("#")
            if not filepart:
                continue
            checked += 1
            abs_target = os.path.normpath(os.path.join(os.path.dirname(path), filepart))
            if not os.path.exists(abs_target):
                broken.append(f"[{rel_file}] 文件不存在: {target}")
                continue
            referenced_paths.add(abs_target)
            if anchor and not args.no_anchors and abs_target.endswith(".md"):
                target_anchors, target_loose = anchor_index_file(abs_target)
                if anchor not in target_anchors and loose(anchor) not in target_loose:
                    broken.append(f"[{rel_file}] 目标文件里没有这个锚点: {target}")

        # ---- ② 代码块里引用的脚本路径（``` 后的第一个词是路径时）----
        for m in FENCE.finditer(text):
            token = m.group(1)
            # 语言标记（```bash）不是路径
            if not token or token in FENCE_LANGUAGES:
                continue
            # 只认含 "/" 的：单个词不可能是仓库里的相对路径
            if "/" not in token:
                continue
            checked += 1
            abs_target = os.path.normpath(os.path.join(os.path.dirname(path), token))
            referenced_paths.add(abs_target)
            if not os.path.exists(abs_target):
                broken.append(f"[{rel_file}] 引用的文件不存在: {token}")

        # ---- ③ 收集正文里出现过的文件名（给 ④ 用）----
        for m in FILE_NAME.finditer(text):
            mentioned_names.add(os.path.basename(m.group(0)))

    print(f"检查了 {len(md_files)} 个 Markdown、{checked} 个链接\n")
    for msg in broken:
        print(f"[BROKEN] {msg}")
    if broken:
        print(f"\n✗ {len(broken)} 个断链")
    else:
        print("✓ 没有断链")

    # ---- ④ 反向检查：没被任何文档提到的文件（只是提示）----
    if not args.no_orphans:
        orphans = find_orphans(root, referenced_paths, mentioned_names)
        if orphans:
            print(f"\nℹ️  下面这些文件没有被任何文档提到（只是提示，不影响退出码）：")
            for rel in orphans:
                print(f"      {rel}")
        else:
            print("ℹ️  所有 .md / .sh / .py 文件都至少被一个文档提到过")

    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
