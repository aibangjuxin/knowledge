# 读懂 git diff 输出：diff --git a/xxx b/xxx 到底在说什么

> 一句话结论：**`a/` 和 `b/` 不是分支，不是 branch，也不是 commit；更不是 "after" 和 "before" 的首字母。**
> 它们只是 diff 两侧的**位置占位符**：
> **`a` = 左边那一栏 = 改动前（old）**，`b` = 右边那一栏 = 改动后（new）**。
> 字母本身没有任何语义，唯一的信息是**顺序**（a 在前/源，b 在后/目标）。
> 和分支毫无关系。

---

## 1. 你看到的那段输出，逐行解剖

```bash
$ git diff
diff --git a/ucp/SUMMARY.md b/ucp/SUMMARY.md
index 689b857..f0adab2 100644
--- a/ucp/SUMMARY.md
+++ b/ucp/SUMMARY.md
@@ -12,7 +12,9 @@ ## 某个上下文标题
 context line
-removed line
+added line
+another added line
```

| 行 | 含义 | 说明 |
| --- | --- | --- |
| `diff --git a/X b/Y` | 文件级头 | `a/X` = 改动前的路径，`b/Y` = 改动后的路径。**通常 X == Y**，表示同一个文件的前后两个版本 |
| `index 689b857..f0adab2 100644` | blob 哈希 + 文件模式 | `689b857` 是**旧内容**的 blob SHA-1 缩写，`f0adab2` 是**新内容**的 blob SHA-1 缩写；两者之间的 `..` 表示「从 → 到」；`100644` 是文件权限模式 |
| `--- a/ucp/SUMMARY.md` | unified diff 的「旧文件」头 | 传统 diff 格式，给 `patch` / `git apply` 用的 |
| `+++ b/ucp/SUMMARY.md` | unified diff 的「新文件」头 | 同上 |
| `@@ -12,7 +12,9 @@` | hunk（变更块）头 | `-12,7` = 旧文件从第 12 行起的 7 行；`+12,9` = 新文件从第 12 行起的 9 行；`@@` 后面的文字是「上一个 section 标题」，纯上下文提示 |
| ` context line` | 未改动的行 | 以**空格**开头 |
| `-removed line` | 被删掉的行 | 以**减号**开头 |
| `+added line` | 新增的行 | 以**加号**开头 |

### 关于 `index 689b857..f0adab2 100644`

- **那两个 hash 是 blob 的 object id，不是 commit id，也不是 tree id**。
  「为什么改一个 bit 全部 hash 都变」在 [How-to-understand-tree-id-and-commit-id.md](How-to-understand-tree-id-and-commit-id.md) 里有完整解释。
- **缩写长度**由 `core.abbrev` 控制（默认 auto：仓库大就多几位，小仓库 7 位）。看到 7 位就是被截断的 SHA-1。
- **文件模式 6 位八进制**含义：

| 模式 | 含义 |
| --- | --- |
| `100644` | 普通文件（`-rw-r--r--`），最常见 |
| `100755` | 可执行文件（`-rwxr-xr-x`） |
| `120000` | 符号链接 symlink |
| `160000` | gitlink（子模块 submodule） |
| `040000` | 目录 tree（只在 raw tree diff 里出现） |

新增/删除文件时还会多出 `new file mode 100644` / `deleted file mode 100644` 两行。

---

## 2. 重点澄清：a/ 和 b/ 不是「临时分支」

你的直觉是「a、b 肯定是两个临时分支，Git 直接用 A/B 来表示了而已」——**这是最常见的误解**，必须纠正：

1. **Git diff 里没有任何分支信息。** 一条 `diff --git` 行只描述「一个文件的两个 blob」。
2. `a/` `b/` 是**路径前缀（prefix）**，不是 ref。Git 在计算 diff 时只关心两个 **tree/blob**，根本不知道你当前在哪个分支上。
3. 同样的 `a/x b/x`，既可能是 `git diff`（工作区 vs 暂存区），也可能是 `git diff HEAD`（commit vs 工作区），也可能是 `git show`（父 commit vs 该 commit）——
   **输出格式一模一样**，区别只在于「被比较的那两个树是谁」。

### 那 a/b 到底代表什么？

历史原因：Unix 传统的 `diff` 命令输出用 `old file` / `new file`；GNU diff 后来引入了 `diff --git old new` 的格式。
Git 为了跟这套「带文件头、可被 `patch -p1` 直接应用」的 diff 格式兼容，给两个操作数统一加上了 `a/` `b/` 两个前缀。

**注意：`a`、`b` 不是 "after"、"before" 的首字母，也不对应任何具体单词。**
它们沿袭了 Unix 给「两个待比较的文件」起的古老代号习惯（`cmp a b`、`comm a b`、`diff a b`），
字母只表达**位置**：a = 第一个（左边 / 源 / old），b = 第二个（右边 / 目标 / new）。

关键是它们**是纯占位符**，真正的路径就写在后面：`a/ucp/SUMMARY.md` 里的路径部分才是真实路径。
`--no-prefix` 就能把前缀去掉（见下）。

### 那 a/b 分别对应「哪两个版本」？

这取决于你跑的是哪条命令 —— 这才是真正需要区分的地方：

| 命令 | `a/` 这一侧（旧） | `b/` 这一侧（新） |
| --- | --- | --- |
| `git diff` | **index（暂存区）** | **worktree（工作区）** |
| `git diff --cached` / `--staged` | **HEAD（当前 commit）** | **index（暂存区）** |
| `git diff HEAD` | **HEAD（当前 commit）** | **worktree（工作区）** |
| `git diff <A>..<B>` | commit A 的 tree | commit B 的 tree |
| `git show <commit>` | 该 commit 的**父 commit** | 该 commit |
| `git diff <A>...<B>`（三点） | merge-base(A,B) | B |

> ⚠️ 记住这条口诀：**`git diff` 默认比的是「暂存区 vs 工作区」，不是「HEAD vs 工作区」**。
> 你以为在「看这次提交改了什么」，实际看的可能是「已经 add 过、但还没 commit 的那部分」。

---

## 3. a / b 这两个字母到底哪来的？——「A 应该是 after 吧？」

你的直觉没错，**但结论是反的**：`a` 不是 "after"。

### 铁证 1：两个文件名不同时，a 永远配第一个文件

```bash
$ printf 'old\n' > x1; printf 'new\n' > x2
$ git diff --no-index x1 x2
diff --git a/x1 b/x2
index 3367afd..3e75765 100644
--- a/x1
+++ b/x2
@@ -1 +1 @@
-old
+new
```

命令的语义是「拿 x1 去比 x2」，结果 **a/ 配 x1、b/ 配 x2**。
如果 a = after，这里就该写成 `a/x2 b/x1`。
**字母是按「位置」分配的，不是按「语义」分配的。**

### 铁证 2：前缀可以整个换掉

```bash
$ git diff --no-index --src-prefix='A_SIDE/' --dst-prefix='B_SIDE/' x1 x2
diff --git A_SIDE/x1 B_SIDE/x2
--- A_SIDE/x1
+++ B_SIDE/x2
```

前缀换成什么字母都行，说明 a/b 本来就只是**可替换的占位符**。

### 铁证 3：真正权威的锚点是 `---` 和 `+++`，不是 a/b

POSIX diff 标准里：

| 记号 | 含义 |
| --- | --- |
| `--- a/f` | **旧**文件那一栏（配合 `-line` 表示「删掉的行」） |
| `+++ b/f` | **新**文件那一栏（配合 `+line` 表示「新增的行」） |

a/ 与 `---` 同侧，b/ 与 `+++` 同侧。
**所以永远正确的读法是：减号开头的行 = 从 a 侧（旧）拿掉的；加号开头的行 = 往 b 侧（新）加上的。**

### 那 a 到底是什么的缩写？

严格说：**它不是任何单词的缩写**，它是「第一个操作数」的代号。
沿袭的是 Unix 给两个待比较文件的古老命名习惯：`cmp a b`、`comm a b`、`diff a b`。

民间流传的解读（都不是官方定义，别记反就行）：

- `a` = **a**ncient / **o**ld / **b**efore（祖先、旧版）← 最常见
- `b` = **b**ranch / **n**ew / 后一版（新版本）

**唯一安全的心智模型：字母表顺序 = diff 的左右顺序 = 旧 → 新。**

### 记错会怎样？

把 `a` 当成 after，会导致**读 diff 时把增删看反**：

```
--- a/f.md
+++ b/f.md
@@ -1,2 +1,2 @@
 keep
-gone      ← 这行是从【旧版】里删掉的
+new       ← 这行是往【新版】里加上的
```

如果你以为 a 是新版，就会把「删掉的行」读成「新增的行」，
于是 review 方向、patch 方向、冲突判断全错 —— 这是比记错字母更贵的代价。

### 建议：别背，用助记前缀

```bash
git -c diff.mnemonicprefix=true diff
# diff --git i/f.md w/f.md    ← i=index(暂存区)  w=worktree(工作区)
```

它直接把「两边到底是谁」写出来，彻底绕开 a/b 的歧义。

---

## 4. 前缀是可以改的 —— 亲手验证

Git 把前缀做成了可配置项，这也是最能证明「a/b 只是占位符」的证据。

```bash
# 1) 默认
$ git diff
diff --git a/f.md b/f.md
--- a/f.md
+++ b/f.md

# 2) 去掉前缀（--no-prefix，或 git config diff.noprefix true）
$ git diff --no-prefix
diff --git f.md f.md
--- f.md
+++ f.md

# 3) 自定义前缀（--src-prefix / --dst-prefix）
$ git diff --src-prefix=OLD/ --dst-prefix=NEW/
diff --git OLD/f.md NEW/f.md
--- OLD/f.md
+++ NEW/f.md

# 4) 助记前缀（--mnemonic-prefix）：直接告诉你两边是谁
$ git -c diff.mnemonicprefix=true diff
diff --git i/f.md w/f.md        # i = index, w = worktree
$ git -c diff.mnemonicprefix=true diff --cached
diff --git c/f.md i/f.md        # c = commit(HEAD), i = index
$ git -c diff.mnemonicprefix=true diff HEAD
diff --git c/f.md w/f.md        # c = commit, w = worktree
```

**`--mnemonic-prefix` 是排查「我到底在跟谁比」的神器**，助记字母表：

| 前缀 | 含义 |
| --- | --- |
| `c/` | commit（具体是哪个 commit 还会在 `diff --git` 行尾标出） |
| `i/` | index（暂存区） |
| `w/` | worktree（工作区） |
| `o/` | object（任意 object，用于 `git diff <sha>`） |
| `1/` | 仓库版本 1（用于 `git diff --no-index` / 外部比较） |
| `2/` | 仓库版本 2 |

也可以写进配置里永久生效：`git config --global diff.mnemonicprefix true`。

---

## 5. 实战中会遇到的几种变体

### 重命名 / 复制

```bash
$ git diff --cached
diff --git c/f.md i/g.md
similarity index 100%
rename from f.md
rename to g.md
```

此时 `a/` 和 `b/` 后面**是两个不同的路径**，不再是同一个文件。
Git 通过内容相似度（`similarity index`）自动检测 rename，阈值默认 50%（可用 `-M`、`--find-renames` 调整，`git config diff.renames`）。

删掉的文件：

```
diff --git a/old.md b/old.md
deleted file mode 100644
index 689b857..0000000
--- a/old.md
+++ /dev/null
```

新增的文件：

```
diff --git a/new.md b/new.md
new file mode 100644
index 0000000..f0adab2
--- /dev/null
+++ b/new.md
```

### 二进制文件

```
diff --git a/logo.png b/logo.png
index 689b857..f0adab2 100644
Binary files a/logo.png and b/logo.png differ
```

### `--stat` 里的字母不是 diff 前缀

```
$ git diff --stat
 ucp/SUMMARY.md | 12 ++++++++---
 1 file changed, 8 insertions(+), 4 deletions(-)
```

而 `git show --stat` / `git diff --summary` 里偶尔看到的 `A`、`M`、`D`，是**状态标记**（Added/Modified/Deleted），
跟 `a/` `b/` 完全是两码事，不要混淆。

---

## 6. 速查命令

```bash
# 我到底在跟谁比？——用助记前缀自问自答
git -c diff.mnemonicprefix=true diff
git -c diff.mnemonicprefix=true diff --cached
git -c diff.mnemonicprefix=true diff HEAD

# 看完整路径（去掉 a/ b/）
git diff --no-prefix

# 指定自定义前缀
git diff --src-prefix=old/ --dst-prefix=new/

# 只要文件名的增删统计
git diff --name-status
git diff --stat

# 显示完整 blob hash（不缩写）
git diff --full-index

# 只看某个文件
git diff -- ucp/SUMMARY.md
git diff --cached -- ucp/SUMMARY.md
```

---

## 7. 记忆要点

1. `a/` = **左边那一栏 = 旧版**，`b/` = **右边那一栏 = 新版**；**不是分支**，也不是 after/before 的首字母，只是位置占位符。
2. `diff --git a/X b/Y` 说的是「**这一个文件**的两个 blob」，不含任何分支/commit 语义。
3. 哪两个版本？看命令：`diff`=index↔worktree，`--cached`=HEAD↔index，`diff HEAD`=HEAD↔worktree，`show`=parent↔commit。
4. `index <hash1>..<hash2> <mode>` = 前后两个 **blob 的 SHA-1 缩写** + 文件权限位。
5. `--no-prefix` / `--src-prefix` / `--mnemonic-prefix` 都能改前缀 —— 改得动，说明它只是占位符。
6. `patch -p1` 会剥掉一层目录，这就是 a/ b/ 前缀存在的原因之一：**让补丁能定位到仓库里的真实路径**。

---

## 相关文档

- [How-to-understand-tree-id-and-commit-id.md](How-to-understand-tree-id-and-commit-id.md) —— blob / tree / commit id 的字节级结构，解释 `index` 行那两个 hash 的来历
- [How-to-understand-git-pull-rebase.md](How-to-understand-git-pull-rebase.md) —— rebase 之后 commit id 会变，拿到新 id 的方法
- [lazygit-guide.md](lazygit-guide.md) —— TUI 面板里看 diff 的快捷键
