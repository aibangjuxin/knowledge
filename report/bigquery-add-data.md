
# summary
- Sets up Jira API connection parameters (URL, token)
- define jql and encoded query
  - JQL
  - ENCODED_JQL=$(echo "$JQL" | jq -sRr @uri)
- Using search endpoint to get the total number of issues
  - https://your-jira-domain.atlassian.net/rest/api/2/search?jql=$ENCODED_JQL
- Using issue endpoint to get the details of each issue
  - https://your-jira-domain.atlassian.net/rest/api/2/issue/$KEY
- 上面是已经完成的几个步骤,我现在有这样一个问题,按照上面步骤,我每次查询比都是所有的数据,然后全部导入到bigquery中,有没有办法只导入新的,或者增量的
- 下面是几个想法? 通过最后的更新时间来获取比如最近7天的有状态更新的数据比如.issues[].key,然后用这个key通过issue接口获取详细信息,更新对应的bigquery表

# 

我看了你的问题，关于增量处理和Description字段的处理，我来给你提供一些建议。

## 关于增量处理

从你的流程图和需求描述来看，你已经有了基本的增量同步思路：使用`updated >= last_sync_time`的JQL查询来获取更新的数据。这是一个很好的方案，但还可以进一步优化：

### 1. 增量同步策略

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
import json
import datetime
import os
from google.cloud import bigquery

# 配置信息
JIRA_BASE_URL = "https://your-company.atlassian.net"
JIRA_API_TOKEN = "your-api-token"
JIRA_EMAIL = "your-email@company.com"
LAST_SYNC_FILE = "last_sync_time.txt"
PROJECT_ID = "your-gcp-project-id"
DATASET_ID = "jira_data"
TABLE_ID = "jira_issues"

def get_last_sync_time():
    """获取上次同步时间，如果不存在则返回7天前"""
    if os.path.exists(LAST_SYNC_FILE):
        with open(LAST_SYNC_FILE, 'r') as f:
            return f.read().strip()
    else:
        # 默认同步最近7天的数据
        seven_days_ago = (datetime.datetime.now() - datetime.timedelta(days=7)).strftime("%Y-%m-%d")
        return seven_days_ago

def update_sync_time():
    """更新同步时间为当前时间"""
    with open(LAST_SYNC_FILE, 'w') as f:
        f.write(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

def fetch_jira_data(last_sync_time):
    """从Jira获取更新的数据"""
    auth = (JIRA_EMAIL, JIRA_API_TOKEN)
    
    # 构建JQL查询 - 获取上次同步后更新的问题
    jql = f'project = YOUR_PROJECT AND updated >= "{last_sync_time}"'
    
    # 分页获取数据
    start_at = 0
    max_results = 100
    all_issues = []
    
    while True:
        url = f"{JIRA_BASE_URL}/rest/api/2/search"
        params = {
            "jql": jql,
            "startAt": start_at,
            "maxResults": max_results,
            "fields": "key,summary,description,status,updated,created,customfield_10000"  # 根据需要调整字段
        }
        
        response = requests.get(url, auth=auth, params=params)
        response.raise_for_status()
        
        data = response.json()
        issues = data.get("issues", [])
        if not issues:
            break
            
        all_issues.extend(issues)
        
        # 检查是否还有更多数据
        start_at += len(issues)
        if start_at >= data.get("total", 0):
            break
    
    return all_issues

def process_description_field(description):
    """处理描述字段，将其标准化为JSON数组"""
    if not description:
        return []
    
    # 假设描述字段包含多个值，需要分割和标准化
    # 这里的分割逻辑需要根据你的实际数据格式调整
    values = [v.strip() for v in description.split(',') if v.strip()]
    
    # 排序以确保一致性
    return sorted(values)

def insert_to_bigquery(issues):
    """将数据插入BigQuery"""
    client = bigquery.Client(project=PROJECT_ID)
    table_ref = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"
    
    rows_to_insert = []
    
    for issue in issues:
        fields = issue.get("fields", {})
        
        # 处理描述字段
        description = fields.get("description", "")
        description_values = process_description_field(description)
        
        row = {
            "issue_key": issue.get("key"),
            "summary": fields.get("summary"),
            "status": fields.get("status", {}).get("name"),
            "created_at": fields.get("created"),
            "updated_at": fields.get("updated"),
            "description_values": json.dumps(description_values),  # 存储为JSON字符串
            "sync_time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        
        rows_to_insert.append(row)
    
    # 使用upsert策略 - 如果记录已存在则更新
    job_config = bigquery.LoadJobConfig(
        schema=[
            bigquery.SchemaField("issue_key", "STRING"),
            bigquery.SchemaField("summary", "STRING"),
            bigquery.SchemaField("status", "STRING"),
            bigquery.SchemaField("created_at", "TIMESTAMP"),
            bigquery.SchemaField("updated_at", "TIMESTAMP"),
            bigquery.SchemaField("description_values", "STRING"),  # JSON字符串
            bigquery.SchemaField("sync_time", "TIMESTAMP")
        ],
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND
    )
    
    # 执行插入
    errors = client.insert_rows_json(table_ref, rows_to_insert, job_config=job_config)
    
    if errors:
        print(f"插入错误: {errors}")
        return False
    else:
        print(f"成功插入 {len(rows_to_insert)} 条记录")
        return True

def main():
    # 1. 获取上次同步时间
    last_sync_time = get_last_sync_time()
    print(f"获取上次同步时间: {last_sync_time}")
    
    # 2. 从Jira获取数据
    issues = fetch_jira_data(last_sync_time)
    print(f"获取到 {len(issues)} 条更新的记录")
    
    if not issues:
        print("没有新的更新，结束同步")
        return
    
    # 3. 插入数据到BigQuery
    success = insert_to_bigquery(issues)
    
    # 4. 如果成功，更新同步时间
    if success:
        update_sync_time()
        print("同步完成，已更新同步时间")

if __name__ == "__main__":
    main()
```

### 2. 关于Description字段的处理

对于Description这种多值且顺序不固定的字段，我建议在数据插入时进行处理，而不是在SQL查询时处理。原因是：

1. **数据一致性**：在插入时处理可以确保数据的一致性
2. **查询效率**：预处理后的数据查询更高效
3. **简化分析**：使Looker Studio的分析工作更简单

#### 具体处理方法：

1. **JSON数组存储**：
   - 将多个值排序后存储为JSON数组
   - 在BigQuery中可以使用JSON函数进行查询

```sql
-- 查询示例
SELECT 
  issue_key, 
  summary,
  JSON_EXTRACT_ARRAY(description_values) as values
FROM `your-project.dataset.jira_issues`
WHERE JSON_QUERY(description_values, "$[0]") = "value1"
  OR JSON_QUERY(description_values, "$[1]") = "value1";
```

2. **历史记录处理**：
   - 每次同步时添加时间戳
   - 保留历史记录以便追踪变化

```sql
-- 查询最新状态
SELECT * FROM (
  SELECT 
    issue_key,
    summary,
    status,
    description_values,
    ROW_NUMBER() OVER (PARTITION BY issue_key ORDER BY sync_time DESC) as rn
  FROM `your-project.dataset.jira_issues`
) 
WHERE rn = 1;
```

这样的设计既能满足增量同步的需求，又能妥善处理Description字段的多值问题，同时还保留了历史记录以便追踪变化。