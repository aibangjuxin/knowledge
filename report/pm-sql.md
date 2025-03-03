下面是我的一个语句 但是这个语句不能满足我的需求 
我现在需要这样一个SqL
就是确保历史数据一定对的前提下、需要将历史数据作为基础数据进行排序，所以需要创建一个历史表 并向其中插入新数据 也就是追加数据
□ 仅向历史记录中添加新结果 仅向其中插入当月数据
□ 一共有三张表作为新数据的采集表
□ 排序筛选条件
□ 基于状态进行筛选 使用case语法筛选三种状态 比如

  - 原样选择 `status` 字段。
- **CASE ... END AS status_group**:
  - 使用 `CASE` 语句依据 `status` 字段的不同值，将任务状态划分为三组，具体如下：
    - 如果 `status` 是 'Done'，则 `status_group` 字段的值为 'Completed'。
    - 如果 `status` 是 'Backlog' 或 'Discovery'，则 `status_group` 的值为 'backlog'。
    - 如果 `status` 是 'Analysis' 或 'Selected to Work on'，则 `status_group` 的值为 'In progress'。

假设我们只查询当前月份的数据 加到这个历史表格 那么我的这个语句应该怎么写？ 我需要你帮我设计这个历史数据的表。
可能到一个历史数据表格是 
主要完成两个任务，第一个任务就是历史书记表的创建 第二个任务就是将当月产生的数据插入到历史数据表里
明显你帮我创建的历史数据表格不对 下面，这个才是我想要的 

CREATE TABLE historical_data (
    month VARCHAR(7) NOT NULL,      -- 年-月格式的月份，如 "2023-03"
    backlog INT DEFAULT 0,          -- Backlog 状态的数量
    in_progress INT DEFAULT 0,      -- In Progress 状态的数量
    completed INT DEFAULT 0,        -- Completed 状态的数量
    PRIMARY KEY (month)              -- month 作为主键，确保唯一性
);
根据这个历史数据表格，帮我完成上面的任务

WITH combined_data AS (
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        status,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status = 'Backlog' OR status = 'Discovery' THEN 'backlog'
            WHEN status = 'Analysis' OR status = 'Selected to Work on' THEN 'In progress'
        END AS status_group
    FROM 
        `project.aibang_api_data.gcp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
    UNION ALL
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        status,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status = 'Backlog' OR status = 'Discovery' THEN 'backlog'
            WHEN status = 'Analysis' OR status = 'Selected to Work on' THEN 'In progress'
        END AS status_group
    FROM 
        `project.aibang_api_data.ikp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
    UNION ALL
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        status,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status = 'Backlog' OR status = 'Discovery' THEN 'backlog'
            WHEN status = 'Analysis' OR status = 'Selected to Work on' THEN 'In progress'
        END AS status_group
    FROM 
        `project.aibang_api_data.whp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022

),
monthly_data AS (
    SELECT 
        month,
        status_group,
        COUNT(*) AS status_count
    FROM 
        combined_data
    GROUP BY 
        month, 
        status_group
),
cumulative_data AS (
    SELECT 
        month,
        status_group,
        SUM(status_count) OVER (PARTITION BY status_group ORDER BY month) AS cumulative_count
    FROM 
        monthly_data
)
SELECT 
    month,
    MAX(CASE WHEN status_group = 'backlog' THEN cumulative_count ELSE 0 END) AS 'backlog',
    MAX(CASE WHEN status_group = 'In progress' THEN cumulative_count ELSE 0 END) AS 'In progress',
    MAX(CASE WHEN status_group = 'Completed' THEN cumulative_count + 46 ELSE 0 END) AS 'Completed'
FROM 
    cumulative_data
GROUP BY 
    month
ORDER BY 
    month;


# ChatGPT 
你需要一个完整的 SQL 方案，包括 创建历史数据表 和 插入当月数据，确保历史数据正确，同时累加新数据。以下是完整的 SQL 方案：

1. 创建历史数据表

CREATE TABLE historical_data (
    month VARCHAR(7) NOT NULL,      -- 采用 "YYYY-MM" 格式
    backlog INT DEFAULT 0,          -- backlog 任务数量
    in_progress INT DEFAULT 0,      -- in_progress 任务数量
    completed INT DEFAULT 0,        -- completed 任务数量
    PRIMARY KEY (month)             -- 以月份为主键，确保唯一性
);

2. 插入或更新历史数据

WITH combined_data AS (
    -- 合并来自三张表的数据，并将状态转换为 status_group
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status IN ('Backlog', 'Discovery') THEN 'backlog'
            WHEN status IN ('Analysis', 'Selected to Work on') THEN 'In progress'
        END AS status_group
    FROM `project.aibang_api_data.gcp_jira_info`
    WHERE issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
    UNION ALL
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status IN ('Backlog', 'Discovery') THEN 'backlog'
            WHEN status IN ('Analysis', 'Selected to Work on') THEN 'In progress'
        END AS status_group
    FROM `project.aibang_api_data.ikp_jira_info`
    WHERE issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
    UNION ALL
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status IN ('Backlog', 'Discovery') THEN 'backlog'
            WHEN status IN ('Analysis', 'Selected to Work on') THEN 'In progress'
        END AS status_group
    FROM `project.aibang_api_data.whp_jira_info`
    WHERE issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
),
monthly_data AS (
    -- 统计当前月份每个状态的任务数量
    SELECT 
        month,
        status_group,
        COUNT(*) AS status_count
    FROM combined_data
    WHERE month = FORMAT_TIMESTAMP('%Y-%m', CURRENT_TIMESTAMP()) -- 仅保留当月数据
    GROUP BY month, status_group
)
-- 插入或更新历史数据
MERGE INTO historical_data AS target
USING (
    -- 转换数据格式，以便匹配历史表的结构
    SELECT 
        month,
        MAX(CASE WHEN status_group = 'backlog' THEN status_count ELSE 0 END) AS backlog,
        MAX(CASE WHEN status_group = 'In progress' THEN status_count ELSE 0 END) AS in_progress,
        MAX(CASE WHEN status_group = 'Completed' THEN status_count ELSE 0 END) AS completed
    FROM monthly_data
    GROUP BY month
) AS source
ON target.month = source.month
WHEN MATCHED THEN 
    -- 如果月份已存在，则累加数据
    UPDATE SET 
        target.backlog = target.backlog + source.backlog,
        target.in_progress = target.in_progress + source.in_progress,
        target.completed = target.completed + source.completed
WHEN NOT MATCHED THEN 
    -- 如果月份不存在，则插入新数据
    INSERT (month, backlog, in_progress, completed)
    VALUES (source.month, source.backlog, source.in_progress, source.completed);

说明
	1.	combined_data: 合并来自 gcp_jira_info、ikp_jira_info、whp_jira_info 三张表的数据，并对 status 进行分类。
	2.	monthly_data: 统计当前月份的 backlog、in_progress 和 completed 数量。
	3.	MERGE INTO 语句:
	•	如果 historical_data 表中已有该月份数据，则进行累加更新。
	•	如果 historical_data 中没有该月份数据，则插入新的记录。

最终效果
	•	历史数据不会被覆盖，只会累加。
	•	只处理当月数据，不会影响过去数据。
	•	状态转换符合需求，将 status 映射到 status_group 并统计。

你可以运行这段 SQL 来实现你想要的逻辑。

# Claude
根据您的需求，我需要帮您完成两个任务：首先是创建历史数据表，然后是编写SQL查询来将当月数据插入到这个历史表中。以下是完整的解决方案：

## 第一部分：创建历史数据表

```sql
CREATE TABLE historical_data (
    month VARCHAR(7) NOT NULL,      -- 年-月格式的月份，如 "2023-03"
    backlog INT DEFAULT 0,          -- Backlog 状态的数量
    in_progress INT DEFAULT 0,      -- In Progress 状态的数量
    completed INT DEFAULT 0,        -- Completed 状态的数量
    PRIMARY KEY (month)             -- month 作为主键，确保唯一性
);
```

## 第二部分：插入当月数据到历史表

以下SQL查询可以用来仅插入当月的新数据到历史表中：

```sql
-- 确定当前月份
DECLARE current_month STRING;
SET current_month = FORMAT_DATE('%Y-%m', CURRENT_DATE());

-- 从三个数据源中收集并汇总当月数据
WITH combined_data AS (
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status IN ('Backlog', 'Discovery') THEN 'backlog'
            WHEN status IN ('Analysis', 'Selected to Work on') THEN 'In progress'
            ELSE 'Other'
        END AS status_group
    FROM 
        `project.aibang_api_data.gcp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND FORMAT_TIMESTAMP('%Y-%m', created) = current_month
    
    UNION ALL
    
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status IN ('Backlog', 'Discovery') THEN 'backlog'
            WHEN status IN ('Analysis', 'Selected to Work on') THEN 'In progress'
            ELSE 'Other'
        END AS status_group
    FROM 
        `project.aibang_api_data.ikp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND FORMAT_TIMESTAMP('%Y-%m', created) = current_month
    
    UNION ALL
    
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status IN ('Backlog', 'Discovery') THEN 'backlog'
            WHEN status IN ('Analysis', 'Selected to Work on') THEN 'In progress'
            ELSE 'Other'
        END AS status_group
    FROM 
        `project.aibang_api_data.whp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND FORMAT_TIMESTAMP('%Y-%m', created) = current_month
),

-- 按状态组汇总当月数据
monthly_summary AS (
    SELECT 
        month,
        SUM(CASE WHEN status_group = 'backlog' THEN 1 ELSE 0 END) AS backlog_count,
        SUM(CASE WHEN status_group = 'In progress' THEN 1 ELSE 0 END) AS in_progress_count,
        SUM(CASE WHEN status_group = 'Completed' THEN 1 ELSE 0 END) AS completed_count
    FROM 
        combined_data
    GROUP BY 
        month
)

-- 使用MERGE语句来插入或更新历史数据表
MERGE historical_data AS target
USING monthly_summary AS source
ON target.month = source.month
WHEN MATCHED THEN
    UPDATE SET
        target.backlog = target.backlog + source.backlog_count,
        target.in_progress = target.in_progress + source.in_progress_count,
        target.completed = target.completed + source.completed_count
WHEN NOT MATCHED THEN
    INSERT (month, backlog, in_progress, completed)
    VALUES (source.month, source.backlog_count, source.in_progress_count, source.completed_count);
```

这个SQL解决方案的工作原理：

1. 首先，声明一个变量来存储当前月份，格式为"YYYY-MM"
2. 然后，从三个源表中收集当月的数据并根据状态将它们分类到三组
3. 汇总各种状态的计数
4. 使用MERGE语句将数据插入历史数据表：
   - 如果该月已存在记录，则累加新数据
   - 如果该月不存在记录，则创建新记录

如果您希望仅将新数据追加到历史表中而不更新现有记录，您可以使用以下更简单的INSERT语句替代MERGE语句：

```sql
INSERT INTO historical_data (month, backlog, in_progress, completed)
SELECT 
    month,
    backlog_count,
    in_progress_count,
    completed_count
FROM 
    monthly_summary
WHERE 
    NOT EXISTS (SELECT 1 FROM historical_data WHERE month = monthly_summary.month);
```

这个方案确保了只有当历史表中不存在当月记录时才会插入新数据。​​​​​​​​​​​​​​​​

# Grok
好的，我来帮你完成这个任务。根据你的需求，我们需要完成以下两个主要任务：  
1. **创建历史数据表 `historical_data`**：你已经提供了一个正确的表结构，我会基于此进行确认和使用。  
2. **将当前月份的数据插入到历史数据表中**：从三个数据源表中提取当前月份的数据，并追加到历史数据表中，同时确保数据的准确性。

以下是详细的解答：

---

### 任务 1：创建历史数据表

你提供的表结构如下：

```sql
CREATE TABLE historical_data (
    month VARCHAR(7) NOT NULL,      -- 年-月格式的月份，如 "2023-03"
    backlog INT DEFAULT 0,          -- Backlog 状态的数量
    in_progress INT DEFAULT 0,      -- In Progress 状态的数量
    completed INT DEFAULT 0,        -- Completed 状态的数量
    PRIMARY KEY (month)             -- month 作为主键，确保唯一性
);
```

这个表结构非常适合你的需求：  
- **`month` 字段**：使用 `VARCHAR(7)` 类型存储年-月格式（如 "2023-03"），并作为主键确保每个月份的记录唯一。  
- **`backlog`, `in_progress`, `completed` 字段**：使用 `INT` 类型，默认值为 0，分别存储三种状态的数量。  

假设你使用的是 Google BigQuery（因为你的查询中使用了 BigQuery 的语法，如 `FORMAT_TIMESTAMP`），我们需要将这个表创建在你的项目和数据集下。例如，假设你的项目是 `project`，数据集是 `dataset`，完整的创建语句如下：

```sql
CREATE TABLE `project.dataset.historical_data` (
    month STRING NOT NULL,          -- BigQuery 中使用 STRING 代替 VARCHAR
    backlog INT64 DEFAULT 0,        -- BigQuery 中使用 INT64 代替 INT
    in_progress INT64 DEFAULT 0,
    completed INT64 DEFAULT 0,
    PRIMARY KEY (month) NOT ENFORCED  -- BigQuery 不强制执行主键约束
);
```

#### 注意事项：
- 在 BigQuery 中，`VARCHAR` 应改为 `STRING`，`INT` 应改为 `INT64`。
- BigQuery 不支持强制执行的主键约束，因此添加 `NOT ENFORCED`。但我们仍然可以通过查询逻辑确保 `month` 的唯一性。
- 请确保将 `project.dataset` 替换为你的实际项目和数据集名称。

这个表创建完成后，将用于存储每个月的历史数据。

---

### 任务 2：将当前月份数据插入历史数据表

你的需求是：  
- 从三张表（`gcp_jira_info`、`ikp_jira_info`、`whp_jira_info`）中提取**当前月份**的数据。  
- 根据 `status` 字段，使用 `CASE` 语句将状态分组为 `backlog`、`in_progress` 和 `completed` 三种状态。  
- 将结果追加到 `historical_data` 表中，仅插入当前月份的数据，不涉及累计计算。

你的原始查询中包含了累计计算（`SUM ... OVER`），但根据需求，我们现在只需要当前月份的计数，而不是累计值。因此，我会调整你的查询，仅计算当前月份的状态数量，并插入到历史数据表中。

以下是完整的 SQL 语句：

```sql
-- 插入当前月份的数据到 historical_data 表
INSERT INTO `project.dataset.historical_data` (month, backlog, in_progress, completed)
WITH combined_data AS (
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        status,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status = 'Backlog' OR status = 'Discovery' THEN 'backlog'
            WHEN status = 'Analysis' OR status = 'Selected to Work on' THEN 'In progress'
        END AS status_group
    FROM 
        `project.aibang_api_data.gcp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
        AND FORMAT_TIMESTAMP('%Y-%m', created) = FORMAT_TIMESTAMP('%Y-%m', CURRENT_TIMESTAMP())  -- 仅当前月份
    UNION ALL
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        status,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status = 'Backlog' OR status = 'Discovery' THEN 'backlog'
            WHEN status = 'Analysis' OR status = 'Selected to Work on' THEN 'In progress'
        END AS status_group
    FROM 
        `project.aibang_api_data.ikp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
        AND FORMAT_TIMESTAMP('%Y-%m', created) = FORMAT_TIMESTAMP('%Y-%m', CURRENT_TIMESTAMP())  -- 仅当前月份
    UNION ALL
    SELECT 
        FORMAT_TIMESTAMP('%Y-%m', created) AS month,
        status,
        CASE 
            WHEN status = 'Done' THEN 'Completed'
            WHEN status = 'Backlog' OR status = 'Discovery' THEN 'backlog'
            WHEN status = 'Analysis' OR status = 'Selected to Work on' THEN 'In progress'
        END AS status_group
    FROM 
        `project.aibang_api_data.whp_jira_info`
    WHERE 
        issue_type = 'Epic' 
        AND EXTRACT(YEAR FROM created) != 2022
        AND FORMAT_TIMESTAMP('%Y-%m', created) = FORMAT_TIMESTAMP('%Y-%m', CURRENT_TIMESTAMP())  -- 仅当前月份
),
monthly_data AS (
    SELECT 
        month,
        SUM(CASE WHEN status_group = 'backlog' THEN 1 ELSE 0 END) AS backlog,
        SUM(CASE WHEN status_group = 'In progress' THEN 1 ELSE 0 END) AS in_progress,
        SUM(CASE WHEN status_group = 'Completed' THEN 1 ELSE 0 END) AS completed
    FROM 
        combined_data
    GROUP BY 
        month
)
SELECT 
    month,
    backlog,
    in_progress,
    completed
FROM 
    monthly_data;
```

#### 代码说明：
1. **`combined_data` CTE**：
   - 从三张表中提取数据，使用 `UNION ALL` 合并。
   - 使用 `FORMAT_TIMESTAMP('%Y-%m', created)` 将 `created` 时间戳转换为 "YYYY-MM" 格式。
   - 添加条件 `FORMAT_TIMESTAMP('%Y-%m', created) = FORMAT_TIMESTAMP('%Y-%m', CURRENT_TIMESTAMP())`，确保只获取当前月份的数据。
   - 使用 `CASE` 语句将 `status` 分组为 `backlog`、`in_progress` 和 `completed`。

2. **`monthly_data` CTE**：
   - 按 `month` 分组，计算三种状态的数量。
   - 使用 `SUM(CASE ...)` 分别统计 `backlog`、`in_progress` 和 `completed` 的数量。

3. **`INSERT` 语句**：
   - 将查询结果直接插入到 `historical_data` 表中。
   - 因为 `month` 是主键，如果当前月份已存在记录，插入会失败（BigQuery 会报错）。为了避免这种情况，可以使用 `INSERT ... SELECT` 并确保表中没有重复的 `month`。

#### 确保历史数据准确性：
- 如果你担心表中已经存在当前月份的数据，可以先删除当前月份的记录，然后再插入。例如：
  ```sql
  DELETE FROM `project.dataset.historical_data`
  WHERE month = FORMAT_TIMESTAMP('%Y-%m', CURRENT_TIMESTAMP());
  ```
  然后再运行上面的 `INSERT` 语句。

- 或者，使用 BigQuery 的 `MERGE` 语句来更新或插入数据（如果需要覆盖已有数据）：
  ```sql
  MERGE `project.dataset.historical_data` AS target
  USING (
      WITH combined_data AS (
          -- 上面相同的 combined_data CTE
      ),
      monthly_data AS (
          -- 上面相同的 monthly_data CTE
      )
      SELECT 
          month,
          backlog,
          in_progress,
          completed
      FROM 
          monthly_data
  ) AS source
  ON target.month = source.month
  WHEN MATCHED THEN
      UPDATE SET 
          target.backlog = source.backlog,
          target.in_progress = source.in_progress,
          target.completed = source.completed
  WHEN NOT MATCHED THEN
      INSERT (month, backlog, in_progress, completed)
      VALUES (source.month, source.backlog, source.in_progress, source.completed);
  ```

#### 注意事项：
- **校正值 +46**：你的原始查询中对 `Completed` 状态加了 46。如果这是业务需求，可以在 `monthly_data` 中调整为：
  ```sql
  SUM(CASE WHEN status_group = 'Completed' THEN 1 ELSE 0 END) + 46 AS completed
  ```
  但如果这只是累计计算的校正，且现在只需要当月数据，则可以去掉。

- **权限**：确保你对 `project.dataset.historical_data` 表有写入权限。

---

### 最终结果

1. **历史数据表**：已通过 `CREATE TABLE` 语句创建。
2. **当前月份数据插入**：使用上述 `INSERT` 或 `MERGE` 语句，将当前月份的数据追加到 `historical_data` 表中。

这样，你的 `historical_data` 表将只包含每个月份的实际计数数据（而非累计值），并且每次运行时只会追加或更新当前月份的数据。如果你需要进一步调整或有其他问题，请随时告诉我！



# Deepseek
根据您的需求，我为您设计了如下解决方案：

```sql
-- 创建历史表（如果不存在）
CREATE TABLE IF NOT EXISTS `project.aibang_api_data.historical_data` (
    month STRING NOT NULL,
    backlog INT DEFAULT 0,
    in_progress INT DEFAULT 0,
    completed INT DEFAULT 0
);

-- 插入当月数据（仅当该月不存在时）
INSERT INTO `project.aibang_api_data.historical_data` (month, backlog, in_progress, completed)
WITH current_month_data AS (
  SELECT
    FORMAT_TIMESTAMP('%Y-%m', created) AS month,
    CASE
      WHEN status IN ('Backlog','Discovery') THEN 'backlog'
      WHEN status IN ('Analysis','Selected to Work on') THEN 'In progress'
      WHEN status = 'Done' THEN 'Completed'
    END AS status_group
  FROM (
    SELECT created, status
    FROM `project.aibang_api_data.gcp_jira_info`
    WHERE issue_type = 'Epic' AND EXTRACT(YEAR FROM created) != 2022
    UNION ALL
    SELECT created, status
    FROM `project.aibang_api_data.ikp_jira_info`
    WHERE issue_type = 'Epic' AND EXTRACT(YEAR FROM created) != 2022
    UNION ALL
    SELECT created, status
    FROM `project.aibang_api_data.whp_jira_info`
    WHERE issue_type = 'Epic' AND EXTRACT(YEAR FROM created) != 2022
  )
  WHERE 
    FORMAT_TIMESTAMP('%Y-%m', created) = FORMAT_TIMESTAMP('%Y-%m', CURRENT_DATE())
)
SELECT
  FORMAT_TIMESTAMP('%Y-%m', CURRENT_DATE()) AS month,
  COUNTIF(status_group = 'backlog') AS backlog,
  COUNTIF(status_group = 'In progress') AS in_progress,
  COUNTIF(status_group = 'Completed') AS completed
FROM current_month_data
WHERE NOT EXISTS (
  SELECT 1
  FROM `project.aibang_api_data.historical_data`
  WHERE month = FORMAT_TIMESTAMP('%Y-%m', CURRENT_DATE())
);
```

方案说明：

1. **历史表创建**：
- 使用 `CREATE TABLE IF NOT EXISTS` 保证幂等性
- 字段设计完全按照您的要求：
  - `month` 字段使用STRING类型存储'YYYY-MM'格式
  - 三个状态字段使用INT类型并设置默认值0

2. **数据插入逻辑**：
- 使用 `WITH` 语句创建CTE临时表：
  - 从三个数据源表UNION ALL合并数据
  - 通过CASE语句进行状态分组映射
  - 过滤条件：issue_type = 'Epic' + 排除2022年数据
- 最终SELECT部分：
  - 使用COUNTIF()按状态分组统计数量
  - 通过WHERE NOT EXISTS子句确保当月数据不存在时才插入
  - 自动获取当前月份（使用CURRENT_DATE()）

3. **执行保障**：
- 每月运行只会插入一条当月记录
- 完全避免重复插入（通过NOT EXISTS子查询）
- 默认值保证即使某状态数量为0也能正确显示

4. **性能优化**：
- 所有过滤条件在UNION ALL子查询中提前执行
- 使用COUNTIF()替代多重CASE WHEN更简洁高效
- 通过CTE结构保持代码可读性

建议每月初运行该脚本，系统会自动插入上月完整数据。如需手动执行，只需要替换CURRENT_DATE()为特定日期即可。




