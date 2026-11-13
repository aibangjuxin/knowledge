# TokenEconomizer 配置与命令速查（Pi）

> 面向 Pi（`earendil-works/pi-coding-agent`）的完整设置项、命令、环境变量与优先级说明。
>
> 相关文档：[SKILL.md](../SKILL.md) · [setup-log.md](setup-log.md) · [mechanisms.md](mechanisms.md)

---

## 1. 命令总表

### 1.1 在 Pi 会话内（每个命令 = 1 个模型回合）

```text
/te status          # 本仓库学到了什么 / 做了什么 / 会话花了多少钱
/te microskills     # 已注入的事实 + 仍在形成中的事实
/te config          # 当前生效的全部设置
/te repos           # 插件为哪些仓库保存了状态
```

### 1.2 在终端（免费）

```bash
cd <repo>
~/.tokeneconomizer/bin/te --host pi <command>
```

| 命令 | 作用 |
| :--- | :--- |
| `status` | 本仓库学到了什么、做了什么、会话成本 |
| `microskills` | 注入的事实与仍在形成的事实 |
| `toolprune` | 裁剪清单（**Pi 上不可用**，仅作状态占位） |
| `toolprune apply [ITEM …]` | 应用待处理提案（Pi 上无效） |
| `toolprune restore [ITEM …]` | 归还被裁剪的项（Pi 上无效） |
| `toolprune refresh-catalog` | 记录会话加载的工具（Claude Code / Copilot 专用） |
| `toolprune measure` | 对比裁剪前后的请求体量 |
| `config` | 查看全部设置 |
| `config set KEY=VALUE … [--global]` | 修改设置（当前仓库 / 全局） |
| `config unset KEY … [--global]` | 撤销该层设置，回落到上层或默认值 |
| `repomap` / `repomap refresh` | 仓库地图（需 `pip install aider-chat`） |
| `history` / `history import [--dry-run]` | Claude Code 专属的早期会话导入 |
| `repos` | 所有仓库的状态 |
| `repos migrate` | 升级后一次性迁移旧版状态布局 |
| `repos merge KEY [INTO]` | 合并仓库状态（分支/克隆场景） |
| `doctor` | **环境自检：Python、状态目录、Agent 探测、错误日志** |

> `doctor`、`history`、`repomap` 只能在终端跑（Pi 里可用 `/te doctor` 等价形式，因为 Pi 扩展直接透传 argv）。

---

## 2. 三大机制开关

| 机制 | 键 | 取值 | 含义 |
| :--- | :--- | :--- | :--- |
| Micro-skills | `microskills` | `on` | `envfacts` + `distiller`：免模型的事实 + 每 N 个会话由模型提议 |
| | | `envfacts` | **只**用免模型的事实（零额外开销）⭐ 推荐起步 |
| | | `distiller` | **只**用模型提议的事实 |
| | | `off` | 关闭（**默认**） |
| Tool pruning | `toolprune` | `auto` | 满足条件后自动应用（**默认**） |
| | | `propose` | 只提案，需手动 `toolprune apply` |
| | | `off` | 停止生成新清单 |
| Loop guard | `loopguard` | `nudge` | judge 模型判定卡死 → 中途 redirect（**默认**） |
| | | `off` | 完全关闭（judge 也不再调用） |
| | | `stop` | 兼容旧名，等价 `nudge`，会给出警告 |

### 示例

```bash
TE=~/.tokeneconomizer/bin/te

"$TE" --host pi config set microskills=on --global        # 完整微技能（含模型提议）
"$TE" --host pi config set microskills=envfacts --global   # 零成本微技能
"$TE" --host pi config set loopguard=off --global          # 关掉循环守卫
"$TE" --host pi config set toolprune=off --global          # （Pi 上本就无效）
```

---

## 3. 全部设置项与默认值

### 3.1 Micro-skills

| 键 | 默认 | 含义 |
| :--- | :--- | :--- |
| `microskills_max_facts` | `4` | 从「重复失败」注入的事实条数上限（模型提议的事实不计入） |
| `microskills_max_tokens` | `150` | 注入块的大小上限（tokens，约 4 字符 ≈ 1 token） |
| `microskills_propose_every` | `3` | 每隔多少个会话跑一次模型提议器（首次会提前一个会话） |

### 3.2 Tool pruning（Pi 上无效，仅列出以便对照）

| 键 | 默认 | 含义 |
| :--- | :--- | :--- |
| `toolprune_evidence` | `10` | 工具需被闲置多少个 prompt 才可被裁掉 |
| `toolprune_min_sessions` | `2` | 这些 prompt 至少要跨越多少个会话 |
| `toolprune_sessions` | `5` | 或任意长度的会话数达到该值即满足 |
| `toolprune_quiet_minutes` | `60` | 仓库需空闲多久才写入裁剪清单（保护 prompt cache；最长等一天） |
| `toolprune_protect` | 空 | 永不裁剪的工具名/模式，逗号分隔 |

### 3.3 Loop guard

| 键 | 默认 | 含义 |
| :--- | :--- | :--- |
| `loopguard_aggr` | `default` | 阈值档位：`conservative` / `default` / `aggressive` |
| `loopguard_nudges` | `1` | 每个回合最多几次 redirect，之后只提示人 |

`loopguard.<name>` 阈值（各档位默认值）：

| 阈值 | conservative | default | aggressive | 含义 |
| :--- | :--- | :--- | :--- | :--- |
| `min_turns` | 28 | 20 | 14 | 判定「卡死」所需的最少工具调用数 |
| `edit_churn` | 5 | 4 | 3 | 同一文件的编辑次数算「反复改」 |
| `distinct_edit_files` | 3 | 3 | 3 | 涉及的文件数算「散乱改」 |
| `error_outputs` | 8 | 6 | 4 | 失败的工具结果数算「持续报错」 |
| `stagnation` | 0.30 | 0.20 | 0.12 | 重复失败占失败总数的比例 |
| `envelope_pct` | 90 | 90 | 90 | 从仓库「正常结束回合」的长度取哪个百分位 |
| `envelope_margin` | 1.5 | 1.25 | 1.0 | 在该百分位上的倍率 |
| `envelope_min_samples` | 7 | 5 | 3 | 需要多少个「正常结束回合」才启用守卫 |
| `backstop_mult` | 3.5 | 2.5 | 1.8 | 超过常规长度的多少倍即无条件 redirect |
| `judge_confidence` | 0.85 | 0.7 | 0.55 | judge 判定「卡死」的置信度门槛 |
| `gate_min_turns` | 24 | 18 | 12 | 触发 judge 询问的工具调用数（不低于 `min_turns`） |
| `gate_error_outputs` | 8 | 8 | 8 | 无需重复失败即可唤起 judge 的失败结果数 |

### 3.4 全局与其他

| 键 | 默认 | 含义 |
| :--- | :--- | :--- |
| `enabled` | `true` | `false` = 整个插件关闭，钩子立即返回且不记录任何东西 |
| `paid_model` | 空 | 插件自身调用使用的模型；Pi 上**空 = 你的 Pi 默认模型** |
| `pi_paid_model` | 空 | 只针对 Pi 覆盖 `paid_model` |
| `pi_extensions` | 空 | 插件自身调用需要加载的扩展文件（仅当模型 provider 由扩展注册时才需要） |
| `pi_cli` | 空 | 插件自身调用使用的 `pi` 可执行文件；空 = PATH 上第一个 |
| `shadow` | `false` | `true` = **只决策不执行**，用于安全观察插件行为 |
| `mode` | `auto` | `interactive` / `headless` 覆盖自动探测 |
| `repomap` | `off` | `on` = 按首个 prompt 排序注入仓库地图；`start` = 会话开始注入缓存地图 |
| `repomap_tokens` | `2048` | 地图大小（tokens） |
| `repomap_python` | auto | 装有 aider 的 Python 路径 |
| `repomap_timeout` | `8` | 首个 prompt 等待排序地图的秒数 |

---

## 4. 优先级

```text
环境变量（单次会话）
   ↓ 覆盖
仓库级设置（repo.json）
   ↓ 覆盖
全局设置（~/.tokeneconomizer/config.json）
   ↓ 覆盖
默认值
```

- 环境变量名 = `TE_` + 设置名全大写：`TE_MICROSKILLS`、`TE_TOOLPRUNE_EVIDENCE`、`TE_LOOPGUARD_NUDGES` …
- 守卫阈值可用 JSON 覆盖：`TE_LOOPGUARD_THRESHOLDS='{"min_turns": 30}'`
- 整体关闭：`TE_DISABLE=1`
- `config unset KEY` 移除本层设置，回落到上层或默认值
- 改动生效时机：**守卫在下次工具调用生效；事实与裁剪清单在下次会话开始生效**

---

## 5. Pi 上的模型调用配置

插件自身调用通过：

```bash
pi --print --mode json --no-session --no-tools --no-extensions "<prompt>"
```

| 需求 | 配置方式 |
| :--- | :--- |
| 换模型 | `config set paid_model=<provider>/<model> --global` 或 `pi_paid_model` |
| provider 由扩展提供 | `config set pi_extensions=/path/to/ext.ts --global` |
| PATH 上的 `pi` 是包装脚本 | `config set pi_cli=/real/path/to/pi --global` |
| 只想观察不干预 | `config set shadow=true --global` |

> 本机实测：`minimax-cn/MiniMax-M3.1-Flash` 为 Pi **内建** provider，
> 在 `--no-extensions` 下照常返回，因此**无需**配置 `pi_extensions`。

---

## 6. 观测与诊断

```bash
TE=~/.tokeneconomizer/bin/te

# 当前仓库状态一览
"$TE" --host pi status

# 环境自检
"$TE" --host pi doctor

# 全部设置
"$TE" --host pi config

# 错误日志（不存在 = 无错误）
cat ~/.tokeneconomizer/errors.log
```

`status` 输出字段说明：

| 字段 | 含义 |
| :--- | :--- |
| `repository` | 仓库路径与标识方式（remote / 路径） |
| `state` | 该仓库的状态目录 |
| `config` | 当前生效的机制与模式 |
| `sessions` | 已折叠会话数、有效 token 数、插件自身开销及占比 |
| `microskills` | 本次注入的事实数、从多少个会话学习而来 |
| `toolprune` | Pi 上固定显示 `not available on this host` |
| `loopguard` | 是否已学到回合长度基准、redirect 次数、still-stuck 提示次数 |

---

## 7. 常用运维动作

```bash
# 更新插件（普通 pi update 不会更新扩展）
pi update --extensions

# 停用但保留（临时）
pi config          # TUI 里开关

# 卸载
pi remove git:github.com/microsoft/TokenEconomizer

# 清空所有学习状态（不可逆）
rm -rf ~/.tokeneconomizer
```

---

## 8. Pi 专属限制清单

| 限制 | 原因 |
| :--- | :--- |
| 工具裁剪（Tool pruning）不可用 | Pi 只加载 4 个内置工具，没有逐工具的持久配置开关 |
| 无 `history_import` 早期会话导入 | 该能力读的是 Claude Code 的会话日志 |
| 模型调用成本按「有效 token」估算 | Pi 的 usage 结构与官方价格表不一定完全匹配 |
| `/te` 在会话内消耗 1 个模型回合 | Pi 的自定义命令实现方式所致；终端调用免费 |
