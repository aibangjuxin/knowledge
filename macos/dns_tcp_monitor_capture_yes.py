#!/usr/bin/env python3
import subprocess
import threading
import socket
import json
import time
import re
import sys
from datetime import datetime, UTC
from collections import OrderedDict

# --- 需要安装 dnslib ---
# pip install dnslib
try:
    from dnslib import DNSRecord, DNSHeader, RR, A, DNSQuestion
    from dnslib.server import DNSLogger, DNSServer
except ImportError:
    print("错误：缺少 dnslib 库。请先执行 'pip install dnslib' 进行安装。", file=sys.stderr)
    exit(1)

# --- 配置 ---
UPSTREAM_DNS = "119.29.29.29"   # 上游 DNS 服务器
CACHE_TTL = 360            # 缓存过期时间（秒）

# --- 全局变量 ---
dns_cache = OrderedDict()
original_dns_servers = []

def find_active_network_service_and_interface():
    """
    查找当前活跃的物理网络服务及其接口，忽略 utun 等虚拟接口。
    返回一个元组 (service_name, interface_name)，例如 ('Wi-Fi', 'en0')。
    """
    try:
        # 1. 获取所有硬件端口及其对应的设备名
        cmd = "networksetup -listallhardwareports"
        ports_info = subprocess.check_output(cmd, shell=True, text=True).strip()
        
        # 2. 解析输出，构建一个 {device: service} 的映射
        device_to_service = {}
        current_port = None
        for line in ports_info.split('\n'):
            if line.startswith("Hardware Port:"):
                current_port = line.split(':', 1)[1].strip()
            elif line.startswith("Device:"):
                device = line.split(':', 1)[1].strip()
                if device and current_port:
                    device_to_service[device] = current_port

        # 3. 查找默认路由，以确定检查接口的优先级
        cmd = "netstat -rn -f inet | grep default"
        default_routes = subprocess.check_output(cmd, shell=True, text=True).strip().split('\n')
        
        for route in default_routes:
            interface = route.split()[-1]
            if interface in device_to_service:
                service = device_to_service[interface]
                cmd = f"networksetup -getnetworkserviceenabled '{service}'"
                if "Enabled" in subprocess.check_output(cmd, shell=True, text=True):
                    print(f"[INFO] 找到活跃的物理网络服务: '{service}' on interface '{interface}'")
                    return service, interface

        raise ValueError("找不到任何一个与默认路由匹配的、可管理的活跃物理网络服务。")

    except Exception as e:
        print(f"[CRITICAL] 无法自动检测网络服务: {e}", file=sys.stderr)
        print("[CRITICAL] 请确认您已连接到网络。", file=sys.stderr)
        exit(1)

def set_system_dns(service, servers):
    """设置指定网络服务的 DNS 服务器"""
    global original_dns_servers
    
    # 备份原始 DNS
    cmd = f"networksetup -getdnsservers '{service}'"
    output = subprocess.check_output(cmd, shell=True, text=True).strip()
    if "There aren't any" not in output:
        original_dns_servers = output.split('\n')
    print(f"[SETUP] 备份 '{service}' 的原始 DNS: {original_dns_servers}")

    # 设置新的 DNS
    servers_str = " ".join(servers) if servers else "empty"
    cmd = f"networksetup -setdnsservers '{service}' {servers_str}"
    print(f"[SETUP] 执行: {cmd}")
    subprocess.run(cmd, shell=True, check=True)
    print(f"[SETUP] '{service}' 的 DNS 已设置为: {servers_str}")

def restore_system_dns(service):
    """恢复指定网络服务的原始 DNS 设置"""
    if not service: return
    if original_dns_servers:
        servers_str = " ".join(original_dns_servers)
        cmd = f"networksetup -setdnsservers '{service}' {servers_str}"
        print(f"\n[RESTORE] 正在恢复 '{service}' 的 DNS: {cmd}")
        subprocess.run(cmd, shell=True, check=True)
    else:
        cmd = f"networksetup -setdnsservers '{service}' empty"
        print(f"\n[RESTORE] 正在清空 '{service}' 的 DNS 设置: {cmd}")
        subprocess.run(cmd, shell=True, check=True)
    print(f"[RESTORE] '{service}' 的 DNS 设置已恢复。")

class DNSProxyResolver:
    def resolve(self, request, handler):
        qname = request.q.qname
        try:
            proxy_req = request.send(UPSTREAM_DNS, 53, timeout=2)
            response = DNSRecord.parse(proxy_req)
            for rr in response.rr:
                if rr.rtype == 1: # A 记录
                    ip, domain = str(rr.rdata), str(qname).rstrip('.')
                    if ip not in dns_cache:
                        print(f"[DNS PROXY] {ip} -> {domain}")
                    dns_cache[ip] = (domain, time.time())
            return response
        except socket.timeout:
            print(f"[DNS PROXY ERROR] Forwarding request for {qname} timed out.", file=sys.stderr)
            return None

def cleanup_cache():
    now = time.time()
    keys_to_delete = [ip for ip, (_, ts) in list(dns_cache.items()) if now - ts > CACHE_TTL]
    for ip in keys_to_delete:
        try: del dns_cache[ip]
        except KeyError: pass

def get_hostname_from_cache(ip):
    cleanup_cache()
    return dns_cache.get(ip, (None,))[0]

def parse_tcpdump_line(line, interface):
    parts = line.split()
    if len(parts) < 5 or "IP" not in parts:
        return None
    try:
        src, dst = parts[2], parts[4]
        src_ip, _ = src.rsplit('.', 1)
        dst_ip, dst_port = dst.rstrip(':').rsplit('.', 1)
        if dst_ip == "127.0.0.1" and dst_port == "53": return None
        return {
            "timestamp": datetime.now(UTC).isoformat(), "src_ip": src_ip,
            "dst_ip": dst_ip, "dst_port": dst_port,
            "hostname": get_hostname_from_cache(dst_ip), "protocol": "TCP",
            "interface": interface
        }
    except (ValueError, IndexError): return None

def tcp_sniffer(interface):
    print(f"[*] TCP sniffer active on '{interface}'")
    cmd = ["sudo", "tcpdump", "-n", "-l", "-i", interface, "tcp[tcpflags] & (tcp-syn) != 0"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    for line in proc.stdout:
        result = parse_tcpdump_line(line.strip(), interface)
        if result:
            if result['hostname'] is None:
                result['hostname'] = get_hostname_from_cache(result['dst_ip'])
            print(json.dumps(result))
    err = proc.stderr.read()
    if err: print(f"[TCP THREAD ERROR] {err}", file=sys.stderr)

def main():
    print("[*] 欢迎使用 DNS 拦截与 TCP 监控脚本。")
    print("[*] 此脚本将临时修改你的系统 DNS 设置。")
    
    active_service, active_interface = None, None
    try:
        active_service, active_interface = find_active_network_service_and_interface()
        set_system_dns(active_service, ["127.0.0.1"])

        resolver = DNSProxyResolver()
        logger = DNSLogger(prefix=False, logf=lambda s: None)
        dns_server = DNSServer(resolver, port=53, address="127.0.0.1", logger=logger)
        dns_thread = threading.Thread(target=dns_server.start, daemon=True, name="DNSProxy")
        dns_thread.start()
        print(f"[*] 本地 DNS 代理已在 127.0.0.1:53 启动，上游服务器: {UPSTREAM_DNS}")

        tcp_thread = threading.Thread(target=tcp_sniffer, args=(active_interface,), daemon=True, name="TCPSniffer")
        tcp_thread.start()

        while True:
            time.sleep(10)
            cleanup_cache()

    except PermissionError:
        print("\n[CRITICAL] 权限错误！请使用 'sudo' 运行此脚本。", file=sys.stderr)
    except Exception as e:
        print(f"\n[CRITICAL] 发生未知错误: {e}", file=sys.stderr)
    finally:
        if active_service:
            restore_system_dns(active_service)
        print("[*] 脚本已停止。")

if __name__ == "__main__":
    main()