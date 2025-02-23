
- [Q](#q)
- [回答](#回答)
- [JQL](#jql)
# Q 
我现在有这样一个需求

1 通过Jira的过滤条件，获取到我想要的一些Jira的信息,比如标题.里面关键字段的信息 我手动是可以导出为csv或者xml文件的

如果想自动获取这些企业内部自己的Jira数据,那么有什么好的解决办法?可能需要登录或者拿到对应的Token才能通过过滤条件获取到这些数据

2 我想将对应的数据插入到Google的igquery中

3 然后通过Google的Looker Studio来做一些统计分析

请帮我提供对应的解决办法,特别是第一步这个操作?

我的任务有些不太一样.需要提供的不是一个一次性任务的导出方式?其实我更期待是这样的工作方式. 比如我有一个计划任务,查询一段时间的Jira Tickets,然后通过我的过滤条件,拿到我想要的数据,把数据灌入到Bigquery里面.这样能实现一个简单的自动化步骤.相当于一个增量的过程.

帮我Review这个流量我现在有这样一个问题,我的JQL查询出来的都是一些比如key对应的value多数都是一对一,或者一对多比较有规律的.但是偶尔会有比如一个Key叫Describtion 里面对应来value1 value2 value3其三个值可能存在排序不一致的问题,那么我放入到bigquery里面 怎么记录比较好.因为后面我可能需要拿这些条件去写SQL 我是直接插入数据的时候去判断还是写SQL的时候来单独处理?

而且我这同一个在不同的时间运行的时候,可能拿到的数据不一样,因为比如我原来的Jira Tickets会更新字段和状态.而这个语句拿到是当前的Jira Tickets的状态.

- [ ] User Jira sql Resutl
- [ ] Create a Bigquery table

# 回答

针对你的需求，我们需要解决以下几个问题：

1. 如何自动化获取企业内部 Jira 数据并通过 JQL 过滤条件获取所需信息。
    
2. 如何将数据增量插入到 BigQuery 中，并处理 description 字段中可能存在的不一致排序问题。
    
3. 如何处理 Jira Tickets 数据随时间更新的情况。
    
4. 最终通过 Google Looker Studio 进行统计分析。
    

以下是详细的解决办法，重点解决你的自动化需求和 description 字段的处理问题。

---

1. 自动化获取 Jira 数据

你希望通过定时任务定期获取 Jira 数据，并通过 JQL 过滤条件获取所需信息，具体流程如下：

1.1 认证和 API 调用

- 认证方式：
    
    - Jira 通常需要认证才能访问 API，推荐使用 API Token 进行认证。
        
    - 在 Jira 中生成 API Token：
        
        1. 登录 Jira，进入“账户设置” → “安全” → “创建和管理 API Token”。
            
        2. 生成 Token 并保存，注意不要泄露。
            
    - 使用 Token 和你的 Jira 账户邮箱进行 Basic Authentication。
        
    - 示例认证字符串：email:token，将其编码为 Base64 格式，用于 API 请求头。
        
- Jira API 请求：
    
    - 使用 Jira REST API 获取数据，推荐使用 /search 端点，通过 JQL 查询获取数据。
        
    - 示例 JQL 查询：updated >= -1d（获取过去 1 天更新的数据）。
        
    - API 请求示例（Python 代码，使用 requests 库）：
        
        python
        
        ```python
        import requests
        from requests.auth import HTTPBasicAuth
        import base64
        
        jira_url = "https://your-domain.atlassian.net/rest/api/3/search"
        email = "your-email@example.com"
        api_token = "your-api-token"
        auth_string = f"{email}:{api_token}"
        auth_header = {
            "Authorization": f"Basic {base64.b64encode(auth_string.encode()).decode()}"
        }
        
        jql_query = "updated >= -1d"  # 过去1天更新的数据
        params = {
            "jql": jql_query,
            "fields": "key,summary,description,status"  # 指定需要的字段
        }
        
        response = requests.get(jira_url, headers=auth_header, params=params)
        jira_data = response.json()
        ```
        

1.2 增量同步

- 记录上次同步时间：
    
    - 在本地文件或数据库中记录上次同步的时间戳（last_sync_time）。
        
    - 每次运行脚本时，读取 last_sync_time，并在 JQL 查询中添加条件，如 updated >= last_sync_time。
        
    - 示例代码：
        
        python
        
        ```python
        import json
        from datetime import datetime
        
        # 读取上次同步时间
        try:
            with open("last_sync_time.json", "r") as f:
                last_sync_time = json.load(f)["timestamp"]
        except FileNotFoundError:
            last_sync_time = "1970-01-01 00:00:00"  # 初始时间
        
        # 更新 JQL 查询
        jql_query = f"updated >= '{last_sync_time}'"
        
        # 在数据插入成功后更新时间戳
        with open("last_sync_time.json", "w") as f:
            json.dump({"timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}, f)
        ```
        
- 定时任务：
    
    - 使用 cron 任务或调度工具（如 Airflow）定期触发 Python 脚本。
        
    - 示例 cron 配置（每天凌晨 1 点运行）：
        
        ```text
        0 1 * * * /usr/bin/python3 /path/to/your_script.py
        ```
        

---

1. 数据插入到 BigQuery

你需要将 Jira 数据插入到 BigQuery 中，并特别处理 description 字段中可能存在的不一致排序问题。

2.1 数据模型设计

- 字段定义：
    
    - 在 BigQuery 中，创建一个表，包含以下字段（根据你的需求调整）：
        
        - key（STRING）：Jira Ticket 的唯一标识。
            
        - summary（STRING）：标题。
            
        - description（STRING）：描述字段。
            
        - status（STRING）：状态。
            
        - updated（TIMESTAMP）：更新时间。
            
    - 示例 BigQuery 表创建语句：
        
        sql
        
        ```sql
        CREATE TABLE your_dataset.jira_tickets (
            key STRING,
            summary STRING,
            description STRING,
            status STRING,
            updated TIMESTAMP
        );
        ```
        
- 处理 description 字段：
    
    - 问题描述：
        
        - description 字段可能包含多个值（如 value1 value2 value3），且顺序不一致。
            
        - 你需要在 BigQuery 中存储这些数据，并能够在 SQL 查询中处理。
            
    - 推荐存储方式：
        
        - 将 description 字段作为一个 STRING 类型存储，内容为原始文本。
            
        - 如果 description 字段内部包含多个子项（如以逗号分隔的列表），可以在插入数据前进行预处理（如排序）。
            
    - 预处理示例：
        
        - 在 Python 脚本中，假设 description 是 value1,value2,value3，可以排序后存储：
            
            python
            
            ```python
            description = "value1,value2,value3"
            sorted_description = ",".join(sorted(description.split(",")))
            # 插入 sorted_description 到 BigQuery
            ```
            
        - 如果不需要排序，可以直接存储原始值。
            
    - 结构化存储（可选）：
        
        - 如果 description 字段包含结构化数据（如 JSON），可以存储为 STRING 类型，并在查询时使用 JSON 函数解析。
            
        - 如果你需要频繁处理子项，可以将 description 解析为数组，存储为 ARRAY<STRING> 类型。
            

2.2 数据插入

- 插入方式：
    
    - 使用 Google Cloud Client Library for Python 将数据插入到 BigQuery。
        
    - 示例代码：
        
        python
        
        ```python
        from google.cloud import bigquery
        
        client = bigquery.Client()
        table_id = "your_project.your_dataset.jira_tickets"
        
        rows_to_insert = [
            {
                "key": "JIRA-123",
                "summary": "Example ticket",
                "description": "value1,value2,value3",
                "status": "Open",
                "updated": "2023-10-01 12:00:00"
            }
        ]
        
        errors = client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            print(f"插入失败: {errors}")
        else:
            print("插入成功")
        ```
        
- 处理更新：
    
    - 由于 Jira Tickets 的字段和状态会随时间更新，每次运行脚本获取的是当前快照。
        
    - 使用 key 作为主键，在 BigQuery 中使用 MERGE 语句更新现有记录。
        
    - 示例 MERGE 语句：
        
        sql
        
        ```sql
        MERGE your_dataset.jira_tickets T
        USING (SELECT 'JIRA-123' AS key, 'Updated summary' AS summary, 'value2,value1,value3' AS description, 'Closed' AS status, '2023-10-02 12:00:00' AS updated) S
        ON T.key = S.key
        WHEN MATCHED THEN
            UPDATE SET summary = S.summary, description = S.description, status = S.status, updated = S.updated
        WHEN NOT MATCHED THEN
            INSERT (key, summary, description, status, updated)
            VALUES (S.key, S.summary, S.description, S.status, S.updated);
        ```
        

---

1. 处理 description 字段的排序问题

- 插入时处理：
    
    - 如果你希望在插入数据时解决排序问题，可以在 Python 脚本中对 description 字段进行预处理（如上文提到的排序）。
        
    - 优点：数据存储后已经规范化，查询时无需额外处理。
        
    - 缺点：如果排序规则变化，需要重新处理历史数据。
        
- 查询时处理：
    
    - 如果你希望保留原始数据，可以在 SQL 查询中处理排序问题。
        
    - 示例查询（假设 description 是以逗号分隔的字符串）：
        
        sql
        
        ```sql
        SELECT key, ARRAY_AGG(value ORDER BY value) AS sorted_description
        FROM your_dataset.jira_tickets
        CROSS JOIN UNNEST(SPLIT(description, ",")) AS value
        GROUP BY key;
        ```
        
    - 优点：灵活性高，可以根据需要调整排序规则。
        
    - 缺点：查询复杂度增加，可能影响性能。
        
- 推荐方案：
    
    - 如果排序规则固定，建议在插入时处理。
        
    - 如果排序规则可能变化，建议在查询时处理。
        

---

1. 数据分析（Looker Studio）

- 连接 BigQuery：
    
    - 在 Looker Studio 中添加数据源，选择 BigQuery，并连接到你的 jira_tickets 表。
        
- 创建报表：
    
    - 使用 Looker Studio 的图表功能，基于 key、description、status 等字段生成统计分析。
        
    - 示例：统计状态分布、按 description 子项进行分组等。
        
- 处理 description 字段：
    
    - 如果 description 是以逗号分隔的字符串，可以在 Looker Studio 中使用计算字段进行拆分和排序。
        
    - 示例计算字段：
        
        ```text
        ARRAY_AGG(SPLIT(description, ","))
        ```
        

---

1. 完整流程（参考序列图）

你的序列图已经很好地描述了自动化流程，以下是补充说明：

- 定时任务：
    
    - 使用 cron 或 Airflow 触发 Python 脚本，推荐每天或每小时运行。
        
- 增量同步：
    
    - 通过 last_sync_time 控制 JQL 查询范围，确保只获取新数据。
        
- 错误处理：
    
    - 在脚本中记录错误日志（如插入失败、API 请求失败），并发送通知。
        
- 数据一致性：
    
    - 使用 MERGE 语句确保数据更新时的一致性。
        
- 分析实时性：
    
    - Looker Studio 连接 BigQuery，支持实时查询和可视化。
        

---

1. 总结

- 自动化获取 Jira 数据：
    
    - 使用 Jira REST API 和 API Token 认证。
        
    - 通过 JQL 查询获取增量数据，记录 last_sync_time。
        
    - 使用 cron 或 Airflow 定时触发脚本。
        
- 处理 description 字段：
    
    - 插入时：对子项排序后存储为 STRING 类型。
        
    - 查询时：使用 SQL 函数（如 SPLIT、ARRAY_AGG）处理排序。
        
    - 推荐在插入时处理，以简化后续查询。
        
- 数据更新：
    
    - 使用 key 作为主键，结合 MERGE 语句处理更新。
        
- 数据分析：
    
    - 在 Looker Studio 中连接 BigQuery，创建报表和图表。
        

希望这个方案能帮助你实现自动化数据处理和分析！如果有进一步问题，欢迎随时讨论。


# JQL
- [jira-jql.md](./jira-jql.md)