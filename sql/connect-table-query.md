

```sql
select distinct a.id,a.owner as team_name,a.name as api_name,a.env,a.region From `gcp-projects-374115.apis.apis` a where a.id not in (select distinct id from `gcp-projects-374115.apis.api_permissions`) and a.name not in ('abc','def')
```

这是一个查询SQL，让我为你解释其功能和结构：

1. 这个查询从`gcp-projects-374115.apis.apis` 表中选择不重复的记录
2. 选择的字段包括：id, owner(别名为team_name), name(别名为api_name), env, region
3. 使用了子查询作为过滤条件：排除了在`api_permissions` 表中已存在id的记录
4. 同时排除了name为'abc'和'def'的记录
5. 这个查询的主要目的是获取未授权的API列表，同时排除了特定的API名称




这个 SQL 语句的作用是查询 apis 表中符合条件的 API 信息，并去除重复数据。下面是对 SQL 语句的详细解释：

⸻

SQL 语句解析
```sql
SELECT DISTINCT 
    a.id,
    a.owner AS team_name,
    a.name AS api_name,
    a.env,
    a.region
FROM `gcp-projects-374115.apis.apis` a
WHERE 
    a.id NOT IN (
        SELECT DISTINCT id 
        FROM `gcp-projects-374115.apis.api_permissions`
    ) 
    AND a.name NOT IN ('abc', 'def');
```
⸻

1. SELECT DISTINCT
```
SELECT DISTINCT 
    a.id,
    a.owner AS team_name,
    a.name AS api_name,
    a.env,
    a.region
```
	•	SELECT DISTINCT：去重，确保查询返回的记录不会出现重复行。
	•	a.id：API 的唯一标识符 (id)。
	•	a.owner AS team_name：API 所属的团队 (owner)，并重命名为 team_name。
	•	a.name AS api_name：API 的名称 (name)，并重命名为 api_name。
	•	a.env：API 部署的环境（如 dev, staging, prod）。
	•	a.region：API 所属的 GCP 物理区域（如 us-central1, asia-east1）。
⸻

2. FROM 语句

FROM `gcp-projects-374115.apis.apis` a

	•	gcp-projects-374115.apis.apis 是 BigQuery 中的表，存储了所有 API 的基本信息。
	•	a 是 apis 表的别名，简化后续 SQL 书写。

⸻

3. WHERE 语句
```sql
WHERE 
    a.id NOT IN (
        SELECT DISTINCT id 
        FROM `gcp-projects-374115.apis.api_permissions`
    ) 
    AND a.name NOT IN ('abc', 'def')
```
条件 1：排除 api_permissions 中的 id
```sql
a.id NOT IN (
    SELECT DISTINCT id 
    FROM `gcp-projects-374115.apis.api_permissions`
)
```
	•	api_permissions 表记录了具有权限控制的 API。
	•	这个子查询：

SELECT DISTINCT id FROM `gcp-projects-374115.apis.api_permissions`

获取 api_permissions 表中所有 id，确保 API 具有某种权限。

	•	a.id NOT IN (...) 排除 apis 表中那些已经存在于 api_permissions 表的 API，即只获取没有权限控制的 API。

⸻

条件 2：排除特定的 API

AND a.name NOT IN ('abc', 'def')

	•	a.name NOT IN ('abc', 'def') 过滤掉名称为 'abc' 和 'def' 的 API。
	•	这确保查询结果不会包含 name 为 'abc' 和 'def' 的 API。

⸻

4. 语句执行流程
	1.	查询 api_permissions 表：
	•	获取 api_permissions 表中所有 id，即已经具有权限的 API。
	2.	查询 apis 表：
	•	获取所有 API，并筛选：
	•	只返回 不在 api_permissions 表中的 id。
	•	过滤掉 name 为 'abc' 和 'def' 的 API。
	3.	去重：
	•	DISTINCT 确保最终的 API 记录不会重复。

⸻

5. 示例数据

表 apis

| id  | owner | name | env     | region       |
| --- | ----- | ---- | ------- | ------------ |
| 1   | teamA | xyz  | dev     | us-central1  |
| 2   | teamB | abc  | prod    | europe-west1 |
| 3   | teamC | def  | staging | asia-east1   |
| 4   | teamD | ghi  | prod    | us-east1     |


⸻

表 api_permissions

| id  | permission |
| --- | ---------- |
| 1   | read       |
| 2   | write      |



⸻

查询执行后的结果

| id  | team_name | api_name | env  | region   |
| --- | --------- | -------- | ---- | -------- |
| 4   | teamD     | ghi      | prod | us-east1 |

解释：
	•	id = 1 在 api_permissions 表中，所以被排除。
	•	id = 2 和 id = 3 被排除，因为 name IN ('abc', 'def')。
	•	只有 id = 4 满足条件，所以返回 teamD 相关的信息。

⸻

1. 总结

作用
	•	查询 apis 表中未出现在 api_permissions 表中的 API。
	•	过滤掉 name 为 'abc' 和 'def' 的 API。
	•	只返回唯一的 API 信息（DISTINCT）。

适用场景
	•	获取未进行权限控制的 API。
	•	过滤掉特定 API（abc 和 def）。
	•	为权限管理、API 监控、数据分析提供数据支持。

你可以根据需求调整 WHERE 条件，比如改成 EXCEPT 或 LEFT JOIN 来优化性能！ 🚀



你的 SQL 语句中定义的 SELECT 语句是：
```sql
SELECT DISTINCT 
    a.id,
    a.owner AS team_name,
    a.name AS api_name,
    a.env,
    a.region
```
根据这个 SELECT 语句，最终的表头应该是：

| id	| team_name | 	api_name |	env | 	region |
| --- | --------- | --------- | ---- | ------- |




⸻

你的输出表格如果和这个表头不匹配，可能有以下几种情况：
	1.	AS team_name 未正确生效
	•	确保 a.owner AS team_name 的 AS 语法没有拼写错误。
	•	在 BigQuery 运行查询时，AS 应该正确起作用，如果发现 team_name 仍然显示为 owner，可能是 SQL 工具或前端解析问题。
	2.	查询工具的行为
	•	有些 SQL 查询工具（如 BigQuery Web 界面）可能不会显示 AS 重命名的列，而是仍然显示原始列名 owner。
	3.	输出解析问题
	•	确保你查看的是 SQL 结果的原始表头，而不是经过 API 或某种数据导出方式处理后的表头。

如果你发现你的表头仍然是 owner 而不是 team_name，可以尝试：
```sql
SELECT DISTINCT 
    a.id,
    a.owner AS team_name,
    a.name AS api_name,
    a.env,
    a.region
FROM `gcp-projects-374115.apis.apis` a
```
然后在 BigQuery 界面直接查看结果，确认 team_name 是否正确显示。


我有下面这个查询
select distinct(id) from `gcp-projects-374115.apis.apis_1` where issue_type = 'bug' and (level='P1' or level='P2')
select distinct(id) from `gcp-projects-374115.apis.apis_2` where issue_type = 'bug' and (level='P1' or level='P2')
select distinct(id) from `gcp-projects-374115.apis.apis_3` where issue_type = 'bug' and (level='P1' or level='P2')



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
