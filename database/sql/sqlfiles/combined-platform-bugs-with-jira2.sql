-- 合并三个平台的bug查询结果并关联project.e表获取jira2
SELECT 
    combined_results.platform,
    combined_results.eid,
    combined_results.jira,
    e.jira as jira2
FROM (
    SELECT 'google' as platform, eid, tier as jira
    FROM project.a
    WHERE issue_type = 'bug'

    UNION ALL

    SELECT 'aliyun' as platform, eid, tier as jira
    FROM project.b
    WHERE issue_type = 'bug'

    UNION ALL

    SELECT 'aws' as platform, eid, tier as jira
    FROM project.c
    WHERE issue_type = 'bug'
) combined_results
LEFT JOIN project.e e ON combined_results.eid = e.eid
ORDER BY platform, eid;