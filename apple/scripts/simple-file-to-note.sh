#!/bin/bash

# 最简单的文件到笔记转换
# 使用方法: ./simple-file-to-note.sh "笔记标题" "文件路径"

TITLE="$1"
FILE_PATH="$2"

if [ -z "$TITLE" ] || [ -z "$FILE_PATH" ]; then
    echo "Usage: $0 <note-title> <file-path>"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ File not found: $FILE_PATH"
    exit 1
fi

echo "📄 Creating note: $TITLE"
echo "📁 From file: $FILE_PATH"

# 方法1: 使用临时文件保持格式（适用于所有文件）
echo "📝 Creating note with preserved formatting..."

# 创建临时文件
TEMP_FILE="/tmp/note-content-$(date +%s).txt"

# 添加文件信息头部
cat > "$TEMP_FILE" << EOF
📄 File: $FILE_PATH
📊 Size: $(wc -c < "$FILE_PATH") bytes
📅 Date: $(date)
🔢 Lines: $(wc -l < "$FILE_PATH")

--- Original Content ---
EOF

# 直接追加原始文件内容（保持所有格式）
cat "$FILE_PATH" >> "$TEMP_FILE"

# 使用 AppleScript 从临时文件读取内容
osascript << EOF
tell application "Notes"
    set fileContent to read (POSIX file "$TEMP_FILE") as «class utf8»
    make new note with properties {name:"$TITLE", body:fileContent}
end tell
EOF

RESULT=\$?

# 清理临时文件
rm -f "$TEMP_FILE"

if [ \$RESULT -eq 0 ]; then
    echo "✅ Note created successfully with preserved formatting"
    exit 0
fi

# 方法2: 创建摘要版本（适用于大文件或复杂文件）
echo "📋 Creating summary version..."

SUMMARY="📄 File: $FILE_PATH
📊 Size: $FILE_SIZE bytes
📅 Date: $(date)
🔢 Lines: $(wc -l < "$FILE_PATH")

📝 First 10 lines:
$(head -10 "$FILE_PATH")

📝 Last 5 lines:
$(tail -5 "$FILE_PATH")

💡 Use 'cat $FILE_PATH' to view full content"

# 创建摘要的临时文件
SUMMARY_TEMP="/tmp/note-summary-$(date +%s).txt"
echo "$SUMMARY" > "$SUMMARY_TEMP"

osascript << EOF
tell application "Notes"
    set summaryContent to read (POSIX file "$SUMMARY_TEMP") as «class utf8»
    make new note with properties {name:"$TITLE (Summary)", body:summaryContent}
end tell
EOF

SUMMARY_RESULT=$?
rm -f "$SUMMARY_TEMP"

if [ $SUMMARY_RESULT -eq 0 ]; then
    echo "✅ Summary note created: $TITLE (Summary)"
else
    echo "❌ Failed to create note"
fi