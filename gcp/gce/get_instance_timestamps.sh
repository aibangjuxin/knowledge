#!/bin/bash

# 设置输出文件路径（您可以根据需要修改路径，确保在允许的目录内）
OUTPUT_FILE="/Users/lex/git/knowledge/gcp/gce/instance_timestamps.txt"

# 检查是否提供了实例名称和区域，否则使用默认值或提示用户输入
if [ $# -lt 2 ]; then
  echo "使用方法: $0 <实例名称> <区域>"
  echo "示例: $0 my-instance us-central1-a"
  echo "您也可以编辑此脚本，在下方设置默认实例和区域。"
  exit 1
fi

INSTANCE_NAME="$1"
ZONE="$2"

echo "正在获取实例 $INSTANCE_NAME (区域: $ZONE) 的时间戳信息..."

# 获取创建时间
CREATION_TIME=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(creationTimestamp)" 2>/dev/null)
if [ -z "$CREATION_TIME" ]; then
  CREATION_TIME="无法获取（实例不存在或无权限）"
fi

# 获取最后启动时间
LAST_START_TIME=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(lastStartTimestamp)" 2>/dev/null)
if [ -z "$LAST_START_TIME" ]; then
  LAST_START_TIME="无法获取（实例不存在或无权限）"
fi

# 获取最后停止时间
LAST_STOP_TIME=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(lastStopTimestamp)" 2>/dev/null)
if [ -z "$LAST_STOP_TIME" ]; then
  LAST_STOP_TIME="无法获取（实例不存在或从未停止）"
fi

# 将结果输出到控制台
echo "实例: $INSTANCE_NAME (区域: $ZONE)"
echo "  创建时间 (creationTimestamp): $CREATION_TIME"
echo "  最后启动时间 (lastStartTimestamp): $LAST_START_TIME"
echo "  最后停止时间 (lastStopTimestamp): $LAST_STOP_TIME"

# 将结果保存到文件
echo "实例: $INSTANCE_NAME (区域: $ZONE)" >> "$OUTPUT_FILE"
echo "  创建时间 (creationTimestamp): $CREATION_TIME" >> "$OUTPUT_FILE"
echo "  最后启动时间 (lastStartTimestamp): $LAST_START_TIME" >> "$OUTPUT_FILE"
echo "  最后停止时间 (lastStopTimestamp): $LAST_STOP_TIME" >> "$OUTPUT_FILE"
echo "--------------------------------" >> "$OUTPUT_FILE"

echo "结果已保存到 $OUTPUT_FILE"
