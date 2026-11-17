# 导出 VS Code / Cursor 已安装扩展列表(Export Installed VS Code Extensions)

> 把本机已经安装好的 VS Code(或 Cursor)插件列表导出成可以粘贴、可以 diff、可以重建的多种格式。同一个脚本,五种输出,覆盖日常 90% 的需求。

适用平台:**Linux / macOS**。Windows 可以在 WSL 或 Git Bash 下运行。

---

## 1. 为什么需要导出?(Why export?)

- **重装系统后批量还原** — 不要一个一个搜 marketplace
- **跨机器同步** — 把主力开发机的插件清单搬到一个新机器上
- **Dotfiles 管理** — 把"我的环境"作为代码纳入版本控制
- **审计 / 文档** — 团队 Onboarding 文档里直接列出每个工程师用了什么插件
- **诊断环境差异** — 两台机器表现不一致时,先比对插件列表是不是源头

---

## 2. 两种数据源 — 你要先知道(CLI vs extensions.json)

VS Code / Cursor 提供两种方式拿到扩展清单,但**它们返回的数量不同**:

| 数据源 | 命令 | 返回数量 | 包含被禁用的扩展? | 需要额外依赖 |
|---|---|---|---|---|
| CLI | `code --list-extensions` | **仅启用的** | ❌ 否 | `code` 命令在 PATH 里 |
| 文件 | `~/.vscode/extensions/extensions.json` | **全部已安装** | ✅ 是 | `jq` |

**实测差异**(2026-07-04 在我的机器上):

```
$ code --list-extensions | wc -l       →  13   (启用的)
$ jq 'length' ~/.vscode/extensions/extensions.json   →  24   (含禁用的)
```

**Cursor 注意**:macOS 上 `/usr/local/bin/code` 通常是指向 Cursor 的 shim(因为 Cursor 是 VS Code 的 fork,CLI 表面一致)。脚本不做区分,两者都能用。

**Linux 注意**:VS Code 在 Linux 上的 extensions.json 默认在 `~/.vscode/extensions/`,不是 `~/.config/Code/`(那个是 Stable 用户态配置)。脚本会自动找 `~/.vscode/`、`~/.cursor/` 两个常见路径。

---

## 3. 一键脚本(`export-vscode-plug.sh`)

放在仓库的 `linux/tools/` 目录,本机用:

```bash
# 名字(一行一个,纯净)
./export-vscode-plug.sh

# 名字@版本(用于精确还原)
./export-vscode-plug.sh --with-versions

# CSV 一行(便于 shell 循环)
./export-vscode-plug.sh --csv

# Markdown 表格(直接贴到文档/wiki)
./export-vscode-plug.sh --table

# 一键重装命令(用 jq 读取 extensions.json,所以带版本号)
./export-vscode-plug.sh --install-cmd

# 原始 JSON(用于脚本二次处理)
./export-vscode-plug.sh --json

# 写到文件(任意 mode 都支持 --out)
./export-vscode-plug.sh --with-versions --out my-plugins.txt
```

**参数速查**

| 参数 | 输出格式 | 数据源 | 包含禁用 |
|---|---|---|---|
| (无) | `publisher.name` 一行一条 | CLI | ❌ |
| `--with-versions` | `publisher.name@version` | CLI | ❌ |
| `--csv` | `a,b,c,...` | CLI | ❌ |
| `--table` | markdown 表格(对齐) | JSON 文件 | ✅ |
| `--json` | 原始 JSON | JSON 文件 | ✅ |
| `--install-cmd` | `code --install-extension ...@...` 一行一条 | JSON 文件 | ✅ |
| `--out FILE` | 把当前 mode 的输出写到 FILE | — | — |
| `--help` / `-h` | 帮助 | — | — |

**依赖**:`bash 3.2+`, `paste`, `column`(`--table` 需要),`jq`(`--table / --json / --install-cmd` 需要)。其它什么都没装。

---

## 4. 使用场景示例(Real-world recipes)

### 4.1 新机器批量安装 — 最常见场景

```bash
# 在源机器导出
./export-vscode-plug.sh --install-cmd > install-plugins.sh
cat install-plugins.sh    # 看一下长啥样

# 把 install-plugins.sh 拷到目标机器,执行
bash install-plugins.sh
```

生成的文件长这样:

```text
code --install-extension naumovs.color-highlight@2.8.0
code --install-extension inferrinizzard.prettier-sql-vscode@1.6.0
code --install-extension mathpix.vscode-mathpix-markdown@0.2.1
...
```

### 4.2 对比两台机器的插件差异

```bash
# 两台机器都跑一遍
./export-vscode-plug.sh --with-versions --out plugins-mac.txt
# (在另一台跑同样命令,得到 plugins-linux.txt)

# diff
diff plugins-mac.txt plugins-linux.txt
```

### 4.3 写进 dotfiles 仓库做版本管理

```bash
./export-vscode-plug.sh --with-versions --out vscode-plugins.lock
git add vscode-plugins.lock
git commit -m "chore: lock vscode plugin versions @ 2026-07-04"
```

### 4.4 写进团队 Onboarding 文档

```bash
./export-vscode-plug.sh --table >> team-onboarding.md
```

直接产生:

```text
id (publisher.name)                     version
-------------------                     -------
naumovs.color-highlight                 2.8.0
inferrinizzard.prettier-sql-vscode      1.6.0
mathpix.vscode-mathpix-markdown         0.2.1
...
```

### 4.5 用 shell 循环做单插件操作

```bash
# 把所有插件全部禁用
./export-vscode-plug.sh --csv | tr ',' '\n' | while read ext; do
  code --disable-extension "$ext"
done

# 检查某个 publisher 的所有插件是否都装了
./export-vscode-plug.sh | grep '^ms-python'
```

---

## 5. 完整脚本源码(`export-vscode-plug.sh`)

```bash
#!/usr/bin/env bash
# export-vscode-plug.sh
#
# Export the list of installed VS Code / Cursor extensions in formats you can
# paste elsewhere. Tested on macOS (Bash 3.2 / Bash 5.x) and Linux (Bash 4+).
#
# Usage:
#   ./export-vscode-plug.sh                  # names only (one per line)
#   ./export-vscode-plug.sh --with-versions  # name@version, one per line
#   ./export-vscode-plug.sh --csv            # comma-separated for shell loops
#   ./export-vscode-plug.sh --table          # markdown table (name, publisher, version)
#   ./export-vscode-plug.sh --install-cmd    # `code --install-extension ...` commands
#   ./export-vscode-plug.sh --json           # raw JSON from extensions/extensions.json
#   ./export-vscode-plug.sh --out FILE       # write to FILE instead of stdout
#
# Notes:
#   - The `code` CLI on macOS may point at Cursor.app (a VS Code fork). Both
#     expose the same `--list-extensions` surface, so this script works for
#     either. The `--json` variant reads ~/.vscode/extensions/extensions.json
#     directly to bypass any CLI quirks.
#   - Run with --help for usage.
#
# Exit codes:
#   0 = success
#   1 = neither `code` nor an extensions.json found
#   2 = bad CLI args

set -euo pipefail

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for --json / --table / --install-cmd. Install with:" >&2
    echo "  brew install jq          # macOS" >&2
    echo "  apt-get install -y jq    # Debian/Ubuntu" >&2
    echo "  yum install -y jq        # RHEL/Fedora" >&2
    exit 1
  fi
}

MODE="names"
OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --with-versions) MODE="versions" ;;
    --csv) MODE="csv" ;;
    --table) MODE="table"; require_jq ;;
    --json) MODE="json" ;;
    --install-cmd) MODE="install-cmd"; require_jq ;;
    --out) OUT="${2:-}"; shift ;;
    *) echo "unknown arg: $1" >&2; usage 2 ;;
  esac
  shift
done

# Where does `code` resolve to?
CODE_BIN="$(command -v code 2>/dev/null || true)"
EXT_JSON=""
[[ -f "$HOME/.vscode/extensions/extensions.json" ]] && EXT_JSON="$HOME/.vscode/extensions/extensions.json"
[[ -z "$EXT_JSON" && -f "$HOME/.cursor/extensions/extensions.json" ]] && EXT_JSON="$HOME/.cursor/extensions/extensions.json"

run() {
  if [[ -n "$OUT" ]]; then
    "$@" > "$OUT"
    echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
  else
    "$@"
  fi
}

case "$MODE" in
  names)
    if [[ -n "$CODE_BIN" ]]; then
      run "$CODE_BIN" --list-extensions
    elif [[ -n "$EXT_JSON" ]]; then
      jq -r '.[].identifier.id' "$EXT_JSON"
    else
      echo "no \`code\` CLI and no extensions.json found" >&2; exit 1
    fi
    ;;
  versions)
    if [[ -n "$CODE_BIN" ]]; then
      run "$CODE_BIN" --list-extensions --show-versions
    elif [[ -n "$EXT_JSON" ]]; then
      jq -r '.[] | "\(.identifier.id)@\(.version)"' "$EXT_JSON"
    else
      echo "no \`code\` CLI and no extensions.json found" >&2; exit 1
    fi
    ;;
  csv)
    if [[ -n "$CODE_BIN" ]]; then
      CMD="$CODE_BIN --list-extensions"
    else
      CMD="jq -r '.[].identifier.id' $EXT_JSON"
    fi
    if [[ -n "$OUT" ]]; then
      bash -c "$CMD" | paste -sd ',' - > "$OUT"
      echo "wrote $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
    else
      bash -c "$CMD" | paste -sd ',' -
    fi
    ;;
  json)
    require_jq
    if [[ -n "$EXT_JSON" ]]; then
      run jq '.' "$EXT_JSON"
    elif [[ -n "$CODE_BIN" ]]; then
      echo "no extensions.json found; \`code --list-extensions\` doesn't emit JSON" >&2
      exit 1
    else
      echo "no \`code\` CLI and no extensions.json found" >&2; exit 1
    fi
    ;;
  table)
    require_jq
    run jq -r '
      ["id (publisher.name)","version"],
      ["-------------------","-------"],
      (.[] | [.identifier.id, .version])
      | @tsv
    ' "$EXT_JSON" | column -t -s $'\t'
    ;;
  install-cmd)
    require_jq
    run jq -r '.[] | "code --install-extension \(.identifier.id)@\(.version)"' "$EXT_JSON"
    ;;
esac
```

---

## 6. 踩坑实录(Pitfalls — things that look broken but aren't)

### 6.1 `code` 命令找不到 / 报"command not found"

VS Code 在 macOS 上**不会自动把 `code` 加入 PATH**。第一次要在 VS Code 里按 `Cmd+Shift+P` → 输入 "Shell Command: Install 'code' command in PATH"。Linux 上如果你用 .deb 装的 VS Code,这个是默认装好的;Snap / Flatpak / 手动 tarball 则不一定,需要自己软链到 `/usr/local/bin/`。

Cursor 同理,首次安装时勾选 "Install 'cursor' command"。

### 6.2 macOS 上 `code` 指向 Cursor 而不是 VS Code

```bash
$ which code
/usr/local/bin/code
$ ls -l /usr/local/bin/code
... /Applications/Cursor.app/Contents/Resources/app/bin/code
```

这不是 bug,是 macOS 上 `code` 这个名字被 Cursor 抢注了(shim 同名)。**两种产品都能用 `code --list-extensions`**,功能一致;扩展文件夹分别在不同位置(`~/.vscode/extensions/` 和 `~/.cursor/extensions/`),互不影响。如果你要严格区分,**建议重命名软链**:

```bash
ln -sf "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" /usr/local/bin/vscode
ln -sf "/Applications/Cursor.app/Contents/Resources/app/bin/code" /usr/local/bin/cursor
```

然后脚本里把 `CODE_BIN` 手动指向你想要的版本。

### 6.3 `code --list-extensions` 和 extensions.json 数量不一致(13 vs 24)

参见 §2。**禁用扩展** 在 extensions.json 里有,但 CLI 不列。脚本对 `names/versions/csv` 三个 mode 优先用 CLI(因为这通常是"我正在用的"清单);对 `table/json/install-cmd` 优先用 JSON 文件(因为这需要 version 字段)。如果想让 CLI mode 也包含禁用扩展,临时禁用再启用重置即可;长期方案是直接读 JSON。

### 6.4 Linux 上 extensions.json 不在 `~/.vscode/`

- **标准 .deb / .rpm 安装**:在 `~/.vscode/extensions/`
- **Snap 安装**:在 `~/snap/code/common/.vscode/extensions/`
- **Flatpak 安装**:在 `~/.var/app/com.visualstudio.code/data/vscode/extensions/`
- **手动 tarball**:由 `--extensions-dir` 启动参数决定

脚本只检查 `~/.vscode/` 和 `~/.cursor/`。如果你用 Snap / Flatpak,改一下 `EXT_JSON` 那一行,或者用 `find` 帮你定位:

```bash
find ~ -name extensions.json -path '*/extensions/*' 2>/dev/null
```

### 6.5 `--table` 在没有 `column` 命令的环境上失败

极少数精简 Linux(Alpine 等 coreutils BusyBox 版)没有 GNU `column`。装 `coreutils` 包,或者把 `| column -t -s $'\t'` 这一段换成 `column -t`(BSD column 也认 `-s`,只是分隔符语法略不同)。

### 6.6 `code --install-extension name@version` 不会降级

如果你在源机器用的是 2.8.0,目标机器已经装了 2.9.0,跑 `code --install-extension xxx@2.8.0` 不会自动降级 — 它会提示"already installed"。要强制降级要先 `code --uninstall-extension xxx` 再装。这种 case 用 dotfiles 管理 + 定时升级更省心。

---

## 7. 验证(Verification)

跑一遍五个 mode,任何报错都意味着脚本坏了:

```bash
cd /path/to/linux/tools
chmod +x export-vscode-plug.sh

./export-vscode-plug.sh | head -3           # 应输出 3 行 publisher.name
./export-vscode-plug.sh --with-versions | head -3   # 应有 @x.y.z
./export-vscode-plug.sh --csv | head -c 50 # 应是一行逗号分隔
./export-vscode-plug.sh --table | head -5  # 应是对齐的 markdown 表
./export-vscode-plug.sh --install-cmd | head -3  # 应是 `code --install-extension ...` 行
./export-vscode-plug.sh --json | jq '.[0].identifier.id'   # 应输出第一个插件 id
bash -n export-vscode-plug.sh && echo "syntax OK"
```

任意一步失败 → 看 §6 排查。如果 `code` 不在 PATH 且 extensions.json 也不存在 → `bash` 退出码 1 并报"no `code` CLI and no extensions.json found"。

---

## 8. 引用 / 相关(References)

- VS Code 官方: [Extension Marketplace](https://marketplace.visualstudio.com/vscode) — 通过 `publisher.name` 搜索
- Cursor 官方: [Cursor Directory](https://cursor.directory/) — Cursor 专属扩展目录
- `extensions.json` schema: <https://github.com/microsoft/vscode/blob/main/src/vs/platform/extensions/common/extensionsRegistry.ts>(无正式文档,以 `jq` 实际结构为准)
- 仓库位置: `linux/tools/export-vscode-plug.sh`(本仓库)