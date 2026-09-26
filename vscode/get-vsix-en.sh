#!/bin/zsh

ITEM_ID="${1:-}"
if [ -z "$ITEM_ID" ]; then
  echo "❌ 用法错误: 请提供插件完整标识符"
  echo "💡 示例: ./get-vsix.sh hediet.vscode-drawio"
  exit 1
fi

PUBLISHER="${ITEM_ID%%.*}"
EXTENSION="${ITEM_ID#*.}"

echo "🔍 正在查询 [publisher: $PUBLISHER, extension: $EXTENSION] 的最新版本..."

API_URL="https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"

PAYLOAD=$(
  cat <<EOF
{
  "filters": [
    {
      "criteria": [
        { "filterType": 7, "value": "$ITEM_ID" }
      ]
    }
  ],
  "assetTypes": [],
  "flags": 914
}
EOF
)

RESPONSE=$(curl -s -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json; api-version=3.0-preview.1" \
  -d "$PAYLOAD")

VERSION=$(echo "$RESPONSE" | jq -r '.results[0].extensions[0].versions[0].version // empty')

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
  echo "❌ 未能找到该插件，请检查插件名称是否正确（格式应为 publisher.extension）。"
  exit 1
fi

VSIX_URL="https://${PUBLISHER}.gallery.vsassets.io/_apis/public/gallery/publisher/${PUBLISHER}/extension/${EXTENSION}/${VERSION}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

# 定义规范的本地文件名
OUT_FILENAME="${EXTENSION}-${VERSION}.vsix"

echo ""
echo "✨ 成功获取最新直链："
echo "--------------------------------------------------"
echo "📦 插件名称: $ITEM_ID"
echo "🔖 最新版本: $VERSION"
echo "🔗 下载地址: $VSIX_URL"
echo "--------------------------------------------------"
echo "💡 建议直接使用以下命令下载并自动重命名："
echo "   curl -o \"$OUT_FILENAME\" \"$VSIX_URL\""
echo ""
echo "📥 或者是直接下载到当前目录："
read "REPLY?是否现在开始自动下载并重命名为 $OUT_FILENAME ? (y/N) "
if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  echo "🚀 正在下载..."
  curl -# -o "$OUT_FILENAME" "$VSIX_URL"
  echo "✅ 下载完成！文件已保存为: $OUT_FILENAME"
fi
