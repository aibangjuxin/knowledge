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