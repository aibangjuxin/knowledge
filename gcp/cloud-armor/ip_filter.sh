#!/opt/homebrew/bin/bash
# 脚本功能: 优化IP地址列表
# 1. 从 YAML 文件中提取 IP/CIDR 列表
# 2. 去除重复的地址
# 3. 排除私有 IP 地址范围
# 4. 如果范围 A 包含范围 B，则只保留范围 A
# 5. 将连续的 IP/CIDR 地址块聚合成一个更大的 CIDR 块

# --- 配置 ---
# 输入的 YAML 文件名
INPUT_FILE="api_list.yaml"

# --- 脚本开始 ---

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "错误: 输入文件 '$INPUT_FILE' 不存在。"
    exit 1
fi

echo "--- 步骤 1 & 2: 从 '$INPUT_FILE' 提取并初步去重 IP 地址 ---"

# 使用 grep -E -o 提取所有符合 IP/CIDR 格式的字符串
# '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' 是一个兼容 macOS grep 的 ERE 表达式
# tr ' ' '\n' 将空格分隔的IP转为每行一个
# sort -u 进行初步的文本去重
initial_ips=$(grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' "$INPUT_FILE" | tr ' ' '\n' | sort -u)

if [ -z "$initial_ips" ]; then
    echo "在文件中没有找到任何 IP/CIDR 地址。"
    exit 0
fi

echo "提取到的独立 IP/CIDR 列表:"
echo "$initial_ips"
echo "----------------------------------------------------"
echo ""
echo "--- 步骤 3, 4, 5: 使用 Python 进行高级处理 ---"
echo "正在排除私有IP、处理包含关系并聚合网络..."
echo ""

# 将初步处理过的IP列表通过管道传递给内联的 Python 脚本
# Python 的 ipaddress 模块是处理这些任务的专业工具
# <<'EOF' 是一个 Here Document, 它将两个 EOF 之间的所有内容作为 Python 脚本的标准输入

# 这个 Python 脚本会:
# - 从标准输入读取每个 CIDR
# - 过滤掉私有地址 (如 10.0.0.0/8, 192.168.0.0/16 等)
# - 使用 ipaddress.collapse_addresses() 函数完美地解决子网包含和地址聚合问题
final_list=$(echo "$initial_ips" | python3 - <<'EOF'
import sys
import ipaddress

networks = []
# 从标准输入逐行读取IP/CIDR
for line in sys.stdin:
    cidr = line.strip()
    if not cidr:
        continue
    
    try:
        # 将字符串转换为 ipaddress 网络对象
        # strict=False 允许主机地址, 例如 205.188.54.82/32 会被正确处理
        net = ipaddress.ip_network(cidr, strict=False)
        
        # 步骤 3: 排除私有IP地址范围
        if not net.is_private:
            networks.append(net)
    except ValueError as e:
        # 忽略无法解析的行
        # e.g., f"无法解析 '{cidr}': {e}"
        pass

# 如果没有有效的公共IP，则退出
if not networks:
    sys.exit(0)

# 步骤 4 & 5: 处理子网包含和聚合
# ipaddress.collapse_addresses 是一个神奇的函数，它会：
# 1. 自动合并相邻的子网 (例如, 1.1.1.0/25 和 1.1.1.128/25 会合并成 1.1.1.0/24)
# 2. 自动丢弃被其他子网完全包含的子网 (例如, 如果列表里有 1.1.1.0/24 和 1.1.1.10/32, 它只会保留 1.1.1.0/24)
collapsed_networks = ipaddress.collapse_addresses(networks)

# 输出最终优化过的列表
for network in collapsed_networks:
    print(network)
EOF
)

echo "--- 最终优化后的 IP 地址范围 ---"
if [ -z "$final_list" ]; then
    echo "没有有效的公共 IP 地址范围需要处理。"
else
    echo "$final_list"
fi
echo "-------------------------------------"