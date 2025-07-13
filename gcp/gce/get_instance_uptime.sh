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
