# sync-skills.py

把 Codex 之外的 skill 树（hermes profiles、opencode skills）暴露给 Codex。

## 为什么需要它

Codex 只扫描固定的几组根目录，**没有任何 config.toml 配置项可以新增目录**：

| 根目录 | 是否被扫描 | 说明 |
|---|---|---|
| `~/.codex/skills` | ✅ | 递归扫描，允许分类子目录 |
| `~/.agents/skills` | ✅ | agents 标准目录，递归扫描 |
| `~/.codex/plugins/cache/**` | ✅ | 已安装插件自带 |
| `<repo>/.codex/skills`、`<repo>/.agents/skills` | ✅ | 仓库级（scope=repo） |
| `~/.config/opencode/skills` | ❌ | opencode 的全局 skills |
| `~/.hermes/profiles/*/skills` | ❌ | hermes 各 profile 的 skills |

但 Codex **会跟随软链接**，所以在这些原生根目录里建软链接农场（symlink farm）是唯一稳定、可持久化的做法。

运行时还有一个 `skills/extraRoots/set` RPC 可以临时挂根目录，但**不持久化**（进程退出即失效），桌面端也没有调用入口，因此不采用。

## 用法

```bash
# 预演，不改文件系统
python3 bin/sync-skills.py --dry-run

# 应用（幂等）
python3 bin/sync-skills.py

# 应用 + 清理失效链接
python3 bin/sync-skills.py --prune

# 强制链接与原生重名的 skill（会与原生版本重复，不推荐）
python3 bin/sync-skills.py --force

# 自定义来源 / 目标
python3 bin/sync-skills.py --source ~/other/skills --dest ~/.codex/skills/external

# 机器可读输出
python3 bin/sync-skills.py --json
```

默认值：

- 来源：`~/.hermes/profiles/*/skills` + `~/.config/opencode/skills`
- 目标：`~/.codex/skills/external/`
- 环境变量覆盖：`SYNC_SKILLS_SOURCES`（冒号分隔）、`SYNC_SKILLS_DEST`、`CODEX_HOME`

## 去重规则

1. **源内重名**：同名只保留第一个（来源顺序 → 路径顺序）。
2. **与原生重名**：默认跳过，保留原生版本（`~/.agents/skills` 里的 google/skills 那批质量更高）。
3. 冲突清单写在 `~/.codex/skills/external/.sync-manifest.json`，含每个链接的来源路径。

如确实要用外部版本覆盖原生版本，用 `config.toml` 禁用原生那条：

```toml
[[skills.config]]
name = "gke-basics"
enabled = false
```

## 注意事项

- **YAML 必须是严格合法的**：frontmatter 任何一行写错（`"a" or "b"` 这种、tab 缩进、未闭合引号）都会让整个 skill 被 Codex 静默丢弃。脚本会把解析失败的条目报在 `invalid` 里。
- **修改后要新开会话**：skill 清单在会话启动时快照，跑完脚本后新开一个 Codex 会话才生效。
- 脚本用 `fcntl.flock` 做单实例锁（`~/.codex/.sync-skills.lock`），cron 与手动执行不会互相覆盖。

## 定时任务

每天凌晨 5 点同步（加进 `crontab -e`）：

```cron
0 5 * * * /opt/homebrew/bin/python3 /Users/lex/git/knowledge/bin/sync-skills.py --prune >> /Users/lex/.codex/logs/sync-skills.log 2>&1
```

创建日志目录并试跑一次：

```bash
mkdir -p /Users/lex/.codex/logs
/opt/homebrew/bin/python3 /Users/lex/git/knowledge/bin/sync-skills.py --prune >> /Users/lex/.codex/logs/sync-skills.log 2>&1
```

> macOS 的 cron 在机器睡眠时不会补跑错过的任务（错过超过 1 小时直接跳过）。如果需要更稳，用 `launchd`：
> `~/Library/LaunchAgents/com.lex.sync-skills.plist`，`StartCalendarInterval` 设 `Hour = 5`，`RunAtLoad = false`。
