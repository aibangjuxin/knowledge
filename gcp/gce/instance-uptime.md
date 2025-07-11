要获取Google Cloud上实例的启动时间，您可以使用以下命令:

```bash
#!/bin/bash

# 检查参数数量
if [ $# -ne 2 ]; then
    echo "使用方法: $0 <instance-name> <zone>"
    echo "示例: $0 my-instance asia-east2-a"
    exit 1
fi

INSTANCE_NAME=$1
ZONE=$2

# 检查gcloud命令是否存在
if ! command -v gcloud &> /dev/null; then
    echo "错误: gcloud命令未找到，请确保已安装Google Cloud SDK"
    exit 1
fi

# 获取实例描述信息
echo "正在获取实例 $INSTANCE_NAME 在区域 $ZONE 的信息..."
INSTANCE_INFO=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format=json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "错误: 无法获取实例信息，请检查实例名称和区域是否正确"
    exit 1
fi

# 函数：转换时间格式
convert_time() {
    local timestamp=$1
    local label=$2
    
    if [ -z "$timestamp" ] || [ "$timestamp" == "null" ]; then
        echo "| $label | N/A | N/A | N/A | N/A |"
        return
    fi
    
    # 处理Google Cloud的时间格式 (RFC3339)
    # 示例: 2024-01-15T10:30:45.123-08:00 或 2024-01-15T18:30:45.123Z
    
    # 显示原始时间
    local original_time="$timestamp"
    
    # 转换为各个时区的时间
    local china_time=$(TZ='Asia/Shanghai' date -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local utc_time=$(TZ='UTC' date -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local london_time=$(TZ='Europe/London' date -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    local pst_time=$(TZ='America/Los_Angeles' date -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
    
    # 如果date命令失败，尝试其他方法
    if [ -z "$china_time" ]; then
        # 尝试使用gdate (macOS)
        if command -v gdate &> /dev/null; then
            china_time=$(TZ='Asia/Shanghai' gdate -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
            utc_time=$(TZ='UTC' gdate -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
            london_time=$(TZ='Europe/London' gdate -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
            pst_time=$(TZ='America/Los_Angeles' gdate -d "$timestamp" +"%Y-%m-%d %H:%M:%S %Z" 2>/dev/null)
        fi
    fi
    
    # 如果仍然失败，显示原始时间
    if [ -z "$china_time" ]; then
        china_time="解析失败"
        utc_time="解析失败"
        london_time="解析失败"
        pst_time="解析失败"
    fi
    
    echo "| $label | $original_time | $china_time | $utc_time | $london_time | $pst_time |"
}

# 提取时间戳
echo "正在提取时间信息..."
CREATION_TIME=$(echo "$INSTANCE_INFO" | jq -r '.creationTimestamp // empty')
LAST_START_TIME=$(echo "$INSTANCE_INFO" | jq -r '.lastStartTimestamp // empty')
LAST_STOP_TIME=$(echo "$INSTANCE_INFO" | jq -r '.lastStopTimestamp // empty')

# 显示实例基本信息
echo ""
echo "## 实例基本信息"
echo "- **实例名称**: $INSTANCE_NAME"
echo "- **区域**: $ZONE"
echo "- **状态**: $(echo "$INSTANCE_INFO" | jq -r '.status // "未知"')"
echo ""

# 显示时间信息表格
echo "## 时间信息对比"
echo ""
echo "| 时间点 | 原始时间 | 中国时间 (CST) | UTC时间 | 伦敦时间 (GMT/BST) | 太平洋时间 (PST/PDT) |"
echo "|--------|----------|----------------|---------|-------------------|---------------------|"

# 转换并显示各个时间点
convert_time "$CREATION_TIME" "创建时间"
convert_time "$LAST_START_TIME" "最后启动时间"
convert_time "$LAST_STOP_TIME" "最后停止时间"

echo ""
echo "## 原始时间戳"
echo "```json"
echo "{"
echo "  \"creationTimestamp\": \"$CREATION_TIME\","
echo "  \"lastStartTimestamp\": \"$LAST_START_TIME\","
echo "  \"lastStopTimestamp\": \"$LAST_STOP_TIME\""
echo "}"
echo "```"

# 如果需要，显示完整的实例信息
if [ "$3" == "--full" ]; then
    echo ""
    echo "## 完整实例信息"
    echo "```json"
    echo "$INSTANCE_INFO"
    echo "```"
fi

echo ""
echo "脚本执行完成！"
```

请将 `INSTANCE_NAME` 替换为您要查询的实例的名称。这将返回实例的启动时间。

如果您想得到实例已经运行的时间，可以结合使用 `date` 命令来计算:

```bash
INSTANCE_NAME="your-instance-name"
START_TIME=$(gcloud compute instances describe $INSTANCE_NAME --format="value(startTime)")
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "Instance $INSTANCE_NAME has been running for: $(date -u -d "$CURRENT_TIME" -d "$START_TIME" +"%H:%M:%S")"
```

这会输出实例已经运行的时间。请注意，这里使用 `-u` 选项来确保使用协调世界时 (UTC)。

如果您想以 Markdown 格式提供结果，我可以帮您转换成相应的格式。


使用 `gcloud compute instance list` 命令列出所有实例时，可以使用 `--format` 选项来指定输出格式。以下是获取启动时间的示例：

```
gcloud compute instances list --format="value(zone, name, creation_timestamp)"
```

此命令将输出以下格式的表格：

```
zone | name | creation_timestamp
------- | -------- | --------
us-central1-a | my-instance | 2023-11-27T14:50:00.000-08:00
```

`creation_timestamp` 列包含实例的启动时间戳。您可以使用 `date` 命令将此时间戳转换为更易读的格式，例如：


date -d @$(gcloud compute instances list --format="value(zone, name, creation_timestamp)" | awk '{print $3}')


此命令将输出以下内容：

```
2023-11-27T06:50:00+08:00
```

您还可以使用 `gcloud compute instances describe` 命令获取实例的详细信息，包括启动时间。以下是获取启动时间的示例：

```
gcloud compute instances describe my-instance
```

此命令将输出以下内容：

```
Name: my-instance
Zone: us-central1-a
Machine type: n1-standard-1
Boot disk size: 10 GB
Boot disk type: pd-standard
Boot disk device name: /dev/disk/by-id/google-pd-standard-us-central1-a
Boot disk path: /dev/disk/by-id/google-pd-standard-us-central1-a
Operating system: Debian GNU/Linux 11 (bullseye)
Metadata:
  creation-timestamp: 2023-11-27T14:50:00.000-08:00
```

`creation-timestamp` 属性包含实例的启动时间戳。

```bash
#!/bin/bash
keyword="aibangrt"

instance_list=$(gcloud compute instances list --filter="name~${keyword}*" --format="value(name,ZONE)")
while read -r instances; do
    NAME=$(echo "$instances" | cut -f1)
    zone=$(echo "$instances" | cut -f2)
    
    # 获取实例的启动时间，并将其转换为本地时区时间
    START_TIME=$(gcloud compute instances describe $NAME --zone $zone --format="value(creationTimestamp)")
    START_TIME_LOCAL=$(echo $START_TIME | awk '{print strftime("%Y-%m-%dT%H:%M:%S%z", $1)}')

    CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "Instance $NAME has been running for: $(date -u -d "$CURRENT_TIME" -d "$START_TIME_LOCAL" +"%H:%M:%S")"
done <<< "$instance_list"

#!/bin/bash
keyword="aibangrt"

instance_list=$(gcloud compute instances list --filter="name~${keyword}*" --format="value(name,ZONE)")
while read -r instances; do
    NAME=$(echo "$instances" | cut -f1)
    zone=$(echo "$instances" | cut -f2)

    # 获取实例的启动时间戳
    START_TIMESTAMP=$(gcloud compute instances describe $NAME --zone $zone --format="value(creationTimestamp.timestamp())")

    # 使用awk处理时间戳格式
    START_TIME_LOCAL=$(echo $START_TIMESTAMP | awk -F"." '{print strftime("%Y-%m-%dT%H:%M:%S%z", $1)}')

    CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "Instance $NAME has been running for: $(date -u -d "$CURRENT_TIME" -d "$START_TIME_LOCAL" +"%H:%M:%S")"
done <<< "$instance_list"

```

# calude
```
#!/bin/bash

keyword="aibangrt"

instance_list=$(gcloud compute instances list --filter="name~${keyword}*" --format="value(name,ZONE)")

while read -r instances; do
  NAME=$(echo "$instances" | cut -f1)
  zone=$(echo "$instances" | cut -f2)

  # 实例启动时间戳(本地时区时间)
  START_TIMESTAMP=$(gcloud compute instances describe $NAME --zone $zone --format="value(creationTimestamp)")

  # 本地时间转换为时间戳
  LOCAL_TS=$(date -d "$START_TIMESTAMP" +%s)

  # 减去时区偏移得到UTC时间戳
  UTC_OFFSET=$(date +%z)
  UTC_TS=$((LOCAL_TS - UTC_OFFSET))

  # UTC时间戳转换为时间字符串
  START_TIME_UTC=$(date -u -d "@$UTC_TS" +"%Y-%m-%dT%H:%M:%SZ")

  CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 按UTC时间计算运行时间
  DURATION=$(date -u -d "$CURRENT_TIME" -d "$START_TIME_UTC" +"%H:%M:%S")

  echo "Instance $NAME has been running for: $DURATION"

done <<< "$instance_list"
```

google
```
#!/bin/bash

keyword="aibangrt"

instance_list=$(gcloud compute instances list --filter="name~${keyword}*" --format="value(name,ZONE)")

while read -r instances; do
  NAME=$(echo "$instances" | cut -f1)
  zone=$(echo "$instances" | cut -f2)

  # 实例启动时间戳(本地时区时间)
  START_TIMESTAMP=$(gcloud compute instances describe $NAME --zone $zone --format="value(creationTimestamp)")

  # 本地时间转换为时间戳
  LOCAL_TS=$(date -d "$START_TIMESTAMP" +%s)

  # 减去时区偏移得到UTC时间戳
  UTC_OFFSET=$(date +%z)
  UTC_TS=$((LOCAL_TS - UTC_OFFSET))

  # UTC时间戳转换为时间字符串
  START_TIME_UTC=$(date -u -d "@$UTC_TS" +"%Y-%m-%dT%H:%M:%SZ")

  CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 按UTC时间计算运行时间
  DURATION=$(date -u -d "$CURRENT_TIME" -d "$START_TIME_UTC" +"%H:%M:%S")

  echo "Instance $NAME has been running for: $DURATION"

done <<< "$instance_list"
```

# last 

1. 将实例的本地启动时间转换为UTC时间
2. 获取当前的UTC时间
3. 基于两个UTC时间计算运行时间差

优化后的脚本:
```bash
#!/bin/bash
keyword="aibangrt"
instance_list=$(gcloud compute instances list --filter="name~${keyword}*" --format="value(name,ZONE)")

while read -r instances; do
  NAME=$(echo "$instances" | cut -f1)
  zone=$(echo "$instances" | cut -f2)

  # 实例启动时间(本地时区时间)
  START_TIMESTAMP=$(gcloud compute instances describe $NAME --zone $zone --format="value(creationTimestamp)")

  # 本地时间转换为UTC时间
  START_TIME_UTC=$(TZ=UTC date -d"$START_TIMESTAMP" +"%Y-%m-%dT%H:%M:%SZ")

  # 当前UTC时间
  CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 基于UTC时间计算持续时间
  #DURATION=$(date -u -d "$CURRENT_TIME" -d "$START_TIME_UTC" +"%H:%M:%S")
  SECONDS1=$(date -u -d "$CURRENT_TIME" +"%s")
  SECONDS2=$(date -u -d "$START_TIME_UTC" +"%s")
  # 计算差值
  DIFF_SECONDS=$((SECONDS1 - SECONDS2))
  # # 将差值转换为时:分:秒格式
  DIFF_TIME=$(date -u -d "@$DIFF_SECONDS" +"%H:%M:%S")

  echo "Instance $NAME has been running for: $DIFF_TIME"

done <<< "$instance_list"

```
