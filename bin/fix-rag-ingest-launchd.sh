#!/usr/bin/env bash
# fix-rag-ingest-launchd.sh
# 把 com.lex.rag-ingest 从 LaunchAgent (gui/501) 迁到 LaunchDaemon (system)
# 原因: LaunchAgent 依赖 GUI session，02:00 机器 DarkWake 时 launchd 不会 spawn。
# 改 LaunchDaemon 后无 GUI session 依赖，dark wake 也会触发。
#
# 用法: 手动 sudo 跑一次
#   sudo /Users/lex/git/knowledge/bin/fix-rag-ingest-launchd.sh
set -euo pipefail

SRC="$HOME/Library/LaunchAgents/com.lex.rag-ingest.plist"
DST="/Library/LaunchDaemons/com.lex.rag-ingest.plist"

[[ -f "$SRC" ]] || { echo "✗ 源 plist 不存在: $SRC"; exit 1; }

echo "▶ 1/4  unload 原 LaunchAgent (gui/501)"
launchctl bootout gui/501/com.lex.rag-ingest 2>/dev/null || true

echo "▶ 2/4  写新 plist 到 /Library/LaunchDaemons/"
cat > "$DST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lex.rag-ingest</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Users/lex/.local/bin/uv</string>
        <string>run</string>
        <string>--project</string>
        <string>/Users/lex/git/rag</string>
        <string>scripts/run_ingest.sh</string>
    </array>

    <key>WorkingDirectory</key>
    <string>/Users/lex/git/rag</string>

    <key>RunAtLoad</key>
    <false/>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>2</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>

    <key>StandardOutPath</key>
    <string>/tmp/rag-ingest-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/rag-ingest-stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/Users/lex/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>/Users/lex</string>
        <key>USER</key>
        <string>lex</string>
    </dict>
</dict>
</plist>
PLIST

echo "▶ 3/4  修正权限 (root:wheel, 644) + lint"
chown root:wheel "$DST"
chmod 644 "$DST"
plutil -lint "$DST"

echo "▶ 4/4  bootstrap 新 daemon"
launchctl bootstrap system "$DST"
sleep 1
launchctl print system/com.lex.rag-ingest | head -5

echo ""
echo "✓ 完成。明早 02:00 会自动跑 (不再依赖 GUI session)。"
echo "  验证: tail -f /tmp/rag-ingest-stdout.log"
