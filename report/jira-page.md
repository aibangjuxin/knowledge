```bash
#!/bin/bash

# Configuration variables
JIRA_BASE_URL="https://abc.com/jira"
JIRA_TOKEN="your_jira_token" # Replace with your actual token
LAST_SYNC_FILE="last_sync_time.txt"
OUTPUT_DIR="./jira_data"
LOG_FILE="jira_sync.log"
MAX_RESULTS_PER_PAGE=100  # Maximum results per page (Jira API allows max 100)

# Create output directory
mkdir -p $OUTPUT_DIR

# Log message function
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

log_message "Starting Jira data sync task"

# Get last sync time, default to 3 days ago
if [ -f "$LAST_SYNC_FILE" ]; then
  LAST_SYNC=$(cat $LAST_SYNC_FILE)
  log_message "Read last sync time: $LAST_SYNC"
else
  LAST_SYNC="-3d"
  log_message "No previous sync record found, defaulting to last 3 days"
fi

# Build JQL query
JQL="project = \"Project Name\" AND updated >= $LAST_SYNC AND status not in (\"Cancelled\", \"On Hold\", \"POC Stage\")"
ENCODED_JQL=$(echo "$JQL" | jq -sRr @uri)

# Create temporary data file
echo "[]" > $OUTPUT_DIR/all_issues_keys.json

# Fetch all issues with pagination
START_AT=0
TOTAL=0
FIRST_PAGE=true

log_message "Executing Jira search query (with pagination): $JQL"

while true; do
  # Build URL with pagination parameters
  SEARCH_URL="$JIRA_BASE_URL/rest/api/2/search?jql=$ENCODED_JQL&startAt=$START_AT&maxResults=$MAX_RESULTS_PER_PAGE"
  
  # Get current page of issues
  log_message "Fetching page results: startAt=$START_AT, maxResults=$MAX_RESULTS_PER_PAGE"
  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
       -H "Content-type: application/json" \
       "$SEARCH_URL" > $OUTPUT_DIR/jira_search_page_$START_AT.json
  
  # Check if request was successful
  if [ $? -ne 0 ]; then
    log_message "Error: Jira search request failed, page startAt=$START_AT"
    exit 1
  fi
  
  # Extract current page issue keys and add to total list
  CURRENT_PAGE_KEYS=$(cat $OUTPUT_DIR/jira_search_page_$START_AT.json | jq -r '.issues[].key')
  
  # Append current page keys to total list file
  for KEY in $CURRENT_PAGE_KEYS; do
    echo "\"$KEY\"" >> $OUTPUT_DIR/temp_keys.txt
  done
  
  # Get total results and current page count
  TOTAL=$(cat $OUTPUT_DIR/jira_search_page_$START_AT.json | jq -r '.total')
  CURRENT_PAGE_COUNT=$(echo "$CURRENT_PAGE_KEYS" | grep -v "^$" | wc -l)
  
  log_message "Retrieved $CURRENT_PAGE_COUNT issues on current page, total $TOTAL issues"
  
  # Calculate next page start position
  START_AT=$((START_AT + CURRENT_PAGE_COUNT))
  
  # Exit loop if no more results or current page is empty
  if [ $START_AT -ge $TOTAL ] || [ $CURRENT_PAGE_COUNT -eq 0 ]; then
    break
  fi
done

# Merge all collected keys into a JSON array
cat $OUTPUT_DIR/temp_keys.txt|sed 's/"/"//g' > $OUTPUT_DIR/all_issues_keys.txt
cat $OUTPUT_DIR/all_issues_keys.txt|jq -R -s -c 'split("\n")' > $OUTPUT_DIR/all_issues_keys.json

# Clean up temporary files
rm -f $OUTPUT_DIR/temp_keys.txt

# Extract all issue numbers from merged JSON file
JIRA_KEYS=$(cat $OUTPUT_DIR/all_issues_keys.json | jq -r '.[]')
ISSUES_COUNT=$(echo "$JIRA_KEYS" | wc -l)
log_message "Found total of $ISSUES_COUNT matching issues"

# Record current time as sync time
CURRENT_TIME=$(date '+%Y-%m-%d')
echo $CURRENT_TIME > $LAST_SYNC_FILE

# Create temporary JSON file for BigQuery import
echo "[" > $OUTPUT_DIR/bigquery_data.json

# Iterate through each issue to get details
COUNTER=0
for KEY in $JIRA_KEYS; do
  COUNTER=$((COUNTER + 1))
  log_message "[$COUNTER/$ISSUES_COUNT] Getting issue details: $KEY"
  
  # Get issue details
  ISSUE_URL="$JIRA_BASE_URL/rest/api/2/issue/$KEY"
  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
       -H "Content-type: application/json" \
       "$ISSUE_URL" > $OUTPUT_DIR/issue_$KEY.json
  
  # Check if detail request was successful
  if [ $? -ne 0 ]; then
    log_message "Warning: Failed to get issue details for $KEY, skipping"
    continue
  fi
  
  # Process data - extract required fields
  # Use jq to extract needed fields and convert to BigQuery format
  jq -c '{
    key: .key,
    summary: .fields.summary,
    status: .fields.status.name,
    priority: .fields.priority.name,
    created_date: .fields.created,
    updated_date: .fields.updated,
    assignee: (.fields.assignee.displayName // "Unassigned"),
    reporter: .fields.reporter.displayName,
    story_points: (.fields.customfield_10002 // 0),
    issue_type: .fields.issuetype.name,
    resolution: (.fields.resolution.name // "Unresolved"),
    project: .fields.project.key,
    components: [.fields.components[].name],
    sprint: (.fields.customfield_10000[0].name // "No Sprint"),
    extract_date: "'$(date '+%Y-%m-%d')'"
  }' $OUTPUT_DIR/issue_$KEY.json >> $OUTPUT_DIR/bigquery_data.json
  
  # Add comma after each record (except the last one)
  if [ $COUNTER -lt $ISSUES_COUNT ]; then
    echo "," >> $OUTPUT_DIR/bigquery_data.json
  fi
done

# Complete JSON array
echo "]" >> $OUTPUT_DIR/bigquery_data.json

# Call BigQuery import command
log_message "Preparing to import data to BigQuery"

# BigQuery settings
BQ_PROJECT="your-gcp-project"
BQ_DATASET="jira_data"
BQ_TABLE="issues"

# Import to BigQuery (requires Google Cloud SDK installed and configured)
bq load --source_format=NEWLINE_DELIMITED_JSON \
  $BQ_PROJECT:$BQ_DATASET.$BQ_TABLE \
  $OUTPUT_DIR/bigquery_data.json \
  key:STRING,summary:STRING,status:STRING,priority:STRING,created_date:TIMESTAMP,updated_date:TIMESTAMP,assignee:STRING,reporter:STRING,story_points:FLOAT,issue_type:STRING,resolution:STRING,project:STRING,components:STRING,sprint:STRING,extract_date:DATE

# Check BigQuery import result
if [ $? -eq 0 ]; then
  log_message "Success: Data imported to BigQuery table $BQ_PROJECT:$BQ_DATASET.$BQ_TABLE"
else
  log_message "Error: BigQuery data import failed"
  exit 1
fi

log_message "Jira data sync task completed, processed $ISSUES_COUNT issues"

#!/bin/bash

# 配置变量
JIRA_BASE_URL="https://abc.com/jira"
JIRA_TOKEN="your_jira_token" # 请替换为你的实际token
LAST_SYNC_FILE="last_sync_time.txt"
OUTPUT_DIR="./jira_data"
LOG_FILE="jira_sync.log"
MAX_RESULTS_PER_PAGE=100  # 每页最多获取的结果数（Jira API允许最大100）

# 创建输出目录
mkdir -p $OUTPUT_DIR

# 记录日志函数
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

log_message "开始Jira数据同步任务"

# 获取上次同步时间，默认为3天前
if [ -f "$LAST_SYNC_FILE" ]; then
  LAST_SYNC=$(cat $LAST_SYNC_FILE)
  log_message "读取上次同步时间: $LAST_SYNC"
else
  LAST_SYNC="-3d"
  log_message "未找到上次同步记录，默认同步近3天数据"
fi

# 构建JQL查询
JQL="project = \"Project Name\" AND updated >= $LAST_SYNC AND status not in (\"Cancelled\", \"On Hold\", \"POC Stage\")"
ENCODED_JQL=$(echo "$JQL" | jq -sRr @uri)

# 创建临时数据文件
echo "[]" > $OUTPUT_DIR/all_issues_keys.json

# 分页获取所有票据
START_AT=0
TOTAL=0
FIRST_PAGE=true

log_message "执行Jira搜索查询（带分页）: $JQL"

while true; do
  # 构建带分页参数的查询URL
  SEARCH_URL="$JIRA_BASE_URL/rest/api/2/search?jql=$ENCODED_JQL&startAt=$START_AT&maxResults=$MAX_RESULTS_PER_PAGE"
  
  # 获取当前页的票据列表
  log_message "获取分页结果: startAt=$START_AT, maxResults=$MAX_RESULTS_PER_PAGE"
  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
       -H "Content-type: application/json" \
       "$SEARCH_URL" > $OUTPUT_DIR/jira_search_page_$START_AT.json
  
  # 检查请求是否成功
  if [ $? -ne 0 ]; then
    log_message "错误: Jira搜索请求失败，页码 startAt=$START_AT"
    exit 1
  fi
  
  # 提取当前页的票据编号并添加到总列表
  CURRENT_PAGE_KEYS=$(cat $OUTPUT_DIR/jira_search_page_$START_AT.json | jq -r '.issues[].key')
  
  # 将当前页的keys追加到总列表文件
  for KEY in $CURRENT_PAGE_KEYS; do
    echo "\"$KEY\"" >> $OUTPUT_DIR/temp_keys.txt
  done
  
  # 获取总结果数和当前页结果数
  TOTAL=$(cat $OUTPUT_DIR/jira_search_page_$START_AT.json | jq -r '.total')
  CURRENT_PAGE_COUNT=$(echo "$CURRENT_PAGE_KEYS" | grep -v "^$" | wc -l)
  
  log_message "当前页获取到 $CURRENT_PAGE_COUNT 个票据，总计 $TOTAL 个票据"
  
  # 计算下一页的起始位置
  START_AT=$((START_AT + CURRENT_PAGE_COUNT))
  
  # 如果没有更多结果或当前页为空，则退出循环
  if [ $START_AT -ge $TOTAL ] || [ $CURRENT_PAGE_COUNT -eq 0 ]; then
    break
  fi
done

# 将所有收集的keys合并为一个JSON数组

#cat $OUTPUT_DIR/temp_keys.txt | tr '\n' ',' | sed 's/,$//' >> $OUTPUT_DIR/all_issues_keys.json
cat $OUTPUT_DIR/temp_keys.txt|sed 's/"/"//g' > $OUTPUT_DIR/all_issues_keys.txt
cat $OUTPUT_DIR/all_issues_keys.txt|jq -R -s -c 'split("\n")' > $OUTPUT_DIR/all_issues_keys.json


# 清理临时文件
rm -f $OUTPUT_DIR/temp_keys.txt

# 从合并后的JSON文件中提取所有票据编号
JIRA_KEYS=$(cat $OUTPUT_DIR/all_issues_keys.json | jq -r '.[]')
ISSUES_COUNT=$(echo "$JIRA_KEYS" | wc -l)
log_message "总共找到 $ISSUES_COUNT 个符合条件的票据"

# 记录当前时间作为本次同步时间
CURRENT_TIME=$(date '+%Y-%m-%d')
echo $CURRENT_TIME > $LAST_SYNC_FILE

# 创建临时JSON文件用于BigQuery导入
echo "[" > $OUTPUT_DIR/bigquery_data.json

# 遍历每个票据获取详细信息
COUNTER=0
for KEY in $JIRA_KEYS; do
  COUNTER=$((COUNTER + 1))
  log_message "[$COUNTER/$ISSUES_COUNT] 获取票据详情: $KEY"
  
  # 获取票据详情
  ISSUE_URL="$JIRA_BASE_URL/rest/api/2/issue/$KEY"
  curl -s -H "Authorization: Bearer $JIRA_TOKEN" \
       -H "Content-type: application/json" \
       "$ISSUE_URL" > $OUTPUT_DIR/issue_$KEY.json
  
  # 检查详情请求是否成功
  if [ $? -ne 0 ]; then
    log_message "警告: 获取票据 $KEY 详情失败，跳过此票据"
    continue
  fi
  
  # 处理数据 - 提取所需字段
  # 使用jq提取需要的字段，并转换为适合BigQuery的格式
  jq -c '{
    key: .key,
    summary: .fields.summary,
    status: .fields.status.name,
    priority: .fields.priority.name,
    created_date: .fields.created,
    updated_date: .fields.updated,
    assignee: (.fields.assignee.displayName // "Unassigned"),
    reporter: .fields.reporter.displayName,
    story_points: (.fields.customfield_10002 // 0),
    issue_type: .fields.issuetype.name,
    resolution: (.fields.resolution.name // "Unresolved"),
    project: .fields.project.key,
    components: [.fields.components[].name],
    sprint: (.fields.customfield_10000[0].name // "No Sprint"),
    extract_date: "'$(date '+%Y-%m-%d')'"
  }' $OUTPUT_DIR/issue_$KEY.json >> $OUTPUT_DIR/bigquery_data.json
  
  # 在每个记录后面添加逗号（除了最后一个）
  if [ $COUNTER -lt $ISSUES_COUNT ]; then
    echo "," >> $OUTPUT_DIR/bigquery_data.json
  fi
done

# 完成JSON数组
echo "]" >> $OUTPUT_DIR/bigquery_data.json

# 调用BigQuery导入命令
log_message "准备导入数据到BigQuery"

# BigQuery设置
BQ_PROJECT="your-gcp-project"
BQ_DATASET="jira_data"
BQ_TABLE="issues"

# 导入BigQuery (需要安装并配置好Google Cloud SDK)
bq load --source_format=NEWLINE_DELIMITED_JSON \
  $BQ_PROJECT:$BQ_DATASET.$BQ_TABLE \
  $OUTPUT_DIR/bigquery_data.json \
  key:STRING,summary:STRING,status:STRING,priority:STRING,created_date:TIMESTAMP,updated_date:TIMESTAMP,assignee:STRING,reporter:STRING,story_points:FLOAT,issue_type:STRING,resolution:STRING,project:STRING,components:STRING,sprint:STRING,extract_date:DATE

# 检查BigQuery导入结果
if [ $? -eq 0 ]; then
  log_message "成功: 数据已导入BigQuery表 $BQ_PROJECT:$BQ_DATASET.$BQ_TABLE"
else
  log_message "错误: BigQuery数据导入失败"
  exit 1
fi

log_message "Jira数据同步任务完成，总共处理 $ISSUES_COUNT 个票据"
```