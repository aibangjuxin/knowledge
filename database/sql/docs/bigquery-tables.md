在Google Cloud Platform (GCP) 的BigQuery服务中，跟踪数据可以通过多种方式实现，包括使用虚拟表和原始表的概念。以下是一些关键点，帮助您理解和跟踪BigQuery中的数据：

1. **虚拟表（视图）**:
   - 在BigQuery中，虚拟表是一种不存储实际数据的表。它们是通过SQL查询动态生成的，通常用于简化复杂的查询或者保护原始数据。
   - 视图可以基于一个或多个表（原始表）创建，并且可以包含复杂的JOIN、聚合和其他SQL操作。
   - 视图对于用户来说是只读的，它们不占用额外的存储空间，因为数据是在查询时实时生成的。
   - 视图可以用来跟踪数据的不同方面，例如，可以创建视图来跟踪特定时间段内的数据变化，或者只展示特定用户的数据。

2. **原始表**:
   - 原始表（物理表）是实际存储数据的表。这些表在BigQuery中占用存储空间，并且可以直接查询、更新或删除数据。
   - 原始表可以是临时表或永久表。临时表在查询后自动保存结果，并且有效期为24小时，之后自动删除。永久表则一直存储数据，直到被显式删除。
   - 原始表中的数据可以通过BigQuery的导入功能从外部数据源导入，或者通过直接在BigQuery中插入数据来创建。

3. **数据跟踪**:
   - 要跟踪数据的变化，可以使用BigQuery的审计日志功能，它可以记录对BigQuery资源的所有操作，包括查询、数据插入、删除和更新等。
   - 通过设置审计日志，可以监控谁访问了数据，执行了哪些操作，以及操作的时间等信息。
   - 另外，可以使用时间戳字段和分区表来跟踪数据的历史变化。分区表可以根据时间或其他属性自动组织数据，使得查询特定时间段的数据更加高效。

4. **数据管理**:
   - BigQuery还提供了数据保留策略，允许您设置数据的保留期限。一旦数据超过这个期限，它将自动被删除，这有助于管理存储成本和遵守数据保留政策。

通过上述方法，您可以有效地跟踪和管理BigQuery中的数据。虚拟表（视图）提供了一种灵活的方式来查询和展示数据，而原始表则用于实际的数据存储和管理。结合审计日志和数据保留策略，可以确保数据的安全性和合规性。

- show table schema
- `select column_name` from `project.INFORMATION_SCHEMA.COLUMNS where table_name ='abc'`

```sql
select column_name,
       data_type
FROM
  `project.dataset.INFORMATION_SCHEMA.COLUMNS`
WHERE
  table= 'v4';
```
- using bq
bq show --schema --format=prettyjson project:dataset.v4


```sql
SELECT
  column_name,
  data_type
FROM
  `project.dataset.INFORMATION_SCHEMA.COLUMNS`
WHERE
  table_name = 'v4';
```
