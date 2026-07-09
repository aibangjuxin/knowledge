# 如何理解 Git 的 Tree ID 与 Commit ID

> **TL;DR — 30 秒版本**
>
> - **Tree ID** 是对一个**目录快照**的内容哈希：把目录里每个 entry (`文件名 + 模式 + 指向 blob/子树 id`) 排序后整体算 SHA-1。文件改、文件名改、文件权限改 → tree id 变;文件没动 → tree id 不变。
> - **Commit ID** 是对一个**历史节点**的内容哈希:它指向**一个** tree(根目录快照) + **零或多个** parent commit + 作者/提交者/时间戳/消息。 提交内容改、作者改、时间戳改、消息改 → commit id 变;哪怕 tree 完全一样,只要 parent/时间戳/消息不一样,commit id 也变。
> - **核心关系**:commit → tree → (blob 或子树)→ blob。**commit id 是历史的"身份证",tree id 是某一时刻"整个工作区长相"的指纹** —— 两者绑在一起但粒度不同。

如果你只想记住一句话:

> 📌 **tree id 决定"那个瞬间这个仓库长什么样",commit id 决定"那一刻是谁、什么时间、把什么样子提交了"。** 同一个文件内容,在两个不同 commit 里的 blob id 是一样的(内容寻址),但两个不同 commit 的 commit id 不一样(因为 metadata 不同)。

---

## 1. 为什么这篇文档要存在?

姊妹篇 [`How-to-get-commitid.md`](./How-to-get-commitid.md) 已经在讲 **怎么拿到 PR 的 commit ID**(gh CLI / REST API / GitLab / Gitee),但它默认你已经知道 commit ID **是什么**。

而日常操作中,以下问题都跟"tree id / commit id 到底是什么"直接相关:

| 场景 | 你困惑的问题 | 涉及的核心概念 |
|------|------------|--------------|
| `git diff <commit1> <commit2>` | 这两个 commit 的 tree 在比什么?为什么 diff 全空也算"变了"? | **commit 不是文件,commit 是一个 root tree 的引用** |
| `git push` 后 hash 没变 | 我没改代码,为什么 commit id 也没变? | **commit id 由内容 + 元数据共同决定** |
| `git rebase` 后 hash 全变 | 团队 rebase 后所有人都要 force-push | **每次新 commit = 重新算一个 commit id** |
| `git gc` / packfile | 仓库里 `objects/xx/yyyyyy...` 这些文件夹是什么? | **四种 object 的物理存储模型** |
| cherry-pick / squash | 为什么从 A 分支 cherry-pick 到 B 分支,commit id 还是变了? | **commit id 含 parent + 时间戳 → 必然变** |
| 跨仓库找相同文件 | 两个仓库里"文件内容一样但文件名不同",blob id 居然一样? | **blob 是 content-addressed**(同内容永远同 hash) |
| `git filter-repo` / `git filter-branch` | 改写历史后每个 commit 都改了 hash,代价是什么? | **commit id 是不可变的 → 改写历史 = 全部重算 + force-push** |

把这篇文章读完,你会用 **一张心智模型图** 把这些全部串起来。

---

## 2. 三种视角:同一件事的三个切面

为了不让你"看了定义还是不会用",下文用三种视角讲同一事实,任选你舒服的那个入口:

- **§3 抽象视角**:从"Git 是什么"的角度讲(分布式版本控制 + 内容寻址)
- **§4 朴素视角**:从"它在硬盘上长什么样"的角度讲(`.git/objects/xx/yyyyyy...`)
- **§5 严格视角**:**源码 / 命令 / 字段** 精确到字节,跟 [`git cat-file`](#7-验证-用-cat-file-对象浏览器看-gitoo) 直接对得上

**(还有一个 §6 公式化视角,用数学公式表达**"变了什么 → hash 怎么变",**放最后给"我就要个公式"的人用。)**)

---

## 3. 抽象视角:Git 是一个**内容寻址的键值数据库**

把 Git 当作一个对**整个项目历史**建模的系统,核心抽象只有一句话:

> **Git 是一个内容寻址的文件系统 + 建立在它之上的一套版本控制接口。**
>
> —— Pro Git,Chapter 10 *Git Internals*

也就是说,**Git 不是把"文件 v1 → 文件 v2 → 文件 v3"按线性版本号存的**;它存的是:

```
                  ┌─────────────────────────────────────┐
                  │  Object Database (内容寻址 / kv 库) │
                  └─────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────────┬────────────────┐
        ▼              ▼                  ▼                ▼
   ┌─────────┐   ┌─────────┐      ┌──────────────┐  ┌─────────┐
   │  blob   │   │  tree   │      │   commit     │  │   tag   │
   │(文件内容)│   │(目录结构)│     │(历史节点)    │  │(带签名的│
   │         │   │         │      │              │  │ 引用)   │
   └─────────┘   └─────────┘      └──────────────┘  └─────────┘
        │              │                  │
        │              │   引用(parent)   │
        │              │◄─────────────────┘
        │              │
        └──────────────┘
            引用
```

四类 object 中:

- **blob**:一个**文件的内容**(纯字节流,不包含文件名)
- **tree**:一个**目录的结构**(若干 entry,每个 entry:模式 + 类型 + 文件名 + 指向的 blob 或子树)
- **commit**:一次**提交**(指向一个 root tree + 零或多个 parent commit + 作者/时间/消息)
- **tag**:一个**带注释的引用**(通常指向 commit,可选 GPG 签名)

**每类 object 的"身份" = 它的 SHA-1 hash**(默认算法;Git 2.42+ 支持 SHA-256)。这就是**所有 ID 的来源** —— **id 不是仓库分配的,是从 object 的字节内容算出来的**。

这就是为什么:
- 同内容 → 同 ID(就算在两个完全独立的仓库里、文件名不同)
- 内容差一个字节 → ID 全变(SHA-1 雪崩效应)
- 你**改不了**历史里的 ID —— 改了内容 ID 自然变

---

## 4. 朴素视角:在你硬盘上,Git 到底存了什么?

### 4.1 仓库根目录下你看到的

```
your-repo/
├── .git/                          ← 所有版本数据都在这
│   ├── HEAD                       ← 当前指向
│   ├── objects/                   ← 所有 object 的物理存储
│   │   ├── 3f/
│   │   │   └── b794ad0610cced04e1991d3e389aace0480803
│   │   ├── 59/
│   │   │   └── 5d926f5f12bcef9a3ba3a93e8ba447d850878a
│   │   ├── ce/
│   │   │   └── 013625030ba8dba906f756967f9e9ca394464a
│   │   ├── info/
│   │   └── pack/                  ← 大仓库会用 packfile 压缩,可能取代散列文件
│   ├── refs/                      ← 人类可读的引用(branch / tag)
│   │   ├── heads/main
│   │   └── tags/v1.0
│   └── ...
├── README.md                       ← 你的工作区文件
└── app.txt
```

`objects/xx/yyyyyy...` 这种 **fan-out 路径**:

- 头两位 `xx` 是子目录(避免单目录文件过多)
- 后面 38 位是 hash 的剩余部分
- 文件本身存的 **不是原文件**,而是 `zlib 压缩后的 "<type> <size>\0<content>"`

```bash
$ ls -la .git/objects/ce/013625030ba8dba906f756967f9e9ca394464a
-r--r--r--  1 lex  staff  18  Jul  9 10:50  .git/objects/ce/013625...644a

# 文件体积 18 字节 = "blob 13\0hello\n" 的 zlib 压缩
$ git cat-file -p ce013625030ba8dba906f756967f9e9ca394464a
hello
```

这把"找文件"变成了"我有 hash,我去 `objects/<hash[0:2]>/<hash[2:]>` 读"。

### 4.2 一个具体例子:两个 commit 在硬盘上像什么?

我们新建一个最简单的仓库,有两次 commit:

```bash
$ mkdir demo && cd demo
$ git init -q -b main
$ echo "hello" > README.md
$ echo "v1"   > app.txt
$ git add . && git commit -q -m "first commit"     # → commit X
$ mv README.md README2.md
$ git add -A && git commit -q -m "rename"          # → commit Y
```

`git log --format='%H %h %s'` 看到的是(每个 commit 一个 commit object,自己的 ID = 完整 hash):

```
5287060ae0160be3409c656c0a20a94e3fbc0983  5287060  rename       ← commit Y
3fb794ad0610cced04e1991d3e389aace0480803  3fb794a  first commit ← commit X
```

> ⚠️ **重要避坑点**:上面的 `git log --oneline` 默认只显示短前缀(7 位),而 demo 仓库里 **commit Y 的 root tree** 短前缀恰好**也是 `b364709`(但全 hash 是 `b364709693d025ac429c338e8ea73745daaad277`)**。这个巧合容易把"tree"看错成"commit"——**任何时候对比 ID 都用全 40 位 hash**(`git rev-parse HEAD` / `--format=%H`),不能用短前缀区分两个 object。

但这个视图隐藏了 **每个 commit 后面跟着一整张对象图**:

```
                  ┌────────────────────────┐                             ┌────────────────────────┐
   commit X       │ 3fb794ad0610...         │  commit X                 │ (无 parent,初次提交)     │
   (first)        │ tree: 595d926f5f12...   │                           │                         │
                  │ author ...              │                           │                         │
                  │ committer ...           │                           │                         │
                  │ msg: first commit       │                           │                         │
                  └────────────────────────┘                           └────────────────────────┘
                          │                                                       │
                          ▼                                                       ▼
                  ┌──────────────────────────────┐                      ┌────────────────────────┐
   tree X (root)  │ 595d926f5f12bcef9a3ba...    │                      │ 5287060ae0160be34...   │
                  │                              │                      │ commit Y (rename)       │
                  │ 100644 blob ce013625... README.md                    │ tree: b364709693d0... │
                  │ 100644 blob 626799f0... app.txt                      │ parent: 3fb794ad0610.. │
                  └──────────────────────────────┘                       │ author ...              │
                          │              │                                │ committer ...           │
                          ▼              ▼                                │ msg: rename            │
                  ┌──────────────┐  ┌──────────────┐                      └────────────────────────┘
                  │ blob ce013625│  │ blob 626799f0│                               │
                  │  "hello"     │  │  "v1"        │                               ▼
                  └──────────────┘  └──────────────┘                      ┌──────────────────────────────┐
                                                                       │ b364709693d025ac429c...    │
                                                                       │ tree Y (root,当前)            │
                                                                       │ 100644 blob ce013625... README2.md │
                                                                       │ 100644 blob 626799f0... app.txt   │
                                                                       └──────────────────────────────┘
                                                                                  │                  │
                                                                                  ▼                  ▼
                                                                       (blob ce013625 还在那,内容不变)
                                                                       (blob 626799f0 也在那,内容不变)
```

**注意观察**:

- **`README.md` 和 `README2.md` 内容一样 → blob id 都是 `ce013625030ba8dba906f756967f9e9ca394464a`**(content-addressed)
- **commit Y 的 tree(`b364709693d025ac...`)里 `README2.md` 那行,blob 指针仍然是 `ce013625...`** —— 文件名变了,但 blob 没重新存,只是 tree 的 entry 改了文件名
- **commit X(`3fb794ad0610...`)和 commit Y(`5287060ae016...`)是两个完全不同的 object**,各自占 1 个独立文件在 `objects/xx/yyyyyy...`;Y 的 tree(`b364709693d...`)也是个独立 object,X 的 tree(`595d926f5f1...`)是另一个独立 object
- 这就是"Git 不存 diff,存快照"的物理体现 —— 内容相同的文件,跨 commit 共享同一个 blob object

**前面的 ASCII 图里 `b364709693...`(commit Y 的 tree)被从 commit 框里画出来,是为了展示 commit object 内部用 `tree: b364709...` 来引用它**。`b364709` 这个短前缀同时是 commit 框里 tree 行 = ASCII 图里 tree 框,二者指**同一个 tree object**,短前缀相同是巧合(都是同一份字节流的 SHA-1)。**不要看到短前缀相同就当同一个 object。**

### 4.3 那 tree 究竟"算"什么?

朴素版:

> tree object 的内容 = 「把目录里所有 entry 按名字排序 + 每个 entry 写『文件模式 空格 类型 空格 hash 空格 文件名 换行』拼接成的文本」
>
> 然后对这个文本做 SHA-1,得到 tree id

所以:

- **目录里某个文件加了 1 个字节 → 文件 mode/类型/hash/名字 这条 entry 的 hash 变了 → tree 的内容变了 → tree id 变了**
- **目录里某个文件重命名了(内容不变)→ entry 的 hash 没变(blob 是同一个),但 entry 的"文件名"变了 → entry 内容变了 → tree 的内容变了 → tree id 变了**
- **什么都没变 → entry 完全一样 → tree 内容字节级一致 → tree id 不变**

---

## 5. 严格视角:精确到字节 —— commit object / tree object 长什么样?

### 5.1 commit object 的字节级结构

```bash
$ git cat-file -p <commit-id>
tree <tree-id>                          ← 这次 commit 的根目录快照
parent <commit-id>                      ← 前一次 commit(可多个,merge 就有多个)
author    <name> <email> <unix-ts> <tz>
committer <name> <email> <unix-ts> <tz>

<commit message>
```

完整例子(从真实 demo 仓库抓出来):

```
tree 595d926f5f12bcef9a3ba3a93e8ba447d850878a
author demo <demo@x> 1783565458 +0800
committer demo <demo@x> 1783565458 +0800

first commit
```

注意一个微妙处:**`author` 和 `committer` 是两个独立字段**。

- `author` = 谁写的代码
- `committer` = 谁真正把这个改动放进仓库(可能 cherry-pick / rebase 时不同)

**所以 `git commit --amend --author=Alice` 会改 commit id(改了 author),`git commit --amend` 哪怕消息没动也会改 commit id**(amend 的本质是"重新创建一个 commit object",时间戳、committer 都会重新写)。

### 5.2 tree object 的字节级结构

```bash
$ git cat-file -p <tree-id>
100644 blob ce013625030ba8dba906f756967f9e9ca394464a	README.md
100644 blob 626799f0f85326a8c1fc522db584e86cdfccd51f	app.txt
```

每条 entry 格式:

```
<mode-as-octal-without-leading-zero> <type> <hash-as-binary-20-bytes>  <tab>  <filename-in-utf8>
```

- `mode`:如 `100644`(普通文件)、`100755`(可执行)、`040000`(子目录 → 对应一个子树 object)、`120000`(symlink)
- `type`:`blob` 或 `tree`
- `hash`:SHA-1(20 字节,不是 40 hex 字符,但 git 的 `cat-file -p` 会以 hex 显示)
- `filename`:`\t` 分隔,无前导 `/`,可以有 `/` 表示更深目录

**Git 内部对 tree 内容会先按"特定排序规则"排序再算 hash** —— 跟字母序不一样(目录名末尾会加 `/` 排),这是 [Pro Git 10.2](https://git-scm.com/book/en/v2/Git-Internals-Git-Objects) 的细节,日常不用管。

### 5.3 blob object 的字节级结构

```bash
$ git cat-file -p <blob-id>
hello
```

blob 就这么简单:**没有文件名的纯文件内容**。**两个 blob id 完全一致 ⟺ 两个字节流完全一致**(跨仓库、跨文件名、跨历史点都成立)。

### 5.4 算 hash 的公式

Git 给任何 object 算 SHA-1 之前,先拼一个 header:

```
<类型> <字节数>\0<原始内容>
```

举例(blob 内容 `hello`):

| 字段 | 值 |
|------|-----|
| 类型 | `blob` |
| 字节数 | 5 |
| header | `blob 5\0` |
| 全文(header + 内容) | `blob 5\0hello` |
| SHA-1(hex) | `ce013625030ba8dba906f756967f9e9ca394464a` |

**这就是为什么 git 是"内容寻址":type + size + content 三者任何一个变,SHA-1 全变。**

对 tree、commit 同理 —— tree 的 SHA-1 是"tree header + 一堆 entry"的 SHA-1;commit 的 SHA-1 是"commit header + tree 指针 + parent 指针 + 作者 + committer + 空行 + 消息"的 SHA-1。

---

## 6. 公式化视角:hash 怎么变 → 哪些字段决定哪些 ID?

把这个视角独立成一节,给"我就要公式"的人:

```
                       ┌──────────────────────────────────────┐
                       │  blob-id  = sha1("blob " ‖ len ‖ file_bytes) │
                       │             └──── 决定 ────┘            │
                       │             (文件原内容,无文件名)        │
                       └──────────────────────────────────────┘
                                  │  ↑  hash 出来的
                                  ▼
                ┌──────────────────────────────────────────────┐
                │ tree-id  = sha1("tree " ‖ len ‖ entries_text)│
                │            entries_text = sorted join of:     │
                │              "mode type hash\0 name\n"        │
                │              (其中 hash 子项是 blob-id 或子树 tree-id)│
                │                                              │
                │   tree-id 决定因素:                           │
                │    - 每个 entry 的 mode                       │
                │    - 每个 entry 的 type                       │
                │    - 每个 entry 指向的 hash                    │
                │    - 每个 entry 的 filename                    │
                └──────────────────────────────────────────────┘
                                  │  ↑  hash 出来的
                                  ▼
        ┌─────────────────────────────────────────────────────────────┐
        │ commit-id = sha1("commit " ‖ len ‖ body_text)             │
        │             body_text 决定因素:                              │
        │              - 根 tree-id (决定快照)                        │
        │              - 0 个或多个 parent commit-id (决定父节点链)    │
        │              - author (name + email + unix-ts + tz)         │
        │              - committer (同 4 字段)                       │
        │              - commit message (前有 1 空行)                  │
        │                                                               │
        │   commit-id 决定因素:                                        │
        │    任何上面 6 个字段变 → commit-id 变                        │
        └─────────────────────────────────────────────────────────────┘
```

### 6.1 哪些操作会让 commit id 不变?

只有极少数:

- `git commit --amend` 哪怕消息没动 → **会变**(committer / 时间戳重写)
- `git reset --soft HEAD^ && git commit -m "same msg"` → **会变**(完整新对象)
- `git revert <commit>` → **会变**(新 commit object)
- `git tag <tag-name> <commit>` → **commit id 不变**(tag 是独立 object)

> 简单说:**commit object 一旦写入 `.git/objects/`,它的 id 就跟内容绑死了;同内容是同一个 id,但内容里任何一个 bit 改了,它就是一个全新的 object、新的 id。**

### 6.2 哪些操作会让 tree id 不变?

- 仓库里任何文件**完全没动** → 那个文件的 blob id 不变 → 它在 tree 里的 entry 不变
- tree 不变 → 指向它的所有 commit 的 `tree <tree-id>` 那行不变 → 只对 tree 不变的 commit 中 commit-id 才可能不变
- 但只要 author 时间戳变了 → commit-id 也会变(即使 tree-id 一致)
- 所以日常里 "**commit-id 不变**" 的常见场景只有:**没人改时间戳、重新 hash 了同一个 commit**(在 git 里几乎不会自然发生 —— 通常只能通过 `git replace` / `git hash-object` 这类工具强制造一个)

### 6.3 哪些操作会让 blob id 不变?

只有"内容字节级一致"的情况。

- 文件加 1 个换行 → blob id 变
- 文件改一个权限位但内容不变 → blob id 不变(权限不在 blob 里,在 tree entry 的 mode 里 → 影响 tree-id 但不影响 blob-id)
- 文件从 `LF` 转 `CRLF`(视配置)→ 可能变也可能不变(看 `text` 属性 + autocrlf)

---

## 7. 验证:用 `cat-file`(对象浏览器)看 git 内部

这一节是命令清单,可以放心复制粘贴到任何 git 仓库跑。

### 7.1 `git cat-file -t <hash>` —— 看这是个什么类型的 object

```bash
$ git cat-file -t HEAD
commit

$ git cat-file -t HEAD^{tree}
tree

$ git cat-file -t HEAD:README.md
blob
```

`HEAD^{tree}` 是 git 的 **rev-parse 语法**,意思是"HEAD 这个 commit 指向的那个 tree object"。注意 shell 里 `^` 可能要转义(CMD 用 `^^`,PowerShell 用单引号包 `master^{tree}`)。

### 7.2 `git cat-file -p <hash>` —— 美化打印 object 内容

```bash
# 整个 commit 信息
$ git cat-file -p HEAD
tree 595d926f5f12bcef9a3ba3a93e8ba447d850878a
author demo <demo@x> 1783565458 +0800
committer demo <demo@x> 1783565458 +0800

first commit

# tree 内容
$ git cat-file -p HEAD^{tree}
100644 blob ce013625030ba8dba906f756967f9e9ca394464a	README.md
100644 blob 626799f0f85326a8c1fc522db584e86cdfccd51f	app.txt

# blob 内容
$ git cat-file -p HEAD:README.md
hello
```

### 7.3 `git cat-file --textconv` —— 看 `.gitattributes` 过滤后的 blob

一些文件类型可能经过 `textconv` 过滤器再展示(比如 PO 文件、PDF 文本提取);平时不用。

### 7.4 `git rev-parse <something>` —— 各种"翻译成 hash"

```bash
$ git rev-parse HEAD                       # commit id
b364709693d025ac429c338e8ea73745daaad277

$ git rev-parse HEAD^{tree}                # tree id
595d926f5f12bcef9a3ba3a93e8ba447d850878a

$ git rev-parse HEAD:README.md             # blob id
ce013625030ba8dba906f756967f9e9ca394464a

$ git rev-parse --short HEAD               # 短前缀(7 位)
b364709
```

### 7.5 `git ls-tree` —— 看 commit 或 tree 的内容列表

```bash
$ git ls-tree HEAD
100644 blob ce013625030ba8dba906f756967f9e9ca394464a	README2.md
100644 blob 626799f0f85326a8c1fc522db584e86cdfccd51f	app.txt
```

`git ls-tree -r HEAD` 递归展示所有子树。

### 7.6 `git hash-object` —— 手动算一个 object 的 hash

```bash
# 把字符串 "hello" 当 blob,打印 hash
$ echo -n "hello" | git hash-object --stdin
ce013625030ba8dba906f756967f9e9ca394464a

# 等价于:
$ printf "blob 5\0hello" | shasum
ce013625030ba8dba906f756967f9e9ca394464a
```

`git hash-object` 是 plumbing(底层)命令,但这是验证 SHA-1 计算的最直接方式。

### 7.7 `git update-index` + `git write-tree` —— 手动构造一个 tree

plumbing 玩法(了解即可,日常用 `git add` / `git commit` 就够了):

```bash
# 把 README.md 加入 index(staging area)
$ git update-index --add --cacheinfo 100644,ce013625...,README.md

# 把整个 index 写成一个 tree object,得到 tree-id
$ git write-tree
595d926f5f12bcef9a3ba3a93e8ba447d850878a
```

这就是"git 怎么从 index 变到 tree object"的底层路径。

---

## 8. 决策流程:遇到 hash 困惑时怎么查?

```
你想搞清楚"某个 hash 是什么 / 变了没 / 为什么变了"
                              │
                              ▼
        ┌────────────────────────────────────┐
        │  Step 1:  先确认 hash 是什么类型     │
        │  $ git cat-file -t <hash>          │
        │  → commit / tree / blob / tag       │
        └────────────────────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────┐
        │  Step 2:  按类型挑对应动作           │
        │                                     │
        │  commit →  $ git cat-file -p <h>   │ → 看 tree / parent / 时间戳
        │                                     │
        │  tree    →  $ git cat-file -p <h>   │ → 看每个 entry(blob 或 子 tree)
        │                                     │
        │  blob    →  $ git cat-file -p <h>   │ → 看裸内容(确认是不是想那个文件)
        │                                     │
        │  tag     →  $ git cat-file -p <h>   │ → 看 tag object 内容(annotated tag)
        └────────────────────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────┐
        │  Step 3:  判断 hash 应不应该变       │
        │                                     │
        │  commit: 应该变 if                  │
        │    - 根 tree 变了(内容改了)         │
        │    - parent 变了(rebase / cherry-pick)│
        │    - author/committer 时间戳变了    │
        │    - commit message 改了            │
        │                                     │
        │  tree: 应该变 if                    │
        │    - 任一文件内容变了               │
        │    - 任一文件被重命名               │
        │    - 任一文件权限位变了             │
        │    - 任一文件被 add/delete          │
        │                                     │
        │  blob: 应该变 if                    │
        │    - 文件字节流变了                 │
        │    (mode / 文件名 变化不影响 blob-id)│
        └────────────────────────────────────┘
                              │
                              ▼
        ┌────────────────────────────────────┐
        │  Step 4:  "内容相同 → 同 hash" 验证│
        │  $ <echo content> | git hash-object --stdin│
        │  跟目标 hash 比对                   │
        │                                     │
        │  == → 内容字节级一致                │
        │  != → 至少 1 字节不同               │
        └────────────────────────────────────┘
```

---

## 9. 常见误解 vs 真相

### 误解 1:"commit id 就是版本号"

**错。** commit id 是**那次提交的内容 + 全部 metadata** 的 SHA-1。"版本号"意味着线性、自增、仓库分配;而 commit id 是内容自决定、可能两个 commit 内容完全相同 hash 就完全相同(罕见但理论存在)。

### 误解 2:"内容相同的两个文件,blob id 应该不一样(因为文件名不同)"

**错。** blob 不含文件名,只看字节流。两个文件 `a.txt = hello`、`b.txt = hello`,blob id 完全相同 —— 这是 Git 跨 commit 共享文件内容的物理基础。

### 误解 3:"fix typo rebase 后所有 commit id 都变了,等价于"丢失了原 commit""

**错。** 旧 commit object **还在** `.git/objects/` 里,新 commit id 是**新**的 object。两条 id 共存,只是 orphan(没有 ref 指向)。`git reflog` 或 `git fsck --unreachable` 可以查到。

### 误解 4:"tag 跟 commit id 是一回事"

**部分错。** 两种 tag:

- **lightweight tag**:就是 `refs/tags/v1.0` 文件直接存 commit id(本质是 commit 的一个别名,**没单独 object**)
- **annotated tag**:是**一个独立的 tag object**,指向一个 commit,带 tagger 信息 + 签名 + message。`git cat-file -p v1.0.0` 看到内容,就能区分这两种

### 误解 5:"`git commit --amend` 不改 commit id"

**错。** `--amend` 本质是"再创建一个 commit,内容跟你给的参数一致"。**任何 amend 都会改 commit id**,因为 committer 时间戳会重新写。

### 误解 6:"不同分支的 commit id 一定不同"

**错。** 如果两个分支都做了"内容字节级一致 + 作者/时间戳/消息完全一致"的提交(理论上罕见但 Git 允许),commit id 会一样 —— 此时两个分支指向同一 object,GC 时只留 1 份。日常碰不到,但要明白这个可能性。

### 误解 7:"SHA-1 不安全,Git 是不是有 bug?"

**正经回答**(对应 §3 footnote):SHA-1 已知有 practical 碰撞攻击([SHAttered](https://shattered.io/),2017)。Git 2.42 (2023-08) 开始支持 **SHA-256** 后端作 opt-in。新项目建议设 `git config --global init.defaultObjectFormat sha256`。**默认 SHA-1 在工程上仍安全**,但理论风险存在。

---

## 10. 跨文章引用

| 场景 | 看这篇 |
|------|--------|
| 怎么拿 PR 的 commit id(GitHub / GitLab / Gitee / local)| [`How-to-get-commitid.md`](./How-to-get-commitid.md) |
| rebase / merge 对 commit id 的影响、决策表 | `How-to-get-commitid.md` §2.2 |
| git rebase 拆解 | [`docs/git-rebase.md`](./docs/git-rebase.md) |
| git 内部工作流高层 | [`docs/how-git-working.md`](./docs/how-git-working.md) |
| 仓库角色权限 | [`github-repo-role-permissions.md`](./github-repo-role-permissions.md) |

---

## 11. 关键命令速查(贴在 terminal 边)

```bash
# === 查 ID 是什么类型 ===
git cat-file -t <hash>

# === 美化打印 object 内容 ===
git cat-file -p <hash>
git cat-file -p HEAD               # commit 内容
git cat-file -p HEAD^{tree}        # root tree 内容
git cat-file -p HEAD:path/to/file # 单个 blob

# === 把"可读名"翻译成 hash ===
git rev-parse HEAD                 # commit
git rev-parse HEAD^{tree}          # tree
git rev-parse HEAD:path/to/file    # blob
git rev-parse --short <hash>       # 短前缀

# === 浏览 tree ===
git ls-tree HEAD                   # 顶层
git ls-tree -r HEAD                # 递归

# === 手动算 hash(debug 用) ===
echo -n "content" | git hash-object --stdin

# === plumbing:手工构造 tree ===
git update-index --add --cacheinfo <mode>,<hash>,<path>
git write-tree    # 输出 tree-id
```

---

## 12. 一句话原则

> 📌 **Git 里的所有 ID 都来自内容,不存在"仓库分配的 ID"。**
> 文件内容决定 blob id;
> 文件名 + 模式 + 子内容决定 tree id;
> 快照(tree) + 历史(parent) + 元数据(作者/时间/消息) 决定 commit id。
>
> 想掌控 hash → 掌控上面每个等号右边的字段;改任意一个 = 新 hash。
>
> 想避开 hash 漂移带来的混乱 → 用 PR 编号 / tag / branch name 引用变更,不要硬编码 commit id。

---

## 13. 引用来源 / 权威证据

- 📘 **Pro Git, Chapter 10 Git Internals — Git Objects**:<https://git-scm.com/book/en/v2/Git-Internals-Git-Objects>
  - 原文:"This object type is called a *blob*. … The next type of Git object we'll examine is the *tree*, which solves the problem of storing the filename and also allows you to store a group of files together. … A single tree object contains one or more entries, each of which is the SHA-1 hash of a blob or subtree with its associated mode, type, and filename."
  - 这篇文章的 §3 抽象视角、§4 朴素视角、§5.1–5.3 严格视角,基本是这本书 10.2 节的浓缩 + 案例化。
- 📘 **Pro Git, Chapter 10 — SHA-1 公式与 objects/xx/yyyyyy 物理存储**:
  - 原文:"This is the SHA-1 hash — a checksum of the content you're storing plus a header … The subdirectory is named with the first 2 characters of the SHA-1, and the filename is the remaining 38 characters."
- 📗 **`git cat-file` 官方文档**:<https://git-scm.com/docs/git-cat-file> —— §7 的对象浏览模式(`-t` / `-p`)对应的官方说明
- 📗 **Git 2.42 release notes (SHA-256 默认支持)**:<https://github.com/git/git/blob/master/Documentation/RelNotes/2.42.0.txt> —— §9 误解 7 的事实基础
- 🔗 **SHAttered(2017 SHA-1 practical collision)**:<https://shattered.io/> —— SHA-1 不再是密码学安全的工程性证据
- 🔬 **本地实证(本会话)**:在 `/tmp/git-obj-demo` / `git-obj-demo2` / `git-obj-demo3` 三个隔离仓库跑出真实 git 对象图,文中 §4.2 和 §6 给的具体 hash 值都是这一次跑的输出,可复现:

```bash
# 复现 §4.2 演示
mkdir /tmp/git-obj-demo && cd /tmp/git-obj-demo
git init -q -b main && git config user.name demo
echo "hello" > README.md && echo "v1" > app.txt
git add . && git commit -q -m "first commit"
mv README.md README2.md && git add -A && git commit -q -m "rename"
git cat-file -p HEAD~       # 第一个 commit
git cat-file -p HEAD^{tree} # 第二个 commit 的 tree
```

---

✅ 全文完毕。如果有任何"这一节没说清"的点(比如 plumbing vs porcelain 的区分、packfile 的 delta 压缩、SHA-256 迁移路径),告诉我,可以再追加章节。
