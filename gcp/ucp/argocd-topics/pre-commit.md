# pre-commit — 多语言 Git Hook 管理框架(探索文档)

> **本文档定位:** 把 https://pre-commit.com 的官方文档读完后,整理成"它是什么 / 不是什么 / 怎么用 / 对我们这个 release 仓库有什么用"。
>
> **一句话结论(先回答问题):**
> **pre-commit 不是一个 release / 发布工具。** 它是一个 **Git hook 的多语言包管理器 + 执行器** ——
> 在 `git commit` / `git push` 等时机,自动跑一堆 lint / format / 校验工具(black、flake8、shellcheck、yamllint、gitleaks……),
> 并替你把"工具怎么装"这件事自动化(不要求 root,不需要你本地装 node / ruby / go……)。
>
> **一句话类比:** pre-commit ≈ **npm / pip 之于"代码检查工具"**,只是包管理器换成了"代码检查工具",而被管理的"依赖"是 git hook。
>
> **本文档交付:**
> - §1 pre-commit 是什么(官方定位原文 + 翻译)
> - §2 它**不是**什么(和 release / CI/CD 的边界,避免误用)
> - §3 核心架构模型(三层 + 执行时序)
> - §4 安装与快速开始
> - §5 配置模型 `.pre-commit-config.yaml`(top-level / repos / hooks 全字段)
> - §6 `language` 支持矩阵 + 自定义 hook(`.pre-commit-hooks.yaml`)
> - §7 CLI 命令全表(13 个子命令 + 全局选项 + 退出码)
> - §8 高级特性(stages / SKIP / args / types / always_run / local hooks / autoupdate)
> - §9 CI 集成(GitHub Actions / GitLab CI 示例 + 缓存)
> - §10 **与本仓库的关系**(现状盘点 + 可落地项 + 与 CR / Prow 的分工 + 风险清单)
> - §11 落地清单(建议拆 3 个 PR)
> - §12 权威证据 URL 列表(全部取自官网 / GitHub API 实际抓取,非杜撰)

---

## 1. pre-commit 是什么

### 1.1 官方定位(原文)

> pre-commit is a framework for managing and maintaining multi-language pre-commit hooks.
>
> — https://pre-commit.com (首页 title / GitHub description)

**翻译:** pre-commit 是一个用于管理和维护**多语言** pre-commit hook 的框架。

### 1.2 官方对"为什么存在"的解释(原文摘录 + 翻译)

| 原文 | 翻译 |
|------|------|
| Git hook scripts are useful for identifying simple issues before submission to code review. | Git hook 脚本适合在提交 code review 之前挑出简单问题。 |
| We run our hooks on every commit to automatically point out issues in code such as missing semicolons, trailing whitespace, and debug statements. | 我们在每次 commit 上跑 hook,自动指出缺分号、行尾空格、debug 语句这类问题。 |
| sharing our pre-commit hooks across projects is painful. We copied and pasted unwieldy bash scripts from project to project. | 跨项目共享 hook 很痛苦,只能到处拷贝改写 bash 脚本。 |
| Some of the best linters are written in languages that you do not use in your project... For example scss-lint is a linter for SCSS written in Ruby. | 最好的 linter 可能用你项目里根本没有的语言写的(比如 Ruby 写的 scss-lint),你不想为了它给 node 项目塞 Gemfile。 |
| pre-commit is a multi-language package manager for pre-commit hooks. You specify a list of hooks you want and pre-commit manages the installation and execution of any hook written in any language before every commit. | pre-commit 是"面向 git hook 的多语言包管理器":你只声明想要哪些 hook,它负责安装和执行。 |
| pre-commit is specifically designed to not require root access. | 专门设计成**不需要 root**。 |

### 1.3 它的 4 个核心能力

| 能力 | 说明 |
|------|------|
| **声明式配置** | 一个 YAML 文件(`.pre-commit-config.yaml`)声明"我要哪些 hook、什么版本、跑在哪些文件上" |
| **自动环境隔离** | 每个 hook 装在**自己的隔离环境**里(独立 venv / node_modules / go mod cache),不污染开发机,不需要 root |
| **多语言通吃** | python / node / ruby / golang / rust / docker / go … 官方支持 20+ 种 `language`,还支持 `unsupported`(直接调你本机已有的可执行文件) |
| **缓存复用** | 环境装一次就缓存(`~/.cache/pre-commit`),第二次跑秒级 |

### 1.4 执行时序(一次 `git commit` 发生了什么)

```
git commit
   │
   ├─► .git/hooks/pre-commit          ← pre-commit install 装的脚本(一个薄壳)
   │      ├─ 1. 读 .pre-commit-config.yaml(解析 + 校验)
   │      ├─ 2. 收集本次暂存(staged)的文件名,按 files/types/exclude 过滤
   │      ├─ 3. 对每个 hook:检查缓存环境 → 没有就 clone repo + 建环境 + 装依赖
   │      ├─ 4. 执行 hook:  entry <args...> <filenames...>
   │      │      └─ 退出码 != 0  或  改动了文件  →  判定失败
   │      └─ 5. 任一 hook 失败 → 阻止 commit,打印失败原因
   │
   └─► .git/hooks/commit-msg          ← 也可由 pre-commit 接管(stages: [commit-msg])
          └─ 校验 commit message(例如 Conventional Commits)
```

---

## 2. 它**不是**什么(边界澄清)

> 这一节专门回答"是不是做 release 发布的东西"。

| 维度 | pre-commit | release / 发布工具 | CI/CD 系统 |
|------|-----------|-------------------|-----------|
| 典型代表 | pre-commit | goreleaser / semantic-release / release-please / `git tag` + `gh release` | Argo CD / Prow / GitHub Actions |
| 触发时机 | 本地 `git commit` / `git push`(**开发者机器上**) | 构建产物生成后 | 仓库事件(PR / push / cron)→ 服务器侧 |
| 干什么 | 检查代码格式 / 风格 / 语法 / 密钥泄漏,**不合格就拦住提交** | 打 tag、构建镜像、推 registry、写 changelog、发版 | 跑测试、部署、审批流 |
| 产出 | 退出码(0 / 非 0) | 版本号 + 制品 + release notes | 部署状态 / PR 状态 |
| 是否需要联网 | 首次需要(clone hook repo + 装依赖),之后走缓存 | 需要 | 需要 |
| 是否影响生产 | ❌ 完全不影响 | ✅ 直接影响 | ✅ 直接影响 |

**结论:**

- ❌ **不是** release 工具,**不做**版本号 / tag / 制品 / 发布。
- ✅ **是** "commit 之前的自动化守门员"(本地静态检查 + 格式化)。
- 🔗 **但它和 release 流程有交集**:我们仓库的 release 目录里有大量 YAML(Argo CD / Crossplane)、shell 脚本;
  如果这些文件格式错误 / 有明文密钥 / shell 有 bug,**在 commit 时就拦住**,比在 release 窗口里炸掉便宜得多。
  这是它在本仓库的**唯一合理定位**:release 质量的**上游前置防线**,而不是 release 工具本身。

---

## 3. 核心架构模型

```
┌──────────────────────────────────────────────────────────────┐
│  层 3: hook 仓库(提供 hook 的 git repo,可以被别人复用)      │
│  ├── .pre-commit-hooks.yaml   ← 声明 id / name / entry /     │
│  │                               language / files / stages    │
│  ├── pyproject.toml / package.json / go.mod ...(决定怎么装)  │
│  └── <实际的 lint/format 脚本或入口>                          │
└──────────────────────────────────────────────────────────────┘
                          ▲  repo: + rev:  指定"从哪拿、拿哪个版本"
┌──────────────────────────────────────────────────────────────┐
│  层 2: .pre-commit-config.yaml(消费方仓库的配置,入仓)       │
│  ├── repos[]   → { repo, rev, hooks[] }                      │
│  └── hooks[]   → { id, args, files, exclude, types, stages,  │
│                    always_run, verbose, additional_dependencies│
│                    language_version, alias, log_file }        │
└──────────────────────────────────────────────────────────────┘
                          ▲  pre-commit install
┌──────────────────────────────────────────────────────────────┐
│  层 1: pre-commit 本体(Python 实现,MIT)                     │
│  ├── 解析配置 → 计算待检查文件集 → 建/复用隔离环境            │
│  ├── 调用 hook,汇总结果,失败则中断 commit                     │
│  └── 缓存:~/.cache/pre-commit(PRE_COMMIT_HOME 可改)          │
└──────────────────────────────────────────────────────────────┘
```

**关键点:**

1. **"hook 仓库"和"使用仓库"是解耦的。** 一个 hook 仓库可以被上千个项目复用(例如 `pre-commit/pre-commit-hooks`、
   `astral-sh/ruff-pre-commit`、`gitleaks/gitleaks`)。
2. **`rev` 是版本锁**,语义上等价于 lockfile:默认写 tag(`v4.7.0`),`--freeze` 会写成 commit SHA(`0161422b4e09...  # frozen: v4.7.0`)。
3. **环境是按 hook 隔离的**,所以"hook 用什么语言"只影响它自己那个环境,不会互相污染,也不要求你本机装那个运行时。
4. **`language: unsupported` 是"逃生舱"**:不建环境,直接执行你本机已有的可执行文件(本仓库的 `cr/cr.sh` 就适合这个)。

---

## 4. 安装与快速开始

### 4.1 安装 pre-commit 本体

```
# 方式 1: pip(推荐)
pip install pre-commit
pre-commit --version        # → pre-commit 4.7.0

# 方式 2: python 项目里写进依赖
# requirements-dev.txt
pre-commit

# 方式 3: 0 依赖 zipapp(不污染 python 环境)
# 从 https://github.com/pre-commit/pre-commit/releases 下载 .pyz
python pre-commit-4.7.0.pyz --version
```

### 4.2 快速开始(官方 4 步)

```
# 1) 生成一个最小配置模板
pre-commit sample-config > .pre-commit-config.yaml

# 2) 编辑 .pre-commit-config.yaml(见 §5)

# 3) 安装 git hook 脚本(写入 .git/hooks/pre-commit)
pre-commit install
# → pre-commit installed at .git/hooks/pre-commit

# 4) 对全仓跑一遍(加新 hook 后强烈建议)
pre-commit run --all-files
```

> ⚠️ **首次执行会慢**:pre-commit 要 clone hook 仓库、装语言运行时(node 可能要现场编译)、装依赖。
> 官方原文:*"Note that running a hook for the first time may be slow."*

### 4.3 最小可用配置示例

```
repos:
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v6.0.0
  hooks:
  - id: check-yaml
  - id: end-of-file-fixer
  - id: trailing-whitespace
- repo: https://github.com/psf/black
  rev: 24.10.0
  hooks:
  - id: black
```

---

## 5. 配置模型 `.pre-commit-config.yaml`

### 5.1 顶层字段

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `repos` | — | **必填**,hook 仓库映射列表 |
| `default_install_hook_types` | `[pre-commit]` | `pre-commit install` 默认装哪些 git hook 类型 |
| `default_language_version` | `{}` | 按 language 指定默认版本(如 `{python: python3.12}`) |
| `default_stages` | 全部 stage | 全局默认 stage,只覆盖没单独设 `stages` 的 hook |
| `files` | `''` | 全局文件包含模式(正则) |
| `exclude` | `^$` | 全局文件排除模式(正则) |
| `fail_fast` | `false` | `true` = 第一个失败就停(不再跑后面的 hook) |
| `minimum_pre_commit_version` | `'0'` | 要求 pre-commit 的最低版本 |

### 5.2 `repos[]` 字段

| 字段 | 说明 |
|------|------|
| `repo` | 要 `git clone` 的仓库 URL;或哨兵值 `local`(本仓库内脚本)/ `meta` |
| `rev` | **版本锁**:tag(`v4.7.0`)、分支、commit SHA |
| `hooks` | 该仓库里要用哪些 hook(见下) |

### 5.3 `hooks[]` 字段(消费方侧的覆盖项)

| 字段 | 默认值 | 说明 |
|------|--------|------|
| `id` | — | **必填**,来自 hook 仓库的 `.pre-commit-hooks.yaml` |
| `alias` | — | 给 hook 起别名,方便 `pre-commit run <alias>` |
| `name` | hook 自带 | 覆盖执行时显示的名字 |
| `language_version` | hook 自带 | 覆盖语言版本(如 `python3.11`) |
| `files` | `''` | 覆盖文件匹配模式 |
| `exclude` | `^$` | 排除模式 |
| `types` / `types_or` / `exclude_types` | — | 按文件类型过滤(AND / OR / 排除) |
| `args` | `[]` | 传给 hook 的额外参数 |
| `stages` | 全部 | 该 hook 在哪些 git hook 上跑(见 §8.1) |
| `additional_dependencies` | `[]` | 在 hook 自己的环境里额外装的依赖(如 eslint 插件) |
| `always_run` | `false` | 即使没有匹配文件也执行(如"检查分支保护配置") |
| `verbose` | `false` | 通过时也打印输出 |
| `log_file` | — | 失败(或 verbose)时把输出写到文件 |
| `pass_filenames` | `true` | `false` = 不把文件名传给 hook |
| `require_serial` | `false` | `true` = 单进程串行执行(不支持并行的工具用) |
| `description` | `''` | 描述(仅元数据) |

### 5.4 版本升级策略

```
pre-commit autoupdate                 # 默认升到各 repo 默认分支上的最新 tag
pre-commit autoupdate --bleeding-edge  # 升到默认分支最新 commit(不可复现,慎用)
pre-commit autoupdate --freeze         # 写成 frozen SHA(rev: 0161422b...  # frozen: v4.7.0)
pre-commit autoupdate --repo <URL>     # 只升某一个 repo
```

> **最佳实践:** 用 `--freeze` 把 `rev` 写成 SHA + 注释,既可复现又能看懂对应版本;升级走单独的 PR。

---

## 6. `language` 支持矩阵 + 自定义 hook

### 6.1 官方支持的 language(共 20 种)

| language | 隔离环境怎么来 | 备注 |
|----------|----------------|------|
| `python` | 建 venv + `pip install` | 最常用;可用 `language_version` 指定 3.9 / 3.11 / 3.12 |
| `node` | 装 node(必要时现场编译)+ `npm install` | 不需要你本机有 node |
| `golang` | `go install` | |
| `rust` | `cargo install` | |
| `ruby` | `bundle install` | |
| `docker` / `docker_image` | 跑 docker 容器 | 需要本机有 docker |
| `swift` | `swift build` | |
| `dotnet` | `dotnet restore` | |
| `julia` / `lua` / `perl` / `r` / `haskell` / `dart` / `coursier` / `conda` | 各自生态 | |
| `pygrep` | 直接跑仓库内脚本(无依赖) | 轻量正则检查常用 |
| `unsupported` | **不建环境**,直接执行 `entry` | 本仓库最可能用这个调 `cr/cr.sh` |
| `unsupported_script` | 直接执行仓库内脚本文件 | |
| `fail` | 永远失败 | 用来强制禁用某个 hook |

### 6.2 写一个自己的 hook 仓库

hook 仓库根目录必须有 `.pre-commit-hooks.yaml`:

```
- id: check-requirements
  name: check requirements
  description: 校验 requirements.txt 里的 pin 版本
  entry: python -m scripts.check_requirements --compare
  language: python
  files: ^requirements.*\.txt$
  types: [text]
  stages: [pre-commit, manual]
  always_run: false
  fail_fast: false
  verbose: false
  pass_filenames: true
  require_serial: false
  args: []
```

- **`entry` 可以自带不可覆盖的参数**(如 `entry: autopep8 -i .`)。
- **`args` 会在 `entry` 之后、文件名之前插入**,所以 hook 脚本的参数顺序要设计成 `[args...] [filenames...]`。
- hook 执行时环境变量 `PRE_COMMIT=1` 会被设置;**hook 必须以非 0 退出码表示失败**,或直接修改文件。

### 6.3 仓库内本地 hook(`repo: local`)

不需要单独开一个仓库,脚本就放本仓库里:

```
repos:
- repo: local
  hooks:
  - id: check-cr-required
    name: CR / commit SHA 关联校验
    entry: ./tooling/check-pr-cr.sh
    language: unsupported
    files: ^(releases/|cr/)
    pass_filenames: false
    always_run: true
```

> **注意:** `language: unsupported` 的 hook **没有环境隔离**,依赖必须是本机已装的(所以 `entry` 要写相对/绝对路径并加 `#!/usr/bin/env bash`)。

### 6.4 交互式开发 hook

```
# 在另一个仓库里"试用"一个还没发布的 hook 仓库
pre-commit try-repo ../hook-repo foo --verbose --all-files
pre-commit try-repo https://github.com/pre-commit/pre-commit-hooks
```

---

## 7. CLI 命令全表

### 7.1 全局选项与退出码

```
--color {auto,always,never}   颜色输出(默认 auto;可用 PRE_COMMIT_COLOR 覆盖,TERM=dumb 会禁用)
-c CONFIG, --config CONFIG   使用别的配置文件
-h, --help                   帮助
```

| 退出码 | 含义 |
|--------|------|
| `1` | 检测到 / 预期的错误(hook 失败) |
| `3` | 意外错误(配置坏了之类) |
| `130` | 被 `^C` 中断 |

### 7.2 子命令

| 命令 | 作用 | 关键选项 |
|------|------|----------|
| `pre-commit install` | 把 pre-commit 装进 `.git/hooks/` | `-f/--overwrite`、`--install-hooks`、`-t/--hook-type`(可多次)、`--allow-missing-config` |
| `pre-commit install-hooks` | 只预装所有 hook 的环境(不装脚本) | — |
| `pre-commit uninstall` | 卸载 hook 脚本(恢复安装前状态) | `-t/--hook-type` |
| `pre-commit run [hook-id]` | 手动跑 hook(默认 = commit 时行为,只跑 staged 文件) | `-a/--all-files`、`--files`、`--from-ref/--to-ref`、`--hook-stage`、`--show-diff-on-failure`、`-v/--verbose` |
| `pre-commit autoupdate` | 升级配置里的 `rev` | `--bleeding-edge`、`--freeze`、`--repo`、`-j/--jobs` |
| `pre-commit clean` | 清空缓存的 hook 仓库 | — |
| `pre-commit gc` | 清理缓存里**不再被引用**的仓库 | — |
| `pre-commit try-repo REPO` | 试用某 hook 仓库(可本地路径) | `--ref` + 所有 `run` 的选项 |
| `pre-commit validate-config` | 校验 `.pre-commit-config.yaml` | `[filenames...]` |
| `pre-commit validate-manifest` | 校验 `.pre-commit-hooks.yaml` | `[filenames...]` |
| `pre-commit sample-config` | 打印一份配置模板 | — |
| `pre-commit init-templatedir DIR` | 给 `git config init.templateDir` 用的目录装 hook(新 clone 的仓库自动带 hook) | `-t/--hook-type` |
| `pre-commit migrate-config` | 把旧版 list 配置迁移成新的 map 格式 | — |

### 7.3 常用组合

```
pre-commit run --all-files                             # 全仓跑(CI 常用)
pre-commit run --from-ref origin/HEAD --to-ref HEAD   # 只跑变更文件(更快)
pre-commit run flake8                                  # 只跑一个 hook
git ls-files -- '*.py' | xargs pre-commit run --files
pre-commit run --hook-stage manual check-cr            # 手动触发某个 stage
```

---

## 8. 高级特性

### 8.1 stages:把 hook 绑到不同的 git hook 上

pre-commit 不只支持 `pre-commit` 这一个 git hook,官方支持的 hook 类型:

```
commit-msg  post-checkout  post-commit  post-merge  post-rewrite
pre-commit  pre-merge-commit  pre-push  pre-rebase  prepare-commit-msg
```

- `stages` 值与 git hook 名一致(3.2.0 起的语义)。
- 特殊 stage `manual`:**不会被任何 git hook 自动触发**,只能手动 `pre-commit run --hook-stage manual`。
- 典型配置(一个通用 linter / formatter):
  ```
  stages: [pre-commit, pre-merge-commit, pre-push, manual]
  ```
- 只想装某几个:
  ```
  pre-commit install --hook-type pre-commit --hook-type pre-push
  ```
- 或在配置里定默认:
  ```
  default_install_hook_types: [pre-commit, pre-push, commit-msg]
  ```

### 8.2 临时跳过某个 hook

```
SKIP=flake8 git commit -m "foo"          # 只跳过 flake8,不用 --no-verify 全跳过
```

### 8.3 migration mode(与已有 hook 共存)

默认 `pre-commit install` 是 **migration mode**:保留你原有的 git hook,并让它们和 pre-commit 的 hook 一起跑。
传 `-f/--overwrite` 才会覆盖掉旧 hook。`pre-commit uninstall` 能恢复到安装前的状态。

### 8.4 按文件类型过滤(`types`)

- `types` = AND 语义;`types_or` = OR 语义;`exclude_types` = 排除。
- 常用类型:`yaml` `json` `markdown` `shell` `python` `text` `file` `executable` `symlink` …
- 例子:只对 yaml 跑 yamllint:
  ```
  - id: yamllint
    types: [yaml]
  ```

### 8.5 always_run

```
- id: check-branch-protection
  always_run: true      # 即使一个文件都没匹配,也执行
  pass_filenames: false # 且不传文件名
```
适合:"校验 SOT 里 release 版本号是否递增"、"校验 CR 编号唯一性"这类**全局性**检查。

### 8.6 其它

- **`require_serial`**:某些工具不支持并发,设 `true` 强制串行。
- **`additional_dependencies`**:在 hook 自己的环境里装插件(如 eslint 的 plugin)。
- **badging**:README 上挂个 badge 展示"本仓库用了 pre-commit"。
- **"global" 安装**:`pre-commit init-templatedir ~/.git-template` + `git config --global init.templateDir ~/.git-template`,
  之后所有新 clone 的仓库自动带 hook(对"很多仓库"的组织很有用)。

---

## 9. CI 集成

### 9.1 基本原则

> 官方原文:*"pre-commit can also be used as a tool for continuous integration."*
> 加一步 `pre-commit run --all-files` 即可保证全仓干净;只想查变更就用
> `pre-commit run --from-ref origin/HEAD --to-ref HEAD`。

### 9.2 GitHub Actions 示例

```
name: pre-commit
on: [push, pull_request]

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0        # --from-ref 需要完整历史
    - uses: actions/setup-python@v5
      with:
        python-version: '3.12'
    - uses: pre-commit/action@v3.0.1
```

### 9.3 缓存管理

pre-commit 默认把仓库缓存放在 `~/.cache/pre-commit`,可用两种方式改:

- `PRE_COMMIT_HOME` 环境变量(优先)
- `XDG_CACHE_HOME` → `$XDG_CACHE_HOME/pre-commit`

在 GitHub Actions 里配 `actions/cache` 时,key 建议包含 `.pre-commit-config.yaml` 的 hash(否则升了 hook 版本还用旧缓存)。

### 9.4 pre-commit.ci

官方托管服务 `pre-commit.ci`:零配置接入,还会**自动修 PR**(autofix pull requests)。

### 9.5 其他平台的官方示例

官网同时给了 AppVeyor、Azure Pipelines、CircleCI、GitLab CI、Travis CI 的 YAML 片段,以及和 `tox` 配合的用法。

---

## 10. 与本仓库的关系(重点)

### 10.1 我们的现状盘点

| 现状 | 事实 |
|------|------|
| 仓库类型 | GCP infra release 工程仓库,内容 = **38 个 `.sh` + 25 个 `.yaml` + 25 个 `.md`** |
| 已有 git hook | `legacy/common/git-hooks/commit-msg` —— **自己手写的** Conventional Commits 校验;配套 `install.sh` 手动同步到 `.git/hooks/` |
| CI | 探索过 Prow(见 [prow/Prow.md](../prow/Prow.md)),尚未落地 |
| 敏感内容 | 有 GCP / gcloud 操作脚本,**可能误提交密钥** |
| YAML 敏感度 | 高:Argo CD / Crossplane YAML 写错 = 直接 apply 失败;YAML 缩进错 = 生产事故 |

### 10.2 为什么值得引入(收益)

1. **YAML 语法错误在 commit 时就被拦下**,而不是在 release 窗口 apply Argo CD 时才炸。
2. **密钥泄漏在 push 前拦截**(gitleaks / detect-private-key),这在 infra 仓库是硬需求。
3. **shell 脚本静态检查**(shellcheck):本仓库 38 个 sh,手写 bash 极易出 `set -e` 漏判 / 引号错误。
4. **统一替代"复制粘贴式 git hook"**:现在的 `legacy/common/git-hooks/install.sh` 需要人工执行;
   pre-commit 只需 `pre-commit install`,且配置入仓、全员一致、可版本化。
5. **和 CR / release 流程分工明确**:
   - pre-commit = **本地第一道门**(秒级反馈,阻止脏 commit 进主干)
   - Prow / CI = **第二道门**(PR 级全量校验 + 测试)
   - CR = **第三道门**(部署风险评审:窗口 / 影响面 / 回滚计划)
   - release = **第四道门**(实际发布)

### 10.3 建议的配置(草稿)

完整可复制版本见本目录下的 [.pre-commit-config.yaml.example](./.pre-commit-config.yaml.example)。

```
repos:
- repo: https://github.com/pre-commit/pre-commit-hooks
  rev: v6.0.0
  hooks:
  - id: check-yaml              # YAML 语法校验(Crossplane/Argo CD 最重要)
  - id: check-json
  - id: check-merge-conflict
  - id: detect-private-key      # 私钥拦截
  - id: end-of-file-fixer
  - id: trailing-whitespace
- repo: https://github.com/adrienverge/yamllint
  rev: v1.35.1
  hooks:
  - id: yamllint
    args: [--config-file=precommit/.yamllint.yml]
- repo: https://github.com/shellcheck-py/shellcheck-py
  rev: v0.10.0.1
  hooks:
  - id: shellcheck
- repo: https://github.com/gitleaks/gitleaks
  rev: v8.24.0
  hooks:
  - id: gitleaks
- repo: local
  hooks:
  - id: cr-consistency            # 仓库自己的检查(unsupported = 调本机 bash)
    entry: ./tooling/check-cr-consistency.sh
    language: unsupported
    pass_filenames: false
    always_run: true
    stages: [pre-commit, pre-push]
```

### 10.4 与现有 `commit-msg` hook 的关系(迁移方案)

**现状:** `legacy/common/git-hooks/commit-msg` 手写,靠 `install.sh` 手动复制到 `.git/hooks/`。

**两个方案,二选一(不要同时用同一个 hook 类型):**

| 方案 | 做法 | 优点 | 缺点 |
|------|------|------|------|
| **A. 保留手写 hook(推荐先做)** | pre-commit 只管 `pre-commit` 阶段(YAML / 密钥 / shell),commit-msg 仍用手写脚本 | 零冲突、渐进、可回退 | 两套机制并存,安装要跑两个命令 |
| **B. 全部收编到 pre-commit** | 把 commit-msg 逻辑搬成一个 `repo: local` 的 hook,`stages: [commit-msg]`,废弃 `install.sh` | 单一配置源,全员一致 | 改动大;需处理 `git commit --amend` / merge commit 的边界;要同步改 onboarding 文档 |

> **建议:** 先走 **A**(pre-commit 只做新增的静态检查),等 CI(Prow)落地、大家习惯后再评估 B。
> 无论哪种方案,都建议在 README 里明确写"clone 后先跑 `pre-commit install`(以及 `legacy/common/git-hooks/install.sh`)"。

### 10.5 风险与坑(必须提前知道)

| 坑 | 说明 | 对策 |
|----|------|------|
| **首次运行极慢** | 要 clone hook 仓库、装 node / go 运行时(可能现场编译),几分钟起步 | 提交前提前跑一次;或用 `pre-commit install-hooks` 预热;CI 里配 cache |
| **需要联网** | 离线环境 / 内网 git 代理要处理 `git clone` | 配好 git url rewrite 或用镜像源 |
| **缓存膨胀** | `~/.cache/pre-commit` 会越攒越大 | 定期 `pre-commit gc` / `pre-commit clean` |
| **和 `install.sh` 抢 `.git/hooks/`** | 两个机制都想写 `.git/hooks/pre-commit` | 见 §10.4,阶段分离,别让 pre-commit 管 commit-msg |
| **`legacy/` 目录历史包袱** | 38 个 sh 里有大量旧代码,shellcheck 会一片红 | 用 `exclude: ^legacy/` 先豁免,新代码严格 |
| **格式化类 hook 会改文件** | `end-of-file-fixer` / `trailing-whitespace` 会直接改你的文件 | 团队约定:先跑 `pre-commit run --all-files` 再提交;或在 CI 里只用只读类检查 |
| **`--no-verify` 绕过** | 任何本地检查都能被 `git commit --no-verify` 绕过 | **关键检查必须在 CI 里也跑一遍**(`pre-commit run --all-files`),本地只是提效 |

### 10.6 明确不推荐的做法

- ❌ 把 pre-commit 当成 release 工具用(它不产制品、不打 tag、不做部署)。
- ❌ 用 pre-commit 做**需要联网访问生产**的检查(慢且不稳,应放 CI / release 流程)。
- ❌ 把 `rev` 写成 `main` 分支(不可复现);至少写 tag,最好 `--freeze` 写 SHA。
- ❌ 一上来就装几十个 hook(首次安装 10+ 分钟);先装 5~8 个高频的。

---

## 11. 落地清单(建议拆 3 个 PR)

| PR | 内容 | 验收标准 |
|----|------|----------|
| **PR-1** 引入基础能力 | 加 `.pre-commit-config.yaml`(check-yaml / check-json / trailing-whitespace / end-of-file-fixer / detect-private-key)+ `.yamllint.yml`;README 增加 "clone 后跑 `pre-commit install`" | `pre-commit run --all-files` 在主干上全绿 |
| **PR-2** 加 shell 与安全 | 加 shellcheck(排除 `legacy/`)+ gitleaks;把 `tooling/` `cr/` 纳入严格范围 | 改一个 sh 有明确的 lint 反馈;误报有 inline `# shellcheck disable` 处理 |
| **PR-3** 接到 CI | 在 Prow(或 GitHub Actions)加 `pre-commit run --all-files` + cache;README 挂 badge | CI 里 pre-commit job 绿;本地与 CI 结果一致 |

> **PR-3 是关键:** 没有 CI 兜底,pre-commit 就只是"看个人自觉"的工具。

---

## 12. 权威证据(全部为实际抓取,非杜撰)

| 内容 | 来源 | 抓取时间 |
|------|------|----------|
| 官方定位:"A framework for managing and maintaining multi-language pre-commit hooks." | https://pre-commit.com / GitHub repo description | 2026-11-17 |
| 完整文档(Introduction / Installation / Plugins / Usage / Creating hooks / CLI / Advanced / Contributing) | https://pre-commit.com | 2026-11-17 |
| 精选 hook 列表(pre-commit-hooks / ruff / black / flake8 / shellcheck / yamllint / gitleaks / markdownlint / actionlint / check-jsonschema / buf / sqlfluff / cfn-lint …) | https://pre-commit.com/hooks.html | 2026-11-17 |
| 最新版本 `v4.7.0`(发布于 2026-10-13) | https://github.com/pre-commit/pre-commit/releases/latest | 2026-11-17 |
| GitHub 统计:⭐ 15,716 / fork 1,121 / open issues 25 / Python / MIT License / 创建于 2014-03-13 / 默认分支 `main` | GitHub API `repos/pre-commit/pre-commit` | 2026-11-17 |

**关联文档(本仓库内):**
- [prow/Prow.md](../prow/Prow.md) — CI 侧的第二道门(Prow 架构探索)
- [docs/cr-workflow.md](../docs/cr-workflow.md) — 第三道门(CR / Change Request 流程)
- [crossplane-gcp-family-best-practices.md](../crossplane-gcp-family-best-practices.md) — v2 主交付(Crossplane + GCP Family)
