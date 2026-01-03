#!/bin/bash

# Get the list of processes and their CPU and memory usage
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 10

# Get the list of processes and their CPU and memory usage, grouped by application
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk '{print $2}' | sort -u | while read app; do
  echo "Application: $app"
  ps -eo pid,comm,%cpu,%mem --sort=-%cpu | grep "$app" | head -n 1
done
