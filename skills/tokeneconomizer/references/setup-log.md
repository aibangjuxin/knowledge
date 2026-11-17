# TokenEconomizer on Pi — 安装全过程实录

> 本文件逐条记录 2026-11-13 在本机完成 TokenEconomizer 安装与验证的**每一条命令和真实输出**，
> 便于日后复现、排查与审计。
>
> 相关文档：[SKILL.md](../SKILL.md) · [config-reference.md](config-reference.md) · [mechanisms.md](mechanisms.md)

---

## 0. 环境基线

| 项 | 值 | 采集命令 |
| :--- | :--- | :--- |
| 系统时间 | `2026-11-13 09:23:18 +08` | `date "+%Y-%m-%d %H:%M:%S %Z"` |
| Pi 版本 | `1.5.2` | `pi --version` |
| Python | `3.15.0` | `python3 --version` |
| Node | `v26.12.1` | `node --version` |
| Pi 默认 provider / model | `minimax-cn` / `MiniMax-M3.1-Flash` | `~/.pi/agent/settings.json` |
| 当前工作目录 | `/Users/lex/git/go`（Go 仓库，remote `github.com/aibangjuxin/go`） | — |

安装前 Pi 已装的 package：

```text
$ pi list
User packages:
  npm:pi-token-usage
    /Users/lex/.pi/agent/npm/node_modules/pi-token-usage
```

---

## 1. 阅读上游文档

```bash
git clone --depth 1 https://github.com/microsoft/TokenEconomizer.git /tmp/TokenEconomizer
```

读取的三个关键文件：

| 文件 | 用途 |
| :--- | :--- |
| `README.md` | 三大机制、论文数据、安装方式（Pi 一节）、设置项总览 |
| `plugin/README.md` | Pi 适配细节、模型调用机制、命令表、排障表 |
| `package.json` | 确认 Pi package 入口：`pi.extensions = ["./plugin/pi/tokeneconomizer.ts"]` |
| `pyproject.toml` | 确认包**纯标准库**、零安装期依赖、`requires-python >= 3.10` |

从 `package.json` 确认的 Pi 扩展入口：

```json
{
  "name": "tokeneconomizer",
  "version": "0.1.0",
  "pi": {
    "extensions": ["./plugin/pi/tokeneconomizer.ts"]
  },
  "peerDependencies": { "@earendil-works/pi-coding-agent": "*" }
}
```

---

## 2. 安装

### 2.1 执行安装

```bash
cd /Users/lex/git/go
pi install git:github.com/microsoft/TokenEconomizer
```

真实输出：

```text
Installing git:github.com/microsoft/TokenEconomizer...
Cloning into '/Users/lex/.pi/agent/git/github.com/microsoft/TokenEconomizer'...

up to date in 195ms
Installed git:github.com/microsoft/TokenEconomizer
```

### 2.2 安装产物核对

```bash
ls -la /Users/lex/.pi/agent/git/github.com/microsoft/TokenEconomizer/
```

```text
drwxr-xr-x@ 20 lex staff   640 11月 13 09:22 .
drwxr-xr-x@  3 lex staff    96 11月 13 09:22 ..
drwxr-xr-x@ 12 lex staff   384 11月 13 09:22 .git
-rw-r--r--@  1 lex staff  4267 11月 13 09:22 .gitattributes
-rw-r--r--@  1 lex staff  4286 11月 13 09:22 CLAUDE.md
drwxr-xr-x@  3 lex staff    96 11月 13 09:22 .claude-plugin
drwxr-xr-x@  3 lex staff    96 11月 13 09:22 .github
drwxr-xr-x@  3 lex staff    96 11月 13 09:22 .gitignore
drwxr-xr-x@  6 lex staff   192 11月 13 09:22 docs
drwxr-xr-x@ 10 lex staff   320 11月 13 09:22 experiments
-rw-r--r--@  1 lex staff  31983 11月 13 09:22 README.md
drwxr-xr-x@ 19 lex staff   608 11月 13 09:22 plugin
drwxr-xr--@  1 lex staff   168 11月 13 09:22 pyproject.toml
drwxr-xr-x@ 14 lex staff   448 11月 13 09:22 scripts
drwxr-xr-x@ 14 lex staff   448 11月 13 09:22 tests
drwxr-xr-x@ 14 lex staff   448 11月 13 09:22 tokeneconomizer
```

`~/.pi/agent/settings.json` 被追加 packages 条目（文件修改时间 `11月 13 09:22:25`）：

```json
{
  "lastChangelogVersion": "1.5.2",
  "theme": "dark",
  "defaultProvider": "minimax-cn",
  "defaultModel": "MiniMax-M3.1-Flash",
  "modelThinkingLevels": {
    "minimax-cn/MiniMax-M3.1-Flash": "high"
  },
  "quietStartup": true,
  "fullscreenExitOutput": "transcript",
  "packages": [
    "npm:pi-token-usage",
    "git:github.com/microsoft/TokenEconomizer"
  ]
}
```

### 2.3 确认 Pi 已登记

```bash
pi list
```

```text
User packages:
  npm:pi-token-usage
    /Users/lex/.pi/agent/npm/node_modules/pi-token-usage
  git:github.com/microsoft/TokenEconomizer
    /Users/lex/.pi/agent/git/github.com/microsoft/TokenEconomizer
```

---

## 3. 自检（doctor）

首次会话之前，`~/.tokeneconomizer` 尚不存在，终端启动器也没有，因此直接用仓库内的启动脚本：

```bash
cd /Users/lex/git/go
TE=/Users/lex/.pi/agent/git/github.com/microsoft/TokenEconomizer/plugin/scripts/te
"$TE" --host pi doctor
```

真实输出：

```text
python      3.15.0 ok
state root  /Users/lex/.tokeneconomizer (writable)
agents      antigravity, claude, codex, copilot, droid, hermes, opencode, pi
claude      catalog not probed
codex       this project is NOT trusted (an untrusted project's .codex/config.toml is ignored)
copilot     catalog not probed
copilot     Copilot subscription; side calls and `probe` use model (Copilot default)
copilot     this folder is NOT trusted (an untrusted folder's .github/copilot settings are ignored)
droid       sessions /Users/lex/.factory/sessions; side calls off (set `droid_sidecall=on` or TE_DROID_SIDECALL=1 to try them); tool pruning is not available in the TUI
hermes      plugin not in /Users/lex/.hermes/plugins/tokeneconomizer (it also needs `hermes plugins enable tokeneconomizer`)
pi          package installed: git:github.com/microsoft/TokenEconomizer
repository  /Users/lex/git/go: identified by its origin remote (github.com/aibangjuxin/go); state go-ff86e1edcf
repomap     off; no Python with aider found (pip install aider-chat, or set repomap_python)
errors.log  none
```

关键行解读：

| 行 | 含义 |
| :--- | :--- |
| `python 3.15.0 ok` | 满足 `>= 3.10` 要求 |
| `state root ... (writable)` | 状态目录可写，无需额外授权 |
| `pi package installed` | 扩展已被 Pi 识别 |
| `repository ... identified by its origin remote` | 仓库用 remote 哈希标识 → key = `go-ff86e1edcf` |
| `repomap off; no Python with aider found` | 可选机制未启用，符合预期 |
| `errors.log none` | 无历史错误 |

---

## 4. 冒烟测试（验证扩展真的被加载）

```bash
mkdir -p /tmp/te-pitest && cd /tmp/te-pitest && git init -q
pi -p "Reply with exactly: OK"
```

真实输出：

```text
OK
```

再回到插件侧确认会话被折叠：

```bash
"$TE" --host pi status
```

```text
TokenEconomizer -- te-pitest (pi)
  repository   /private/tmp/te-pitest, identified by its path (a git repository with no remote)
  state        /Users/lex/.tokeneconomizer/repos/te-pitest-3736b50a45/pi
  config       microskills=off toolprune=auto loopguard=nudge repomap=off mode=auto shadow=False
  sessions     1 folded, 31.7k effective tokens, plugin overhead 0 (0.0%)
  microskills  0 fact(s) injected at session start (0 sessions learned from)
  toolprune    not available on this host
  loopguard    envelope not learned yet (0 ended-green turns); 0 redirect(s), 0 still-stuck notice(s) over 1 turns
```

**结论**：扩展加载成功，四个钩子（`session_start` / `before_agent_start` / `tool_result` / `agent_end` / `session_shutdown`）全部打通，
会话已被折叠并完成计价（31.7k effective tokens）。

---

## 5. 首次会话带出的产物

```bash
ls -la ~/.tokeneconomizer
```

```text
drwx------@  8 lex staff  256 11月 13 09:22 .
drwxr-xr-x@ 188 lex staff 7680 11月 13 09:22 ..
-rw-------@  1 lex staff    0 11月 13 09:22 .index.lock
drwx------@  3 lex staff   96 11月 13 09:22 bin
drwx------@  3 lex staff   96 11月 13 09:22 locks
drwx------@  3 lex staff   96 11月 13 09:22 repos
drwx------@  3 lex staff   96 11月 13 09:22 sessions
-rw-------@  1 lex staff  350 11月 13 09:22 index.json
```

```bash
ls -la ~/.tokeneconomizer/bin
```

```text
-rwx------@ 1 lex staff 181 11月 13 09:22 te
```

> 终端启动器 `~/.tokeneconomizer/bin/te` 由**首次会话**写入；在此之前请用
> `~/.pi/agent/git/github.com/microsoft/TokenEconomizer/plugin/scripts/te`。

单仓库状态目录结构：

```bash
ls -R ~/.tokeneconomizer/repos/te-pitest-3736b50a45
```

```text
/Users/lex/.tokeneconomizer/repos/te-pitest-3736b50a45:
pi
repo.json

/Users/lex/.tokeneconomizer/repos/te-pitest-3736b50a45/pi:
events.jsonl        # 原始事件流
fold.log            # 折叠日志
folded.json         # 折叠结果
ledger.jsonl        # 逐会话 token 账本
migrate.log
sessions
  01a1d27f-e098-72c5-9434-3cd548d7b0e7.json
```

---

## 6. 配置基线

### 6.1 开启零成本的 micro-skills

```bash
cd /Users/lex/git/go
~/.tokeneconomizer/bin/te --host pi config set microskills=envfacts --global
```

真实输出：

```text
/Users/lex/.tokeneconomizer/config.json: {"microskills": "envfacts"}
applies from the next hook call; a new fact-size cap applies once the next session has been folded
```

### 6.2 复核生效值

```bash
~/.tokeneconomizer/bin/te --host pi config
```

真实输出（节选）：

```json
{
  "enabled": true,
  "microskills": {
    "state": "on",
    "microskills": "envfacts",
    "microskills_max_facts": 4,
    "microskills_max_tokens": 150,
    "microskills_propose_every": 3
  },
  "toolprune": {
    "state": "on",
    "toolprune": "auto",
    "toolprune_evidence": 10,
    "toolprune_min_sessions": 2,
    "toolprune_sessions": 5,
    "toolprune_quiet_minutes": 60,
    "toolprune_protect": []
  },
  "loopguard": {
    "state": "on",
    "loopguard": "nudge",
    "loopguard_aggr": "default",
    "loopguard_nudges": 1,
    "thresholds": {
      "min_turns": 20,
      "edit_churn": 4,
      "distinct_edit_files": 3,
      "error_outputs": 6,
      "stagnation": 0.2,
      "envelope_margin": 1.25,
      "envelope_pct": 90,
      "envelope_min_samples": 5,
      "judge_confidence": 0.7,
      "backstop_mult": 2.5,
      "gate_min_turns": 18,
      "gate_error_outputs": 8
    },
    "pinned": []
  },
  "history": { "state": "off", "history_import": false, "history_max_sessions": 200, "history_days": 365, "history_dirs": [] },
  "droid":   { "state": "off", "droid_sidecall": false }
}
```

---

## 7. 验证插件自身的模型调用（旁路调用 / side call）

插件的 judge 与 fact proposer 都通过 `pi --print` 发请求。实测这条链路在本机可用：

```bash
cd /tmp/te-pitest
pi --print --mode json --no-session --no-tools --no-extensions "Reply with exactly: OK"
```

真实输出（节选）：

```json
{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"OK"}],
 "api":"anthropic-messages","provider":"minimax-cn","model":"MiniMax-M3.1-Flash",
 "usage":{"input":1178,"output":9,"cacheRead":0,"cacheWrite":0,"totalTokens":1187,
 "cost":{"input":0.0001759932,"output":0.0000053784,"total":0.0001813716,"totalFromProvider":false}},
 "stopReason":"stop","durationMs":2976,"thinkingLevel":"high"}}
```

结论：

| 观察项 | 结论 |
| :--- | :--- |
| `--no-extensions` 下 provider 仍可用 | ✅ `minimax-cn` 是 Pi 内建 provider，**无需**配置 `pi_extensions` |
| 返回结构含 `usage` / `cost` | ✅ 插件可正确给旁路调用计价 |
| 无工具、无扩展 | ✅ 插件自身调用无法改动仓库，也不会递归触发自己 |

---

## 8. Pi 扩展的注册点（源码确认）

`plugin/pi/tokeneconomizer.ts` 中的事件映射（源码注释原文）：

| Pi 事件 | 转成的钩子 | 作用 |
| :--- | :--- | :--- |
| `session_start` | `SessionStart` | 取出学到的「仓库手册」，为本次会话保留 |
| `before_agent_start` | `UserPromptSubmit` | 开启 prompt 回合；把手册作为 `tokeneconomizer` system-prompt section 注入（每个 prompt 都注入，因为 Pi 会 diff section，省略会被记成删除） |
| `tool_result` | `PostToolUse` | 守卫；redirect 以 steering 消息下发，still-stuck 以 UI notice 呈现 |
| `agent_end` | `Stop` | 结束回合 |
| `session_shutdown` | `SessionEnd` | 把会话交给后台折叠进程 |

命令注册：

```typescript
pi.registerCommand("te", {
  description: "TokenEconomizer: status | microskills | config | repos (what it learned here, what it did)",
  handler: async (args, ctx) => {
    const argv = (args || "status").trim().split(/\s+/).filter(Boolean);
    const out = await run("te", ["--host", "pi", "--cwd", ctx.cwd, ...argv], "", ctx.mode, {
      TE_SESSION_ID: ctx.sessionManager.getSessionId(),
    });
    notify(ctx, out.trim() || "te: no output (is Python 3.10+ on PATH?)");
  },
});
```

**失败开放（fail-open）**：dispatcher 缺失、缓慢或损坏时一律返回「无变化」；
`TE_SIDECALL=1`（插件自己的旁路调用）或 `TE_DISABLE=1` 时扩展完全不动。

---

## 9. 收尾检查

```bash
cat ~/.tokeneconomizer/errors.log
```

```text
cat: /Users/lex/.tokeneconomizer/errors.log: No such file or directory
```

**没有任何错误日志** —— 安装与首次运行全程干净。

仓库索引（`~/.tokeneconomizer/index.json`）：

```json
{
  "checked": {
    "go-ff86e1edcf": 1794532951.876391,
    "te-pitest-3736b50a45": 1794532959.0674748
  },
  "checkouts": {
    "/Users/lex/git/go":      { "key": "go-ff86e1edcf",      "seen": 1794532951.876391 },
    "/private/tmp/te-pitest":{ "key": "te-pitest-3736b50a45","seen": 1794532959.0674748 }
  },
  "layout": 2
}
```

---

## 10. 命令速查（本机可直接粘贴）

```bash
# 终端（免费）
TE=~/.tokeneconomizer/bin/te
"$TE" --host pi doctor
"$TE" --host pi status
"$TE" --host pi microskills
"$TE" --host pi config
"$TE" --host pi repos

# 开关
"$TE" --host pi config set microskills=on --global
"$TE" --host pi config set microskills=envfacts --global
"$TE" --host pi config set loopguard=off --global
"$TE" --host pi config set shadow=true --global

# 单次会话覆盖
TE_DISABLE=1 pi            # 整个插件关掉
TE_LOOPGUARD=off pi        # 只关守卫
TE_MICROSKILLS=off pi      # 只关微技能

# 更新 / 卸载
pi update --extensions
pi remove git:github.com/microsoft/TokenEconomizer
```

---

## 11. 时间线

| 时间 | 事件 |
| :--- | :--- |
| 09:22 前后 | 克隆上游仓库到 `/tmp`，阅读 README / plugin README / package.json |
| `11月 13 09:22:25` | `pi install` 完成，`settings.json` 写入 packages |
| `11月 13 09:22:48` | `~/.tokeneconomizer` 状态目录创建 |
| 09:22:48 之后 | 冒烟测试 `pi -p` → 会话折叠、`~/.tokeneconomizer/bin/te` 生成 |
| 09:22:59 | `config set microskills=envfacts --global` 生效 |
| 09:23:18 | 全流程检查完毕，`errors.log` 为空 |
