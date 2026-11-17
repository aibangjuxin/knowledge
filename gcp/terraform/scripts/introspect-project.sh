#!/usr/bin/env bash
# introspect-project.sh — dump an existing GCP project's infra into resourceset YAML.
#
# Usage:
#   scripts/introspect-project.sh <project_id> <region>
#   scripts/introspect-project.sh aibang-uk-prd-001 europe-west2
#
# Output:
#   resourceset/<region>/<project_id>.yaml
#
# Requires:
#   - gcloud CLI authenticated (gcloud auth login / gcloud auth application-default login)
#   - jq
#   - python3 with PyYAML
#
# What it captures:
#   - project metadata (services, billing account, folder)
#   - VPC + subnets (purpose + secondary ranges)
#   - GKE clusters in the given region
#   - (Phase 2) Cloud NAT, Cloud Armor, MIGs, etc. — see TODO at bottom
#
# What it does NOT capture:
#   - Workloads running inside the cluster (Pods, Deployments, Services) —
#     use `kubectl` for those, they don't belong in terraform.
#
# Exit codes:
#   0 = success, YAML written
#   1 = validation error (project doesn't exist, no VPC, etc.)
#   2 = usage / dependency error

set -euo pipefail

# ---------------------------------------------------------------------------
# Args & preflight
# ---------------------------------------------------------------------------

if [[ $# -ne 2 ]]; then
    cat <<EOF >&2
Usage: $0 <project_id> <region>

Example:
    $0 aibang-uk-prd-001 europe-west2

Output:
    resourceset/<region>/<project_id>.yaml
EOF
    exit 2
fi

PROJECT_ID="$1"
REGION="$2"

DRY_RUN=false
if [[ "${3:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

for cmd in gcloud jq python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command '$cmd' not found in PATH" >&2
        exit 2
    fi
done

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "ERROR: PyYAML not installed. Install with: pip install --user pyyaml" >&2
    exit 2
fi

if [[ "$DRY_RUN" == "false" ]]; then
    # Quick auth check
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null | head -1 | grep -q .; then
        echo "ERROR: gcloud has no active account. Run: gcloud auth login" >&2
        exit 2
    fi

    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        echo "ERROR: cannot access project '$PROJECT_ID'. Check name + permissions." >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Pull data via gcloud
# ---------------------------------------------------------------------------

echo "→ Introspecting project metadata..." >&2
PROJECT_JSON="$(gcloud projects describe "$PROJECT_ID" --format=json)"
BILLING_ACCOUNT="$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingAccount.name)" 2>/dev/null || echo "")"
BILLING_ACCOUNT="${BILLING_ACCOUNT##*/}"  # strip "billingAccounts/" prefix
ENABLED_SERVICES="$(gcloud services list --project="$PROJECT_ID" --enabled --format="value(config.name)" 2>/dev/null | sort)"

echo "→ Introspecting VPC + subnets..." >&2
VPCS_JSON="$(gcloud compute networks list --project="$PROJECT_ID" --format=json)"
# Pick the "main" VPC: prefer one whose name contains the project_id, else first.
VPC_NAME="$(echo "$VPCS_JSON" | jq -r --arg pid "$PROJECT_ID" \
    '.[] | select(.name | contains($pid)) | .name' | head -1)"
if [[ -z "$VPC_NAME" ]]; then
    VPC_NAME="$(echo "$VPCS_JSON" | jq -r '.[0].name // empty')"
fi
if [[ -z "$VPC_NAME" ]]; then
    echo "ERROR: no VPC found in project '$PROJECT_ID'. Nothing to introspect." >&2
    exit 1
fi

SUBNETS_JSON="$(gcloud compute networks subnets list \
    --project="$PROJECT_ID" --network="$VPC_NAME" --format=json)"
VPC_ROUTING_MODE="$(gcloud compute networks describe "$VPC_NAME" \
    --project="$PROJECT_ID" --format="value(routingConfig.routingMode)" 2>/dev/null || echo REGIONAL)"

# Cloud NAT (only check default NAT on the region; custom NAT routers not handled yet)
NAT_ROUTER="$(gcloud compute routers list \
    --project="$PROJECT_ID" --region="$REGION" --format="value(name)" 2>/dev/null | head -1 || true)"
HAS_NAT=false
if [[ -n "$NAT_ROUTER" ]]; then
    if gcloud compute routers nats list --router="$NAT_ROUTER" \
        --project="$PROJECT_ID" --region="$REGION" --format="value(name)" 2>/dev/null | grep -q .; then
        HAS_NAT=true
    fi
fi

echo "→ Introspecting GKE clusters in $REGION..." >&2
GKE_JSON="$(gcloud container clusters list \
    --project="$PROJECT_ID" --region="$REGION" --format=json)"

# ---------------------------------------------------------------------------
# Emit YAML
# ---------------------------------------------------------------------------

OUT_PATH="resourceset/${REGION}/${PROJECT_ID}.yaml"
mkdir -p "$(dirname "$OUT_PATH")"

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 <<PYEOF
import json
import sys
import yaml

with open("/dev/stdin") as f:
    pass

project = json.loads('''$PROJECT_JSON''')
vpcs = json.loads('''$VPCS_JSON''')
subnets_raw = json.loads('''$SUBNETS_JSON''')
gke_clusters = json.loads('''$GKE_JSON''')

billing_account = "$BILLING_ACCOUNT"
enabled_services = """$ENABLED_SERVICES""".split()
vpc_routing_mode = "$VPC_ROUTING_MODE" or "REGIONAL"
vpc_name = "$VPC_NAME"
nat_router = "$NAT_ROUTER" or None
has_nat = "$HAS_NAT" == "true"

def yn(b):
    return bool(b)

# --- project services
services = sorted(s for s in enabled_services if s.endswith(".googleapis.com"))

# --- folder / org parent
parent = project.get("parent", {})
parent_str = ""
if parent.get("type") == "folder":
    parent_str = f"folders/{parent['id']}"
elif parent.get("type") == "organization":
    parent_str = f"organizations/{parent['id']}"

# --- subnets
subnets = []
for sn in subnets_raw:
    purpose_map = {
        "PRIVATE": "GCE",
        "REGIONAL_MANAGED_PROXY": "REGIONAL_MANAGED_PROXY",
        "PRIVATE_SERVICE_CONNECT": "PSC_PROXY",
        "INTERNAL_HTTPS_LOAD_BALANCER": "INTERNAL_HTTPS_LOAD_BALANCER",
    }
    purpose = purpose_map.get(sn.get("purpose", ""), "GCE")
    entry = {
        "name": sn["name"],
        "cidr": sn["ipCidrRange"],
        "region": sn["region"],
        "purpose": purpose,
        "private_google_access": yn(sn.get("privateIpGoogleAccess", False)),
    }
    # Secondary ranges (typically GKE pods/services)
    sec_ranges = sn.get("secondaryIpRanges") or []
    if sec_ranges:
        entry["secondary_ranges"] = {
            r.get("rangeName"): r["ipCidrRange"] for r in sec_ranges
        }
    subnets.append(entry)

# --- VPC CIDR (derive from largest subnet; or use compute networks describe's routingConfig)
vpc_cidr = ""
for v in vpcs:
    if v["name"] == vpc_name:
        # CIDR isn't in the network resource directly — derive from subnets' parent range
        # (won't be perfect if subnets were added ad-hoc, but works for greenfield)
        vpc_cidr = subnets[0]["cidr"].rsplit(".", 1)[0] + ".0.0/16" if subnets else "10.0.0.0/16"
        break
if not vpc_cidr:
    vpc_cidr = "10.0.0.0/16"

# --- GKE cluster (pick first in region)
gke_block = None
if gke_clusters:
    c = gke_clusters[0]
    # Master IPv4 CIDR
    master_cidr = ""
    private_cfg = c.get("privateClusterConfig") or {}
    if private_cfg.get("enablePrivateEndpoint"):
        master_cidr = private_cfg.get("masterIpv4CidrBlock", "")
    pod_cidr = ""
    svc_cidr = ""
    ipa = c.get("ipAllocationPolicy") or {}
    pod_cidr = ipa.get("clusterIpv4Cidr", "") or ipa.get("servicesIpv4Cidr", "")
    svc_cidr = ipa.get("servicesIpv4Cidr", "")
    # Sometimes pod range comes via subnetwork secondaryRange
    node_pools = c.get("nodePools", [])
    min_nodes = sum(np.get("initialNodeCount", 0) for np in node_pools) if node_pools else 1
    max_nodes = max((np.get("autoscaling", {}).get("maxNodeCount", 0)
                     for np in node_pools), default=min_nodes)
    machine_type = (node_pools[0].get("config", {}).get("machineType", "n2-standard-4")
                    if node_pools else "n2-standard-4")
    release_channel = c.get("releaseChannel", {}).get("channel", "REGULAR")
    maint_window = c.get("maintenancePolicy", {}).get("window", {})
    maint_start = ""
    if maint_window.get("recurringWindow"):
        mw = maint_window["recurringWindow"]
        maint_start = mw.get("startTime", "")
    labels = {}
    # Labels can be on resourceLabels
    rl = c.get("resourceLabels") or {}
    labels = {k: v for k, v in rl.items()}

    gke_block = {
        "cluster_name": c["name"],
        "region": c.get("location", "$REGION"),
        "machine_type": machine_type,
        "min_nodes": min_nodes,
        "max_nodes": max_nodes,
        "enable_private_nodes": yn(private_cfg.get("enablePrivateNodes", False)),
        "enable_private_endpoint": yn(private_cfg.get("enablePrivateEndpoint", False)),
        "master_ipv4_cidr": master_cidr,
        "pod_ipv4_cidr": pod_cidr,
        "service_ipv4_cidr": svc_cidr,
        "release_channel": release_channel,
        "enable_workload_identity": yn(c.get("workloadIdentityConfig", {}).get("workloadPool") != ""),
        "maintenance_start_time": maint_start,
        "labels": labels,
    }

# --- backend (convention)
backend_block = {
    "bucket": f"terraform-state-$REGION",  # placeholder; adjust per project naming
    "prefix": f"gke/$REGION",
}

out = {
    "metadata": {
        "schema_version": "1.0",
        "project_id": project["projectId"],
        "region": "$REGION",
        "source": "introspect",
        "generated_at": "$GENERATED_AT",
        "generated_by": "scripts/introspect-project.sh $PROJECT_ID $REGION",
        "notes": f"Introspected from live GCP project via gcloud. Review and edit before using as template.",
    },
    "project": {
        "id": project["projectId"],
        "name": project["name"],
        "billing_account": billing_account,
        "parent": parent_str or None,
        "services": services,
        "labels": project.get("labels", {}),
    },
    "network": {
        "vpc_name": vpc_name,
        "vpc_cidr": vpc_cidr,
        "routing_mode": vpc_routing_mode,
        "subnets": subnets,
        "cloud_nat": has_nat,
        "cloud_router": nat_router,
        "private_google_access": True,
    },
    "backend": backend_block,
}
if gke_block:
    out["gke"] = gke_block

# Default YAML flow style for inline lists
class FlowList(list): pass

def str_representer(dumper, data):
    return dumper.represent_str(data)

yaml.add_representer(str, str_representer)

with open("$OUT_PATH", "w") as f:
    f.write("# ResourceSet: $PROJECT_ID\n")
    f.write("# Introspected from live GCP project at $GENERATED_AT\n")
    f.write("# Review, edit, then use as template for new projects.\n")
    f.write("# Schema v1.0 — see resourceset/SCHEMA.md\n\n")
    yaml.safe_dump(out, f, sort_keys=False, default_flow_style=False, width=100)

print(f"→ Wrote $OUT_PATH", file=sys.stderr)
PYEOF

echo "→ Validating generated YAML..." >&2
python3 "$(dirname "$0")/validate-resourceset.py" "$OUT_PATH"
echo "✓ Done." >&2