#!/bin/zsh

# 配置你的目标仓库 (例如: "aibangjuxin/knowledge")
REPO="${1:-}"
if [ -z "$REPO" ]; then
  # 如果没传参，尝试自动检测当前目录的仓库
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  if [ -z "$REPO" ]; then
    echo "❌ 错误: 请指定仓库，如: ./gh-weekly-dashboard.sh owner/repo"
    exit 1
  fi
fi

echo "=================================================="
echo "📊 GitHub 仓库周报 Dashboard: $REPO"
echo "⏳ 正在拉取最近 7 天的提交与活动数据..."
echo "=================================================="

# 计算 7 天前的 ISO 8601 时间
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS 的 date 写法
  SINCE_DATE=$(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ')
else
  # Linux 的 date 写法
  SINCE_DATE=$(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ')
fi

# 修改后的写法：只提取日期，彻底避开 commit message 中的非法控制字符
COMMITS_JSON=$(gh api "repos/$REPO/commits?since=$SINCE_DATE&per_page=100" \
    --jq '[.[] | {date: (.commit.committer.date | split("T")[0])}]')

if [ $? -ne 0 ]; then
  echo "❌ 获取数据失败，请检查 gh 登录状态及仓库权限。"
  exit 1
fi

# 统计总数
TOTAL_COMMITS=$(echo "$COMMITS_JSON" | jq 'length')

echo ""
echo "📈 【核心指标概览】"
echo "  • 统计周期: 最近 7 天"
echo "  • 总提交次数 (Commits): $TOTAL_COMMITS"
echo ""

echo "📅 【每日提交频率分布】"
echo "--------------------------------------------------"

# 使用 jq 按日期分组并生成简易的 ASCII 柱状图
echo "$COMMITS_JSON" | jq -r '
    group_by(.date) | 
    map({date: .[0].date, count: length}) | 
    sort_by(.date) | 
    .[] | "\(.date) | \(.count)"
' | while IFS='|' read -r commit_date count; do
  count=$(echo "$count" | tr -d ' ')
  # 生成可视化柱状条 (每个 count 代表一个 █)
  bar=""
  for ((i = 0; i < count; i++)); do
    bar="${bar}█"
  done
  printf "  %s : %-3s %s\n" "$commit_date" "$count" "$bar"
done

echo "--------------------------------------------------"
echo "💡 提示: 你可以通过修改过滤条件来重点统计特定后缀的文件（如 .md, .yaml）"
