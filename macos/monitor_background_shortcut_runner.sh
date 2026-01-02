#!/usr/bin/env bash

PROCESS_NAME="BackgroundShortcutRunner"
CPU_THRESHOLD=30

while true; do
  ps -axo pid,pcpu,command |
    grep "$PROCESS_NAME" |
    grep -v grep |
    while read -r pid cpu cmd; do
      cpu_int=${cpu%.*}

      if [ "$cpu_int" -gt "$CPU_THRESHOLD" ]; then
        echo "$(date '+%F %T') Killing $PROCESS_NAME (PID=$pid, CPU=${cpu}%)"
        kill -9 "$pid"
      fi
    done

  sleep 180
done
