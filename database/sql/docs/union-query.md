# 合并三个表的查询结果并去重

以下SQL语句使用UNION操作符合并三个表的查询结果，并自动去重：

```sql
SELECT id
FROM (
    SELECT DISTINCT id
    FROM `gcp-projects-374115.apis.apis_1`
    WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
    UNION
    SELECT id
    FROM `gcp-projects-374115.apis.apis_2`
    WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
    UNION
    SELECT id
    FROM `gcp-projects-374115.apis.apis_3`
    WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
)
```

说明：
1. 使用UNION而不是UNION ALL，因为UNION会自动去重
2. 外层的SELECT不需要DISTINCT，因为UNION本身就会去重
3. 这个查询会返回所有表中符合条件（issue_type为bug且level为P1或P2）的唯一ID列表
4. 查询结果会包含一个字段：id

性能优化建议：
- 如果各个表的id字段已建立索引，查询性能会更好
- 如果不需要去重，可以使用UNION ALL来提高性能


但是我查询的时候报错了.

syntax error: expected keyword all or keyword distingct but got keyword select at [9:5]



你的 SQL 语句的错误原因在于 UNION 操作的 SELECT 语句外层多加了一层 SELECT id FROM (...)，但 UNION 本身已经会自动去重，因此外层 SELECT 并不需要再嵌套子查询。

修正后的 SQL

SELECT DISTINCT id
FROM `gcp-projects-374115.apis.apis_1`
WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')

UNION

SELECT DISTINCT id
FROM `gcp-projects-374115.apis.apis_2`
WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')

UNION

SELECT DISTINCT id
FROM `gcp-projects-374115.apis.apis_3`
WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2');



⸻

错误分析

错误代码

SELECT id
FROM (
    SELECT DISTINCT id FROM `apis_1` WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
    UNION
    SELECT id FROM `apis_2` WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
    UNION
    SELECT id FROM `apis_3` WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
)

	1.	BigQuery 语法限制
	•	BigQuery 不允许在 UNION 查询外部再使用 SELECT id FROM (...) 这样的子查询，除非子查询被 WITH 或 TABLE 明确包装。
	2.	UNION 已经去重
	•	UNION 本身已经会去重，所以子查询里 SELECT DISTINCT 是多余的（但不会引发错误）。

⸻

进一步优化

如果数据量较大，考虑使用 UNION ALL
	•	UNION 默认去重，可能会导致额外的计算开销。如果你确认 id 在不同表中不会重复，可以使用 UNION ALL 来提升性能：

SELECT id
FROM `gcp-projects-374115.apis.apis_1`
WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')

UNION ALL

SELECT id
FROM `gcp-projects-374115.apis.apis_2`
WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')

UNION ALL

SELECT id
FROM `gcp-projects-374115.apis.apis_3`
WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2');

然后，如果仍然需要去重，可以在最外层再做 DISTINCT：
```sql
SELECT DISTINCT id
FROM (
    SELECT id FROM `gcp-projects-374115.apis.apis_1`
    WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')

    UNION ALL

    SELECT id FROM `gcp-projects-374115.apis.apis_2`
    WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')

    UNION ALL

    SELECT id FROM `gcp-projects-374115.apis.apis_3`
    WHERE issue_type = 'bug' AND (level = 'P1' OR level = 'P2')
);
```

这种方式比直接 UNION 更高效，特别是数据量较大时。