#!/bin/bash

# 安全的文件到笔记转换脚本
# 使用方法: ./create-note-from-file.sh "笔记标题" "文件路径"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <note-title> <file-path>"
    exit 1
fi

TITLE="$1"
FILE_PATH="$2"

if [ ! -f "$FILE_PATH" ]; then
    echo "❌ File not found: $FILE_PATH"
    exit 1
fi

echo "📄 Creating note from file: $FILE_PATH"

# 创建临时文件来存储处理后的内容
TEMP_FILE="/tmp/notes-content-$(date +%s).txt"

# 创建文件信息头部
cat > "$TEMP_FILE" << EOF
File: $FILE_PATH
Size: $(wc -c < "$FILE_PATH") bytes
Lines: $(wc -l < "$FILE_PATH") lines
Created: $(date)

--- Content ---
EOF

# 添加文件内容到临时文件
cat "$FILE_PATH" >> "$TEMP_FILE"

# 使用 AppleScript 从临时文件创建笔记
osascript << EOF
tell application "Notes"
    set fileContent to read (POSIX file "$TEMP_FILE") as «class utf8»
    make new note with properties {name:"$TITLE", body:fileContent}
end tell
EOF

RESULT=$?

# 清理临时文件
rm -f "$TEMP_FILE"

if [ $RESULT -eq 0 ]; then
    echo "✅ Note created successfully: $TITLE"
    echo "📊 File size: $(wc -c < "$FILE_PATH") bytes"
else
    echo "❌ Failed to create note"
    echo "🔄 Trying alternative method..."
    
    # 备用方法：创建文件摘要
    SUMMARY="File: $FILE_PATH
Size: $(wc -c < "$FILE_PATH") bytes
Lines: $(wc -l < "$FILE_PATH") lines
Created: $(date)

First 20 lines:
$(head -20 "$FILE_PATH")

... (content truncated for safety)"
    
    osascript -e "tell application \"Notes\" to make new note with properties {name:\"$TITLE (Summary)\", body:\"$SUMMARY\"}"
    
    if [ $? -eq 0 ]; then
        echo "✅ Summary note created: $TITLE (Summary)"
    else
        echo "❌ All methods failed"
    fi
fi