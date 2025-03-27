# Requirements
- [ ] 1. 从GCP的SQL查询出ID,Teamname,Platform
- [ ] 2. 调用API获取ID-Name,Appservicename
- [ ] 3. 写入到Bigquery里面
## GCP SQL Query
```sql
select 
DISTINCT Id,
owner AS Teamname,
'GCP' AS Platform
From `tab`
where Id IS NOT NUll
and REGEXP_CONTAINS(Id,r'^\d+$')
```
## API
假如我现在有个SQL语句,查询结果出来是有三个字段,比如
1 ID 2 Teamname 3 Platform

| ID  | Teamname | Platform |
| --- | -------- | -------- |
| 101 | AIBANG   | GCP      |
| 200 | AIBANG   | GCP      |
| 302 | AIBANG   | GCP      |
| 302 | AIBANG   | CN       |
| 440 | AIBANG   | GCP      |
| 59  | AIBANG   | GCP      |
| 68  | AIBANG   | GCP      |

我现在有一个接口程序去通过第一个字段获取一些信息
比如我通过循环这个ID拿到了一些我想要的值, 比如ID-Name,Appservicename,
我还想增加2个字段比如Updatetime,CreateTime.那么我如何将查询的结果这些都写入到一个Bigquery里面,比如我的bigquery是project.aibang_api_data.chstatus

## 期待的结果是

| ID  | Teamname | Platform | ID-Name | Appservicename | Updatetime | CreateTime |
| --- | -------- | -------- | ------- | -------------- | ---------- | ---------- |
| 101 | AIBANG   | GCP      | 101lex  | aibang-lex     | 2023-10-10 | 2023-10-10 |
| 200 | AIBANG   | GCP      | wcl     | api-1          | 2023-10-10 | 2023-10-10 |
| 302 | AIBANG   | GCP      | wcl     | api-2          | 2023-10-10 | 2023-10-10 |
| 200 | AIBANG   | GCP      | wcl     | api-3          | 2023-10-10 | 2023-10-10 |
          |
那么其实是不是有个问题需要考虑,比如我查询到的值 之后如果有变化我才去更新我的数据,这时候我可能需要更新那个字段Updatetime然后把结果写入.我第一次创建这个表格的数据的时候才需要这个CreateTIme


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



```sql
#!/bin/bash

# 设置错误处理
set -e

# 配置日志文件
LOG_FILE="process_data.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') 开始执行数据处理" > "$LOG_FILE"

# 临时文件
TEMP_DATA="temp_data.csv"
FINAL_DATA="final_data.csv"

# 清理函数
cleanup() {
    rm -f "$TEMP_DATA" "$FINAL_DATA"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 清理临时文件" >> "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 错误发生: $1" >> "$LOG_FILE"
    cleanup
    exit 1
}

# 注册清理函数
trap cleanup EXIT
trap 'handle_error "脚本被中断"' INT TERM

# 执行初始SQL查询并保存结果
echo "$(date '+%Y-%m-%d %H:%M:%S') 执行初始SQL查询" >> "$LOG_FILE"
bq query --format=csv \
    'SELECT DISTINCT Id, owner AS Teamname, "GCP" AS Platform \
     FROM `tab` \
     WHERE Id IS NOT NULL \
     AND REGEXP_CONTAINS(Id,r"^\\d+$")' > "$TEMP_DATA" \
    || handle_error "SQL查询失败"

# 创建最终数据文件的表头
echo "ID,Teamname,Platform,ID-Name,Appservicename,Updatetime,CreateTime" > "$FINAL_DATA"

# 处理每一行数据
while IFS=, read -r id teamname platform; do
    # 跳过表头
    if [ "$id" = "Id" ]; then continue; fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 处理ID: $id" >> "$LOG_FILE"
    
    # 调用API获取额外信息（这里需要替换为实际的API调用）
    # 示例：使用curl调用API
    response=$(curl -s "https://api.example.com/info/$id" 2>/dev/null) \
        || handle_error "API调用失败: $id"
    
    # 从API响应中提取数据（这里需要根据实际API响应格式调整）
    id_name=$(echo "$response" | jq -r '.id_name')
    app_service_name=$(echo "$response" | jq -r '.app_service_name')
    update_time=$(date '+%Y-%m-%d')
    create_time=$(date '+%Y-%m-%d')
    
    # 将数据写入最终文件
    echo "$id,$teamname,$platform,$id_name,$app_service_name,$update_time,$create_time" >> "$FINAL_DATA"
    
    # 添加延迟以避免API限制
    sleep 1
done < "$TEMP_DATA"

# 将数据导入BigQuery
echo "$(date '+%Y-%m-%d %H:%M:%S') 导入数据到BigQuery" >> "$LOG_FILE"
bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    project.aibang_api_data.chstatus \
    "$FINAL_DATA" \
    id:STRING,teamname:STRING,platform:STRING,id_name:STRING,appservicename:STRING,updatetime:DATE,createtime:DATE \
    || handle_error "BigQuery导入失败"

echo "$(date '+%Y-%m-%d %H:%M:%S') 数据处理完成" >> "$LOG_FILE"
```

- sync_data.sh
```bash
#!/bin/bash

# 设置错误处理
set -e

# 配置日志文件
LOG_FILE="process_data.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') 开始执行数据处理" > "$LOG_FILE"

# 临时文件
TEMP_DATA="temp_data.csv"
FINAL_DATA="final_data.csv"

# 清理函数
cleanup() {
    rm -f "$TEMP_DATA" "$FINAL_DATA"
    echo "$(date '+%Y-%m-%d %H:%M:%S') 清理临时文件" >> "$LOG_FILE"
}

# 错误处理函数
handle_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') 错误发生: $1" >> "$LOG_FILE"
    cleanup
    exit 1
}

# 注册清理函数
trap cleanup EXIT
trap 'handle_error "脚本被中断"' INT TERM

# 执行初始SQL查询并保存结果
echo "$(date '+%Y-%m-%d %H:%M:%S') 执行初始SQL查询" >> "$LOG_FILE"
bq query --format=csv \
    'SELECT DISTINCT Id, owner AS Teamname, "GCP" AS Platform \
     FROM `tab` \
     WHERE Id IS NOT NULL \
     AND REGEXP_CONTAINS(Id,r"^\\d+$")' > "$TEMP_DATA" \
    || handle_error "SQL查询失败"

# 创建最终数据文件的表头
echo "ID,Teamname,Platform,ID-Name,Appservicename,Updatetime,CreateTime" > "$FINAL_DATA"

# 处理每一行数据
while IFS=, read -r id teamname platform; do
    # 跳过表头
    if [ "$id" = "Id" ]; then continue; fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') 处理ID: $id" >> "$LOG_FILE"
    
    # 调用API获取额外信息（这里需要替换为实际的API调用）
    # 示例：使用curl调用API
    response=$(curl -s "https://api.example.com/info/$id" 2>/dev/null) \
        || handle_error "API调用失败: $id"
    
    # 从API响应中提取数据（这里需要根据实际API响应格式调整）
    id_name=$(echo "$response" | jq -r '.id_name')
    app_service_name=$(echo "$response" | jq -r '.app_service_name')
    update_time=$(date '+%Y-%m-%d')
    create_time=$(date '+%Y-%m-%d')
    
    # 将数据写入最终文件
    echo "$id,$teamname,$platform,$id_name,$app_service_name,$update_time,$create_time" >> "$FINAL_DATA"
    
    # 添加延迟以避免API限制
    sleep 1
done < "$TEMP_DATA"

# 将数据导入BigQuery
echo "$(date '+%Y-%m-%d %H:%M:%S') 导入数据到BigQuery" >> "$LOG_FILE"
bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    project.aibang_api_data.chstatus \
    "$FINAL_DATA" \
    id:STRING,teamname:STRING,platform:STRING,id_name:STRING,appservicename:STRING,updatetime:DATE,createtime:DATE \
    || handle_error "BigQuery导入失败"

echo "$(date '+%Y-%m-%d %H:%M:%S') 数据处理完成" >> "$LOG_FILE"
```