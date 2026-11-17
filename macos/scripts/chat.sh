#!/bin/bash

# 获取所有进程的PID、CPU占用率、内存占用（以MB为单位）、以及所属应用名称
ps -axo pid,%cpu,rss,comm | awk 'NR>1 {rss[$4]+=$3/1024; cpu[$4]+=$2} END {for (app in rss) print cpu[app], rss[app], app}' | sort -nr | head -n 5 | awk '{printf "App: %-20s | CPU: %-5.2f%% | Memory: %-5.2f MB\n", $3, $1, $2}'
