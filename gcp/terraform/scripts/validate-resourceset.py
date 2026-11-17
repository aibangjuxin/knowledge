#!/usr/bin/env python3
"""
validate-resourceset.py — validate a resourceset YAML against the canonical schema.

Usage:
    python3 scripts/validate-resourceset.py path/to/resourceset.yaml [...]

Exit codes:
    0 = all valid
    1 = validation errors (printed to stderr)
    2 = usage / I/O errors

This script is dependency-free (stdlib only) so it can run anywhere Python 3
is available — including in pre-commit hooks and CI without a `pip install`.

Schema version validated: 1.0
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SUPPORTED_SCHEMA_VERSIONS = ("1.0",)

# GCP project_id: lowercase letter start, 6-30 chars, lowercase letters/digits/hyphens,
# must end with letter or digit.
PROJECT_ID_RE = re.compile(r"^[a-z][-a-z0-9]{4,28}[a-z0-9]$")

# GCP region list — frozen set to keep validation local (no network).
GCP_REGIONS = frozenset({
    "asia-east1", "asia-east2", "asia-northeast1", "asia-northeast2", "asia-northeast3",
    "asia-south1", "asia-south2", "asia-southeast1", "asia-southeast2",
    "australia-southeast1", "australia-southeast2",
    "europe-central2", "europe-north1", "europe-southwest1", "europe-west1",
    "europe-west2", "europe-west3", "europe-west4", "europe-west6", "europe-west8",
    "europe-west9", "europe-west10", "europe-west12",
    "me-central1", "me-west1",
    "northamerica-northeast1", "northamerica-northeast2", "northamerica-south1",
    "southamerica-east1", "southamerica-west1",
    "us-central1", "us-east1", "us-east4", "us-east5", "us-south1",
    "us-west1", "us-west2", "us-west3", "us-west4",
})

VALID_SUBNET_PURPOSES = frozenset({
    "GKE", "GCE", "REGIONAL_MANAGED_PROXY", "PSC_PROXY",
    "INTERNAL_HTTPS_LOAD_BALANCER",
})

VALID_SERVICE_TYPES = frozenset({
    "nginx", "squid", "gateway", "mig", "cloudrun", "cloudfunction",
})

# Private (RFC-1918) CIDR ranges — only validate shape here; full overlap check
# requires ipaddress module (already stdlib).
CIDR_RE = re.compile(r"^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/(\d{1,2})$")

# ---------------------------------------------------------------------------
# Validator
# ---------------------------------------------------------------------------


class ValidationError:
    def __init__(self, path: str, msg: str) -> None:
        self.path = path
        self.msg = msg

    def __str__(self) -> str:
        return f"  ✗ {self.path}: {self.msg}"


def validate(data: dict[str, Any]) -> list[ValidationError]:
    """Return a list of validation errors (empty list = valid)."""
    errors: list[ValidationError] = []

    # ---- metadata ----------------------------------------------------------
    md = data.get("metadata")
    if not isinstance(md, dict):
        errors.append(ValidationError("metadata", "must be a mapping (top-level section)"))
        return errors  # Cannot continue without metadata

    version = md.get("schema_version")
    if version not in SUPPORTED_SCHEMA_VERSIONS:
        errors.append(ValidationError(
            "metadata.schema_version",
            f"must be one of {SUPPORTED_SCHEMA_VERSIONS}, got {version!r}",
        ))

    project_id = md.get("project_id")
    if not isinstance(project_id, str) or not PROJECT_ID_RE.match(project_id):
        errors.append(ValidationError(
            "metadata.project_id",
            f"must match GCP project_id regex, got {project_id!r}",
        ))

    region = md.get("region")
    if region not in GCP_REGIONS:
        errors.append(ValidationError(
            "metadata.region",
            f"must be a valid GCP region (got {region!r}; e.g. europe-west2, asia-east2, us-central1)",
        ))

    source = md.get("source")
    if source not in ("introspect", "manual", "merge"):
        errors.append(ValidationError(
            "metadata.source",
            f"must be one of introspect|manual|merge, got {source!r}",
        ))

    if not isinstance(md.get("generated_at"), str):
        errors.append(ValidationError("metadata.generated_at", "must be an ISO-8601 string"))

    # ---- project -----------------------------------------------------------
    prj = data.get("project")
    if not isinstance(prj, dict):
        errors.append(ValidationError("project", "must be a mapping"))
    else:
        if prj.get("id") != project_id:
            errors.append(ValidationError(
                "project.id",
                f"must equal metadata.project_id ({project_id!r}), got {prj.get('id')!r}",
            ))
        if not isinstance(prj.get("name"), str) or len(prj["name"]) > 30:
            errors.append(ValidationError(
                "project.name",
                "must be a string ≤30 chars",
            ))
        if not isinstance(prj.get("billing_account"), str):
            errors.append(ValidationError("project.billing_account", "must be a string"))
        services = prj.get("services")
        if not isinstance(services, list) or not services:
            errors.append(ValidationError("project.services", "must be a non-empty list"))
        else:
            for i, svc in enumerate(services):
                if not isinstance(svc, str) or not svc.endswith(".googleapis.com"):
                    errors.append(ValidationError(
                        f"project.services[{i}]",
                        f"must be a *.googleapis.com service name, got {svc!r}",
                    ))
        parent = prj.get("parent")
        if parent is not None:
            if not (isinstance(parent, str) and (
                parent.startswith("folders/") or parent.startswith("organizations/")
            )):
                errors.append(ValidationError(
                    "project.parent",
                    f"must start with 'folders/' or 'organizations/', got {parent!r}",
                ))

    # ---- network -----------------------------------------------------------
    net = data.get("network")
    if not isinstance(net, dict):
        errors.append(ValidationError("network", "must be a mapping"))
    else:
        vpc_cidr = net.get("vpc_cidr")
        if not _is_valid_cidr(vpc_cidr):
            errors.append(ValidationError(
                "network.vpc_cidr",
                f"must be a valid CIDR (e.g. 10.10.0.0/16), got {vpc_cidr!r}",
            ))
        subnets = net.get("subnets")
        if not isinstance(subnets, list) or not subnets:
            errors.append(ValidationError("network.subnets", "must be a non-empty list"))
        else:
            seen_names: set[str] = set()
            for i, sn in enumerate(subnets):
                if not isinstance(sn, dict):
                    errors.append(ValidationError(f"network.subnets[{i}]", "must be a mapping"))
                    continue
                name = sn.get("name")
                if not isinstance(name, str):
                    errors.append(ValidationError(f"network.subnets[{i}].name", "must be a string"))
                elif name in seen_names:
                    errors.append(ValidationError(
                        f"network.subnets[{i}].name",
                        f"duplicate subnet name {name!r}",
                    ))
                elif name:
                    seen_names.add(name)
                if not _is_valid_cidr(sn.get("cidr")):
                    errors.append(ValidationError(
                        f"network.subnets[{i}].cidr",
                        f"must be a valid CIDR, got {sn.get('cidr')!r}",
                    ))
                purpose = sn.get("purpose")
                if purpose not in VALID_SUBNET_PURPOSES:
                    errors.append(ValidationError(
                        f"network.subnets[{i}].purpose",
                        f"must be one of {sorted(VALID_SUBNET_PURPOSES)}, got {purpose!r}",
                    ))
                if purpose == "GKE":
                    sec = sn.get("secondary_ranges", {})
                    if not isinstance(sec, dict) or "pods" not in sec or "services" not in sec:
                        errors.append(ValidationError(
                            f"network.subnets[{i}].secondary_ranges",
                            "must contain 'pods' and 'services' for purpose=GKE",
                        ))
        if net.get("cloud_nat") and not net.get("cloud_router"):
            errors.append(ValidationError(
                "network.cloud_router",
                "required when cloud_nat=true",
            ))

    # ---- gke (optional) ----------------------------------------------------
    gke = data.get("gke")
    if gke is not None:
        if not isinstance(gke, dict):
            errors.append(ValidationError("gke", "must be a mapping"))
        else:
            for field in ("cluster_name", "region", "machine_type"):
                if not isinstance(gke.get(field), str):
                    errors.append(ValidationError(f"gke.{field}", "must be a string"))
            for field in ("min_nodes", "max_nodes"):
                if not isinstance(gke.get(field), int) or gke[field] < 1:
                    errors.append(ValidationError(f"gke.{field}", "must be a positive integer"))
            if (isinstance(gke.get("min_nodes"), int)
                    and isinstance(gke.get("max_nodes"), int)
                    and gke["max_nodes"] < gke["min_nodes"]):
                errors.append(ValidationError("gke.max_nodes", "must be ≥ gke.min_nodes"))
            if gke.get("enable_private_endpoint") and not _is_valid_cidr(gke.get("master_ipv4_cidr")):
                errors.append(ValidationError(
                    "gke.master_ipv4_cidr",
                    "required and must be a valid CIDR when enable_private_endpoint=true",
                ))

    # ---- services (optional) ----------------------------------------------
    svcs = data.get("services")
    if svcs is not None:
        if not isinstance(svcs, list):
            errors.append(ValidationError("services", "must be a list"))
        else:
            seen_service_names: set[str] = set()
            for i, svc in enumerate(svcs):
                if not isinstance(svc, dict):
                    errors.append(ValidationError(f"services[{i}]", "must be a mapping"))
                    continue
                name = svc.get("name")
                if name in seen_service_names:
                    errors.append(ValidationError(
                        f"services[{i}].name",
                        f"duplicate service name {name!r}",
                    ))
                seen_service_names.add(name)
                stype = svc.get("type")
                if stype not in VALID_SERVICE_TYPES:
                    errors.append(ValidationError(
                        f"services[{i}].type",
                        f"must be one of {sorted(VALID_SERVICE_TYPES)}, got {stype!r}",
                    ))

    # ---- backend -----------------------------------------------------------
    bk = data.get("backend")
    if not isinstance(bk, dict):
        errors.append(ValidationError("backend", "must be a mapping"))
    else:
        if not isinstance(bk.get("bucket"), str):
            errors.append(ValidationError("backend.bucket", "must be a string"))
        if not isinstance(bk.get("prefix"), str):
            errors.append(ValidationError("backend.prefix", "must be a string"))

    return errors


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _is_valid_cidr(cidr: Any) -> bool:
    if not isinstance(cidr, str):
        return False
    m = CIDR_RE.match(cidr)
    if not m:
        return False
    # Validate octets and prefix length
    octets = [int(m.group(i)) for i in range(1, 5)]
    prefix = int(m.group(5))
    if not all(0 <= o <= 255 for o in octets):
        return False
    if not (0 <= prefix <= 32):
        return False
    return True


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _is_placeholder(value: Any) -> bool:
    """Return True if a value is a CHANGEME-style template placeholder."""
    if not isinstance(value, str):
        return False
    return value.startswith("CHANGEME") or value == ""


def _collect_placeholder_paths(data: Any, prefix: str = "") -> set[str]:
    """Return dotted paths of all placeholder values in the data tree."""
    paths: set[str] = set()
    if isinstance(data, dict):
        for k, v in data.items():
            child = f"{prefix}.{k}" if prefix else str(k)
            if _is_placeholder(v):
                paths.add(child)
            else:
                paths.update(_collect_placeholder_paths(v, child))
    elif isinstance(data, list):
        for i, v in enumerate(data):
            child = f"{prefix}[{i}]"
            if _is_placeholder(v):
                paths.add(child)
            else:
                paths.update(_collect_placeholder_paths(v, child))
    return paths


def main(argv: list[str]) -> int:
    import argparse
    parser = argparse.ArgumentParser(
        description="Validate a resourceset YAML against the canonical schema (v1.0).",
    )
    parser.add_argument("files", nargs="+", help="resourceset YAML files")
    parser.add_argument(
        "--allow-placeholders", action="store_true",
        help="Skip validation on fields whose value starts with CHANGEME (for templates).",
    )
    args = parser.parse_args(argv[1:])

    total_errors = 0
    for filepath in args.files:
        if not os.path.isfile(filepath):
            print(f"ERROR: not a file: {filepath}", file=sys.stderr)
            total_errors += 1
            continue
        try:
            with open(filepath) as f:
                data = yaml.safe_load(f)
        except yaml.YAMLError as e:
            print(f"ERROR: {filepath}: invalid YAML: {e}", file=sys.stderr)
            total_errors += 1
            continue
        if not isinstance(data, dict):
            print(f"ERROR: {filepath}: top-level must be a mapping", file=sys.stderr)
            total_errors += 1
            continue
        if args.allow_placeholders:
            placeholder_paths = _collect_placeholder_paths(data)
            errors = [
                e for e in validate(data)
                if not any(e.path == p or e.path.startswith(p + ".") or e.path.startswith(p + "[")
                           for p in placeholder_paths)
            ]
        else:
            errors = validate(data)
        if errors:
            print(f"FAIL: {filepath}", file=sys.stderr)
            for err in errors:
                print(f"  {err}", file=sys.stderr)
            total_errors += len(errors)
        else:
            print(f"OK:   {filepath}")
    return 1 if total_errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))