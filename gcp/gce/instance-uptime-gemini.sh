#!/bin/bash

# 脚本: instance-uptime-gemini.sh
# 用途: 获取GCE实例的时间戳信息并转换为不同时区的时间.
# 用法: ./instance-uptime-gemini.sh <instance-name> <zone>
# 示例: ./instance-uptime-gemini.sh my-instance asia-east2-a

# 1. 参数校验
if [ "$#" -ne 2 ]; then
    echo "错误: 需要提供2个参数."
    echo "用法: $0 <instance-name> <zone>"
    echo "示例: $0 my-instance asia-east2-a"
    exit 1
fi

INSTANCE_NAME=$1
ZONE=$2

# 2. 依赖检查
if ! command -v gcloud &> /dev/null; then
    echo "错误: gcloud 命令未找到. 请确保 Google Cloud SDK 已安装并配置."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "错误: jq 命令未找到. 请使用 'brew install jq' 或 'apt-get install jq' 安装."
    exit 1
fi

# 3. 获取实例信息
echo "正在获取实例 '$INSTANCE_NAME' 在区域 '$ZONE' 的信息..."
INSTANCE_INFO=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format=json 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$INSTANCE_INFO" ]; then
    echo "错误: 无法获取实例信息. 请检查实例名称和区域是否正确."
    exit 1
fi

# 4. 时间转换函数
# $1: 时间戳字符串 (e.g., "2024-01-15T10:30:45.123-08:00")
# $2: 时间点的标签 (e.g., "创建时间")
convert_time() {
    local timestamp=$1
    local label=$2
    
    if [ -z "$timestamp" ] || [ "$timestamp" == "null" ]; then
        printf "| %-15s | %-35s | %-25s | %-25s | %-25s |\n" "$label" "N/A" "N/A" "N/A" "N/A"
        return
    fi
    
    local original_time="$timestamp"
    local date_cmd="date"

    # 检查是否为macOS，并使用gdate（如果存在）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v gdate &>/dev/null; then
            date_cmd="gdate"
        else
            echo "警告: 在macOS上, 建议安装 'gdate' (brew install coreutils) 以获得更强大的日期处理功能." >&2
        fi
    fi

    # 尝试转换时间
    local china_time=$(TZ='Asia/Shanghai' $date_cmd -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local utc_time=$(TZ='UTC' $date_cmd -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local london_time=$(TZ='Europe/London' $date_cmd -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    
    # 如果转换失败，显示错误信息
    if [ -z "$china_time" ]; then
        china_time="解析失败"
        utc_time="解析失败"
        london_time="解析失败"
    fi
    
    printf "| %-15s | %-35s | %-25s | %-25s | %-25s |\n" "$label" "$original_time" "$china_time" "$utc_time" "$london_time"
}

# 5. 提取并显示时间信息
echo "正在提取和转换时间信息..."

CREATION_TIMESTAMP=$(echo "$INSTANCE_INFO" | jq -r '.creationTimestamp // empty')
LAST_START_TIMESTAMP=$(echo "$INSTANCE_INFO" | jq -r '.lastStartTimestamp // empty')
LAST_STOP_TIMESTAMP=$(echo "$INSTANCE_INFO" | jq -r '.lastStopTimestamp // empty')

# 打印表头
echo ""
echo "实例 '$INSTANCE_NAME' 的时间信息:"
printf "+-----------------+-------------------------------------+---------------------------+---------------------------+---------------------------+\n"
printf "| %-15s | %-35s | %-25s | %-25s | %-25s |\n" "时间点" "原始时间" "中国时间 (CST)" "UTC 时间" "伦敦时间 (GMT/BST)"
printf "+-----------------+-------------------------------------+---------------------------+---------------------------+---------------------------+\n"

# 打印每一行数据
convert_time "$CREATION_TIMESTAMP" "创建时间"
convert_time "$LAST_START_TIMESTAMP" "最后启动时间"
convert_time "$LAST_STOP_TIMESTAMP" "最后停止时间"

printf "+-----------------+-------------------------------------+---------------------------+---------------------------+---------------------------+\n"
echo ""
echo "脚本执行完毕."
