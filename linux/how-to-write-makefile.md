# How to Write a Makefile —— 从零到能维护

> 这篇文档基于你本机 7 个真实 Makefile 提炼：
> `knowledge/develop/java/java-scan`、`knowledge/gcp/ucp/argocd-topics/git-apps/cr-check`、
> `knowledge/gcp/ucp/argocd-topics/examples/gitops-layout`、
> `go/daydayup`、`go/cr-check`、`go/ci-simulation`、`go/ci-simulation/trigger`。
>
> 读完你应该能：**看懂任何 Makefile**、**自己从零写一个**、**知道每一行为什么这么写**。

---

## 0. TL;DR —— 最小可用的 Makefile

如果只看一个例子，这就是"最简单但完整"的形态：

```makefile
# 变量定义（:= 立即展开，?= 可被外部覆盖）
APP    := hello
OUT    ?= bin/$(APP)
PYTHON ?= python3
SRC    := main.py

# 默认目标：敲 make 时跑哪个
.DEFAULT_GOAL := help

# 声明这些"目标"不是真实文件
.PHONY: help build run clean

# 目标: 依赖
#   ↓       ↓
help:            ## 显示帮助
	@echo "hello —— 可用命令："
	@echo "  make build   编译"
	@echo "  make run     运行"
	@echo "  make clean   清理"

build: $(OUT)   ## 编译

# 产出物 $(OUT) 依赖 $(SRC)：src 变了才重编（这就是 make 的增量魔法）
$(OUT): $(SRC)
	@mkdir -p $(dir $@)
	@$(PYTHON) -m py_compile $<
	@cp $< $@

run: build      ## 运行
	@$(PYTHON) $(OUT)

clean:          ## 清理
	@rm -rf bin __pycache__
```

### 这个 Makefile 到底生成了什么（产物清单）

跑完 `make build` 之后，目录里多出来的东西只有这些：

| 路径 | 谁生成的 | 是 Make 眼里的「目标」吗 |
| --- | --- | --- |
| `bin/` | `mkdir -p $(dir $@)` | 否，只是个目录 |
| `bin/hello` | `cp $< $@` | ✅ 是，它就是 `$(OUT)` |
| `__pycache__/main.cpython-*.pyc` | `py_compile` 的副作用 | 否，不在依赖图里 |

**目标名 ≠ 文件名** —— 这是最容易混的地方：

- `build` / `help` / `run` / `clean` 都在 `.PHONY` 里，**跑完不留任何文件**
- `bin/hello`（即 `$(OUT)`）→ **唯一真正的产物**，也是 Make 靠时间戳追踪的那个文件
- `build: $(OUT)` 这一行**没有配方**，它只是「转发依赖」：Make 自己去更新 `bin/hello`

所以 `make build` 之后你 `ls` 看到的是 `bin/hello`，**看不到叫 `build` 的文件 —— 这是对的**。

> 副产物 `__pycache__` 是个典型例子：它不在依赖图里，Make 不知道它存在，
> 但 `clean` 目标必须手动 `rm -rf bin __pycache__` 才能清干净。
> **凡是「跑一次就会生成、但不在依赖图里」的东西，都要在 `clean` 里手动列出来。**

### 怎么自己验证

```bash
make -n build              # 干跑：只打印将要执行的 3 条命令
make --debug=b build       # 看 make 的决策过程（谁比谁新）
make clean && ls -R        # 确认 clean 真的清干净了
```

### 亲手跑一遍（复制到 /tmp 就能跑）

```bash
$ cat main.py
print("hello from app")

$ make             # 不带参数 -> 走 .DEFAULT_GOAL = help
hello —— 可用命令：
  make build   编译
  make run     运行
  make clean   清理

$ make build       # 第一次：真的编译
$ make build       # 第二次：Nothing to be done for 'build'   <-- 增量生效
$ touch main.py && sleep 1 && make build    # 源文件更新 -> 重新编译
$ make run
hello from app
$ make clean
```

> 注意上面那个 `sleep 1`：Make 比较的是**文件修改时间**，
> 老版本 make 的时间戳精度只有 1 秒，同一秒内改文件可能"看起来没变"。
> 这是新手最常见的"我明明改了却没重编"的原因。

只有 4 个概念就够用：

| 概念 | 写法 | 作用 |
| --- | --- | --- |
| 目标 (target) | `build:` | 一个要做的事 |
| 依赖 (prerequisite) | `build: main.go` | 做这件事需要什么 |
| 配方 (recipe) | 行首 **Tab** + 命令 | 具体怎么做 |
| 变量 (variable) | `APP := hello` | 给值起个名字 |

```
目标 ←── 依赖
  ↓
配方（Tab 开头）
```

---

## 1. Make 到底是怎么工作的（原理）

### 1.1 核心心智模型：Make 是个"依赖图调度器 + 脏检查器"

Make 不是"跑脚本"。它做的是：

1. **读** Makefile，把所有 `目标: 依赖` 解析成一张有向图（DAG）。
2. **找** 你命令行要求的目标（`make build` → `build`）。
3. **递归向上找依赖**：`build` 依赖 `bin/app`，`bin/app` 依赖 `main.go`，`main.go` 依赖 `main.c`……
4. **自底向上执行**：只有当"依赖比目标新"（或依赖不存在）时，才执行目标的配方。
5. **执行顺序**：一个目标的所有依赖都完成后，才执行它自己的配方。

### 1.2 时间戳比较：为什么 `make` 有时什么都不做

```makefile
app: main.o
	@echo "link"

main.o: main.c
	@echo "compile"
```

- `main.c` 比 `main.o` 新 → 跑 `compile`
- `main.o` 比 `app` 新 → 不跑 `link`
- 结果：`make` 打印 `make: 'app' is up to date.`

这就是 Make 的核心价值：**增量构建**。改哪个文件只重做哪一段。

### 1.3 三种"时间戳判定"

| 情况 | Make 的判断 | 结果 |
| --- | --- | --- |
| 目标文件不存在 | 依赖存在也要做 | 执行配方 |
| 依赖比目标新 | 需重做 | 执行配方 |
| 目标比所有依赖都新 | 已最新 | **跳过**（输出 up to date） |

### 1.4 为什么几乎所有"逻辑型"目标都要 `.PHONY`

```makefile
.PHONY: clean test build
```

`clean`、`test` 这种目标**不对应任何文件**。如果你目录里恰好有个叫 `clean` 的文件，Make 会认为"clean 已存在且是最新的" → **什么都不做**。

`.PHONY: clean` 就是在告诉 Make："clean 是假的，不管有没有同名文件，每次都执行。"

规则：

- **不产生文件的动作**（clean / test / lint / install / deploy）→ 一定要 `.PHONY`
- **产生文件的动作**（build → bin/app）→ **不要** `.PHONY`，否则每次都重编，增量构建失效

你现有代码里对比：

- `go/cr-check/Makefile`：`build:` 没 `.PHONY`（产出 `bin/cr-check`）→ 正确
- `go/cr-check/Makefile`：`test:` 在 `.PHONY` 里 → 正确
- `knowledge/.../java-scan/Makefile`：`package:` 在 `.PHONY` 里，但它产出 `target/*.jar` → 略保守（每次都重打包），无害但不优雅

### 1.5 Make 的四种行类型 —— 认准缩进就懂了一半

```makefile
VAR := value       # ① 变量赋值（非 recipe 行）

target: deps       # ② 目标定义（依赖列表可以续行）
	command        # ③ 配方（必须以 Tab 开头）

# ④ 特殊目标 / 指令（以 . 开头）
.PHONY: ...
.DEFAULT_GOAL := ...
.DELETE_ON_ERROR:
.NOTPARALLEL: ...
```

> ⚠️ **最容易踩的坑**：recipe 必须用 **Tab**（`\t`）缩进，**不能**用空格。
> 报错信息通常是：`** missing separator. Stop.`
> VS Code / vim 里按 `<Tab>` 键，不是输入 4 个空格。

---

## 2. 语法逐个拆解

### 2.1 变量：几种赋值运算符

```makefile
A =  value        # 递归展开（延迟）：用到 A 时才展开右边
B := value        # 立即展开（简单）：定义时就展开
C ::= value       # 立即展开，且不受命令行/环境覆盖（同 :=）
D ?= value        # 只有在"未定义"时才赋值（可被覆盖）
E += value        # 追加
F != value        # shell 赋值（make 4.0+）
```

**实战该怎么选：**

| 场景 | 用 | 例子（来自你的代码） |
| --- | --- | --- |
| 常量、路径、要立刻展开的 | `:=` | `APP := cr-check`、`LDFLAGS := -s -w` |
| 允许本地/CI 覆盖的默认值 | `?=` | `CONFIG ?= config/policy.yaml`、`ADDR ?= :8080` |
| 需要运行时才求值的 | `=` | 少用 |

对照你的代码：

```makefile
# go/cr-check/Makefile
APP      := cr-check              # 常量，立即展开
CONFIG   ?= config/policy.yaml   # 可被 make CONFIG=xxx 覆盖
ADDR     ?= :8081                 # 可覆盖
LDFLAGS  := -s -w
```

```makefile
# go/ci-simulation/Makefile
HOST_OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
HOST_ARCH := $(shell uname -m)
TOOLS_BIN_DIR ?= $(CURDIR)/.tools/$(HOST_OS)-$(HOST_ARCH)/bin
export TOOLS_BIN_DIR
```

这里三个细节值得学：

- `$(shell ...)`：**立即**执行 shell 命令，把输出当字符串塞进变量。
- `$(CURDIR)`：Make 内置变量，当前目录。
- `export VAR`：把变量导出成环境变量给子进程用（脚本里 `$TOOLS_BIN_DIR` 就能读到）。

### 2.2 覆盖变量的几种方式（优先级从高到低）

```bash
make FOO=bar          # ① 命令行（最高）
make -e               # ② 环境变量覆盖 makefile
FOO=bar make          # ③ 环境变量
FOO=bar               # ④ makefile 里的 ?= / =
```

**这就是为什么"可配置的东西"要用 `?=`**：CI 里 `make test PYTHON=python3.11`、本地 `make test` 都能跑。

### 2.3 常用内置变量

| 变量 | 含义 | 用在哪 |
| --- | --- | --- |
| `$@` | 当前目标名 | `@echo "building $@"` |
| `$<` | 第一个依赖 | `$<$(CC) -c $< -o $@` |
| `$^` | 所有依赖（去重） | `$<$(CC) -o $@ $^` |
| `$+` | 所有依赖（保留重复，顺序同 makefile） | 链接顺序敏感时 |
| `$?` | 比目标新的依赖 | 增量更新 |
| `$(CURDIR)` | 当前工作目录 | 拼绝对路径 |
| `$(MAKEFILE_LIST)` | 所有读入的 makefile | `help` 目标自省 |
| `$(wildcard PAT)` | 展开通配符 | `$(wildcard apps/*)` |
| `$(notdir ...)` | 取文件名 | `$(notdir $(wildcard d[0-9][0-9]))` |
| `$(sort ...)` | 排序去重 | 同上 |
| `$(patsubst from,to,text)` | 字符串替换 | `$(patsubst %/,%,$(dir ...))` |
| `$(abspath ...)` | 绝对路径 | `$(abspath $(LAYOUT_DIR))` |
| `$(shell CMD)` | 执行 shell | 探测工具是否存在 |
| `$(if cond,then,else)` | 条件表达式 | `$(if $(DRY_RUN),--dry-run,)` |
| `$(or a,b)` | 取第一个非空 | `$(or $(CR),1234)` |
| `$(words LIST)` | 单词数 | `$(words $(MAKECMDGOALS))` |
| `$(MAKECMDGOALS)` | 命令行指定的所有目标 | 取参数 |
| `$(MAKE)` | 子 make | 递归调用 |

### 2.4 自动变量 `$@ $< $^` 实战

```makefile
bin/app: $(wildcard src/*.c)
	@mkdir -p $(dir $@)
	@gcc -o $@ $^        # $^ = 所有 .c 文件
```

### 2.5 条件语句

```makefile
ifeq ($(VAR),value)
	@echo "等于"
endif

ifneq ($(VAR),value)
	@echo "不等于"
endif

ifdef VAR
	@echo "已定义"
endif
```

你代码里的典型用法（`go/daydayup/Makefile`）：

```makefile
GOTESTSUM ?= $(shell command -v gotestsum 2>/dev/null)

test:
ifeq ($(GOTESTSUM),)
	@$(GO) test ./...
else
	@$(GOTESTSUM) --format testname -- ./...
endif
```

**模式：探测工具 → 有就用好的，没有就降级。** 你的三个 Makefile 都用了这招。

### 2.6 `@` 前缀和 `-` 前缀

```makefile
@echo "quiet"        # @ 开头 → 不回显这条命令
-rm -f nonexist     # - 开头 → 忽略错误（失败也继续）
```

你的代码里 `@` 到处都是（只想要结果，不想要命令回显），`|| true` 是等效但更啰嗦的写法：

```makefile
# knowledge/.../java-scan/Makefile
docker rmi $(DOCKER_IMAGE) $(DOCKER_LATEST) 2>/dev/null || true
# 更简洁的等价写法：
-docker rmi $(DOCKER_IMAGE) $(DOCKER_LATEST)
```

### 2.7 多行配方（续行 `\`）

一行 shell 命令太长时：

```makefile
build:
	@CGO_ENABLED=0 go build \
		-trimpath \
		-ldflags '$(LDFLAGS)' \
		-o bin/$(APP) ./cmd/server
```

**注意**：续行的 `\` 后不能有空格；每行都是独立的 shell 进程，所以环境变量前缀写法（`A=1 B=2 cmd`）只对那一行生效。

### 2.8 `.PHONY` / `.DEFAULT_GOAL` / `.DELETE_ON_ERROR` / `.NOTPARALLEL`

来自 `knowledge/.../gitops-layout/Makefile` 的注释，是很好的工程实践总结：

```makefile
.DEFAULT_GOAL := help      # 敲 make 不该误触发任何有副作用的事
.DELETE_ON_ERROR:          # 生成物中途失败不要留半成品
.NOTPARALLEL: sync render-all   # 涉及共享状态的目标不要并行
```

### 2.9 模式规则（进阶，先不用）

```makefile
# 静态模式：obj/%.o: src/%.c
%:
	@echo "unknown target: $@"
```

你 `daydayup/Makefile` 末尾那个 `%:` 就是"兜底目标"——未知目标时报友好错误，而不是 make 的默认报错。写法值得学，但**新手不建议一开始就加**。

---

## 3. 一个真实 Makefile 的"解剖图"

拿最短最清晰的这个：`go/cr-check/Makefile`

```makefile
# CR Check —— 开发常用命令
APP      := cr-check
PKG      := ./...
CONFIG   ?= config/policy.yaml
ADDR     ?= :8081
LDFLAGS  := -s -w

.PHONY: help run run-real show-config build test test-watch air probe event lint fmt vet tidy clean docker

help: ## 显示可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

run: ## 本地起服务（mock 模式）
	go run ./cmd/server -config $(CONFIG) -mode mock -addr $(ADDR) -sync-eval

build: ## 编译到 bin/
	CGO_ENABLED=0 go build -trimpath -ldflags '$(LDFLAGS)' -o bin/$(APP) ./cmd/server

clean: ## 清理
	rm -rf bin
	go clean -testcache
```

**逐层看：**

1. **注释头**：先说这个仓库是干什么的。→ 好习惯。
2. **变量区**：把"会变的命令行参数"抽成变量。`?=` 表示可覆盖。
3. **`.PHONY` 一行声明所有假目标**：集中声明，不散落各处。
4. **`help` 目标**：从 `$(MAKEFILE_LIST)` 里 grep 出带 `## 说明` 的行，自动生成帮助。
5. **每个目标：`名字: ## 一句话说明` + 配方**。
6. **`@` 前缀**：不想在终端里看到回显的命令（帮助、清理、探测）加 `@`，实际构建命令不加（要看到过程）。

---

## 4. 五个"套路"模板（直接抄）

### 4.1 自动 `help`（基于 `##` 注释）

```makefile
help: ## 显示帮助信息
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
```

原理：Makefile 里所有形如 `target: ## 描述` 的行会被 grep 出来，用 awk 按 `:` 分割，printf 上色输出。

> 注意 `$$` —— 在 Makefile 里 `$` 开头是变量引用，要输出字面 `$` 给 shell/awk 必须写 `$$`。
> **这是新手第二大坑**（第一是 Tab）。

### 4.2 "工具不存在就优雅降级"

```makefile
GOTESTSUM ?= $(shell command -v gotestsum 2>/dev/null)

test:
ifeq ($(GOTESTSUM),)
	@$(GO) test ./...
else
	@$(GOTESTSUM) --format testname -- ./...
endif
```

更简洁的写法（`go/daydayup` 里也有）：

```makefile
lint:
	@command -v golangci-lint >/dev/null 2>&1 || { echo "⚠️  没装 golangci-lint"; exit 1; }
	@golangci-lint run
```

### 4.3 "必填参数检查"

```makefile
run: ## make run DAY=d01
ifeq ($(DAY),)
	@echo "用法: make run DAY=d01"
	@exit 1
endif
	@$(GO) run ./$(DAY)
```

来自 `daydayup/Makefile`。**模式**：先 `ifeq` 检查 → 报错退出 → 再干活。

### 4.4 "一个目标聚合多个目标"

```makefile
test: test-helm test-python test-bash   # 依赖即顺序
	@echo "所有测试通过"
```

来自 `go/ci-simulation/Makefile`。Make 会按依赖顺序执行（有依赖的先跑），但**并行时（`make -j`）不保证**，所以互不相关的才敢 `-j`。

### 4.5 "生成物 + 增量 + 清理"

```makefile
OUT := bin/$(APP)

$(OUT): $(shell find . -name '*.go')
	@mkdir -p $(dir $@)
	@go build -o $@ ./cmd/server

clean:
	@rm -rf bin
```

---

## 5. 工程约定（你的代码里已经形成的"团队规范"）

从 7 个 Makefile 归纳出来的统一风格，新写的时候照抄：

| 约定 | 原因 | 出处 |
| --- | --- | --- |
| 顶部注释写清"这个 Makefile 是干什么的 + 常用命令" | 半年后自己也会忘 | 全部 |
| `.DEFAULT_GOAL := help` | 敲 `make` 不该误触发副作用 | daydayup / gitops-layout / ci-simulation |
| 可配置参数用 `?=` | 本地/CI 可各自覆盖 | 全部 |
| 常量用 `:=` | 立即展开，行为可预测 | 全部 |
| 副作用目标一律 `.PHONY` | 防止"有同名文件就不执行" | 全部 |
| `help` 目标用 `##` 自动生成 | 不用手写两份文档 | 全部 |
| `help` 放在第一个且不依赖任何东西 | 任何时候都能跑 | 全部 |
| 危险操作必须显式传参 + `ifeq` 拦截 | 防止误操作 | gitops-layout 的 `sync`（强制 `REV`） |
| CI 和本地跑同一条命令（`make test`） | 消除"本地过 CI 挂" | ci-simulation |
| 工具路径按 `os-arch` 分目录 | 本地 mac 和 CI linux 不打架 | ci-simulation |
| 多行命令用 `\` | 可读性 | 全部 |

**特别值得学的一条**（`gitops-layout/Makefile`）：

```makefile
# ★ 同步必须显式给 APP 和 REV：绝不"同步到 latest"。
sync:
ifeq ($(APP),)
	@echo "用法: make sync APP=<name> REV=<sha>"; exit 1
endif
ifeq ($(REV),)
	@echo "★ 必须显式指定 REV（不要同步到 latest）"; exit 1
endif
	@$(ARGOCD) app sync "$(APP)" --revision "$(REV)" --prune=false
```

> **Makefile 不只是"命令快捷方式"，更是"安全的命令行入口"。**
> 有副作用的操作（deploy / sync / push / 删数据）应当：
> 1. 用 `ifeq` 强制必填参数；
> 2. 提供 `DRY_RUN=1` 之类的试运行开关；
> 3. 默认目标是 `help` 而不是危险操作。

---

## 6. 用 Makefile 到底能得到什么（拿 ci-simulation 实测）

前面讲的都是「怎么做」。这一节讲「**为什么要做**」——用你 `go/ci-simulation` 这个真实项目当证据。

### 6.0 先看没有 Makefile 时的痛苦

`ci-test.yaml`（Cloud Build 配置）里，一个 step 原本要这么写：

```yaml
- name: 'python:3.11'
  id: 'helm-lint-render'
  dir: 'ci-simulation'
  entrypoint: bash
  args: ['-c', 'make test-helm']      # ← 有 Makefile 之后，参数只有这一行
  env:
    - 'TOOLS_BIN_DIR=/workspace/ci-simulation/.tools/bin'
    - 'PATH=/workspace/ci-simulation/.tools/bin:...'
  waitFor: ['install-deps']
```

没有 Makefile 时，那个 `args` 会是长这样：

```yaml
args: ['-c', 'helm lint charts/ci-demo --strict && helm template argocd-bootstrap charts/ci-demo > /dev/null']
```

而且「helm 从哪来」这件事，你得在**每一个 step** 里重复一遍安装逻辑。

> **Makefile 把这些命令收口成 1 行 `make test-helm`，并且把「谁依赖谁」写进了依赖图。**

### 6.1 好处一：单一入口，命令不散落在各处

实测 `make help`：

```
ci-simulation —— Cloud Build PR CI 最小样例

  make test             跑全部检查（CI 用的就是这条）
  make test-helm        helm lint + helm template
  make test-python      python 单测
  make test-bash        bash 断言
  make install-deps     安装依赖（helm -> /Users/lex/git/go/ci-simulation/.tools/darwin-arm64/bin）
  make clean            清理产物

  工具目录: /Users/lex/git/go/ci-simulation/.tools/darwin-arm64/bin
```

新人不用读 README、不用翻 CI 配置，`make help` 就是全部命令表。
CI yaml 里也只有 `make xxx`，**参数只写一遍**。

### 6.2 好处二：本地和 CI 跑的是同一条命令

Makefile 顶部注释写得很直白：

> ★ 核心原则：**本地和 CI 跑的是同一条命令**（make test），
> 所以「本地过了 CI 挂」这种事基本不会发生，差异只剩环境。

对应到代码，`ci-test.yaml` 的 4 个 step ↔ Makefile 的 4 个 target，一一对应：

| Cloud Build step | 调用的命令 | Makefile target |
| --- | --- | --- |
| `install-deps` | `scripts/utils/install_ci_dependencies.sh` | `install-deps` |
| `helm-lint-render` | `make test-helm` | `test-helm: install-deps` |
| `cluster-onboarding` | `make test-python` | `test-python: prepare-foundation-apps` |
| `bootstrap-tests` | `make test-bash` | `test-bash: prepare-foundation-apps` |

**CI 配置从此不再是「另一份实现」，而是 Makefile 的一层壳。**

### 6.3 好处三：依赖关系写一次，顺序自动保证

`make -n test` 实测输出（这就是依赖图展开后的真实执行顺序）：

```bash
bash scripts/utils/install_ci_dependencies.sh      # ← install-deps 自动先跑
helm lint charts/ci-demo --strict
helm template argocd-bootstrap charts/ci-demo > /dev/null
echo "[test-helm] OK"
python3 scripts/utils/prepare_foundation_apps.py   # ← prepare-foundation-apps 自动先跑
python3 -m unittest discover -s scripts/utils -p 'test_*.py' -v
python3 -m unittest discover -s scripts/02-cluster-onboarding -p 'test_onboard_cluster.py' -v
bash scripts/utils/test_install_ci_dependencies.sh
bash scripts/01-aoa-onboarding/test_checks.sh
```

注意 `test-helm: install-deps` 这一行 —— **「先装依赖再跑测试」这条规则只写了一次**。
CI 里对应的是手写的 `waitFor: ['install-deps']`，本地是 Make 自动保证的。
两边不会漂移，因为它们本来就是同一张依赖图的两种翻译。

### 6.4 好处四：环境差异用变量收敛，一处覆盖

```makefile
HOST_OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
HOST_ARCH := $(shell uname -m)
TOOLS_BIN_DIR ?= $(CURDIR)/.tools/$(HOST_OS)-$(HOST_ARCH)/bin
export TOOLS_BIN_DIR
export PATH := $(TOOLS_BIN_DIR):$(PATH)
```

- 本地 mac → `.tools/darwin-arm64/bin`（实测 help 里打印的就是这个）
- CI linux → 环境变量覆盖成 `/workspace/ci-simulation/.tools/bin`

**同一份 Makefile，两个环境，零改动。**
而且 `export` 把这个约定传给了所有子脚本（`scripts/*.sh` 里直接读 `$TOOLS_BIN_DIR`），
不需要每个脚本再写一遍路径推导逻辑。

> 这条不是 Make 独有的能力（shell 也能做），但 Make 把它做成了**声明式**的：
> 你声明一次变量，所有 recipe 和子进程自动继承。

### 6.5 好处五：默认安全，裸敲 make 不会误触发

```makefile
.DEFAULT_GOAL := help
```

在这个仓库里，如果默认目标是 `test`，你随手敲一次 `make` 就会：
装 helm → 跑 helm lint → 跑 python 单测 → 跑 bash 断言，
在错误的时机、在错误的目录。设成 `help` 之后，**裸敲 make 只会打印帮助**。

同理 `clean` / `install-deps` / `sync` 这类有副作用的目标，
都靠 `ifeq` + 显式参数来兜底（见 `gitops-layout/Makefile` 的 `sync`）。

### 6.6 好处六：幂等 + 自举，依赖永远就绪

`install-deps` 是幂等的：重复跑不会重复下载 helm。
配合 Make 的依赖语义，**你永远不需要手动先装依赖**：

```bash
$ make test-helm
bash scripts/utils/install_ci_dependencies.sh    # 缺什么装什么
helm lint charts/ci-demo --strict
...
```

### 6.7 好处七：可组合、可拆开、可干跑

```makefile
test: test-helm test-python test-bash   # 全套
ci: test                                 # 别名，给 CI 用
```

- `make test` → 全套检查
- `make test-helm` → 只跑一个（实测只执行 3 条命令）
- `make -n test` → **干跑**，只打印将要执行的命令，不真的执行

`make -n` 是极好用的「变更审计」手段：改完 CI 配置先干跑一遍，确认没多跑也没少跑。

### 6.8 好处八：产物可清理，环境不污染

```makefile
clean:
	rm -rf build .tools
```

一键回到干净状态。工具装在仓库内的 `.tools/`，不污染系统目录，也不需要 sudo。

### 6.9 一句话总结

> Makefile 干的事：**把「跑什么、按什么顺序、在什么环境下跑」这三件事，
> 从散落在 CI 配置 / 文档 / 人的记忆里，收敛成一个可执行的依赖图。**

| 维度 | 没有 Makefile | 有 Makefile（ci-simulation） |
| --- | --- | --- |
| 命令在哪 | CI yaml、README、聊天记录各一份 | 只有 Makefile 一份 |
| 新人上手 | 问人 | `make help` |
| 执行顺序 | 人肉记 / CI 手写 waitFor | 依赖图自动保证 |
| 本地 vs CI | 两套实现，容易漂移 | 同一条命令 |
| 环境差异 | 到处硬编码路径 | `?=` + `export` 一处收敛 |
| 误操作风险 | 默认目标可能是重活 | `.DEFAULT_GOAL := help` |
| 改动的可审计性 | 只能看 yaml | `make -n` 干跑 |

### 6.10 什么时候**不该**用 Makefile

- 只有一个命令的项目 → 直接跑脚本就行，别为了 Make 而 Make
- 复杂分支 / 循环 / 条件判断 → 那是 shell 或 python 的活，Makefile 会变成「用 make 写代码」
- 需要跨平台且差异很大 → 每个平台一套 Makefile，不如一套脚本 + 参数

**判断标准**：如果你在 Makefile 里开始写 `$(if)`、`$(foreach)`、`$(eval)`，
说明这件事应该写进脚本，让 Makefile 只做「调度」。

## 7. 调试 Makefile 的工具箱

```bash
make -n            # dry-run：只打印不执行（最有用的调试命令）
make -d            # 打印完整决策过程（为什么这个目标被跳过）
make -p            # 打印所有变量和规则（调试变量展开）
make --warn-undefined-variables   # 用了未定义变量时警告
make -j4           # 并行执行 4 个
make -n build V=1  # 传变量
```

调试变量展开的技巧：

```makefile
show:
	@echo "APP=$(APP)"
	@echo "CONFIG=$(CONFIG)"
```

---

## 8. 从零写一个 Makefile 的步骤（照做就行）

### Step 1：先写注释头

```makefile
# myapp —— 一句话说清这个仓库
#
#   make help     看所有命令
#   make build    编译
#   make test     测试
```

### Step 2：抽变量

```makefile
APP  := myapp
PY   ?= python3
SRC  := $(wildcard src/*.py)
OUT  ?= bin/$(APP)
```

### Step 3：设默认目标 + 声明 .PHONY

```makefile
.DEFAULT_GOAL := help
.PHONY: help build run test clean
```

### Step 4：写 help（用 ## 注释）

```makefile
help: ## 显示所有命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
```

### Step 5：写具体目标

```makefile
build: $(OUT)   ## 编译

$(OUT): $(SRC)
	@mkdir -p $(dir $@)
	@$(PY) -m compileall src
	@cp src/main.py $@

run: build      ## 运行
	@$(PY) $(OUT) --config $(CONFIG)

test:           ## 测试
	@$(PY) -m pytest -q

clean:          ## 清理
	@rm -rf bin .pytest_cache
```

### Step 6：自检清单

- [ ] 所有 recipe 行用 **Tab** 开头？
- [ ] 需要输出字面 `$` 的地方都写了 `$$`？
- [ ] 所有"不产出文件"的目标都在 `.PHONY` 里？
- [ ] `make`（不带参数）不会做危险的事？
- [ ] `make help` 能跑出来？
- [ ] `make -n` 干跑一遍，命令符合预期？
- [ ] 参数化的地方用了 `?=`？

---

## 9. 常见坑速查表

| 现象 | 原因 | 解法 |
| --- | --- | --- |
| `missing separator` | recipe 用了空格缩进 | 换成 Tab |
| `No rule to make target 'xxx'` | 拼错目标名 / 缺文件 | 检查拼写，看 `make -p` |
| 目标明明要跑却"up to date" | 目录里有同名文件 | 加 `.PHONY` |
| `command not found` | 变量没展开 / 路径没导出 | `make -p` 看展开结果 |
| 变量值里带空格被拆开 | 没加引号 | `"$(VAR)"` |
| awk 里 `$1` 报错 | Make 把它当变量了 | 写 `$$1` |
| 每次都重编 | 产出文件被 `.PHONY` 了 | 从 `.PHONY` 里拿掉 |
| `make -j` 结果错乱 | 目标间有隐式依赖 | 写清依赖，或用 `.NOTPARALLEL:` |
| 多行 shell 变量丢失 | 续行/子 shell | 用 `\` 续行，或 `export` |
| 改了文件却没重新编译 | 时间戳精度 1 秒，同秒修改看不出来 | `sleep 1` 后再 make，或 `touch -t` |

---

## 10. 进阶主题（知道有就行）

| 主题 | 用在哪 | 说明 |
| --- | --- | --- |
| `include` | 大项目拆多个 Makefile | `include common.mk` |
| `-include` | 可选包含 | 文件不存在也不报错 |
| 递归 make | 复杂多模块 | `$(MAKE) -C subdir` |
| `export` | 传给子进程 | `export VAR` |
| `unexport` | 取消导出 | |
| `vpath` | 多目录找文件 | |
| `$(shell)` 缓存 | 每次调用都执行 shell | 赋值时展开一次 |
| `.SECONDEXPANSION` | 复杂依赖计算 | 很少需要 |
| 静态模式规则 | 一类目标共用配方 | `obj/%.o: src/%.c` |
| `make -f` | 指定其他 makefile | |
| `include $(wildcard *.mk)` | 插件式 | |

---

## 11. 30 秒总结

1. **Make = 依赖图 + 时间戳增量 + 命令调度器**，不是脚本。
2. 三件套：**目标 : 依赖** + **Tab 缩进的配方** + **变量**。
3. **不产文件的目标 → `.PHONY`**；**产文件的目标 → 别 `.PHONY`**。
4. **可覆盖的默认值用 `?=`**，常量用 `:=`。
5. **默认目标设成 `help`**，别让 `make` 裸跑触发副作用。
6. **危险操作要 `ifeq` 拦参数 + DRY_RUN**。
7. 两个必记的符号：**Tab** 和 `$$`。
8. 调试三件套：`make -n` / `make -d` / `make -p`。

---

## 附：本文涉及的源文件

| 文件 | 特点 |
| --- | --- |
| `go/cr-check/Makefile` | 最标准的 Go 项目 Makefile，最适合入门 |
| `go/daydayup/Makefile` | 动态发现目录、参数校验、兜底目标 |
| `go/ci-simulation/Makefile` | 工具探测、平台分目录、CI 同源 |
| `go/ci-simulation/trigger/Makefile` | 多层依赖、环境变量传参 |
| `knowledge/.../git-apps/cr-check/Makefile` | 精简版 + 自动 help |
| `knowledge/.../examples/gitops-layout/Makefile` | 参数强校验、`.DELETE_ON_ERROR`、dry-run |
| `knowledge/develop/java/java-scan/Makefile` | Maven + Docker 多阶段构建 |
