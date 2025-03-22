| platform | eid | jiratier | fromapi | consistency_status |
|----------|-----|-----------|----------|-------------------|
| google | ISSUE-1001 | P1 | P1 | 一致 |
| google | ISSUE-1002 | P2 | P2 | 一致 |
| google | ISSUE-1003 | P3 | P4 | 不一致 |
| aliyun | ALI-2001 | Critical | Critical | 一致 |
| aws | AWS-3001 | High | NULL | 无 API 数据 |

```sql
-- Assuming the table is named 'id_table' and the columns are as described in the markdown.

-- 1. Filter for a specific platform (e.g., 'google'):
SELECT *
FROM id_table
WHERE platform = 'google';

-- 2. Filter for multiple platforms (e.g., 'google' and 'aliyun'):
SELECT *
FROM id_table
WHERE platform IN ('google', 'aliyun');

-- 3. Filter for platforms that are NOT a specific value (e.g., not 'google'):
SELECT *
FROM id_table
WHERE platform <> 'google';

-- OR (alternative to <>):
SELECT *
FROM id_table
WHERE platform != 'google';

-- 4. Filter for platforms that are NOT in a list (e.g., not 'google' or 'aliyun'):
SELECT *
FROM id_table
WHERE platform NOT IN ('google', 'aliyun');

-- 5. Filter for platforms that start with a specific string (e.g., 'a'):
SELECT *
FROM id_table
WHERE platform LIKE 'a%';

-- 6. Filter for platforms that contain a specific string (e.g., 'goo'):
SELECT *
FROM id_table
WHERE platform LIKE '%goo%';

-- 7. Filter for platforms that end with a specific string (e.g., 'yun'):
SELECT *
FROM id_table
WHERE platform LIKE '%yun';

-- 8. Filter for platforms where the platform is not null
SELECT *
FROM id_table
WHERE platform IS NOT NULL;

-- 9. Filter for platforms where the platform is null
SELECT *
FROM id_table
WHERE platform IS NULL;
```
