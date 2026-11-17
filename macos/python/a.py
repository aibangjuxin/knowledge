#!/usr/bin/env python3
import subprocess
import threading
import re
import json
import time
from datetime import datetime, UTC
from collections import OrderedDict

INTERFACE = "en1"
dns_cache = OrderedDict()
CACHE_TTL = 360  # 增加 TTL 到 6 分钟

# 优化后的 DNS 响应解析正则
dns_response_re = re.compile(r'A? ([\w.-]+).')
ip_re = re.compile(r'(\d{1,3}.\d{1,3}.\d{1,3}.\d{1,3})')

def cleanup_cache():
    """清理过期的缓存条目"""
    now = time.time()
    keys_to_delete = [ip for ip, (_, ts) in list(dns_cache.items()) if now - ts > CACHE_TTL]
    for ip in keys_to_delete:
        try:
            del dns_cache[ip]
        except KeyError:
            pass

def reverse_dns_lookup(ip):
    """对指定 IP 执行反向 DNS 查询并更新缓存"""
    try:
        # 使用 dig 进行反向查询，设置超时
        cmd = ["dig", "-x", ip, "+short", "+time=2"]
        proc = subprocess.run(cmd, capture_output=True, text=True, check=True)
        hostname = proc.stdout.strip()
        if hostname and hostname.endswith('.'):
            hostname = hostname[:-1]
        
        if hostname:
            print(f"[REVERSE DNS] {ip} -> {hostname}")
            dns_cache[ip] = (hostname, time.time())
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        # 查询失败或超时，静默处理
        # print(f"[REVERSE DNS FAILED] for {ip}: {e}")
        pass
    except Exception as e:
        print(f"[REVERSE DNS ERROR] for {ip}: {e}")


def dns_sniffer():
    """被动监听 DNS 响应以填充缓存"""
    print(f"[*] DNS sniffer active on {INTERFACE}")
    cmd = ["sudo", "tcpdump", "-n", "-l", "-i", INTERFACE, "udp port 53"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    for line in proc.stdout:
        line = line.strip()
        domain_match = dns_response_re.search(line)
        if domain_match:
            domain = domain_match.group(1)
            # 从行尾开始查找 IP，通常是解析结果
            ip_matches = ip_re.findall(line)
            if ip_matches:
                resolved_ip = ip_matches[-1]
                if resolved_ip not in dns_cache:
                     print(f"[DNS SNIFFER] {resolved_ip} -> {domain}")
                dns_cache[resolved_ip] = (domain, time.time())
                cleanup_cache()

    err = proc.stderr.read()
    if err:
        print(f"[DNS THREAD ERROR] {err}")


def get_hostname(ip):
    """从缓存获取主机名，如果不存在则触发后台反向查询"""
    cleanup_cache()
    if ip in dns_cache:
        return dns_cache[ip][0]
    
    # 对于私有地址，不进行反向查询
    if ip.startswith('192.168.') or ip.startswith('10.') or ip.startswith('172.'):
        return None

    # 触发后台反向查询
    threading.Thread(target=reverse_dns_lookup, args=(ip,), daemon=True).start()
    return None

def parse_tcpdump_line(line):
    """解析 tcpdump 输出行"""
    parts = line.split()
    if len(parts) < 5 or "IP" not in parts:
        return None
    try:
        # 调整索引以匹配 tcpdump 输出格式
        src, dst = parts[2], parts[4]
        src_ip, src_port = src.rsplit('.', 1)
        dst_ip, dst_port = dst.rstrip(':').rsplit('.', 1)
        
        return {
            "timestamp": datetime.now(UTC).isoformat(),
            "src_ip": src_ip,
            "src_port": src_port,
            "dst_ip": dst_ip,
            "dst_port": dst_port,
            "hostname": get_hostname(dst_ip),
            "protocol": "TCP",
            "interface": INTERFACE
        }
    except (ValueError, IndexError) as e:
        # print(f"[PARSE ERROR] {e} - line: {line}")
        return None

def tcp_sniffer():
    """监听 TCP SYN 包并解析"""
    print(f"[*] TCP sniffer active on {INTERFACE}")
    # 监听 TCP SYN 包
    cmd = ["sudo", "tcpdump", "-n", "-l", "-i", INTERFACE, "tcp[tcpflags] & (tcp-syn) != 0"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    for line in proc.stdout:
        line = line.strip()
        # print(f"[TCP RAW] {line}") # 调试时可以取消注释
        result = parse_tcpdump_line(line)
        if result:
            # 再次尝试获取 hostname，因为反向查询可能已经完成
            if result['hostname'] is None:
                result['hostname'] = dns_cache.get(result['dst_ip'], (None,))[0]
            print(json.dumps(result))

    err = proc.stderr.read()
    if err:
        print(f"[TCP THREAD ERROR] {err}")

def main():
    print(f"[*] Monitoring interface: {INTERFACE}")
    print("[*] DNS and TCP sniffers started...")

    # 启动后台线程
    dns_thread = threading.Thread(target=dns_sniffer, daemon=True, name="DnsSniffer")
    tcp_thread = threading.Thread(target=tcp_sniffer, daemon=True, name="TcpSniffer")

    dns_thread.start()
    tcp_thread.start()

    try:
        while True:
            time.sleep(10) # 每10秒清理一次旧缓存
            cleanup_cache()
    except KeyboardInterrupt:
        print("\n[*] Stopped by user")

if __name__ == "__main__":
    main()
