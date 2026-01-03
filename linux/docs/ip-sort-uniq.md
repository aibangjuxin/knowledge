这个需求可以拆解为两个关键部分：

1. 去重 IP 地址段（包括完全相同的子网如 /32）；
2. 判断某个 IP 段是否被另一个 IP 段包含，并找出被包含的子段。

我们可以用如下三种语言提供对应的实现方式：Python（推荐）、Groovy、Shell（利用 ipcalc 或 iprange + awk 等工具）。

✅ 推荐方法：Python（使用标准库

ipaddress

）

import ipaddress

# 输入示例：一组字符串形式的 IP 段

ip_list = [

"192.168.0.0/24",

"192.168.0.32/28",

"192.168.0.64/26",

"192.168.0.32/32",

"10.0.0.1/32",

"10.0.0.0/24",

"10.0.0.1/32",  # duplicate

]

# 去重 + 转换为 ip_network 对象

networks = list({ipaddress.ip_network(ip) for ip in ip_list})

# 输出包含关系的子网

contained = []

for i in range(len(networks)):

for j in range(len(networks)):

if i == j:

continue

# 如果 i 被 j 包含，加入列表

if networks[i].subnet_of(networks[j]):

contained.append((str(networks[i]), str(networks[j])))

# 打印结果

print("被其他段包含的 IP 子段：")

for child, parent in contained:

print(f"{child} ⊂ {parent}")

示例输出：

被其他段包含的 IP 子段：

192.168.0.32/28 ⊂ 192.168.0.0/24

192.168.0.32/32 ⊂ 192.168.0.0/24

192.168.0.64/26 ⊂ 192.168.0.0/24

10.0.0.1/32 ⊂ 10.0.0.0/24

🧩 Groovy 实现（基于 Java IP 库）

Groovy 默认没有内建 IP 处理，但你可以使用 Apache Commons Net（或手动计算）：

@Grab('com.googlecode.ipv6:ipv6:0.17')

import inet.ipaddr.IPAddressString

def ipList = [

"192.168.0.0/24",

"192.168.0.32/28",

"192.168.0.64/26",

"192.168.0.32/32",

"10.0.0.1/32",

"10.0.0.0/24",

"10.0.0.1/32"

]

// 去重

def networks = ipList.toSet().collect { new IPAddressString(it).address }

// 查找包含关系

networks.each { net1 ->

networks.each { net2 ->

if (net1 != net2 && net1.isContainedBy(net2)) {

println "${net1} ⊂ ${net2}"

}

}

}

你需要在 Groovy 环境中加载 inet.ipaddr 库（可以通过 @Grab 或构建系统如 Gradle/Maven 加载）。

🔧 Shell 实现（依赖

ipcalc

+ awk）

#!/bin/bash

input_file="ips.txt"

# 去重

uniq_ips=$(sort -u "$input_file")

# 转换成数组

mapfile -t ip_array <<< "$uniq_ips"

echo "被包含的 IP 子段："

for ((i=0; i<${#ip_array[@]}; i++)); do

for ((j=0; j<${#ip_array[@]}; j++)); do

[ $i -eq $j ] && continue

if ipcalc -nb ${ip_array[$i]} | grep -q "${ip_array[$j]%/\*}"; then

# 检查 netmask 是否包含关系

ip_in_subnet=$(sipcalc "${ip_array[$j]}" | grep "Usable range" | grep -oE '([0-9]+\.){3}[0-9]+')

if [[${ip_array[$i]} == $ip_in_subnet*]]; then

echo "${ip_array[$i]} ⊂ ${ip_array[$j]}"

fi

fi

done

done

注意：Shell 的精度较差，不推荐用于复杂网段关系判断。需要 sipcalc 和 ipcalc 工具。

结论

|        |                            |                        |
| ------ | -------------------------- | ---------------------- |
| 方法   | 优点                       | 缺点                   |
| Python | 简洁、标准库支持 ipaddress | 需 Python 环境         |
| Groovy | 适合已有 JVM 环境          | 需要引入 IP 库         |
| Shell  | 可快速执行在 Linux 上      | 精度有限、处理逻辑复杂 |

需要我根据你的 YAML 结构（如 ip_list.yaml）进一步集成成完整的 YAML 输入处理程序（支持读取和解析）也可以告诉我。

