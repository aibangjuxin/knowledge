#!/opt/homebrew/bin/bash

# Enhanced macOS Resource Usage Monitor
# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_section() {
    echo -e "${YELLOW}$1${NC}"
    echo "--------------------------------"
}

# Check if bc is available for calculations
if ! command -v bc &> /dev/null; then
    echo "Warning: bc not found, using basic calculations"
    USE_BC=false
else
    USE_BC=true
fi

# 获取CPU使用率最高的进程
print_header "macOS 系统资源使用情况"
print_section "CPU使用率最高的进程 (Top 10):"
ps -Ao %cpu,pid,comm | grep -v "ps -Ao" | sort -nr | head -n 10 | while read cpu pid comm; do
    # 简化应用名称
    if [[ "$comm" == *".app"* ]]; then
        app_name=$(echo "$comm" | sed 's|.*/||' | sed 's|\.app.*|.app|')
    else
        app_name=$(echo "$comm" | sed 's|.*/||')
    fi
    
    # 只显示CPU使用率大于0的进程
    if [[ "$cpu" != "0.0" ]] && [[ "$cpu" != "0" ]]; then
        printf "${GREEN}%6.1f%%${NC} [PID: %5s] %s\n" "$cpu" "$pid" "$app_name"
    fi
done

echo

# 获取内存使用最多的进程
print_section "内存使用最多的进程 (Top 10):"
ps -Ao rss,pid,comm | grep -v "ps -Ao" | sort -nr | head -n 10 | while read rss pid comm; do
    # 简化应用名称
    if [[ "$comm" == *".app"* ]]; then
        app_name=$(echo "$comm" | sed 's|.*/||' | sed 's|\.app.*|.app|')
    else
        app_name=$(echo "$comm" | sed 's|.*/||')
    fi
    
    # 转换为MB并显示 (RSS is in KB on macOS)
    if [[ "$rss" =~ ^[0-9]+$ ]] && [ "$rss" -gt 0 ]; then
        if [ "$USE_BC" = true ]; then
            mem_mb=$(echo "scale=2; $rss / 1024" | bc)
        else
            mem_mb=$((rss / 1024))
        fi
        printf "${GREEN}%8.2f MB${NC} [PID: %5s] %s\n" "$mem_mb" "$pid" "$app_name"
    fi
done

echo

# 按应用统计CPU使用率 (聚合相同应用)
print_section "按应用聚合的CPU使用率 (Top 10):"
ps -Ao %cpu,comm | tail -n +2 | awk '
{
    comm = $2
    cpu = $1
    
    # 简化应用名称 - 获取最后一个路径组件
    n = split(comm, parts, "/")
    app = parts[n]
    
    # 如果是.app结尾，保留.app
    if (index(app, ".app") > 0) {
        sub(/\.app.*/, ".app", app)
    }
    
    if (cpu > 0) {
        cpu_totals[app] += cpu
    }
}
END {
    for (app in cpu_totals) {
        if (cpu_totals[app] > 0) {
            printf "%.2f %s\n", cpu_totals[app], app
        }
    }
}' | sort -nr | head -n 10 | while read cpu_val app; do
    printf "${GREEN}%6.2f%%${NC} - %s\n" "$cpu_val" "$app"
done

echo

# 按应用统计内存使用 (聚合相同应用)
print_section "按应用聚合的内存使用 (Top 10):"
ps -Ao rss,comm | tail -n +2 | awk '
{
    comm = $2
    rss = $1
    
    # 简化应用名称 - 获取最后一个路径组件
    n = split(comm, parts, "/")
    app = parts[n]
    
    # 如果是.app结尾，保留.app
    if (index(app, ".app") > 0) {
        sub(/\.app.*/, ".app", app)
    }
    
    if (rss > 0) {
        mem_totals[app] += rss
    }
}
END {
    for (app in mem_totals) {
        if (mem_totals[app] > 0) {
            printf "%.2f %s\n", mem_totals[app]/1024, app
        }
    }
}' | sort -nr | head -n 10 | while read mem_mb app; do
    printf "${GREEN}%8.2f MB${NC} - %s\n" "$mem_mb" "$app"
done

echo

# 系统总体资源使用情况
print_section "系统总体资源使用情况:"

# CPU核心数和负载
cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "Unknown")
load_avg=$(uptime | awk -F'load averages:' '{print $2}' | xargs)

echo -e "CPU 核心数: ${CYAN}$cpu_cores${NC}"
echo -e "系统负载 (1m, 5m, 15m): ${CYAN}$load_avg${NC}"

# 内存使用情况 (简化版本，兼容性更好)
if command -v vm_stat &> /dev/null; then
    echo -e "${CYAN}内存使用情况:${NC}"
    vm_stat | head -n 10 | while read line; do
        echo -e "  ${line}"
    done
else
    echo -e "${CYAN}内存信息不可用${NC}"
fi

echo

# 磁盘使用情况
print_section "磁盘使用情况:"
df -h / 2>/dev/null | tail -n 1 | while read filesystem size used avail capacity mounted; do
    echo -e "${CYAN}根分区: $filesystem 已使用 $used / $size ($capacity)${NC}"
done

echo

# 进程总数
print_section "进程统计:"
total_processes=$(ps -ax | wc -l | xargs)
echo -e "${CYAN}总进程数: $total_processes${NC}"

# 显示当前用户的进程数
user_processes=$(ps -u $(whoami) | wc -l | xargs)
echo -e "${CYAN}当前用户进程数: $user_processes${NC}"

echo
print_header "资源监控完成"