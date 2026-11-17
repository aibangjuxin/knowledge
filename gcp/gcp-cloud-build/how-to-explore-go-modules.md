# Go 依赖探索手册（`go mod why` / `go mod graph` / `go list -deps`）

> **TL;DR**
>
> - **“这个依赖为什么在我的 `go.mod` 里？谁 import 了它？”** → `go mod why -m <模块路径>`（模块级）或 `go mod why <包路径>`（包级）。
> - `-m` 的参数是**模块根路径**（`golang.org/x/sync`），**不是包路径**（`golang.org/x/sync/errgroup`）。传错会直接输出 “does not need module”，这是最常见的误用。
> - **输出方向是从主模块指向目标**：最后一行是目标本身，**倒数第二行才是直接 import 它的人**。
> - **`go mod why` 在「没找到」时退出码仍是 `0`**（只有 `go.mod` 缺失这类硬错误才返回 1），所以不能靠 `$?` 判断有没有找到，必须读输出文本。
> - **默认会把「依赖的测试依赖」算进来**（`testify` 能通过 `logrus.test` 进入图里），加 `-vendor` 可排除依赖的测试（但保留你自己模块的测试）。
> - 模块级反向查找用 `go mod graph`，包级反向查找用 `go list -deps -f '...'`，二者都不是 `go mod why` 的功能。

---

## 目录

1. [前置：三层心智模型](#1-前置三层心智模型)
2. [命令速查矩阵](#2-命令速查矩阵)
3. [`go mod why` 详解](#3-go-mod-why-详解)
4. [`go mod graph`：模块级反向查找](#4-go-mod-graph模块级反向查找)
5. [`go list -deps`：包级反向查找](#5-go-list-deps包级反向查找)
6. [`go mod graph` / `go list -deps` / `go mod why` 三者对比](#6-go-mod-graph--go-list-deps--go-mod-why-三者对比)
7. [实战场景](#7-实战场景)
8. [常见坑清单](#8-常见坑清单)
9. [与 Cloud Build 的结合](#9-与-cloud-build-的结合)
10. [附录：一键探索脚本](#10-附录一键探索脚本)

---

## 1. 前置：三层心智模型

不懂这三层，`go mod why` 的输出永远看不懂。

| 层 | 是什么 | 出现在哪 | 例子 |
| :--- | :--- | :--- | :--- |
| **Module（模块）** | 一个可独立版本化的代码仓库，有唯一 `module` 路径 + 版本号 | `go.mod` 里的 `require` | `golang.org/x/sync v0.7.0` |
| **Package（包）** | 模块内的一个目录，import 路径 = 模块路径 + 目录路径 | 代码里的 `import` 语句 | `golang.org/x/sync/errgroup` |
| **Module graph（模块图）** | 模块之间的 requires 关系 | `go mod graph` 的输出 | `main → golang.org/x/sync@v0.7.0` |
| **Import graph（导入图）** | 包之间的 import 关系 | `go list all` 的结果 | `main/cmd/app → golang.org/x/sync/errgroup` |

**关键推论**：

- `go.mod` 里写的是 **模块**（一个模块多个版本，但只 require 一个版本）。
- 代码里 import 的是 **包**（一个模块可以包含几十个包）。
- **`go mod why` 查的是导入图**；加 `-m` 就把参数从「包」换成「模块」，并把查询目标从导入图换成模块图。

```text
  MODULE 图（go mod graph）                IMPORT 图（go list all）
  ─────────────────────────                ─────────────────────────
  example.com/demo                          example.com/demo/cmd/app
      ├──▶ github.com/sirupsen/logrus@v1.9.3     ├──▶ github.com/sirupsen/logrus
      └──▶ golang.org/x/sync@v0.7.0              └──▶ golang.org/x/sync/errgroup
                     ▲                                        ▲
                     │                                        │
          logrus 依赖它（模块级）              demo/cmd/app 依赖它（包级）

  go mod why -m 走左边        go mod why 走右边
```

---

## 2. 命令速查矩阵

| 你想问的问题 | 命令 | 粒度 |
| :--- | :--- | :--- |
| 这个**模块**为什么在我的 `go.mod` 里？ | `go mod why -m <module/path>` | 模块 |
| 这个**包**是谁 import 的？ | `go mod why <pkg/path>` | 包 |
| 哪些**模块**依赖了 X？（反向） | `go mod graph \| awk '$2 ~ "^X@" {print $1}'` | 模块 |
| 哪些**包**直接 import 了 X？（反向） | `go list -deps -f '...' ./... \| grep X` | 包 |
| `go.mod` 是否干净、能否 tidy？ | `go mod tidy -diff`（Go ≥ 1.23） | 文件 |
| 我这个二进制里实际带了哪些模块和版本？ | `go version -m <binary>` | 二进制 |
| 依赖有没有被篡改？ | `go mod verify` | 缓存 |
| 哪些依赖可以升级？ | `go list -m -u all` | 模块 |
| 全量依赖清单（含间接） | `go list -m all` | 模块 |
| `go.mod` 原始结构（机器可读） | `go mod edit -json` | 文件 |

---

## 3. `go mod why` 详解

### 3.1 官方语义

> `why` shows a shortest path in the import graph from the main module to each of the listed packages.
> If the `-m` flag is given, `why` treats the arguments as a list of **modules** and finds a path to **any package in each of the modules**.

即：**输出主模块 → 目标的最短依赖路径**。

### 3.2 输出格式

```text
# <目标>
<主模块的包>
<中间包>
...
<目标包>
```

- 第一行 `# <目标>` 是分隔用的注释行。
- 后面每行一个包，**构成一条最短路径**。
- 找不到时只输出一行括号说明：

```text
# github.com/nonexistent/mod
(main module does not need module github.com/nonexistent/mod)
```

- 多个参数 → 多个 stanza，**用空行分隔**。

### 3.3 三种调用形态（实测）

```bash
# ① 模块级：模块根路径 + -m
$ go mod why -m golang.org/x/sync
# golang.org/x/sync
example.com/demo/cmd/app
golang.org/x/sync/errgroup

# ② 包级：完整包路径，不加 -m
$ go mod why golang.org/x/sync/errgroup
# golang.org/x/sync/errgroup
example.com/demo/cmd/app
golang.org/x/sync/errgroup

# ③ 模块级但参数写成了包路径 → 找不到（最常见的坑）
$ go mod why -m golang.org/x/sync/errgroup
# golang.org/x/sync/errgroup
(main module does not need module golang.org/x/sync/errgroup)
```

> ⚠️ **结论**：`-m` 后面**只能跟模块根路径**。想知道是哪个包 import 的，就去掉 `-m` 并写完整包路径。

### 3.4 怎么读路径（回答“谁 import 了它”）

路径是**从主模块 → 目标**排列的：

```text
example.com/demo/cmd/app          ← 第 1 行：主模块里发起导入的包
github.com/sirupsen/logrus         ← 第 2 行：中间依赖
golang.org/x/sys/unix              ← 第 3 行（最后一行）：目标包
```

- **最后一行** = 目标本身。
- **倒数第二行** = **直接 import 目标的那个包** → 这就是“谁 import 了它”的答案。
- 行数越多 = 依赖链越长 = 这个包离你的代码越远，升级它影响面越大。

### 3.5 `-vendor` 标志：排除“依赖的测试依赖”

**默认行为**：`go mod why` 查的是 `go list all` 的图，它**包含依赖的测试依赖**。

实测：一个从未在自己的代码里 import 过 `testify` 的项目：

```bash
$ go mod why -m github.com/stretchr/testify
# github.com/stretchr/testify
example.com/demo/cmd/app
github.com/sirupsen/logrus
github.com/sirupsen/logrus.test          ← 依赖的「测试」包
github.com/stretchr/testify/assert
```

看起来「用到了 testify」，其实只是 `logrus` 的测试用了一下，**生产构建根本不会编进去**。

加 `-vendor` 排除依赖的测试：

```bash
$ go mod why -m -vendor github.com/stretchr/testify
# github.com/stretchr/testify
(main module does not need to vendor module github.com/stretchr/testify)
```

> `-vendor` **只排除「依赖的」测试**，**你自己模块的测试仍然保留**（下面实测里 `internal/util.test` 那条链依然在）。

### 3.6 主模块自身测试引入的依赖

```bash
$ go mod why -m github.com/stretchr/testify
# github.com/stretchr/testify
example.com/demo/internal/util
example.com/demo/internal/util.test        ← 你自己包的测试变体
github.com/stretchr/testify/assert
```

这条链里的 `X.test` 是 Go 为每个包生成的**测试变体包**，`X.test` 表示「在测试 `X` 的上下文里」。

---

## 4. `go mod graph`：模块级反向查找

`go mod why` **只能正向**（主模块 → 目标）。想知道「哪些模块依赖了 X」，必须换工具。

### 4.1 输出格式

每行 `A B` 表示：**模块 A 需要模块 B**。字段是 `模块路径@版本`。

```bash
$ go mod graph
example.com/demo github.com/sirupsen/logrus@v1.9.3
example.com/demo golang.org/x/sync@v0.7.0
github.com/sirupsen/logrus@v1.9.3 golang.org/x/sys@v0.0.0-20220715151400-c0bba94af5f8
...
```

### 4.2 反向：谁依赖 X

```bash
# X 的所有直接依赖方
$ go mod graph | awk '$2 ~ "^golang.org/x/sys@" {print $1}'
example.com/demo
github.com/sirupsen/logrus@v1.9.3
```

### 4.3 正向：X 依赖了谁

```bash
$ go mod graph | awk '$1 ~ "^golang.org/x/sync@" {print $2}'
```

### 4.4 找出「谁让我装上了 X」

```bash
# 找出主模块到 X 的所有模块级路径
go mod graph | awk -v target='golang.org/x/sys' '
  { edge[$1" -> "$2] = 1 }
  END { for (e in edge) print e }' | grep "$target"
```

### 4.5 找「孤儿依赖」

`go.mod` 里 require 了、但**整个依赖图里没有任何包真正用到**的依赖（手工加的、删了 import 但忘了 tidy 的）。用 `go mod why -m` 逐个探测：

```bash
# 找出 go.mod 里所有 require 但没人用的模块
for m in $(go mod edit -json | jq -r '.Require[] | .Path' | sort -u); do
  go mod why -m "$m" 2>&1 | grep -q '(main module does not need module' && echo "ORPHAN: $m" || true
done
```

> 末尾的 `|| true` **不能省**：`go mod why` 找不到时 `grep` 返回 1，在 `set -e` 的脚本里会直接把循环中断（实测会漏报后面的模块）。

实测（一个故意加进去的 `github.com/spf13/cobra`）：

```text
ORPHAN: github.com/spf13/cobra
```

> 注意：这招基于 `go mod why`，它**默认包含测试**。所以「只被测试用到的依赖」不会被误报为孤儿（这是对的 —— 测试依赖本来就该留在 `go.mod` 里）。

更省事的整体检查还是 `go mod tidy -diff`（见 §7.3），它会把该删的行直接 diff 出来。

---

## 5. `go list -deps`：包级反向查找

`go mod graph` 只到模块粒度。要精确到「**哪个包** import 了 X」，用 `go list -deps`。

### 5.1 基本用法

```bash
# 列出某个包构建时依赖的全部包
$ go list -deps ./...
# ...
github.com/sirupsen/logrus
golang.org/x/sync/errgroup
example.com/demo/cmd/app
```

### 5.2 反向：找出直接 import X 的包

```bash
$ go list -deps -test -f '{{.ImportPath}}|{{join .Imports " "}}' ./... \
  | awk -F'|' -v t="github.com/stretchr/testify/assert" 'index($2, t) > 0 {print $1}' | sort -u
example.com/demo/internal/util [example.com/demo/internal/util.test]
```

- `{{.ImportPath}}` = 导入者的包路径；`{{join .Imports " "}}` = 它 import 的包列表。
- 用 `|` 分隔 + `awk -F'|'` 只在**右半段**（导入列表）里匹配 `t`，这样**不会把目标包自己匹配进去**。
- ⚠️ 不要写成 `grep "X"` 扫整行 —— 目标包那一行（`X -> ...`）的**左半段**也含 `X`，会被误报成「自己 import 自己」。
- 输出里的 `[pkg.test]` 后缀是 Go 为该包生成的**测试变体包**。

### 5.3 必须加 `-test` 才包含测试依赖

```bash
# 不加 -test：只有生产构建依赖
$ go list -deps ./... | grep stretchr
(无输出)

# 加 -test：包含测试依赖
$ go list -deps -test ./... | grep stretchr
github.com/stretchr/testify/assert
```

> ⚠️ `go list -deps` **默认不含测试**，这跟 `go mod why` 的默认行为相反。两者一起用时容易得出矛盾结论。

### 5.4 输出 JSON 做更复杂的分析

```bash
# 列出某个包的所有依赖及其来源
go list -deps -json ./... | jq -r 'select(.Imports) | "\(.ImportPath) -> \(.Imports | join(", "))"'

# 列出某个包自身的元信息（Dir、Module、GoFiles）
go list -json ./cmd/app | jq '{ImportPath, Dir, Module, GoFiles}'

# 列出某个模块内所有包
go list -m -f '{{.Dir}}' github.com/sirupsen/logrus | xargs -I{} find {} -name '*.go' | head
```

---

## 6. `go mod graph` / `go list -deps` / `go mod why` 三者对比

| 维度 | `go mod why [-m]` | `go mod graph` | `go list -deps` |
| :--- | :--- | :--- | :--- |
| 图类型 | 导入图（`-m` 时为模块图） | **模块图** | **导入图** |
| 粒度 | 包（`-m` 时为模块） | 模块 | 包 |
| 方向 | **正向**：主模块 → 目标 | 双向（`awk` 加工后） | 正向（`grep` 加工后） |
| 含测试 | 默认含（`-vendor` 排除依赖的测试） | ❌ 不含 | 默认不含（需 `-test`） |
| 回答「谁依赖它」 | 需自己看倒数第二行 | ✅ 直接 awk | ✅ 直接 grep |
| 输出 | 最短路径链 | 全部边 | 全部包 + 导入列表 |
| 适合场景 | 「这个依赖**为什么**在 go.mod 里」 | 「**谁**引入了这个模块」 | 「**哪个包** import 了它」 |

**选择原则**：

1. 想知道**动机**（为什么 go.mod 里有它）→ `go mod why -m`
2. 想知道**责任方**（哪个模块引入的）→ `go mod graph`
3. 想知道**具体代码位置**（哪个包 import 的、文件在哪）→ `go list -deps`

---

## 7. 实战场景

### 7.1 `go.mod` 里有个依赖，没人知道谁在用

```bash
$ go mod why -m github.com/spf13/cobra
# github.com/spf13/cobra
example.com/demo/cmd/app
github.com/spf13/cobra
```

倒数第二行 `example.com/demo/cmd/app` 说明是**自己的代码**直接 import 的 → 可以直接删掉那行 import 再 `go mod tidy`。

如果输出是：

```text
(main module does not need module github.com/spf13/cobra)
```

说明是**残留**（`go.mod` 里有但实际没用到）→ `go mod tidy` 会清掉。

### 7.2 定位某个 CVE 依赖的引入路径

```bash
# 第 1 步：确认这个模块确实在依赖图里
$ go mod why -m golang.org/x/net
# golang.org/x/net
example.com/demo/internal/httpclient
golang.org/x/net/http2

# 第 2 步：找出是哪个上游模块拖进来的（indirect 依赖）
$ go mod graph | awk '$2 ~ "^golang.org/x/net@" {print $1}'
example.com/demo
github.com/grpc-ecosystem/grpc-gateway/v2@v2.19.0    ← 真正的元凶

# 第 3 步：看它为什么需要
$ go mod why -m github.com/grpc-ecosystem/grpc-gateway/v2
```

### 7.3 审查 `go.mod` 是否干净（不改动文件）

```bash
# Go ≥ 1.23：--diff 只打印差异，不写文件
$ go mod tidy -diff
diff old/go.mod new/go.mod
--- old/go.mod
+++ new/go.mod
@@ -3,6 +3,5 @@
 require (
     github.com/sirupsen/logrus v1.9.3
-    github.com/spf13/cobra v1.8.0      ← 这一行会被删掉
 )
diff old/go.sum new/go.sum
exit=0     # 无差异时 exit=0 且无输出
```

`go mod tidy -diff` 存在差异时退出码非 0 → **可以直接用作 CI 门禁**：

```bash
go mod tidy -diff && echo "go.mod is clean" || { echo "go.mod 需要 tidy"; exit 1; }
```

### 7.4 查二进制里实际带了哪些模块（生产排障神器）

```bash
$ go build -o app ./cmd/app
$ go version -m app
app: go1.27.3
	path	example.com/demo/cmd/app
	mod	example.com/demo	(devel)
	dep	github.com/sirupsen/logrus	v1.9.3	h1:dueUQJ1C2q9oE3F7wvmSGAaVtTmUizReu6fjN8uqzbQ=
	dep	golang.org/x/sync	v0.7.0	h1:YsImfSBoP9QPYL0xyKJPp0gcaJdG3rInoqxTWbfQu9M=
	dep	golang.org/x/sys	v0.0.0-20220715151400-c0bba94af5f8	h1:0A+M6Uqn+Eje4kHMK80dtF3JCXC4ykBgQG4Fe06QRh=
	build	-buildmode=exe
	build	CGO_ENABLED=1
```

- `dep` 行 = **实际链接进二进制的模块及版本 + 校验和**。
- 这是回答「线上这个二进制到底用了哪个版本？」的唯一权威来源。
- 同理可用于排查「明明 go.mod 写了 v1.9.3，为什么线上的包有 v1.8.0 的漏洞？」→ 二进制是唯一证据。

### 7.5 排查升级某个依赖的影响面

```bash
# 1. 谁依赖它（模块级）
go mod graph | awk '$2 ~ "^golang.org/x/net@" {print $1}'

# 2. 我方代码里哪些包直接 import 了它（包级）
go list -deps -test -f '{{.ImportPath}}|{{join .Imports " "}}' ./... \
  | awk -F'|' -v t="golang.org/x/net" 'index($2, t) > 0 {print $1}' | sort -u

# 3. 直接升级看会动到哪些 go.mod 行
go get -u golang.org/x/net && git diff go.mod go.sum

# 4. 不想改文件就只看会升到哪个版本
go list -m -u all | grep 'golang.org/x/net'
golang.org/x/net v0.23.0 [v0.38.0]
```

### 7.6 检查依赖完整性

```bash
$ go mod verify
all modules verified
```

### 7.7 没有 `go.mod` 时的错误

```bash
$ go mod why -m github.com/x/y
go: go.mod file not found in current directory or any parent directory; see 'go help modules'
$ echo $?
1
```

说明当前目录不在任何 module 内 —— 常见于：clone 了仓库但没跑 `go mod download`、在错误的子目录执行、或者用 `GO111MODULE=off` 跑在了 GOPATH 模式。

自查：`go env GOMOD` 在这种情况下返回 `/dev/null`。

---

## 8. 常见坑清单

| # | 坑 | 现象 | 解法 |
| :-- | :--- | :--- | :--- |
| 1 | `-m` 后面传了包路径 | `(main module does not need module X/pkg)` | `-m` 只配模块根路径；查包就去掉 `-m` |
| 2 | 靠退出码判断 | 「没找到」时 `$?` 仍是 `0`（只有 `go.mod` 缺失才返回 1） | 判断输出文本里有没有 `(main module does not need ...)` |
| 3 | 误把测试依赖当生产依赖 | `go mod why -m testify` 有输出，但生产构建根本不用 | 加 `-vendor`，或用 `go list -deps`（不含测试）交叉验证 |
| 4 | `go list -deps` 漏掉测试依赖 | 明明测试文件 import 了，列表里没有 | 加 `-test` |
| 5 | 路径方向看反 | 以为最后一行是「使用者」 | 最后一行是**目标**，**倒数第二行**才是直接使用者 |
| 6 | 在 workspace 模式下结果诡异 | `go.work` 存在时命令跨模块运行 | `GOWORK=off go mod why -m ...` 单模块视角 |
| 7 | `go mod tidy` 误改 `go` 指令 | 下游依赖被迫一起升级 | 只改 `toolchain`，不动 `go` 指令（见 `examples/cve-fix-go-deps.yaml`） |
| 8 | 在错误目录执行 | `go.mod file not found` | 先 `pwd` + `ls go.mod`，或用 `go env GOMOD`（不在 module 内时返回 `/dev/null`） |
| 9 | `go mod graph` 的字段带版本 | `grep 'golang.org/x/sys'` 匹配不到 | 正则用 `'^golang.org/x/sys@'` |
| 10 | 代理不可达 / 私有仓库 | `dial tcp: i/o timeout` | `GOPROXY=direct` 或配置 `GOPRIVATE`/`GONOSUMDB` |

### 环境自检命令

```bash
go env GOMOD          # 当前生效的 go.mod 绝对路径（= /dev/null 表示不在 module 内）
go env GOWORK         # 生效的 go.work（= /dev/null 或空 = 非 workspace 模式）
go env GOMODCACHE     # 模块缓存位置
go env GOPROXY GOPRIVATE GONOSUMDB GONOSUMCHECK
```

> ⚠️ `go env GOMOD` 在**不在任何 module 内**时返回的是 **`/dev/null`**，不是空字符串。判断要用 `[ "$(go env GOMOD)" = "/dev/null" ]`。

---

## 9. 与 Cloud Build 的结合

本仓库是 Cloud Build 知识库，Go 依赖探索在 CI 里有三个直接落点：

### 9.1 构建前：`go.mod` 必须是 tidy 的

在 `cloudbuild.yaml` 里加一步门禁，**避免把脏 `go.mod` 带进构建**：

```yaml
- name: 'golang:1.22'
  id: 'verify-mod'
  args: ['mod', 'tidy', '-diff']
  env:
    - 'GOWORK=off'
    - 'GOCACHE=/workspace/.gocache'
    - 'GOMODCACHE=/workspace/.gomodcache'
```

`go mod tidy -diff` 有差异时退出码非 0 → Cloud Build 直接判该 step 失败。也可以用 `script` 包装成更友好的报错信息。

### 9.2 构建中：依赖审计

```yaml
- name: 'golang:1.22'
  id: 'audit'
  entrypoint: bash
  args:
    - '-c'
    - |
      set -euo pipefail
      echo "── 主模块依赖树 ──"
      go mod graph | head -50
      echo "── 关键依赖引入路径 ──"
      go mod why -m golang.org/x/net || true
      echo "── 可升级项 ──"
      go list -m -u all
      echo "── 漏洞扫描 ──"
      go install golang.org/x/vuln/cmd/govulncheck@latest
      /go/bin/govulncheck ./...
```

### 9.3 构建后：确认二进制里的版本

静态二进制上传 GCS 后，用 `go version -m` 核对实际版本，把结果写进元数据：

```bash
go version -m /workspace/bin/app | grep '^\s*dep' | awk '{print $2, $3}' > /workspace/dist/deps.txt
```

这样制品出问题时，能立刻回答「这个包用的到底哪个版本」，而不是去猜 `go.mod` 里写的值。

> 完整可用的 Go 流水线模板见 [`examples/golang-binary.yaml`](examples/golang-binary.yaml)；依赖修复场景见 [`examples/cve-fix-go-deps.yaml`](examples/cve-fix-go-deps.yaml)。

---

## 10. 附录：一键探索脚本

把下面这段存成 `go-dep-explorer.sh` 放进仓库根目录，可直接复用：

```bash
#!/usr/bin/env bash
# go-dep-explorer.sh —— Go 依赖探索小工具
# 用法: ./go-dep-explorer.sh why <module>   谁引入了这个模块
#       ./go-dep-explorer.sh who  <package>  哪个包 import 了它
#       ./go-dep-explorer.sh tree <module>   模块级依赖子树
#       ./go-dep-explorer.sh orphan          go.mod 里的孤儿依赖
#       ./go-dep-explorer.sh outdated        可升级依赖
#       ./go-dep-explorer.sh audit           一次性全量体检
set -euo pipefail

if [ "$(go env GOMOD)" = "/dev/null" ] || [ -z "$(go env GOMOD)" ]; then
  echo "✗ 当前目录不在任何 Go module 内 (go env GOMOD = $(go env GOMOD))" >&2
  exit 1
fi

cmd="${1:-help}"; target="${2:-}"

case "$cmd" in
  why)
    # 模块级正向：主模块 → 目标 的最短路径
    go mod why -m "$target"
    ;;
  who)
    # 包级反向：谁直接 import 了这个包
    # 注意只在 Imports（右半段）里匹配，避免把目标自己匹配进去
    go list -deps -test -f '{{.ImportPath}}|{{join .Imports " "}}' ./... \
      | awk -F'|' -v t="$target" 'index($2, t) > 0 {print $1}' | sort -u
    ;;
  tree)
    # 模块级正向依赖树
    go mod graph | awk -v m="$target" '$1 ~ "^"m"@" {print "  "$2}'
    ;;
  orphan)
    # go.mod 里 require 但依赖图中无人引用的依赖
    # 末尾 || true 不能省：否则 set -e 会在第一个 grep 失败时中断循环
    for m in $(go mod edit -json | jq -r '.Require[] | .Path' | sort -u); do
      go mod why -m "$m" 2>&1 | grep -q '(main module does not need module' && echo "ORPHAN: $m" || true
    done
    ;;
  outdated)
    go list -m -u all
    ;;
  audit)
    echo "═══ 1. go.mod 是否 tidy ═══"
    go mod tidy -diff && echo "✓ clean" || echo "✗ 需要 tidy"
    echo
    echo "═══ 2. 模块图 ═══"
    go mod graph
    echo
    echo "═══ 3. 直接依赖方 ═══"
    go list -deps -test -f '{{.ImportPath}}|{{join .Imports " "}}' ./... \
      | awk -F'|' 'index($2, "github.com") > 0 {print $1}' | sort -u | head -30
    echo
    echo "═══ 4. 缓存校验 ═══"
    go mod verify
    echo
    echo "═══ 5. 可升级项 ═══"
    go list -m -u all
    ;;
  *)
    sed -n '2,9p' "$0"
    ;;
esac
```

---

## 相关文档

| 文档 | 内容 |
| :--- | :--- |
| [`cloudbuild-guide.md`](cloudbuild-guide.md) | Cloud Build 是什么 / 怎么用 / Schema 速查 / 排错 |
| [`how-to-autofix-cve-with-cloud-build.md`](how-to-autofix-cve-with-cloud-build.md) | CVE 自动修复闭环（含 Go 依赖修复 T3/T4） |
| [`examples/golang-binary.yaml`](examples/golang-binary.yaml) | Go 静态二进制构建模板 |
| [`examples/cve-fix-go-deps.yaml`](examples/cve-fix-go-deps.yaml) | Go 依赖 CVE 修复模板（注意 `toolchain` vs `go`） |
