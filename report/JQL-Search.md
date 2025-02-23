我对 Jira REST API 的 /search 端点和 JQL 查询还不太熟悉，特别是如何通过 JQL 查询不同的条件、日期、关键字等内容。详细讲解 JQL 查询的基础知识，并提供大量示例，帮助我理解如何通过不同的查询条件获取 Jira 数据。所有示例都可以直接用于 /search 端点。



JQL（Jira Query Language）是 Jira 提供的一种查询语言，用于在 Jira 中进行复杂的搜索和筛选。它允许你基于各种条件（如日期、状态、关键字等）查询 Jira 的问题（Issues）。

  

**JQL 查询基础**

  

JQL 查询由字段、操作符和值组成，查询条件通过 “AND” 或 “OR” 连接。例如：

• **字段**：如 status, assignee, priority, created, updated 等。

• **操作符**：如 =, !=, >, <, IN, NOT IN, ~（模糊匹配）等。

• **值**：字段的实际值，如状态（Open, Done），日期（2025-01-01），用户（john.doe）等。

  

**常用的 JQL 查询示例**

  

**1. 查找指定状态的问题**

```
status = "To Do"
```

查找所有状态为 “To Do” 的问题。

  

**2. 查找指定人员分配的问题**

```
assignee = "john.doe"
```

查找分配给用户 “john.doe” 的所有问题。

  

**3. 查找多个状态的问题**

```
status IN ("To Do", "In Progress")
```

查找状态为 “To Do” 或 “In Progress” 的所有问题。

  

**4. 查找某个项目中的问题**

```
project = "MyProject"
```

查找项目 “MyProject” 中的所有问题。

  

**5. 查找创建日期在特定日期范围内的问题**

```
created >= "2025-01-01" AND created <= "2025-02-01"
```

查找在 2025年1月1日 到 2025年2月1日 之间创建的所有问题。

  

**6. 查找包含特定关键字的问题**

```
summary ~ "login issue"
```

查找问题标题中包含 “login issue” 的所有问题。

  

**7. 查找优先级为高的未解决问题**

```
priority = "High" AND resolution = Unresolved
```

查找优先级为高且尚未解决的问题。

  

**8. 查找更新日期在过去 7 天内的问题**

```
updated >= -7d
```

查找在过去 7 天内被更新过的问题。

  

**9. 查找某个类型的已关闭问题**

```
type = Bug AND status = "Closed"
```

查找类型为 “Bug” 且状态为 “Closed” 的所有问题。

  

**10. 查找特定版本中的问题**

```
fixVersion = "1.0.0"
```

查找已修复版本为 “1.0.0” 的问题。

  

**11. 查找自定义字段满足条件的问题**

```
"Custom Field" = "Some Value"
```

查找自定义字段 “Custom Field” 值为 “Some Value” 的问题。

  

**12. 查找过去一周内的所有问题**

```
created >= -1w
```

查找过去一周内创建的所有问题。

  

**13. 查找已解决且未关闭的问题**

```
resolution = Fixed AND status != "Closed"
```

查找已解决但状态不是 “Closed” 的问题。

  

**结合多个条件**

  

JQL 允许你组合多个条件，使用 AND 或 OR 连接条件。

  

**14. 查找状态为 “To Do” 且分配给某人的问题**

```
status = "To Do" AND assignee = "john.doe"
```

查找状态为 “To Do” 且分配给 “john.doe” 的问题。

  

**15. 查找优先级为高或紧急的问题**

```
priority IN ("High", "Urgent")
```

查找优先级为 “High” 或 “Urgent” 的问题。

  

**16. 查找过去一个月内创建并且优先级为高的问题**

```
created >= -1M AND priority = "High"
```

查找过去一个月内创建且优先级为高的问题。

  

**17. 查找某个项目中由特定人处理的未解决问题**

```
project = "MyProject" AND assignee = "john.doe" AND resolution = Unresolved
```

查找项目 “MyProject” 中，分配给 “john.doe” 且尚未解决的问题。

  

**日期查询**

  

JQL 支持相对日期查询，可以使用 -1d, -1w, -1M 等，表示过去一天、过去一周、过去一个月。

  

**18. 查找过去 24 小时内创建的问题**

```
created >= -1d
```

查找过去 24 小时内创建的所有问题。

  

**19. 查找过去 30 天内的所有问题**

```
created >= -30d
```

查找过去 30 天内创建的所有问题。

  

**20. 查找某个日期之后未解决的问题**

```
created >= "2025-01-01" AND resolution = Unresolved
```

查找在 2025年1月1日 后创建且尚未解决的问题。

  

**使用 ORDER BY 排序结果**

  

JQL 查询的结果可以通过 ORDER BY 子句进行排序。

  

**21. 按创建日期排序问题**

```
project = "MyProject" ORDER BY created DESC
```

查找项目 “MyProject” 中的所有问题，并按创建日期降序排序。

  

**22. 按优先级排序问题**

```
priority = "High" ORDER BY priority DESC
```

查找优先级为高的所有问题，并按优先级降序排序。

  

**23. 按更新日期排序**

```
ORDER BY updated DESC
```

查找所有问题，并按更新时间降序排序。

  

**使用 /search 端点查询**

  

你可以将 JQL 查询作为参数传递给 /search 端点来获取 Jira 数据。例如，使用以下的 curl 请求来查询所有状态为 “To Do” 的问题：

```
curl -X GET \
  'https://your-jira-instance.atlassian.net/rest/api/3/search?jql=status="To Do"' \
  -H 'Authorization: Bearer your_api_token' \
  -H 'Content-Type: application/json'
```

**总结**

  

通过 JQL，你可以灵活地查询 Jira 中的问题，利用字段、操作符、值以及逻辑操作符组合出复杂的查询条件。你可以根据需要调整查询以获取特定的数据，并通过 /search 端点将这些查询集成到 API 请求中。


---

1. 什么是 Jira REST API 的 /search 端点？

- 用途：通过 JQL（Jira Query Language，Jira 查询语言）来搜索 Jira 中的 issue（问题、任务等）。
    
- 请求方法：GET
    
- URL 示例：https://your-domain.atlassian.net/rest/api/3/search
    
- 主要参数：
    
    - jql：JQL 查询字符串，用于指定过滤条件。
        
    - fields：指定返回的字段，例如 key,summary,description,status。
        
    - maxResults：返回的最大 issue 数量（默认 50，最大 1000）。
        
    - startAt：分页参数，用于获取更多结果。
        

通过 /search 端点，你可以使用 JQL 查询来灵活地获取符合特定条件的 issue 数据。下面我会通过大量示例，展示如何查询不同的条件、日期、关键字等。

---

1. JQL 查询基础

JQL 的语法类似于 SQL，主要由以下部分组成：

- 字段：如 project（项目）、status（状态）、assignee（分配人）等。
    
- 操作符：如 =（等于）、!=（不等于）、IN（在...中）、NOT IN（不在...中）、<（小于）、>（大于）等。
    
- 值：如文本、日期、用户等。
    
- 逻辑操作符：AND（与）、OR（或）。
    
- 函数：如 currentUser()（当前用户）、startOfDay()（今天开始时间）等。
    

---

1. JQL 查询示例

以下是大量 JQL 查询示例，涵盖了不同的查询条件、日期、关键字等场景。你可以将这些 JQL 查询字符串直接传递给 /search 端点的 jql 参数。

3.1 按项目查询

- 查询特定项目中的所有 issue：
    
    jql
    
    ```text
    project = "My Project"
    ```
    
    - 说明：查询项目名为 "My Project" 的所有 issue。
        
- 查询多个项目中的 issue：
    
    jql
    
    ```text
    project IN ("Project A", "Project B")
    ```
    
    - 说明：查询项目 "Project A" 和 "Project B" 中的所有 issue。
        
- 查询不属于某个项目的 issue：
    
    jql
    
    ```text
    project != "Project C"
    ```
    
    - 说明：查询不属于 "Project C" 的 issue。
        

---

3.2 按状态查询

- 查询特定状态的 issue：
    
    jql
    
    ```text
    status = "In Progress"
    ```
    
    - 说明：查询状态为 "In Progress" 的 issue。
        
- 查询不在某个状态的 issue：
    
    jql
    
    ```text
    status != "Closed"
    ```
    
    - 说明：查询状态不是 "Closed" 的 issue。
        
- 查询多个状态的 issue：
    
    jql
    
    ```text
    status IN ("Open", "In Progress", "Resolved")
    ```
    
    - 说明：查询状态为 "Open"、"In Progress" 或 "Resolved" 的 issue。
        
- 查询状态为 "Open" 或 "In Progress" 的 issue（使用 OR）：
    
    jql
    
    ```text
    status = "Open" OR status = "In Progress"
    ```
    
    - 说明：与上面的 IN 查询效果相同，但使用 OR 更直观。
        

---

3.3 按分配人查询

- 查询分配给当前用户的 issue：
    
    jql
    
    ```text
    assignee = currentUser()
    ```
    
    - 说明：查询分配给当前登录用户的 issue。
        
- 查询未分配的 issue：
    
    jql
    
    ```text
    assignee IS EMPTY
    ```
    
    - 说明：查询没有分配人的 issue。
        
- 查询分配给特定用户的 issue：
    
    jql
    
    ```text
    assignee = "john.doe"
    ```
    
    - 说明：查询分配给用户 "john.doe" 的 issue。
        
- 查询分配给多个用户的 issue：
    
    jql
    
    ```text
    assignee IN ("john.doe", "jane.smith")
    ```
    
    - 说明：查询分配给 "john.doe" 或 "jane.smith" 的 issue。
        

---

3.4 按日期查询

日期查询是 JQL 中非常常用的场景，以下是不同类型的日期查询示例。

- 查询在特定日期之后创建的 issue：
    
    jql
    
    ```text
    created >= "2023-01-01"
    ```
    
    - 说明：查询在 2023 年 1 月 1 日或之后创建的 issue。
        
- 查询在特定日期范围内更新的 issue：
    
    jql
    
    ```text
    updated >= "2023-10-01" AND updated <= "2023-10-31"
    ```
    
    - 说明：查询在 2023 年 10 月更新的 issue。
        
- 查询过去 N 天更新的 issue：
    
    jql
    
    ```text
    updated >= -7d
    ```
    
    - 说明：查询过去 7 天内更新的 issue。-7d 表示过去 7 天，d 可以替换为：
        
        - w：周（例如 -2w 表示过去 2 周）
            
        - m：月（例如 -1m 表示过去 1 个月）
            
        - y：年（例如 -1y 表示过去 1 年）
            
- 查询过去 1 天更新的 issue（类似于你提到的示例）：
    
    jql
    
    ```text
    updated >= -1d
    ```
    
    - 说明：查询过去 1 天内更新的 issue。
        
- 查询今天创建的 issue：
    
    jql
    
    ```text
    created >= startOfDay()
    ```
    
    - 说明：查询今天创建的 issue。startOfDay() 返回当天的开始时间。
        
- 查询本周创建的 issue：
    
    jql
    
    ```text
    created >= startOfWeek()
    ```
    
    - 说明：查询本周创建的 issue。startOfWeek() 返回本周的开始时间。
        
- 查询本月创建的 issue：
    
    jql
    
    ```text
    created >= startOfMonth()
    ```
    
    - 说明：查询本月创建的 issue。startOfMonth() 返回本月的开始时间。
        
- 查询过去 30 天内创建且未解决的 issue：
    
    jql
    
    ```text
    created >= -30d AND resolution IS EMPTY
    ```
    
    - 说明：查询过去 30 天内创建且 resolution 为空（未解决）的 issue。
        

---

3.5 按关键字查询

关键字查询可以用于在 issue 的 summary（概要）、description（描述）、comment（评论）等字段中搜索特定文本。

- 在 summary 或 description 中搜索关键字：
    
    jql
    
    ```text
    summary ~ "error" OR description ~ "error"
    ```
    
    - 说明：查询 summary 或 description 中包含 "error" 的 issue。~ 表示模糊匹配。
        
- 在 comment 中搜索关键字：
    
    jql
    
    ```text
    comment ~ "urgent"
    ```
    
    - 说明：查询 comment 中包含 "urgent" 的 issue。
        
- 精确匹配 summary：
    
    jql
    
    ```text
    summary = "Fix login issue"
    ```
    
    - 说明：查询 summary 完全匹配 "Fix login issue" 的 issue。
        
- 在多个字段中搜索关键字：
    
    jql
    
    ```text
    (summary ~ "bug" OR description ~ "bug" OR comment ~ "bug")
    ```
    
    - 说明：查询 summary、description 或 comment 中包含 "bug" 的 issue。
        
- 排除某个关键字：
    
    jql
    
    ```text
    summary !~ "test"
    ```
    
    - 说明：查询 summary 中不包含 "test" 的 issue。!~ 表示不包含。
        

---

3.6 按 issue 类型查询

- 查询特定 issue 类型的 issue：
    
    jql
    
    ```text
    issuetype = "Bug"
    ```
    
    - 说明：查询类型为 "Bug" 的 issue。
        
- 查询多个 issue 类型的 issue：
    
    jql
    
    ```text
    issuetype IN ("Task", "Story")
    ```
    
    - 说明：查询类型为 "Task" 或 "Story" 的 issue。
        
- 查询不是某种类型的 issue：
    
    jql
    
    ```text
    issuetype != "Sub-task"
    ```
    
    - 说明：查询类型不是 "Sub-task" 的 issue。
        

---

3.7 按优先级查询

- 查询高优先级的 issue：
    
    jql
    
    ```text
    priority = "High"
    ```
    
    - 说明：查询优先级为 "High" 的 issue。
        
- 查询优先级高于某个级别的 issue：
    
    jql
    
    ```text
    priority > "Medium"
    ```
    
    - 说明：查询优先级高于 "Medium" 的 issue（假设优先级顺序为 Blocker > Critical > High > Medium > Low）。
        
- 查询多个优先级的 issue：
    
    jql
    
    ```text
    priority IN ("High", "Critical")
    ```
    
    - 说明：查询优先级为 "High" 或 "Critical" 的 issue。
        

---

3.8 按自定义字段查询

如果你的 Jira 实例中有自定义字段（custom fields），也可以通过 JQL 查询。

- 查询自定义字段的值：
    
    jql
    
    ```text
    cf[10000] = "Value"
    ```
    
    - 说明：查询自定义字段（ID 为 10000）的值为 "Value" 的 issue。cf[10000] 是自定义字段的标识符。
        
- 查询自定义字段为空的 issue：
    
    jql
    
    ```text
    cf[10001] IS EMPTY
    ```
    
    - 说明：查询自定义字段（ID 为 10001）为空的 issue。
        
- 查询自定义字段为特定值的 issue：
    
    jql
    
    ```text
    cf[10002] IN ("Option A", "Option B")
    ```
    
    - 说明：查询自定义字段（ID 为 10002）的值为 "Option A" 或 "Option B" 的 issue。
        

---

3.9 组合查询

通过 AND、OR 和括号，可以组合多个条件，构建复杂的查询。

- 查询分配给当前用户且状态为 "In Progress" 的 issue：
    
    jql
    
    ```text
    assignee = currentUser() AND status = "In Progress"
    ```
    
    - 说明：使用 AND 组合多个条件。
        
- 查询项目为 "My Project" 且（状态为 "Open" 或 "In Progress"）的 issue：
    
    jql
    
    ```text
    project = "My Project" AND (status = "Open" OR status = "In Progress")
    ```
    
    - 说明：使用括号控制逻辑优先级。
        
- 查询过去 7 天内创建、状态为 "Open" 且分配给当前用户的 issue：
    
    jql
    
    ```text
    created >= -7d AND status = "Open" AND assignee = currentUser()
    ```
    
    - 说明：组合日期、状态和分配人条件。
        
- 查询项目为 "My Project" 且（类型为 "Bug" 或 summary 中包含 "error"）的 issue：
    
    jql
    
    ```text
    project = "My Project" AND (issuetype = "Bug" OR summary ~ "error")
    ```
    
    - 说明：组合项目、类型和关键字条件。
        

---

3.10 排序

查询结果可以通过 ORDER BY 子句排序。

- 按创建日期降序排序：
    
    jql
    
    ```text
    project = "My Project" ORDER BY created DESC
    ```
    
    - 说明：查询 "My Project" 中的 issue，并按创建日期降序排序。
        
- 按优先级升序排序：
    
    jql
    
    ```text
    status = "Open" ORDER BY priority ASC
    ```
    
    - 说明：查询状态为 "Open" 的 issue，并按优先级升序排序。
        
- 按更新日期降序排序：
    
    jql
    
    ```text
    updated >= -7d ORDER BY updated DESC
    ```
    
    - 说明：查询过去 7 天内更新的 issue，并按更新日期降序排序。
        

---

1. 在 API 请求中使用 JQL

假设你已经有了 Jira 的 API 访问权限（需要 email 和 API token），以下是一个 Python 示例，展示如何通过 /search 端点使用 JQL 查询。

示例代码

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

# 示例 JQL 查询：过去 7 天内更新的、状态为 "In Progress" 的 issue
jql_query = 'updated >= -7d AND status = "In Progress"'

params = {
    "jql": jql_query,
    "fields": "key,summary,description,status,updated",
    "maxResults": 100
}

response = requests.get(jira_url, headers=auth_header, params=params)
if response.status_code == 200:
    jira_data = response.json()
    for issue in jira_data['issues']:
        print(f"Key: {issue['key']}, Summary: {issue['fields']['summary']}")
else:
    print(f"请求失败: {response.status_code}")
```

说明

- 将 jql_query 替换为你想查询的 JQL 字符串（例如上面提到的任何一个示例）。
    
- fields 参数指定返回的字段，可以根据需要调整。
    
- 如果查询结果较多，可能会需要分页处理（通过 startAt 和 maxResults 参数）。
    

---

1. 更多资源

- Jira JQL 官方文档：https://support.atlassian.com/jira-software-cloud/docs/use-advanced-search-with-jira-query-language-jql/
    
- Jira REST API 文档：https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-jql/
    

---

1. 总结

通过以上大量的 JQL 查询示例，你应该能够灵活地根据项目、状态、分配人、日期、关键字、issue 类型、优先级、自定义字段等条件，构建适合自己需求的查询。这些 JQL 查询都可以直接用于 Jira REST API 的 /search 端点。如果你有更多具体的需求或问题，欢迎随时提问！