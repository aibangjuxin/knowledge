#!/usr/bin/env python3
"""
Observe which remote IPs, ports, and best-effort domains a macOS app talks to.

The tool is intentionally dependency-free. It combines:
- lsof polling for process-owned network connections
- optional tcpdump DNS observation to map DNS answers back to remote IPs

It does not modify system DNS settings.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import ipaddress
import json
import os
import queue
import re
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable


DNS_QUERY_RE = re.compile(
    r":\s+(?P<id>\d+)\+?\s+(?P<rtype>A|AAAA|CNAME|HTTPS|SVCB)\?\s+"
    r"(?P<domain>[A-Za-z0-9_.-]+)\."
)
DNS_RESPONSE_RE = re.compile(r":\s+(?P<id>\d+)\s+\d+/\d+/\d+\s+(?P<body>.*)")
IPV4_ANSWER_RE = re.compile(r"\bA\s+((?:\d{1,3}\.){3}\d{1,3})\b")
IPV6_ANSWER_RE = re.compile(r"\bAAAA\s+([0-9A-Fa-f:]+)\b")
LSOF_REMOTE_RE = re.compile(
    r"->(?P<host>\[[0-9A-Fa-f:.]+\]|[^:\s]+):(?P<port>[^\s)]+)"
)


COMMON_SECOND_LEVEL_TLDS = {
    "com.cn",
    "net.cn",
    "org.cn",
    "com.hk",
    "com.tw",
    "co.jp",
    "co.kr",
    "co.uk",
    "com.au",
    "com.br",
    "com.sg",
}


@dataclass
class ConnectionEvent:
    ts: str
    pid: int
    process: str
    protocol: str
    remote_ip: str
    remote_port: str
    state: str
    domain: str | None
    registered_domain: str | None
    category: str


@dataclass
class Stats:
    started_at: str = field(default_factory=lambda: now_iso())
    connection_events: int = 0
    dns_queries: collections.Counter[str] = field(default_factory=collections.Counter)
    domain_hits: collections.Counter[str] = field(default_factory=collections.Counter)
    ip_hits: collections.Counter[str] = field(default_factory=collections.Counter)
    port_hits: collections.Counter[str] = field(default_factory=collections.Counter)
    category_hits: collections.Counter[str] = field(default_factory=collections.Counter)
    pid_hits: collections.Counter[str] = field(default_factory=collections.Counter)
    unresolved_ips: set[str] = field(default_factory=set)
    unique_connections: set[tuple[int, str, str, str]] = field(default_factory=set)


class DnsMap:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._query_by_id: dict[str, str] = {}
        self._domains_by_ip: dict[str, collections.Counter[str]] = {}
        self._last_seen: dict[str, float] = {}

    def add_query(self, dns_id: str, domain: str) -> None:
        with self._lock:
            self._query_by_id[dns_id] = normalize_domain(domain)

    def add_answers(self, dns_id: str, ips: Iterable[str]) -> list[tuple[str, str]]:
        mapped: list[tuple[str, str]] = []
        with self._lock:
            domain = self._query_by_id.get(dns_id)
            if not domain:
                return mapped
            for ip in ips:
                self._domains_by_ip.setdefault(ip, collections.Counter())[domain] += 1
                self._last_seen[ip] = time.time()
                mapped.append((ip, domain))
        return mapped

    def lookup(self, ip: str) -> str | None:
        with self._lock:
            domains = self._domains_by_ip.get(ip)
            if not domains:
                return None
            return domains.most_common(1)[0][0]


def now_iso() -> str:
    return dt.datetime.now(dt.UTC).astimezone().isoformat(timespec="seconds")


def normalize_domain(domain: str | None) -> str | None:
    if not domain:
        return None
    return domain.rstrip(".").lower()


def registered_domain(domain: str | None) -> str | None:
    domain = normalize_domain(domain)
    if not domain:
        return None
    parts = domain.split(".")
    if len(parts) <= 2:
        return domain
    last_two = ".".join(parts[-2:])
    if last_two in COMMON_SECOND_LEVEL_TLDS and len(parts) >= 3:
        return ".".join(parts[-3:])
    return last_two


def category_for(domain: str | None, ip: str, port: str) -> str:
    d = normalize_domain(domain) or ""
    if port in {"443", "8443"}:
        base = "https"
    elif port in {"80", "8080"}:
        base = "http"
    elif port in {"53"}:
        base = "dns"
    elif port in {"5223"}:
        base = "apple-push"
    else:
        base = f"tcp-{port}"

    vendor = None
    for key, label in [
        ("apple.com", "apple"),
        ("icloud.com", "apple"),
        ("mzstatic.com", "apple"),
        ("google", "google"),
        ("gstatic.com", "google"),
        ("cloudflare", "cloudflare"),
        ("akamai", "cdn"),
        ("fastly", "cdn"),
        ("amazonaws.com", "aws"),
        ("azure", "azure"),
    ]:
        if key in d:
            vendor = label
            break

    if not vendor:
        try:
            addr = ipaddress.ip_address(ip)
            if addr.is_private or addr.is_loopback or addr.is_link_local:
                vendor = "local"
        except ValueError:
            pass

    return f"{vendor}/{base}" if vendor else base


def run(cmd: list[str], timeout: float = 8) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def launch_app(args: argparse.Namespace) -> None:
    if args.launch_bundle:
        subprocess.Popen(["open", "-b", args.launch_bundle])
        print(f"[launch] open -b {args.launch_bundle}")
    elif args.launch_app:
        subprocess.Popen(["open", "-a", args.launch_app])
        print(f"[launch] open -a {args.launch_app}")
    elif args.launch_path:
        subprocess.Popen(["open", args.launch_path])
        print(f"[launch] open {args.launch_path}")


def process_rows() -> list[tuple[int, str, str]]:
    proc = run(["ps", "-axo", "pid=,comm=,args="])
    rows: list[tuple[int, str, str]] = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 2)
        if len(parts) < 2:
            continue
        try:
            pid = int(parts[0])
        except ValueError:
            continue
        comm = Path(parts[1]).name
        full_args = parts[2] if len(parts) == 3 else ""
        rows.append((pid, comm, full_args))
    return rows


def find_pids(args: argparse.Namespace) -> dict[int, str]:
    pids: dict[int, str] = {}
    if args.pid:
        for pid in args.pid:
            name = command_name(pid)
            if name:
                pids[pid] = name
        return pids

    if args.bundle_id:
        bundle_pids = pids_for_bundle_id(args.bundle_id)
        if bundle_pids:
            return bundle_pids

    needle = (args.app or args.match or args.bundle_id or "").lower()
    if not needle:
        return pids

    for pid, comm, full_args in process_rows():
        haystack = f"{comm} {full_args}".lower()
        if args.exact_app:
            matched = comm.lower() == needle
        else:
            matched = needle in haystack
        if matched and pid != os.getpid():
            pids[pid] = comm
    return pids


def pids_for_bundle_id(bundle_id: str) -> dict[int, str]:
    script = (
        'tell application "System Events"\n'
        f'  set matches to every process whose bundle identifier is "{bundle_id}"\n'
        '  set rows to {}\n'
        '  repeat with p in matches\n'
        '    set end of rows to ((unix id of p as text) & tab & (name of p as text))\n'
        '  end repeat\n'
        '  return rows\n'
        'end tell'
    )
    proc = run(["osascript", "-e", script], timeout=8)
    if proc.returncode != 0:
        return {}
    pids: dict[int, str] = {}
    for row in proc.stdout.replace(", ", "\n").splitlines():
        if not row.strip():
            continue
        parts = row.split("\t", 1)
        try:
            pid = int(parts[0].strip())
        except ValueError:
            continue
        pids[pid] = parts[1].strip() if len(parts) > 1 else command_name(pid) or str(pid)
    return pids


def command_name(pid: int) -> str | None:
    proc = run(["ps", "-p", str(pid), "-o", "comm="])
    if proc.returncode != 0:
        return None
    return Path(proc.stdout.strip()).name or None


def parse_lsof_line(line: str) -> tuple[str, str, str, str] | None:
    parts = line.split(None, 8)
    if len(parts) < 9:
        return None
    if " TCP " in f" {line} ":
        protocol = "TCP"
    elif " UDP " in f" {line} ":
        protocol = "UDP"
    else:
        protocol = "IP"
    match = LSOF_REMOTE_RE.search(parts[8])
    if not match:
        return None
    host = match.group("host").strip("[]")
    port = match.group("port").rstrip(",")
    state_match = re.search(r"\(([^)]+)\)", parts[8])
    state = state_match.group(1) if state_match else "UNKNOWN"
    return protocol, host, port, state


def poll_connections(
    args: argparse.Namespace,
    dns_map: DnsMap,
    stats: Stats,
    out_q: queue.Queue[dict],
    stop: threading.Event,
) -> None:
    reverse_cache: dict[str, str | None] = {}
    while not stop.is_set():
        pids = find_pids(args)
        if not pids:
            time.sleep(args.interval)
            continue

        for pid, process in sorted(pids.items()):
            proc = run(["lsof", "-nP", "-a", "-p", str(pid), "-i"], timeout=5)
            if proc.returncode not in {0, 1}:
                continue
            for line in proc.stdout.splitlines()[1:]:
                parsed = parse_lsof_line(line)
                if not parsed:
                    continue
                protocol, ip, port, state = parsed
                if args.established_only and state != "ESTABLISHED":
                    continue

                domain = dns_map.lookup(ip)
                if not domain and args.reverse_dns:
                    domain = reverse_cache.get(ip)
                    if ip not in reverse_cache:
                        domain = reverse_dns(ip)
                        reverse_cache[ip] = domain

                key = (pid, ip, port, protocol)
                stats.unique_connections.add(key)
                stats.connection_events += 1
                stats.ip_hits[ip] += 1
                stats.port_hits[port] += 1
                stats.pid_hits[f"{process}:{pid}"] += 1
                if domain:
                    stats.domain_hits[domain] += 1
                else:
                    stats.unresolved_ips.add(ip)
                category = category_for(domain, ip, port)
                stats.category_hits[category] += 1

                event = ConnectionEvent(
                    ts=now_iso(),
                    pid=pid,
                    process=process,
                    protocol=protocol,
                    remote_ip=ip,
                    remote_port=port,
                    state=state,
                    domain=domain,
                    registered_domain=registered_domain(domain),
                    category=category,
                )
                out_q.put({"type": "connection", **event.__dict__})
        time.sleep(args.interval)


def reverse_dns(ip: str) -> str | None:
    try:
        return normalize_domain(socket.gethostbyaddr(ip)[0])
    except (socket.herror, socket.gaierror, ValueError):
        return None


def dns_sniffer(
    interface: str,
    dns_map: DnsMap,
    stats: Stats,
    out_q: queue.Queue[dict],
    stop: threading.Event,
) -> None:
    cmd = [
        "tcpdump",
        "-l",
        "-n",
        "-vvv",
        "-i",
        interface,
        "((udp or tcp) port 53)",
    ]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    out_q.put({"type": "dns_sniffer_started", "ts": now_iso(), "interface": interface})

    def terminate() -> None:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()

    try:
        assert proc.stdout is not None
        while not stop.is_set():
            line = proc.stdout.readline()
            if not line:
                if proc.poll() is not None:
                    break
                continue
            line = line.strip()
            query = DNS_QUERY_RE.search(line)
            if query:
                domain = normalize_domain(query.group("domain"))
                dns_map.add_query(query.group("id"), domain)
                stats.dns_queries[domain] += 1
                out_q.put(
                    {
                        "type": "dns_query",
                        "ts": now_iso(),
                        "dns_id": query.group("id"),
                        "record_type": query.group("rtype"),
                        "domain": domain,
                    }
                )
                continue

            response = DNS_RESPONSE_RE.search(line)
            if response:
                body = response.group("body")
                ips = IPV4_ANSWER_RE.findall(body) + IPV6_ANSWER_RE.findall(body)
                for ip, domain in dns_map.add_answers(response.group("id"), ips):
                    out_q.put(
                        {
                            "type": "dns_answer",
                            "ts": now_iso(),
                            "dns_id": response.group("id"),
                            "domain": domain,
                            "ip": ip,
                        }
                    )
    finally:
        terminate()


def guess_interface() -> str:
    proc = run(["route", "-n", "get", "default"])
    match = re.search(r"interface:\s+(\S+)", proc.stdout)
    return match.group(1) if match else "en0"


def write_loop(
    args: argparse.Namespace,
    stats: Stats,
    out_q: queue.Queue[dict],
    stop: threading.Event,
) -> None:
    with open(args.output, "a", encoding="utf-8") as handle:
        while not stop.is_set() or not out_q.empty():
            try:
                item = out_q.get(timeout=0.5)
            except queue.Empty:
                continue
            handle.write(json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            if args.verbose or item["type"] == "connection":
                print_event(item)


def print_event(item: dict) -> None:
    if item["type"] == "connection":
        domain = item.get("domain") or "-"
        print(
            f"[{item['ts']}] {item['process']}:{item['pid']} "
            f"{item['protocol']} {domain} {item['remote_ip']}:{item['remote_port']} "
            f"{item['state']} {item['category']}"
        )
    elif item["type"] == "dns_query":
        print(f"[dns] {item['record_type']} {item['domain']}")
    elif item["type"] == "dns_answer":
        print(f"[dns] {item['domain']} -> {item['ip']}")
    else:
        print(f"[event] {item}")


def print_summary(stats: Stats, output: Path) -> None:
    print("\n=== Summary ===")
    print(f"Started: {stats.started_at}")
    print(f"Ended:   {now_iso()}")
    print(f"Connection samples: {stats.connection_events}")
    print(f"Unique pid/ip/port/protocol: {len(stats.unique_connections)}")
    print(f"JSONL log: {output}")
    print_counter("Top domains", stats.domain_hits)
    print_counter("Top remote IPs", stats.ip_hits)
    print_counter("Top ports", stats.port_hits)
    print_counter("Top categories", stats.category_hits)
    print_counter("Top DNS queries", stats.dns_queries)
    if stats.unresolved_ips:
        print("\nUnresolved IPs:")
        for ip in sorted(stats.unresolved_ips)[:20]:
            print(f"  {ip}")


def print_counter(title: str, counter: collections.Counter[str], limit: int = 15) -> None:
    if not counter:
        return
    print(f"\n{title}:")
    for key, count in counter.most_common(limit):
        print(f"  {count:5d}  {key}")


def default_output_path() -> Path:
    ts = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    repo = Path(__file__).resolve().parents[1]
    out_dir = repo / "output"
    out_dir.mkdir(parents=True, exist_ok=True)
    return out_dir / f"app-network-{ts}.jsonl"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Observe network destinations for a macOS app or PID.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  sudo ./macos/scripts/app_network_observer.py --app Safari --launch-app Safari --dns --duration 60
  ./macos/scripts/app_network_observer.py --pid 12345 --reverse-dns --duration 30
  sudo ./macos/scripts/app_network_observer.py --match 'Google Chrome' --dns --interval 1

Notes:
  - lsof gives process-owned remote IP/port; DNS correlation is best effort.
  - --dns needs sudo because tcpdump needs packet-capture permission.
  - Domains can be missed when the app uses cached DNS, DoH/DoT, QUIC, proxy/VPN,
    or when another helper process resolves names on behalf of the app.
""",
    )
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--app", help="Process/app name to match, for example Safari")
    target.add_argument("--match", help="Substring to match in process args")
    target.add_argument("--bundle-id", help="Bundle identifier substring to match in process args")
    target.add_argument("--pid", type=int, action="append", help="PID to monitor; repeatable")
    parser.add_argument("--launch-app", help="Run open -a APP before observing")
    parser.add_argument("--launch-bundle", help="Run open -b BUNDLE_ID before observing")
    parser.add_argument("--launch-path", help="Run open PATH before observing")
    parser.add_argument("--exact-app", action="store_true", help="Match app process name exactly")
    parser.add_argument("--duration", type=int, default=60, help="Observation seconds, default 60")
    parser.add_argument("--interval", type=float, default=1.0, help="lsof polling interval seconds")
    parser.add_argument("--dns", action="store_true", help="Enable tcpdump DNS observation")
    parser.add_argument("--interface", default=None, help="Network interface, default auto")
    parser.add_argument("--reverse-dns", action="store_true", help="Try PTR reverse DNS for unresolved IPs")
    parser.add_argument("--established-only", action="store_true", help="Only count ESTABLISHED TCP")
    parser.add_argument("--verbose", action="store_true", help="Print DNS events too")
    parser.add_argument("--output", type=Path, default=default_output_path(), help="JSONL output file")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output = args.output.expanduser().resolve()
    args.output.parent.mkdir(parents=True, exist_ok=True)

    if args.dns and os.geteuid() != 0:
        print("ERROR: --dns uses tcpdump and must be run with sudo.", file=sys.stderr)
        return 2

    launch_app(args)
    if args.launch_app or args.launch_bundle or args.launch_path:
        time.sleep(2)

    interface = args.interface or guess_interface()
    dns_map = DnsMap()
    stats = Stats()
    out_q: queue.Queue[dict] = queue.Queue()
    stop = threading.Event()
    threads: list[threading.Thread] = []

    print(f"[start] output={args.output}")
    print(f"[start] duration={args.duration}s interval={args.interval}s")
    if args.dns:
        print(f"[start] dns tcpdump interface={interface}")
    print("[start] press Ctrl-C to stop early\n")

    threads.append(
        threading.Thread(
            target=poll_connections,
            args=(args, dns_map, stats, out_q, stop),
            daemon=True,
        )
    )
    threads.append(
        threading.Thread(target=write_loop, args=(args, stats, out_q, stop), daemon=True)
    )
    if args.dns:
        threads.append(
            threading.Thread(
                target=dns_sniffer,
                args=(interface, dns_map, stats, out_q, stop),
                daemon=True,
            )
        )

    for thread in threads:
        thread.start()

    def handle_signal(signum: int, frame: object) -> None:
        stop.set()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    deadline = time.time() + args.duration
    try:
        while time.time() < deadline and not stop.is_set():
            time.sleep(0.2)
    finally:
        stop.set()
        for thread in threads:
            thread.join(timeout=3)
        print_summary(stats, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
