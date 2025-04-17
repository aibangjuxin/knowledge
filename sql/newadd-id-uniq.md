```sql
SELECT DISTINCT t1.teamName, t1.capOrg, t2.eimId
FROM (
    SELECT DISTINCT t1.teamName, t1.capOrg
    FROM `bigqueryproject.aibang_api_data.team_level_api_dev_historical_data` t1
    LEFT JOIN `bigqueryproject.aibang_api_data.team_level_api_dev_historical_data` t2
    ON t1.teamName = t2.teamName AND t1.capOrg = t2.capOrg
    AND SUBSTR(t2.backuptime, 7, 4) != '2025'
    WHERE SUBSTR(t1.backuptime, 7, 4) = '2025'
    AND t2.teamName IS NULL
) t1
LEFT JOIN (
    SELECT DISTINCT owner AS team, eimId
    FROM `bigqueryproject.aibang_api_data.firestore_apimetadatas`
    WHERE eimId IS NOT NULL
    AND REGEXP_CONTAINS(eimId, r'^\d+$')
    AND eimId != '1111111'
    AND eimId != '2222222'
) t2
ON t1.teamName = t2.team;
```
让我先解释这个 SQL 查询的功能，然后提供优化建议：

### SQL 解析
这个查询主要分为两部分：

1. **第一部分（子查询 t1）**：
```sql
SELECT DISTINCT t1.teamName, t1.capOrg
FROM team_level_api_dev_historical_data t1
LEFT JOIN team_level_api_dev_historical_data t2
ON t1.teamName = t2.teamName AND t1.capOrg = t2.capOrg
AND SUBSTR(t2.backuptime, 7, 4) != '2025'
WHERE SUBSTR(t1.backuptime, 7, 4) = '2025'
AND t2.teamName IS NULL
```
- 查找在 2025 年存在，但在其他年份不存在的团队和组织
- 使用 LEFT JOIN 和 IS NULL 实现"仅在2025年存在"的逻辑

2. **第二部分（子查询 t2）**：
```sql
SELECT DISTINCT owner AS team, eimId
FROM firestore_apimetadatas
WHERE eimId IS NOT NULL
AND REGEXP_CONTAINS(eimId, r'^\d+$')
AND eimId != '1111111'
AND eimId != '2222222'
```
- 获取有效的 eimId（数字格式且不为特定值）
- 将 owner 映射为 team

### 优化建议

1. **使用 NOT EXISTS 替代 LEFT JOIN**：
```sql
SELECT DISTINCT t1.teamName, t1.capOrg, t2.eimId
FROM (
    SELECT DISTINCT teamName, capOrg
    FROM `bigqueryproject.aibang_api_data.team_level_api_dev_historical_data`
    WHERE SUBSTR(backuptime, 7, 4) = '2025'
    AND NOT EXISTS (
        SELECT 1
        FROM `bigqueryproject.aibang_api_data.team_level_api_dev_historical_data` t_inner
        WHERE t_inner.teamName = teamName 
        AND t_inner.capOrg = capOrg
        AND SUBSTR(t_inner.backuptime, 7, 4) != '2025'
    )
) t1
LEFT JOIN (
    SELECT DISTINCT owner AS team, eimId
    FROM `bigqueryproject.aibang_api_data.firestore_apimetadatas`
    WHERE eimId IS NOT NULL
    AND REGEXP_CONTAINS(eimId, r'^\d+$')
    AND eimId NOT IN ('1111111', '2222222')
) t2
ON t1.teamName = t2.team;
```

优化点说明：
1. 使用 NOT EXISTS 代替 LEFT JOIN + IS NULL，通常性能更好
2. 使用 NOT IN 代替多个 != 条件
3. 减少了不必要的表别名
4. 保留了 DISTINCT 以确保结果唯一性

建议：
1. 在 teamName, capOrg, backuptime 字段上建立索引
2. 在 firestore_apimetadatas 表的 owner, eimId 字段上建立索引
3. 考虑将 backuptime 改为日期类型，避免字符串操作
4. 如果可能，将年份提取为单独的字段并建立索引

```sql
SELECT t1.teamName, t1.capOrg, t2.eimId
FROM (
    SELECT t1.teamName, t1.capOrg
    FROM `bigqueryproject.aibang_api_data.team_level_api_dev_historical_data` t1
    WHERE SUBSTR(t1.backuptime, 7, 4) = '2025'
    AND NOT EXISTS (
        SELECT 1
        FROM `bigqueryproject.aibang_api_data.team_level_api_dev_historical_data` t2
        WHERE t1.teamName = t2.teamName 
        AND t1.capOrg = t2.capOrg
        AND SUBSTR(t2.backuptime, 7, 4) != '2025'
    )
) t1
LEFT JOIN (
    SELECT owner AS team, eimId
    FROM `bigqueryproject.aibang_api_data.firestore_apimetadatas`
    WHERE eimId IS NOT NULL
    AND REGEXP_CONTAINS(eimId, r'^\d+$')
    AND eimId NOT IN ('1111111', '2222222')
) t2
ON t1.teamName = t2.team;
```