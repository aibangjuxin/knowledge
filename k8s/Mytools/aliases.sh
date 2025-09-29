#!/bin/bash

# 自定义别名配置文件
# 用于 Kali Linux 安全测试环境

# ============================================================================
# 安全测试工具别名
# ============================================================================

# Nmap 扫描别名
alias nmap-syn='nmap -sS -T4'
alias nmap-tcp='nmap -sT -T4'
alias nmap-udp='nmap -sU -T4'
alias nmap-ping='nmap -sn'
alias nmap-top='nmap --top-ports 1000 -T4'
alias nmap-vuln='nmap --script vuln -T4'
alias nmap-os='nmap -O -T4'
alias nmap-service='nmap -sV -T4'
alias nmap-all='nmap -A -T4'
alias nmap-stealth='nmap -sS -f -T2'

# 快速搜索别名
alias grep-ip='grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}"'
alias grep-email='grep -E "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"'
alias grep-url='grep -E "https?://[^\s]+"'

# 网络信息别名
alias myip-external='curl -s ifconfig.me'
alias myip-internal='hostname -I | awk "{print \$1}"'
alias ports-open='nmap -sT -O localhost'

echo "✅ 自定义别名已加载"