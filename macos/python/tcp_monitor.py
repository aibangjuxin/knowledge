#!/usr/bin/env python3
import subprocess
import json
import socket
import re
from datetime import datetime, UTC

INTERFACE = "en1"  # 替换为你实际的接口名称（如en0）
EXCLUDE_LOCAL_NETS = ["10.", "192.168.", "172.16.", "172.17.", "172.18.", "172.19.", "127."]

def is_private_ip(ip):
    return any(ip.startswith(prefix) for prefix in EXCLUDE_LOCAL_NETS)

def resolve_hostname(ip):
    try:
        return socket.gethostbyaddr(ip)[0]
    except Exception:
        return None

def parse_tcpdump_line(line):
    # 示例： 0.000000 IP 192.168.1.10.52168 > 142.250.207.142.443: Flags [S], ...
    match = re.search(r'IP (\d+\.\d+\.\d+\.\d+)\.(\d+) > (\d+\.\d+\.\d+\.\d+)\.(\d+): Flags \[S\]', line)
    if not match:
        return None
    src_ip, src_port, dst_ip, dst_port = match.groups()
    if is_private_ip(dst_ip):  # 排除内网目标
        return None
    return {
        "timestamp": datetime.now(UTC).isoformat(),
        "src_ip": src_ip,
        "src_port": src_port,
        "dst_ip": dst_ip,
        "dst_port": dst_port,
        "hostname": resolve_hostname(dst_ip),
        "protocol": "TCP",
        "interface": INTERFACE
    }

def run_tcpdump():
    cmd = [
        "sudo", "tcpdump", "-l", "-n", "-i", INTERFACE,
        "tcp[tcpflags] & tcp-syn != 0"
    ]
    with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as proc:
        for line in proc.stdout:
            result = parse_tcpdump_line(line)
            if result:
                print(json.dumps(result))

if __name__ == "__main__":
    try:
        print(f"[*] Monitoring interface: {INTERFACE}")
        run_tcpdump()
    except KeyboardInterrupt:
        print("\n[!] Interrupted by user")
