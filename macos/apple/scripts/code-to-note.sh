#!/bin/bash

# 专门用于代码文件的笔记创建工具
# 使用方法: ./code-to-note.sh "笔记标题" "文件路径"

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

echo "📄 Creating code note: $TITLE"
echo "📁 From file: $FILE_PATH"

# 检测文件类型
FILE_EXT="${FILE_PATH##*.}"
case $FILE_EXT in
    sh|bash) LANG="Shell Script" ;;
    js) LANG="JavaScript" ;;
    py) LANG="Python" ;;
    md) LANG="Markdown" ;;
    json) LANG="JSON" ;;
    yaml|yml) LANG="YAML" ;;
    *) LANG="Text File" ;;
esac

# 创建临时文件，添加代码块格式
TEMP_FILE="/tmp/code-note-$(date +%s).txt"

cat > "$TEMP_FILE" << EOF
📄 File: $FILE_PATH
🔤 Type: $LANG
📊 Size: $(wc -c < "$FILE_PATH") bytes
🔢 Lines: $(wc -l < "$FILE_PATH")
📅 Created: $(date)

--- Code Content ---

EOF

# 添加原始代码内容
cat "$FILE_PATH" >> "$TEMP_FILE"

# 添加结尾
cat >> "$TEMP_FILE" << EOF

--- End of Code ---
💡 Original file: $FILE_PATH
EOF

# 使用 AppleScript 创建笔记
osascript << EOF
tell application "Notes"
    set codeContent to read (POSIX file "$TEMP_FILE") as «class utf8»
    make new note with properties {name:"$TITLE", body:codeContent}
end tell
EOF

RESULT=$?
rm -f "$TEMP_FILE"

if [ $RESULT -eq 0 ]; then
    echo "✅ Code note created successfully: $TITLE"
    echo "🎯 Language: $LANG"
    echo "📊 Lines: $(wc -l < "$FILE_PATH")"
else
    echo "❌ Failed to create code note"
fi