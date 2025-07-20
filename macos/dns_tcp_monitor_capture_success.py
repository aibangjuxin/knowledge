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
CACHE_TTL = 180  # 秒

# 正则解析 DNS 响应行：192.168.1.1.53 > 192.168.1.100.5353: 12345 1/0/0 A 93.184.216.34
dns_response_re = re.compile(r'(\d+\.\d+\.\d+\.\d+)\.\d+ > .*: \d+ \d+\/\d+\/\d+ A (\d+\.\d+\.\d+\.\d+)')

def cleanup_cache():
    now = time.time()
    keys_to_delete = [ip for ip, (_, ts) in dns_cache.items() if now - ts > CACHE_TTL]
    for ip in keys_to_delete:
        del dns_cache[ip]

def dns_sniffer():
    print(f"[*] DNS sniffer active on {INTERFACE}")
    cmd = ["sudo", "tcpdump", "-n", "-l", "-i", INTERFACE, "udp port 53"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    for line in proc.stdout:
        line = line.strip()
        match = dns_response_re.search(line)
        if match:
            responder_ip, resolved_ip = match.groups()
            query_domain_match = re.search(r'A\? ([^\s]+)\.', line)
            if query_domain_match:
                domain = query_domain_match.group(1)
                dns_cache[resolved_ip] = (domain, time.time())
                cleanup_cache()

    err = proc.stderr.read()
    if err:
        print(f"[DNS THREAD ERROR] {err}")

def resolve_from_cache(ip):
    cleanup_cache()
    return dns_cache[ip][0] if ip in dns_cache else None

def parse_tcpdump_line(line):
    parts = line.split()
    if "IP" not in parts:
        print(f"[PARSE SKIP] No IP in line: {line}")
        return None
    try:
        src, dst = parts[2], parts[4]
        src_ip, src_port = src.rsplit('.', 1)
        dst_ip, dst_port = dst.rstrip(':').rsplit('.', 1)
        return {
            "timestamp": datetime.now(UTC).isoformat(),
            "src_ip": src_ip,
            "src_port": src_port,
            "dst_ip": dst_ip,
            "dst_port": dst_port,
            "hostname": resolve_from_cache(dst_ip),
            "protocol": "TCP",
            "interface": INTERFACE
        }
    except Exception as e:
        print(f"[PARSE ERROR] {e} - line: {line}")
        return None

def tcp_sniffer():
    print(f"[*] TCP sniffer active on {INTERFACE}")
    cmd = ["sudo", "tcpdump", "-n", "-l", "-i", INTERFACE, "tcp and (tcp[13] & 2 != 0)"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)

    for line in proc.stdout:
        line = line.strip()
        print(f"[TCP RAW] {line}")
        result = parse_tcpdump_line(line)
        if result:
            print(json.dumps(result))

    err = proc.stderr.read()
    if err:
        print(f"[TCP THREAD ERROR] {err}")

def main():
    print(f"[*] Monitoring interface: {INTERFACE}")
    print("[*] DNS and TCP sniffers started...")

    dns_thread = threading.Thread(target=dns_sniffer, daemon=True)
    tcp_thread = threading.Thread(target=tcp_sniffer, daemon=True)

    dns_thread.start()
    tcp_thread.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[*] Stopped by user")

if __name__ == "__main__":
    main()
