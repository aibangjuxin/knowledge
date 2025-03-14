
- flow
```mermaid
sequenceDiagram
    participant API as API服务
    participant BQ as BigQuery
    participant Scheduler as 定时任务调度器
    
    Note over API,BQ: 数据获取和更新阶段
    Scheduler->>Scheduler: 触发定时任务
    Scheduler->>API: 请求Bug数据
    API-->>Scheduler: 返回Bug数据
    Scheduler->>BQ: 写入/更新 emid_tier 表
    
    Note over BQ: 数据比较阶段
    BQ->>BQ: 执行SQL查询
    Note right of BQ: WITH子句合并三个平台的Bug数据
    Note right of BQ: 1. google平台的Bug数据
    Note right of BQ: 2. aliyun平台的Bug数据
    Note right of BQ: 3. aws平台的Bug数据
    
    BQ->>BQ: 与API数据(emid_tier表)进行LEFT JOIN
    BQ->>BQ: 使用CASE语句比较优先级
    Note right of BQ: 判断结果类型:
    Note right of BQ: - MATCH (完全匹配)
    Note right of BQ: - MISSING_FROM_API (API中未找到)
    Note right of BQ: - MISSING_FROM_JIRA (JIRA中未找到)
    Note right of BQ: - MISMATCH (优先级不匹配)
    
    BQ->>BQ: 按platform和eimId排序结果

```
---
```mermaid
sequenceDiagram
    participant User
    participant Scheduled Task
    participant API Data Source
    participant BigQuery (emid_tier)
    participant BigQuery (Jira Tables)
    participant SQL Query Engine

    User->Scheduled Task: Request Data Update & Comparison (Implicitly)
    Scheduled Task->API Data Source: Fetch API Data (e.g., /emid_tier_api)
    API Data Source->Scheduled Task: Return API Data
    Scheduled Task->BigQuery: Update/Insert API Data into emid_tier
    Scheduled Task->SQL Query Engine: Trigger SQL Query Execution
    SQL Query Engine->BigQuery (Jira Tables): Read Data from Jira Tables (gcp_jira_info, aliyun_jira_info, aws_jira_info)
    SQL Query Engine->BigQuery (emid_tier): Read Data from emid_tier
    SQL Query Engine->SQL Query Engine: Execute Comparison SQL
    SQL Query Engine->User: Return Comparison Results
```

```bash
#!/bin/bash
# 文件路径
EIMID_FILE="eimld-uniq.txt"
# 输出文件
OUTPUT_FILE="output.txt"
# 未找到数据的记录文件
NOT_FOUND_FILE="not_found.txt"

# 检查输入文件是否存在
if [ ! -f "$EIMID_FILE" ]; then
    echo "错误：输入文件 $EIMID_FILE 不存在"
    exit 1
fi

# 清空输出文件
> "$OUTPUT_FILE"
> "$NOT_FOUND_FILE"

# 读取 eimld-uniq.txt 文件中的每一行
while IFS= read -r eimld; do
    echo "Processing eimld: $eimld"
    
    # 使用 eimld 获取 ServiceId
    response=$(curl -s -X 'GET' \
        "https://apiurl/v2/appId=$eimld&ServiceId=-1" \
        -H 'accept: application/json')
    
    # 检查curl是否成功执行
    if [ $? -ne 0 ]; then
        echo "错误：API调用失败 - $eimld"
        echo "$eimld,API_CALL_FAILED" >> "$NOT_FOUND_FILE"
        continue
    fi
    
    # 检查response是否为空
    if [ -z "$response" ]; then
        echo "错误：API返回空响应 - $eimld"
        echo "$eimld,EMPTY_RESPONSE" >> "$NOT_FOUND_FILE"
        continue
    fi
    
    ServiceId=$(echo "$response" | jq -r '.results[0].ServiceId')
    
    if [ "$ServiceId" != "null" ] && [ ! -z "$ServiceId" ]; then
        echo "ServiceId: $ServiceId"
        
        # 使用 ServiceId 获取 pladaCriticality
        response=$(curl -s -X 'GET' \
            "https://apiurl/v1/$ServiceId" \
            -H 'accept: application/json')
        
        pladaCriticality=$(echo "$response" | jq -r '.results[0].pladaCriticality')
        
        if [ "$pladaCriticality" != "null" ] && [ ! -z "$pladaCriticality" ]; then
            echo "pladaCriticality: $pladaCriticality"
            # 将结果写入输出文件
            echo "$eimld,$ServiceId,$pladaCriticality" >> "$OUTPUT_FILE"
        else
            echo "pladaCriticality not found for ServiceId: $ServiceId"
            echo "$eimld,$ServiceId,NO_CRITICALITY" >> "$NOT_FOUND_FILE"
        fi
    else
        echo "ServiceId not found for eimld: $eimld"
        echo "$eimld,NO_SERVICE_ID" >> "$NOT_FOUND_FILE"
    fi
done < "$EIMID_FILE"

echo "处理完成。"
echo "成功结果保存在: $OUTPUT_FILE"
echo "未找到数据的记录保存在: $NOT_FOUND_FILE"
```