#!/usr/bin/env bash
# fix-pi-tools.sh —— 把 Rex Markdown 运行时从 Pi 已废弃的 ~/.pi/tools/ 迁到 ~/.local/share/rex-markdown/
#
# 背景
#   Pi 启动时做一次迁移检查（源码：packages/coding-agent/src/migrations.ts → checkDeprecatedExtensionDirs）：
#     - 全局位：~/.pi/agent/tools/
#     - 项目位：<cwd>/.pi/tools/
#   该目录下只要存在 fd / rg 之外的条目（只看顶层条目名，不递归、不看扩展名），就打印：
#     Warning: Project tools/ directory contains custom tools.
#     Custom tools have been merged into extensions.
#
#   Pi 早已不再从 tools/ 加载自定义工具（resource-loader 只扫 extensions/ 目录），
#   所以 ~/.pi/tools/ 是纯遗留位置，继续放东西只会一直触发这条警告。
#
# 幂等：已迁移过则只跑校验并退出；可反复执行。
#
# 用法
#   bash fix-pi-tools.sh            # 实际执行
#   bash fix-pi-tools.sh --dry-run  # 只打印将要做的事
#
# 相关文档：./Rex-Markdown-tools-migration.md

set -euo pipefail

OLD_DIR="$HOME/.pi/tools/rex-markdown"
NEW_DIR="$HOME/.local/share/rex-markdown"
EXTENSION="$HOME/.pi/agent/extensions/rex-markdown.ts"
CHECK_SH="$HOME/.pi/agent/skills/rex-md-links/check.sh"
INFO_PLIST="$HOME/Applications/Rex Markdown.app/Contents/Info.plist"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

log()  { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n\033[36m==> %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY" = 1 ]; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

log "fix-pi-tools.sh —— Rex Markdown 运行时迁移到 ~/.local/share/rex-markdown/"
[ "$DRY" = 1 ] && warn "--dry-run：不会真的改动任何文件"

# --------------------------------------------------------------------------
step "0. 前置检查"
[ -f "$EXTENSION" ] || die "找不到扩展 $EXTENSION"

if   [ -f "$OLD_DIR/bridge.mjs" ]; then SOURCE_DIR="$OLD_DIR"
elif [ -f "$NEW_DIR/bridge.mjs" ]; then SOURCE_DIR="$NEW_DIR"
else die "两个位置都没有 bridge.mjs：$OLD_DIR / $NEW_DIR"; fi
ok "bridge.mjs 位于 $SOURCE_DIR"

if [ -f "$SOURCE_DIR/install.mjs" ] && ! command -v swiftc >/dev/null 2>&1; then
  warn "缺少 swiftc（Xcode CLT），第 5 步会跳过 URL handler 重装；"
  warn "那样的话手动跑：node $NEW_DIR/install.mjs"
fi

# --------------------------------------------------------------------------
step "1. 备份"
if [ "$SOURCE_DIR" = "$OLD_DIR" ]; then
  BACKUP="$HOME/.pi-tools-backup-$(date +%Y%m%dT%H%M%S)"
  run cp -a "$OLD_DIR" "$BACKUP"
  ok "备份 → $BACKUP"
else
  ok "已迁移过，跳过备份"
fi

# --------------------------------------------------------------------------
step "2. 搬运文件"
if [ "$SOURCE_DIR" = "$OLD_DIR" ]; then
  run mkdir -p "$NEW_DIR"
  run cp -a "$OLD_DIR/." "$NEW_DIR/"
  ok "已复制到 $NEW_DIR"
else
  ok "已在目标位置，跳过"
fi

# --------------------------------------------------------------------------
step "3. 改写扩展里的路径引用"
# 上游扩展用相对路径 new URL("../../tools/rex-markdown/bridge.mjs", source)；
# 迁移后必须改成绝对路径，否则 import 解析不到。
run node -e '
  const fs = require("node:fs");
  const file = process.argv[1];
  let s = fs.readFileSync(file, "utf8");
  const before = s;
  s = s.replace(
    /new URL\("\.\.\/\.\.\/tools\/rex-markdown\/bridge\.mjs", source\)\.href/g,
    "pathToFileURL(join(homedir(), \".local\", \"share\", \"rex-markdown\", \"bridge.mjs\")).href"
  );
  s = s.split("~/.pi/tools/rex-markdown").join("~/.local/share/rex-markdown");
  if (s !== before) fs.writeFileSync(file, s);
  console.log(s === before ? "    无需改动" : "    已更新");
' "$EXTENSION"
ok "扩展: $EXTENSION"

step "4. 改写 skill 自检脚本"
if [ -f "$CHECK_SH" ]; then
  run node -e '
    const fs = require("node:fs");
    const file = process.argv[1];
    const before = fs.readFileSync(file, "utf8");
    const after = before.split("$HOME/.pi/tools/rex-markdown").join("$HOME/.local/share/rex-markdown");
    if (after !== before) fs.writeFileSync(file, after);
    console.log(after === before ? "    无需改动" : "    已更新");
  ' "$CHECK_SH"
  ok "skill: $CHECK_SH"
else
  warn "跳过：$CHECK_SH 不存在"
fi

# --------------------------------------------------------------------------
step "5. 重装 URL handler（Info.plist 里写死了 open.mjs 的绝对路径）"
if command -v swiftc >/dev/null 2>&1; then
  if [ "$DRY" = 1 ]; then
    printf '  [dry-run] node %s/install.mjs\n' "$NEW_DIR"
  else
    (cd "$NEW_DIR" && node install.mjs)
  fi
  ok "已重装 ~/Applications/Rex Markdown.app"
else
  warn "跳过（无 swiftc）"
fi

# --------------------------------------------------------------------------
step "6. 清理旧目录"
if [ -d "$OLD_DIR" ]; then
  run rm -rf "$OLD_DIR"
  ok "已删除 $OLD_DIR"
fi
if [ -d "$HOME/.pi/tools" ]; then
  LEFT="$(find "$HOME/.pi/tools" -mindepth 1 -maxdepth 1 2>/dev/null | head -1)"
  if [ -z "$LEFT" ]; then
    run rmdir "$HOME/.pi/tools"
    ok "已删除空目录 ~/.pi/tools"
  else
    warn "~/.pi/tools 仍有内容，保留：$LEFT"
  fi
fi

# --------------------------------------------------------------------------
step "7. 校验"
[ "$DRY" = 1 ] && { log "dry-run 结束"; exit 0; }

[ ! -d "$HOME/.pi/tools" ] && ok "~/.pi/tools 已不存在（启动不再报警告）" \
                         || warn "~/.pi/tools 仍存在"

if [ -f "$NEW_DIR/bridge.mjs" ]; then
  node --input-type=module -e '
    const m = await import(process.argv[1]);
    const need = ["createTickets", "resolveMarkdownPath", "rewriteMarkdown"];
    const missing = need.filter((k) => typeof m[k] !== "function");
    if (missing.length) { console.error("    缺少导出: " + missing.join(", ")); process.exit(1); }
    console.log("    bridge.mjs 导出完整 ✓");
  ' "$NEW_DIR/bridge.mjs"
else
  die "$NEW_DIR/bridge.mjs 不存在"
fi

if [ -f "$INFO_PLIST" ]; then
  SCRIPT="$(plutil -extract RexMarkdownScript raw "$INFO_PLIST" 2>/dev/null || echo '')"
  case "$SCRIPT" in
    "$NEW_DIR"/*) ok "Info.plist → $SCRIPT" ;;
    "")          warn "Info.plist 里读不到 RexMarkdownScript" ;;
    *)           die "Info.plist 仍指向旧路径 $SCRIPT（需要重跑 install.mjs）" ;;
  esac
fi

if [ -f "$NEW_DIR/bridge.test.mjs" ]; then
  if (cd "$NEW_DIR" && node --test bridge.test.mjs >/dev/null 2>&1); then
    ok "bridge.test.mjs 全部通过"
  else
    warn "bridge.test.mjs 有失败项（详见 ./Rex-Markdown-tools-migration.md）"
  fi
fi

log "完成。重启 pi（或在会话里 /reload）即可生效。"
