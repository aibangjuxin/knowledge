#!/bin/bash

echo "=== CVE-2025-8941 状态检查 ==="

# 1. 检查 Ubuntu Security Notices
echo ">> 检查官方安全公告"
curl -s "https://ubuntu.com/security/notices?q=pam&release=noble" | grep -A 5 "CVE-2025-8941" || echo "未找到相关公告"

# 2. 检查 CVE 数据库
echo -e "\n>> 检查 CVE 详情"
curl -s "https://ubuntu.com/security/CVE-2025-8941" || echo "CVE 可能不存在或尚未公开"

# 3. 验证当前版本是否已修复
echo -e "\n>> 当前 PAM 版本信息"
apt-cache show libpam0g | grep -E "Version|CVE"

# 4. 检查 changelog
echo -e "\n>> 查看更新日志"
apt-cache changelog libpam0g | head -50
