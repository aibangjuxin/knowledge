#!/usr/bin/env python3
"""
Discover GCP load balancer resources starting from one or more Managed Instance Groups.

Typical usage:
  python3 lb-poc-from-mig.py my-mig
  python3 lb-poc-from-mig.py api --project my-proj --region us-central1
  python3 lb-poc-from-mig.py api --backend-pattern web --lb-scheme EXTERNAL_MANAGED
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def run_json(cmd: Sequence[str]) -> Any:
    try:
        proc = subprocess.run(
            cmd,
            check=True,
            text=True,
            abjture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        stderr = exc.stderr.strip()
        raise RuntimeError(
            f"Command failed: {' '.join(shlex.quote(p) for p in cmd)}\n{stderr}"
        ) from exc

    stdout = proc.stdout.strip()
    if not stdout:
        return []
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Invalid JSON from command: {' '.join(shlex.quote(p) for p in cmd)}"
        ) from exc


def gcloud_json(args: Sequence[str], project: Optional[str] = None) -> Any:
    cmd = ["gcloud", *args, "--format=json"]
    if project:
        cmd.extend(["--project", project])
    return run_json(cmd)


def get_name(url_or_name: Optional[str]) -> str:
    if not url_or_name:
        return ""
    return url_or_name.rstrip("/").split("/")[-1]


def match_pattern(value: Optional[str], pattern: Optional[re.Pattern[str]]) -> bool:
    if pattern is None:
        return True
    if value is None:
        return False
    return bool(pattern.search(value))


def compile_pattern(raw: Optional[str]) -> Optional[re.Pattern[str]]:
    if not raw:
        return None
    return re.compile(raw, re.IGNORECASE)


def iter_service_refs(obj: Any) -> Iterable[str]:
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in {
                "service",
                "defaultService",
                "urlMap",
                "backendService",
                "target",
                "group",
            } and isinstance(value, str):
                yield value
            else:
                yield from iter_service_refs(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from iter_service_refs(item)


def as_list(value: Optional[Any]) -> List[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def safe_get(dct: Dict[str, Any], *keys: str) -> Optional[Any]:
    cur: Any = dct
    for key in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
    return cur


def resource_scope(resource: Dict[str, Any]) -> str:
    if "region" in resource and resource["region"]:
        return f"regional:{get_name(resource['region'])}"
    return "global"


def load_balancing_scheme(resource: Dict[str, Any]) -> str:
    return resource.get("loadBalancingScheme", "UNKNOWN")


@dataclass
class Filters:
    mig: Optional[re.Pattern[str]]
    backend: Optional[re.Pattern[str]]
    url_map: Optional[re.Pattern[str]]
    forwarding_rule: Optional[re.Pattern[str]]
    lb_scheme: Optional[str]
    region: Optional[str]
    zone: Optional[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Discover load balancer resources related to one or more MIGs."
    )
    parser.add_argument("mig", help="MIG name or regex-like pattern to search")
    parser.add_argument("--project", help="GCP project id")
    parser.add_argument("--region", help="Filter MIG/LB resources by region name")
    parser.add_argument("--zone", help="Filter MIGs by zone name")
    parser.add_argument(
        "--backend-pattern",
        help="Only keep backend services whose name matches this regex",
    )
    parser.add_argument(
        "--url-map-pattern",
        help="Only keep URL maps whose name matches this regex",
    )
    parser.add_argument(
        "--forwarding-rule-pattern",
        help="Only keep forwarding rules whose name matches this regex",
    )
    parser.add_argument(
        "--lb-scheme",
        help="Only keep backend services with this load balancing scheme",
    )
    parser.add_argument(
        "--include-empty",
        action="store_true",
        help="Show MIGs even if no related LB resources are found",
    )
    parser.add_argument(
        "--suggest-names",
        action="store_true",
        help="Print starter resource names for a POC clone",
    )
    return parser.parse_args()


def list_migs(project: Optional[str]) -> List[Dict[str, Any]]:
    return gcloud_json(["compute", "instance-groups", "managed", "list"], project=project)


def list_backend_services(project: Optional[str]) -> List[Dict[str, Any]]:
    return gcloud_json(["compute", "backend-services", "list"], project=project)


def list_url_maps(project: Optional[str]) -> List[Dict[str, Any]]:
    listed = gcloud_json(["compute", "url-maps", "list"], project=project)
    detailed: List[Dict[str, Any]] = []
    for item in listed:
        name = item["name"]
        if item.get("region"):
            region = get_name(item["region"])
            detailed.append(
                gcloud_json(
                    ["compute", "url-maps", "describe", name, "--region", region],
                    project=project,
                )
            )
        else:
            detailed.append(
                gcloud_json(["compute", "url-maps", "describe", name], project=project)
            )
    return detailed


def list_target_proxies(project: Optional[str]) -> Dict[str, List[Dict[str, Any]]]:
    proxy_groups: Dict[str, List[Dict[str, Any]]] = {}
    commands = {
        "http": ["compute", "target-http-proxies", "list"],
        "https": ["compute", "target-https-proxies", "list"],
        "tcp": ["compute", "target-tcp-proxies", "list"],
        "ssl": ["compute", "target-ssl-proxies", "list"],
        "grpc": ["compute", "target-grpc-proxies", "list"],
    }
    for kind, cmd in commands.items():
        proxy_groups[kind] = gcloud_json(cmd, project=project)
    return proxy_groups


def list_forwarding_rules(project: Optional[str]) -> List[Dict[str, Any]]:
    return gcloud_json(["compute", "forwarding-rules", "list"], project=project)


def mig_matches(mig: Dict[str, Any], filters: Filters) -> bool:
    if not match_pattern(mig.get("name"), filters.mig):
        return False

    zone = get_name(mig.get("zone"))
    region = get_name(mig.get("region"))

    if filters.zone and zone != filters.zone:
        return False
    if filters.region and filters.region not in {zone.rsplit("-", 1)[0], region}:
        return False
    return True


def backend_references_group(backend_service: Dict[str, Any], group_url: str) -> bool:
    for backend in as_list(backend_service.get("backends")):
        if backend.get("group") == group_url:
            return True
    return False


def backend_matches(backend_service: Dict[str, Any], filters: Filters) -> bool:
    if not match_pattern(backend_service.get("name"), filters.backend):
        return False
    if filters.lb_scheme and load_balancing_scheme(backend_service) != filters.lb_scheme:
        return False
    if filters.region:
        scope = resource_scope(backend_service)
        if scope.startswith("regional:") and scope != f"regional:{filters.region}":
            return False
    return True


def find_url_maps_for_backend(
    url_maps: List[Dict[str, Any]],
    backend_service: Dict[str, Any],
    filters: Filters,
) -> List[Dict[str, Any]]:
    backend_refs = {
        backend_service.get("selfLink", ""),
        backend_service.get("selfLinkWithId", ""),
        backend_service.get("id", ""),
        backend_service.get("name", ""),
    }
    found = []
    for url_map in url_maps:
        if not match_pattern(url_map.get("name"), filters.url_map):
            continue
        refs = set(iter_service_refs(url_map))
        if backend_refs & refs or backend_service["name"] in {get_name(r) for r in refs}:
            found.append(url_map)
    return found


def find_proxies_for_url_map(
    proxy_groups: Dict[str, List[Dict[str, Any]]],
    url_map: Dict[str, Any],
) -> List[Tuple[str, Dict[str, Any]]]:
    url_map_refs = {url_map.get("selfLink", ""), url_map.get("name", "")}
    found: List[Tuple[str, Dict[str, Any]]] = []
    for kind, proxies in proxy_groups.items():
        for proxy in proxies:
            refs = set(iter_service_refs(proxy))
            if url_map_refs & refs or url_map["name"] in {get_name(r) for r in refs}:
                found.append((kind, proxy))
    return found


def find_proxies_for_backend(
    proxy_groups: Dict[str, List[Dict[str, Any]]],
    backend_service: Dict[str, Any],
) -> List[Tuple[str, Dict[str, Any]]]:
    backend_refs = {backend_service.get("selfLink", ""), backend_service.get("name", "")}
    found: List[Tuple[str, Dict[str, Any]]] = []
    for kind, proxies in proxy_groups.items():
        for proxy in proxies:
            refs = set(iter_service_refs(proxy))
            if backend_refs & refs or backend_service["name"] in {get_name(r) for r in refs}:
                found.append((kind, proxy))
    return found


def find_forwarding_rules(
    forwarding_rules: List[Dict[str, Any]],
    resource: Dict[str, Any],
    filters: Filters,
) -> List[Dict[str, Any]]:
    refs = {resource.get("selfLink", ""), resource.get("name", "")}
    found = []
    for rule in forwarding_rules:
        if not match_pattern(rule.get("name"), filters.forwarding_rule):
            continue
        target = rule.get("target") or rule.get("backendService") or ""
        if target in refs or get_name(target) == resource.get("name"):
            found.append(rule)
    return found


def infer_named_ports(mig: Dict[str, Any]) -> List[Dict[str, Any]]:
    named_ports = safe_get(mig, "namedPorts")
    if isinstance(named_ports, list):
        return named_ports
    return []


def suggest_resource_names(mig_name: str) -> Dict[str, str]:
    base = re.sub(r"[^a-z0-9-]+", "-", mig_name.lower()).strip("-")
    if len(base) > 35:
        base = base[:35].rstrip("-")
    return {
        "health_check": f"{base}-poc-hc",
        "backend_service": f"{base}-poc-bs",
        "url_map": f"{base}-poc-um",
        "target_proxy": f"{base}-poc-proxy",
        "forwarding_rule": f"{base}-poc-fr",
    }


def print_backend_summary(backend_service: Dict[str, Any]) -> None:
    health_checks = [get_name(hc) for hc in as_list(backend_service.get("healthChecks"))]
    print(f"  - Backend Service: {backend_service['name']}")
    print(f"    scope: {resource_scope(backend_service)}")
    print(f"    scheme: {load_balancing_scheme(backend_service)}")
    print(f"    protocol: {backend_service.get('protocol', 'UNKNOWN')}")
    print(f"    healthChecks: {', '.join(health_checks) if health_checks else '-'}")
    print(f"    sessionAffinity: {backend_service.get('sessionAffinity', '-')}")
    print(f"    timeoutSec: {backend_service.get('timeoutSec', '-')}")


def print_url_map_summary(url_map: Dict[str, Any]) -> None:
    print(f"    - URL Map: {url_map['name']} ({resource_scope(url_map)})")
    default_service = get_name(url_map.get("defaultService"))
    if default_service:
        print(f"      defaultService: {default_service}")


def print_proxy_summary(kind: str, proxy: Dict[str, Any]) -> None:
    print(f"      - Target {kind.upper()} Proxy: {proxy['name']} ({resource_scope(proxy)})")
    if proxy.get("urlMap"):
        print(f"        urlMap: {get_name(proxy.get('urlMap'))}")
    if proxy.get("service"):
        print(f"        service: {get_name(proxy.get('service'))}")
    if proxy.get("sslCertificates"):
        certs = ", ".join(get_name(c) for c in proxy.get("sslCertificates", []))
        print(f"        sslCertificates: {certs}")


def print_forwarding_rule_summary(rule: Dict[str, Any]) -> None:
    print(f"        - Forwarding Rule: {rule['name']} ({resource_scope(rule)})")
    print(f"          scheme: {rule.get('loadBalancingScheme', '-')}")
    print(f"          ip: {rule.get('IPAddress', '-')}")
    ports = (
        ",".join(rule.get("ports", []))
        if isinstance(rule.get("ports"), list)
        else rule.get("portRange", "-")
    )
    print(f"          ports: {ports}")
    if rule.get("target"):
        print(f"          target: {get_name(rule.get('target'))}")
    if rule.get("backendService"):
        print(f"          backendService: {get_name(rule.get('backendService'))}")


def main() -> int:
    args = parse_args()
    filters = Filters(
        mig=compile_pattern(args.mig),
        backend=compile_pattern(args.backend_pattern),
        url_map=compile_pattern(args.url_map_pattern),
        forwarding_rule=compile_pattern(args.forwarding_rule_pattern),
        lb_scheme=args.lb_scheme,
        region=args.region,
        zone=args.zone,
    )

    try:
        migs = [mig for mig in list_migs(args.project) if mig_matches(mig, filters)]
        backend_services = list_backend_services(args.project)
        url_maps = list_url_maps(args.project)
        proxy_groups = list_target_proxies(args.project)
        forwarding_rules = list_forwarding_rules(args.project)
    except RuntimeError as exc:
        eprint(f"ERROR: {exc}")
        return 1

    if not migs:
        eprint("No MIG matched the provided filters.")
        return 2

    total_hits = 0
    print("# Load Balancer Discovery From MIG")
    print("")
    print(f"- project: {args.project or '(gcloud default)'}")
    print(f"- mig filter: {args.mig}")
    if args.region:
        print(f"- region filter: {args.region}")
    if args.zone:
        print(f"- zone filter: {args.zone}")
    if args.lb_scheme:
        print(f"- lb scheme filter: {args.lb_scheme}")
    print("")

    for mig in migs:
        mig_name = mig["name"]
        zone = get_name(mig.get("zone"))
        region = get_name(mig.get("region"))
        instance_group = mig.get("instanceGroup", "")
        named_ports = infer_named_ports(mig)

        candidate_backends = [
            bs
            for bs in backend_services
            if backend_references_group(bs, instance_group) and backend_matches(bs, filters)
        ]

        if not candidate_backends and not args.include_empty:
            continue

        total_hits += 1
        print(f"## MIG: {mig_name}")
        print("")
        print(f"- zone: {zone or '-'}")
        print(f"- region: {region or '-'}")
        print(f"- instanceGroup: {get_name(instance_group)}")
        if named_ports:
            port_view = ", ".join(f"{p['name']}:{p['port']}" for p in named_ports)
            print(f"- namedPorts: {port_view}")
        else:
            print("- namedPorts: -")
        print("")

        if not candidate_backends:
            print("_No related backend services found._")
            print("")
            continue

        for backend_service in candidate_backends:
            print_backend_summary(backend_service)

            url_map_hits = find_url_maps_for_backend(url_maps, backend_service, filters)
            for url_map in url_map_hits:
                print_url_map_summary(url_map)
                proxy_hits = find_proxies_for_url_map(proxy_groups, url_map)
                for kind, proxy in proxy_hits:
                    print_proxy_summary(kind, proxy)
                    rule_hits = find_forwarding_rules(forwarding_rules, proxy, filters)
                    for rule in rule_hits:
                        print_forwarding_rule_summary(rule)

            direct_proxy_hits = find_proxies_for_backend(proxy_groups, backend_service)
            if direct_proxy_hits:
                print("    - Direct backend-attached proxies:")
            for kind, proxy in direct_proxy_hits:
                print_proxy_summary(kind, proxy)
                rule_hits = find_forwarding_rules(forwarding_rules, proxy, filters)
                for rule in rule_hits:
                    print_forwarding_rule_summary(rule)

            direct_rule_hits = find_forwarding_rules(forwarding_rules, backend_service, filters)
            if direct_rule_hits:
                print("    - Direct backend-attached forwarding rules:")
            for rule in direct_rule_hits:
                print_forwarding_rule_summary(rule)

        if args.suggest_names:
            names = suggest_resource_names(mig_name)
            print("")
            print("### POC Name Suggestions")
            print("")
            for key, value in names.items():
                print(f"- {key}: {value}")
        print("")

    if total_hits == 0:
        eprint("No resources matched after applying filters.")
        return 3

    print("## Notes")
    print("")
    print("- MIG 只能帮你反推出已绑定它的 backend service 和上游 LB 依赖链。")
    print("- 如果 MIG 还没有被任何 backend service 使用，这个脚本拿不到完整 LB 信息。")
    print("- 如果一个 MIG 被多个 backend service / LB 复用，这个脚本会全部列出来，便于你挑选最适合 POC 的那一条。")
    print("- 做 POC 前仍然需要确认依赖是否可共享，例如 health check、named port、firewall、证书、静态 IP、proxy-only subnet。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
