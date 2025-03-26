# BigQuery 表结构定义

## 数据表设计

### 字段说明

```sql
CREATE TABLE IF NOT EXISTS `project_id.dataset_id.table_name` (
  id STRING,           -- 记录唯一标识
  data STRING,         -- 记录数据(JSON格式)
  CreateTime TIMESTAMP, -- 记录创建时间(仅首次创建时设置)
  UpdateTime TIMESTAMP  -- 记录更新时间(每次更新都会更新)
);
```

### 字段用途

- CreateTime: 仅在记录首次创建时设置，后续更新不会改变此值
- UpdateTime: 每次记录发生更新时都会更新此字段值

### 数据同步逻辑

1. 首次创建记录:
   ```sql
   INSERT INTO `table_name` (id, data, CreateTime, UpdateTime)
   VALUES ('record_id', 'data_json', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());
   ```

2. 更新已有记录:
   ```sql
   UPDATE `table_name`
   SET data = 'new_data_json',
       UpdateTime = CURRENT_TIMESTAMP()
   WHERE id = 'record_id'
   AND data != 'new_data_json';
   ```

### 增量同步策略

1. 获取需要同步的数据:
   ```sql
   SELECT id, data, UpdateTime
   FROM `table_name`
   WHERE UpdateTime >= 'last_sync_time';
   ```

2. 比较数据变化:
   - 如果记录不存在，执行INSERT操作并设置CreateTime和UpdateTime
   - 如果记录存在且数据有变化，执行UPDATE操作只更新UpdateTime
   - 如果记录存在但数据无变化，不执行任何操作