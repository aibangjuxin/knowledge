#!/bin/bash

# 显示最近20次提交涉及的文件列表
git log -20 --name-only --oneline | grep -v "^[0-9a-f]\{7\}" | sort | uniq