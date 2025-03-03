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

