```python
import ipaddress
import re
import sys

# --- 配置 ---
# 输入的 YAML 文件名
INPUT_FILE = "api_list.yaml"

def extract_ips_from_file(file_path: str) -> set[str]:
    """
    步骤 1: 从文件中提取所有符合 IP/CIDR 格式的字符串。
    使用正则表达式来查找，不关心 YAML 的具体结构。
    返回一个集合以自动处理文本级别的重复。
    """
    print(f"--- 步骤 1: 从 '{file_path}' 提取 IP 地址 ---")
    
    # 正则表达式，用于匹配 IPv4 地址或 CIDR
    # e.g., "205.188.54.82/32", "205.188.54.82"
    # The '?' makes the CIDR part optional.
    ip_pattern = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:/[0-9]{1,2})?\b')
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
            # 查找所有匹配项
            found_ips = ip_pattern.findall(content)
            # 使用集合来完成初步去重 (步骤 2)
            unique_ips = set(found_ips)
            print(f"找到了 {len(unique_ips)} 个唯一的 IP/CIDR 字符串。")
            print("----------------------------------------------------")
            return unique_ips
    except FileNotFoundError:
        print(f"错误: 输入文件 '{file_path}' 不存在。")
        sys.exit(1)
    except Exception as e:
        print(f"读取或解析文件时出错: {e}")
        sys.exit(1)

def process_ip_list(ip_strings: set[str]) -> list:
    """
    对提取出的 IP 字符串列表进行核心处理。
    - 步骤 3: 排除私有 IP 地址范围
    - 步骤 4 & 5: 处理包含关系并聚合网络
    """
    print("--- 步骤 3, 4, 5: 过滤、去包含并聚合网络 ---")
    
    public_networks = []
    for cidr_str in ip_strings:
        try:
            # 将字符串转换为 ipaddress 对象。
            # strict=False 允许主机地址（如 205.188.54.82）被正确地视为 /32 网络。
            net = ipaddress.ip_network(cidr_str, strict=False)
            
            # 步骤 3: 排除私有IP地址范围
            if net.is_private:
                print(f"  [排除] {str(net):<18} (私有地址)")
                continue
            
            public_networks.append(net)
            
        except ValueError:
            # 忽略无法解析的字符串
            print(f"  [忽略] '{cidr_str}' 不是一个有效的 IP 地址或 CIDR。")
            pass
            
    if not public_networks:
        return []

    # 步骤 4 (包含) & 5 (聚合): ipaddress.collapse_addresses 是核心函数
    # 它会自动处理子网的包含关系和连续地址块的聚合。
    # 1. 它会丢弃被其他更大范围包含的子网。
    # 2. 它会合并可以合并成一个更大 CIDR 的相邻网络。
    print("\n正在进行网络聚合...")
    optimized_networks = list(ipaddress.collapse_addresses(public_networks))
    
    print(f"处理完成，最终得到 {len(optimized_networks)} 个优化后的网络范围。")
    print("----------------------------------------------------")
    
    return optimized_networks


def main():
    """主执行函数"""
    
    # 步骤 1 & 2
    unique_ip_strings = extract_ips_from_file(INPUT_FILE)
    
    if not unique_ip_strings:
        print("在文件中没有找到任何 IP/CIDR 地址。")
        return
        
    # 步骤 3, 4, 5
    final_list = process_ip_list(unique_ip_strings)
    
    # 打印最终结果
    print("\n--- 最终优化后的 IP 地址范围 ---")
    if not final_list:
        print("没有有效的公共 IP 地址范围需要输出。")
    else:
        for network in sorted(final_list): # 按 IP 地址排序输出
            print(network)
    print("-------------------------------------")


if __name__ == "__main__":
    main()
```