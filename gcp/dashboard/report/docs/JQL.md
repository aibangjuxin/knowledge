入门 Jira 查询语言 (JQL) 和 Jira REST API 的 `/search` 端点。JQL 是非常强大的工具，可以让你精确地从 Jira 中检索你想要的数据。让我们一步一步来学习。

**JQL 基础知识详解**

JQL (Jira Query Language) 是一种用于在 Jira 中搜索 issue 的强大查询语言。它类似于 SQL，但专门为 Jira 的 issue 跟踪系统设计。你可以使用 JQL 来定义复杂的搜索条件，例如：

* **项目 (Project):**  指定 issue 所属的项目。
* **Issue 类型 (Issue Type):**  例如任务、缺陷、故事等。
* **状态 (Status):**  例如待办、进行中、已完成等。
* **经办人 (Assignee):**  负责处理 issue 的用户。
* **报告人 (Reporter):**  创建 issue 的用户。
* **创建日期 (Created Date)、更新日期 (Updated Date)、解决日期 (Resolved Date)、截止日期 (Due Date):**  与 issue 时间相关的字段。
* **关键字 (Keywords):**  在 issue 的摘要、描述、评论等文本字段中搜索关键词。
* **标签 (Labels)、组件 (Components)、版本 (Versions):**  用于组织和分类 issue 的字段。
* **自定义字段 (Custom Fields):**  你可以在 Jira 中创建的自定义字段。

**JQL 的基本结构**

一个 JQL 查询通常由以下几个部分组成：

1. **字段 (Field):**  你要查询的 issue 属性，例如 `project`, `issuetype`, `status`, `assignee` 等。
2. **运算符 (Operator):**  定义字段和值之间的关系，例如 `=`, `!=`, `>`, `<`, `IN`, `NOT IN`, `CONTAINS`, `IS EMPTY` 等。
3. **值 (Value):**  你要搜索的具体值，例如项目名称、Issue 类型名称、用户名、日期、文本关键词等。
4. **关键字 (Keywords):**  用于组合多个条件或修改查询行为，例如 `AND`, `OR`, `NOT`, `ORDER BY`。

**JQL 运算符详解**

以下是一些常用的 JQL 运算符及其说明：

* **比较运算符:**
    * `=`:  等于。例如 `project = "TEST"` (项目等于 "TEST")
    * `!=`:  不等于。例如 `status != "已完成"` (状态不等于 "已完成")
    * `>`:  大于。例如 `created > startOfDay("-7d")` (创建日期大于 7 天前的今天)
    * `>=`:  大于等于。
    * `<`:  小于。
    * `<=`:  小于等于。

* **逻辑运算符:**
    * `AND`:  与。连接两个条件，两个条件都必须满足。例如 `project = "TEST" AND status = "待办"`
    * `OR`:  或。连接两个条件，至少一个条件必须满足。例如 `status = "待办" OR status = "进行中"`
    * `NOT`:  非。否定一个条件。例如 `NOT status = "已完成"` (状态不是 "已完成")

* **IN 和 NOT IN 运算符:**
    * `IN`:  在列表中。字段的值在指定的列表中。例如 `status IN ("待办", "进行中", "已解决")`
    * `NOT IN`:  不在列表中。字段的值不在指定的列表中。例如 `status NOT IN ("已完成", "已关闭")`

* **CONTAINS 和 NOT CONTAINS 运算符:**
    * `~`:  包含。用于文本字段，搜索包含指定文本的值。例如 `summary ~ "错误信息"` (摘要包含 "错误信息")
    * `!~`:  不包含。用于文本字段，搜索不包含指定文本的值。例如 `description !~ "性能问题"` (描述不包含 "性能问题")
    * `CONTAINS`:  用于集合字段 (例如 Labels, Components, Versions)，判断集合中是否包含指定值。例如 `labels CONTAINS "bug"` (标签包含 "bug")
    * `NOT CONTAINS`: 用于集合字段，判断集合中是否不包含指定值。例如 `components NOT CONTAINS "前端"` (组件不包含 "前端")

* **IS EMPTY 和 IS NOT EMPTY 运算符:**
    * `IS EMPTY`:  为空。字段的值为空。例如 `resolution IS EMPTY` (解决方案为空，表示 issue 尚未解决)
    * `IS NOT EMPTY`:  不为空。字段的值不为空。例如 `duedate IS NOT EMPTY` (截止日期不为空)

* **ORDER BY 运算符:**
    * `ORDER BY`:  排序。按照指定的字段和排序方向 (ASC 升序, DESC 降序) 对结果进行排序。例如 `ORDER BY created DESC` (按照创建日期降序排列)

**JQL 值类型**

JQL 查询中可以使用不同类型的值：

* **文本 (Text):**  用双引号 `" "` 或单引号 `' '` 包裹。例如 `"Bug"`, `'Task'`, `"测试项目"`.  如果文本值包含空格或特殊字符，必须用引号包裹。
* **数字 (Number):**  直接输入数字。例如 `priority = 3`.
* **日期 (Date):**  可以使用不同的日期格式和函数。
    * **具体日期:**  `"YYYY-MM-DD"`, 例如 `"2023-10-26"`.
    * **相对日期:**  使用 `w`, `d`, `h`, `m` 分别表示周、天、小时、分钟，并使用 `+` 或 `-` 表示未来或过去。例如 `-1w` (一周前), `+2d` (两天后), `startOfDay("-3d")` (三天前的今天开始时间).
    * **日期函数:**  Jira 提供了许多日期函数，例如 `now()`, `startOfDay()`, `endOfDay()`, `startOfWeek()`, `endOfWeek()`, `startOfMonth()`, `endOfMonth()`, `startOfYear()`, `endOfYear()`.  你可以查阅 Jira 文档获取完整的日期函数列表。
* **用户 (User):**  可以使用用户名或用户 ID。例如 `assignee = "john.doe"`, `reporter = currentUser()`.
* **函数 (Function):**  Jira 提供了许多 JQL 函数来扩展查询能力。例如 `currentUser()` (当前用户), `membersOf("jira-developers")` (属于 "jira-developers" 组的成员), `votedIssues()` (当前用户投票的 issue), `watchedIssues()` (当前用户关注的 issue) 等。 你可以查阅 Jira 文档获取完整的函数列表。

**Jira REST API `/search` 端点**

Jira REST API 的 `/search` 端点用于执行 JQL 查询并检索 issue 数据。你需要使用 HTTP POST 请求，并将 JQL 查询作为请求体中的 `jql` 参数传递。

**请求方法:** `POST`

**请求 URL:** `YOUR_JIRA_URL/rest/api/3/search`  (注意 `/rest/api/3/` 部分可能根据你的 Jira 版本有所不同，请查阅你的 Jira REST API 文档)

**请求头:**
* `Content-Type: application/json`
* `Authorization: Basic <Base64 编码的用户名:密码>` (或使用其他认证方式，例如 API Token)

**请求体 (JSON):**

```json
{
  "jql": "YOUR_JQL_QUERY",
  "startAt": 0,  // 可选，分页起始位置，默认为 0
  "maxResults": 50, // 可选，每页返回的最大结果数，默认为 50，最大为 1000
  "fields": [  // 可选，指定返回的字段，如果不指定，默认返回所有可展示字段
    "key",
    "summary",
    "status",
    "assignee"
  ],
  "expand": [  // 可选，扩展返回的信息，例如 "changelog", "transitions"
    // "changelog"
  ]
}
```

**示例：使用 `/search` 端点执行 JQL 查询**

假设你的 Jira URL 是 `https://your-jira.example.com`，你想搜索项目 "TEST" 中所有状态为 "待办" 的 issue，并返回 issue 的 key, summary, status 和 assignee 字段。

**JQL 查询:** `project = "TEST" AND status = "待办"`

**API 请求 (使用 curl 示例):**

```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic $(echo -n 'your_username:your_password' | base64)" \
  -d '{
    "jql": "project = \"TEST\" AND status = \"待办\"",
    "fields": ["key", "summary", "status", "assignee"]
  }' \
  "https://your-jira.example.com/rest/api/3/search"
```

**响应 (JSON 示例):**

```json
{
  "expand": "schema,names",
  "startAt": 0,
  "maxResults": 50,
  "total": 2,
  "issues": [
    {
      "expand": "operations,versionedRepresentations,changelog,transitions,…",
      "id": "10001",
      "key": "TEST-1",
      "self": "https://your-jira.example.com/rest/api/3/issue/10001",
      "fields": {
        "summary": "待办任务 1",
        "status": {
          "self": "https://your-jira.example.com/rest/api/3/status/10000",
          "id": "10000",
          "name": "待办",
          "statusCategory": {
            "self": "https://your-jira.example.com/rest/api/3/statuscategory/2",
            "id": 2,
            "key": "new",
            "colorName": "blue-gray",
            "name": "待办"
          }
        },
        "assignee": {
          "self": "https://your-jira.example.com/rest/api/3/user?accountId=5bxxxxxx",
          "accountId": "5bxxxxxx",
          "displayName": "John Doe"
        }
      }
    },
    {
      "expand": "operations,versionedRepresentations,changelog,transitions,…",
      "id": "10002",
      "key": "TEST-2",
      "self": "https://your-jira.example.com/rest/api/3/issue/10002",
      "fields": {
        "summary": "待办任务 2",
        "status": {
          "self": "https://your-jira.example.com/rest/api/3/status/10000",
          "id": "10000",
          "name": "待办",
          "statusCategory": {
            "self": "https://your-jira.example.com/rest/api/3/statuscategory/2",
            "id": 2,
            "key": "new",
            "colorName": "blue-gray",
            "name": "待办"
          }
        },
        "assignee": {
          "self": "https://your-jira.example.com/rest/api/3/user?accountId=5byyyyyy",
          "accountId": "5byyyyyy",
          "displayName": "Jane Smith"
        }
      }
    }
  ]
}
```

**JQL 查询示例 (直接用于 `/search` 端点)**

以下提供大量 JQL 查询示例，你可以直接复制粘贴到 `/search` 端点的请求体中 `jql` 参数的值。

**1. 基本搜索 (项目、Issue 类型、状态)**

* **查询特定项目的所有 issue:**
    ```jql
    project = "TEST"
    ```
    ```json
    { "jql": "project = \"TEST\"" }
    ```

* **查询特定项目和 Issue 类型的 issue:**
    ```jql
    project = "TEST" AND issuetype = "Bug"
    ```
    ```json
    { "jql": "project = \"TEST\" AND issuetype = \"Bug\"" }
    ```

* **查询特定项目、Issue 类型和状态的 issue:**
    ```jql
    project = "TEST" AND issuetype = "Task" AND status = "进行中"
    ```
    ```json
    { "jql": "project = \"TEST\" AND issuetype = \"Task\" AND status = \"进行中\"" }
    ```

* **查询状态为 "待办" 或 "进行中" 的所有 issue (所有项目):**
    ```jql
    status IN ("待办", "进行中")
    ```
    ```json
    { "jql": "status IN (\"待办\", \"进行中\")" }
    ```

* **查询状态不是 "已完成" 的所有 issue (所有项目):**
    ```jql
    status != "已完成"
    ```
    ```json
    { "jql": "status != \"已完成\"" }
    ```
    或者
    ```jql
    NOT status = "已完成"
    ```
    ```json
    { "jql": "NOT status = \"已完成\"" }
    ```

**2. 日期搜索 (创建日期、更新日期、截止日期)**

* **查询今天创建的所有 issue:**
    ```jql
    created = startOfDay()
    ```
    ```json
    { "jql": "created = startOfDay()" }
    ```

* **查询昨天创建的所有 issue:**
    ```jql
    created = startOfDay("-1d")
    ```
    ```json
    { "jql": "created = startOfDay(\"-1d\")" }
    ```

* **查询过去 7 天创建的所有 issue:**
    ```jql
    created >= startOfDay("-7d")
    ```
    ```json
    { "jql": "created >= startOfDay(\"-7d\")" }
    ```

* **查询特定日期范围创建的 issue:**
    ```jql
    created >= "2023-10-20" AND created <= "2023-10-25"
    ```
    ```json
    { "jql": "created >= \"2023-10-20\" AND created <= \"2023-10-25\"" }
    ```

* **查询截止日期为空的 issue:**
    ```jql
    duedate IS EMPTY
    ```
    ```json
    { "jql": "duedate IS EMPTY" }
    ```

* **查询截止日期在未来 7 天内的 issue:**
    ```jql
    duedate >= now() AND duedate <= endOfDay("+7d")
    ```
    ```json
    { "jql": "duedate >= now() AND duedate <= endOfDay(\"+7d\")" }
    ```

**3. 用户搜索 (经办人、报告人)**

* **查询经办人是特定用户的 issue:**
    ```jql
    assignee = "john.doe"  // 使用用户名
    ```
    ```json
    { "jql": "assignee = \"john.doe\"" }
    ```
    或
    ```jql
    assignee = currentUser() // 查询经办人是当前用户的 issue
    ```
    ```json
    { "jql": "assignee = currentUser()" }
    ```

* **查询经办人是 "john.doe" 或 "jane.smith" 的 issue:**
    ```jql
    assignee IN ("john.doe", "jane.smith")
    ```
    ```json
    { "jql": "assignee IN (\"john.doe\", \"jane.smith\")" }
    ```

* **查询没有经办人的 issue (未分配的 issue):**
    ```jql
    assignee IS EMPTY
    ```
    ```json
    { "jql": "assignee IS EMPTY" }
    ```

* **查询报告人是特定用户的 issue:**
    ```jql
    reporter = "jane.smith"
    ```
    ```json
    { "jql": "reporter = \"jane.smith\"" }
    ```

**4. 文本搜索 (摘要、描述、评论)**

* **在摘要中搜索关键词 "错误":**
    ```jql
    summary ~ "错误"
    ```
    ```json
    { "jql": "summary ~ \"错误\"" }
    ```

* **在描述中搜索关键词 "性能问题":**
    ```jql
    description ~ "性能问题"
    ```
    ```json
    { "jql": "description ~ \"性能问题\"" }
    ```

* **在评论中搜索关键词 "需要测试":**
    ```jql
    comment ~ "需要测试"
    ```
    ```json
    { "jql": "comment ~ \"需要测试\"" }
    ```

* **在摘要或描述中搜索关键词 "用户界面":**
    ```jql
    summary ~ "用户界面" OR description ~ "用户界面"
    ```
    ```json
    { "jql": "summary ~ \"用户界面\" OR description ~ \"用户界面\"" }
    ```

**5. 关键字搜索 (标签、组件、版本)**

* **查询包含标签 "bug" 的 issue:**
    ```jql
    labels = "bug"
    ```
    或
    ```jql
    labels CONTAINS "bug"
    ```
    ```json
    { "jql": "labels CONTAINS \"bug\"" }
    ```

* **查询同时包含标签 "bug" 和 "urgent" 的 issue:**
    ```jql
    labels = "bug" AND labels = "urgent"
    ```
    或
    ```jql
    labels CONTAINS "bug" AND labels CONTAINS "urgent"
    ```
    ```json
    { "jql": "labels CONTAINS \"bug\" AND labels CONTAINS \"urgent\"" }
    ```

* **查询属于组件 "前端" 的 issue:**
    ```jql
    component = "前端"
    ```
    或
    ```jql
    component IN ("前端")
    ```
    ```json
    { "jql": "component = \"前端\"" }
    ```

* **查询修复版本是 "1.0" 的 issue:**
    ```jql
    fixVersion = "1.0"
    ```
    ```json
    { "jql": "fixVersion = \"1.0\"" }
    ```

* **查询影响版本是 "2.0" 或 "2.1" 的 issue:**
    ```jql
    affectedVersion IN ("2.0", "2.1")
    ```
    ```json
    { "jql": "affectedVersion IN (\"2.0\", \"2.1\")" }
    ```

**6. 高级搜索 (组合条件、排序)**

* **查询项目 "TEST" 中，Issue 类型为 "Bug" 或 "缺陷"，且状态为 "待办" 或 "进行中" 的 issue，并按照创建日期降序排列:**
    ```jql
    project = "TEST" AND issuetype IN ("Bug", "缺陷") AND status IN ("待办", "进行中") ORDER BY created DESC
    ```
    ```json
    { "jql": "project = \"TEST\" AND issuetype IN (\"Bug\", \"缺陷\") AND status IN (\"待办\", \"进行中\") ORDER BY created DESC" }
    ```

* **使用括号分组条件:**
    ```jql
    (project = "TEST" AND issuetype = "Bug") OR (project = "PROJ" AND issuetype = "Task")
    ```
    ```json
    { "jql": "(project = \"TEST\" AND issuetype = \"Bug\") OR (project = \"PROJ\" AND issuetype = \"Task\")" }
    ```

**7. 搜索特定字段 (系统字段和自定义字段)**

* **搜索特定系统字段 (例如优先级 Priority):**
    ```jql
    priority = "高"  // 假设你的 Jira 中 "高" 是优先级选项
    ```
    ```json
    { "jql": "priority = \"高\"" }
    ```

* **搜索自定义字段 (假设你的自定义字段 ID 是 `customfield_10000`):**
    ```jql
    "customfield_10000" = "自定义字段值"
    ```
    ```json
    { "jql": "\"customfield_10000\" = \"自定义字段值\"" }
    ```
    **注意:**  自定义字段的字段名通常是 `customfield_XXXXX` 的格式，你需要查找你的自定义字段的实际 ID。你可以通过 Jira UI 或 REST API 获取自定义字段信息。

**8. 使用函数 (例如 `currentUser()`, `membersOf()` )**

* **查询经办人是当前用户所属 "开发团队" 组的成员的 issue:**
    ```jql
    assignee in membersOf("开发团队")
    ```
    ```json
    { "jql": "assignee in membersOf(\"开发团队\")" }
    ```

* **查询当前用户报告的所有 issue:**
    ```jql
    reporter = currentUser()
    ```
    ```json
    { "jql": "reporter = currentUser()" }
    ```

**重要提示:**

* **项目 Key 和 Issue 类型名称:**  在 JQL 查询中，项目 Key 和 Issue 类型名称通常是字符串，需要用引号包裹。请确保使用正确的项目 Key 和 Issue 类型名称 (区分大小写，空格等)。
* **状态名称:**  状态名称也需要用引号包裹，并确保使用正确的状态名称 (区分大小写，空格等)。状态名称可能因 Jira 工作流配置而异。
* **日期格式:**  日期格式要符合 Jira 的要求，通常是 `"YYYY-MM-DD"`。
* **用户名称:**  可以使用用户名 (例如 `john.doe`) 或用户 Account ID (例如 `5bxxxxxx`)。推荐使用 Account ID，因为它更稳定，不受用户名更改的影响。
* **自定义字段 ID:**  自定义字段需要使用其字段 ID (例如 `customfield_10000`) 进行查询。
* **权限:**  你需要有足够的权限才能搜索特定项目或 issue。
* **Jira 版本:**  Jira REST API 的版本和 JQL 的语法可能因 Jira 版本而异。请参考你使用的 Jira 版本的官方文档。
* **错误处理:**  在实际使用 REST API 时，需要处理 API 响应中的错误信息，例如 JQL 查询语法错误、权限错误等。

**建议:**

* **使用 Jira 高级搜索 UI 测试 JQL 查询:**  Jira UI 的高级搜索功能允许你构建和测试 JQL 查询，并查看结果。这可以帮助你快速验证你的 JQL 查询是否正确。
* **查阅 Jira 官方文档:**  Atlassian 官方文档提供了最权威和详细的 JQL 和 Jira REST API 信息。请参考 [Atlassian Jira Cloud REST API documentation](https://developer.atlassian.com/cloud/jira/platform/rest/v3/) 和 [Jira Query Language (JQL) documentation](https://support.atlassian.com/jira-software-cloud/docs/use-advanced-search-with-jira-query-language-jql/).
* **逐步构建复杂的查询:**  从简单的查询开始，逐步添加条件，验证每一步的结果，可以帮助你更好地理解 JQL 并避免错误。

希望这些详细的讲解和示例能够帮助你入门 JQL 查询和 Jira REST API 的 `/search` 端点。 实践是最好的老师，请尝试使用这些示例，并根据你的实际需求进行修改和扩展，你会逐渐掌握 JQL 的强大功能。 如果你有任何其他问题，请随时提出！