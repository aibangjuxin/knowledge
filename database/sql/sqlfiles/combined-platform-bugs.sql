-- 合并三个平台的bug查询结果
SELECT platform, eid, jira
FROM (
    SELECT 'google' as platform, eid, tier as jira
    FROM project.a
    WHERE issue_type = 'bug'

    UNION ALL

    SELECT 'aliyun' as platform, eid, tier as jira
    FROM project.b
    WHERE issue_type = 'bug'

    SELECT 'aws' as platform, eid, tier as jira
    FROM project.c
    WHERE issue_type = 'bug'
) combined_results;