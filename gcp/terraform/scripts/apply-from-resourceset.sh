#!/usr/bin/env bash
# apply-from-resourceset.sh — provision a new GCP project from a resourceset YAML.
#
# Usage:
#   scripts/apply-from-resourceset.sh <resourceset.yaml> [--plan-only] [--auto-approve]
#
# What it does:
#   1. Validates the resourceset YAML against the canonical schema
#   2. Renders the YAML into a terraform.tfvars file in a temp envs/ directory
#   3. Copies backend.tf / providers.tf / versions.tf from templates/env/
#   4. Runs `terraform init`, `terraform plan` (always), then `terraform apply`
#      (unless --plan-only)
#
# Examples:
#   # Dry run — show what would be created
#   scripts/apply-from-resourceset.sh resourceset/uk/aibang-uk-prd-001.yaml --plan-only
#
#   # Apply for real (will prompt for confirmation)
#   scripts/apply-from-resourceset.sh resourceset/uk/aibang-uk-prd-001.yaml
#
#   # Apply without prompt (CI / scripted)
#   scripts/apply-from-resourceset.sh resourceset/uk/aibang-uk-prd-001.yaml --auto-approve
#
# Requires:
#   - terraform (>= 1.5)
#   - jq
#   - python3 with PyYAML
#   - templates/env/, templates/module/, modules/ checked out alongside this script

set -euo pipefail

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
    cat <<EOF >&2
Usage: $0 <resourceset.yaml> [--plan-only] [--auto-approve]

Examples:
    $0 resourceset/uk/aibang-uk-prd-001.yaml --plan-only
    $0 resourceset/uk/aibang-uk-prd-001.yaml --auto-approve
EOF
    exit 2
fi

RESOURCESET="$1"
shift
PLAN_ONLY=false
AUTO_APPROVE=false
for arg in "$@"; do
    case "$arg" in
        --plan-only) PLAN_ONLY=true ;;
        --auto-approve) AUTO_APPROVE=true ;;
        *) echo "ERROR: unknown flag '$arg'" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for cmd in terraform jq python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command '$cmd' not found in PATH" >&2
        exit 2
    fi
done

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "ERROR: PyYAML not installed. Install with: pip install --user pyyaml" >&2
    exit 2
fi

if [[ ! -f "$RESOURCESET" ]]; then
    echo "ERROR: resourceset file not found: $RESOURCESET" >&2
    exit 2
fi

echo "→ Validating resourceset YAML against schema..." >&2
python3 scripts/validate-resourceset.py "$RESOURCESET"

# ---------------------------------------------------------------------------
# Render YAML → envs/<region>/<project_id>/
# ---------------------------------------------------------------------------

PROJECT_ID="$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['metadata']['project_id'])")"
REGION="$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['metadata']['region'])")"

ENV_DIR="envs/${REGION}/${PROJECT_ID}"
mkdir -p "$ENV_DIR"

echo "→ Rendering env skeleton to $ENV_DIR/..." >&2

# 1. backend.tf — bucket/prefix from the YAML
python3 <<PYEOF > "$ENV_DIR/backend.tf"
import yaml
with open("$RESOURCESET") as f:
    rs = yaml.safe_load(f)
b = rs["backend"]
print(f"""# Generated from $RESOURCESET — do not edit by hand.
# Re-run scripts/apply-from-resourceset.sh to regenerate.

terraform {{
  backend "gcs" {{
    bucket = "{b['bucket']}"
    prefix = "{b['prefix']}"
  }}
}}
""")
PYEOF

# 2. providers.tf — using local.project_id from locals.tf
cat > "$ENV_DIR/providers.tf" <<'EOF'
# Generated — see backend.tf.

provider "google" {
  project = local.project_id
  region  = local.region
}

provider "google-beta" {
  project = local.project_id
  region  = local.region
}
EOF

# 3. versions.tf — copied from templates/env
cp templates/env/versions.tf "$ENV_DIR/versions.tf"

# 4. variables.tf — flat pass-through of every YAML leaf that maps to a TF var
#    Generated from SCHEMA.md mapping; keeps the env simple, all values come
#    from terraform.tfvars.
cp templates/env/variables.tf "$ENV_DIR/variables.tf"

# 5. locals.tf — pulls project_id / region / common_labels from the YAML
python3 <<PYEOF > "$ENV_DIR/locals.tf"
import yaml
with open("$RESOURCESET") as f:
    rs = yaml.safe_load(f)
p = rs["project"]
md = rs["metadata"]
labels = p.get("labels") or {}
common_labels = "{\n"
for k, v in labels.items():
    common_labels += f'    {k} = "{v}"\n'
common_labels += "  }"

print(f"""# Generated from $RESOURCESET — do not edit by hand.

locals {{
  project_id        = "{p['id']}"
  project_id_short  = "{p['name']}"
  env               = split("-", "{p['name']}")[length(split("-", "{p['name']}")) - 1]
  region            = "{md['region']}"
  common_labels     = {common_labels}
}}
""")
PYEOF

# 6. main.tf — calls modules from the canonical mapping (see resourceset/SCHEMA.md §10).
#    We render a sensible default; users edit this for their specific workload mix.
cat > "$ENV_DIR/main.tf" <<'EOF'
# Generated from resourceset/<region>/<project_id>.yaml.
# Edit module blocks to match your workload needs. The terraform.tfvars
# carries all values; main.tf only wires them up.

module "project_bootstrap" {
  source     = "../../../modules/project-bootstrap"
  project_id = local.project_id
  apis       = var.apis
  labels     = local.common_labels
}

module "network" {
  source     = "../../../modules/network"
  project_id = module.project_bootstrap.project_id
  region     = local.region
  vpc_name   = var.vpc_name
  vpc_cidr   = var.vpc_cidr
  subnets    = var.subnets
  cloud_nat  = var.cloud_nat
}

module "gke" {
  source                   = "../../../modules/gke"
  project_id               = module.project_bootstrap.project_id
  cluster_name             = var.cluster_name
  region                   = local.region
  machine_type             = var.machine_type
  min_nodes                = var.min_nodes
  max_nodes                = var.max_nodes
  enable_private_nodes     = var.enable_private_nodes
  enable_private_endpoint  = var.enable_private_endpoint
  master_ipv4_cidr         = var.master_ipv4_cidr
  pod_ipv4_cidr            = var.pod_ipv4_cidr
  service_ipv4_cidr        = var.service_ipv4_cidr
  enable_workload_identity = var.enable_workload_identity
  labels                   = local.common_labels
}
EOF

# 7. terraform.tfvars — the actual values
python3 <<PYEOF > "$ENV_DIR/terraform.tfvars"
# Generated from $RESOURCESET — do not edit by hand.
# Re-run scripts/apply-from-resourceset.sh to regenerate.

# project
project_id  = "$PROJECT_ID"
project_name = "$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['project']['name'])")"
billing_account = "$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['project']['billing_account'])")"
folder_id = "$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['project'].get('folder_id',''))")"
apis = $(python3 -c "import yaml; import json; print(json.dumps(yaml.safe_load(open('$RESOURCESET'))['project']['services']))")

# network
vpc_name = "$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['network']['vpc_name'])")"
vpc_cidr = "$(python3 -c "import yaml; print(yaml.safe_load(open('$RESOURCESET'))['network']['vpc_cidr'])")"
subnets = $(python3 -c "import yaml; import json; print(json.dumps(yaml.safe_load(open('$RESOURCESET'))['network']['subnets']))")
cloud_nat = $(python3 -c "import yaml; print(str(yaml.safe_load(open('$RESOURCESET'))['network'].get('cloud_nat', False)).lower())")
EOF

# Append GKE block if present
python3 <<'PYEOF' >> "$ENV_DIR/terraform.tfvars"
import yaml
rs = yaml.safe_load(open("$RESOURCESET"))
if rs.get("gke"):
    g = rs["gke"]
    print()
    print("# gke")
    print(f'cluster_name             = "{g["cluster_name"]}"')
    print(f'machine_type             = "{g["machine_type"]}"')
    print(f'min_nodes                = {g["min_nodes"]}')
    print(f'max_nodes                = {g["max_nodes"]}')
    print(f'enable_private_nodes     = {str(g["enable_private_nodes"]).lower()}')
    print(f'enable_private_endpoint  = {str(g["enable_private_endpoint"]).lower()}')
    print(f'master_ipv4_cidr         = "{g["master_ipv4_cidr"]}"')
    print(f'pod_ipv4_cidr            = "{g["pod_ipv4_cidr"]}"')
    print(f'service_ipv4_cidr        = "{g["service_ipv4_cidr"]}"')
    print(f'enable_workload_identity = {str(g["enable_workload_identity"]).lower()}')
PYEOF

# ---------------------------------------------------------------------------
# Terraform workflow
# ---------------------------------------------------------------------------

cd "$ENV_DIR"

echo "→ terraform init..." >&2
terraform init -input=false

echo "→ terraform plan..." >&2
terraform plan -input=false -out=tfplan

if [[ "$PLAN_ONLY" == "true" ]]; then
    echo "✓ Plan complete. Saved to $ENV_DIR/tfplan (--plan-only was set)." >&2
    echo "  Inspect: terraform show $ENV_DIR/tfplan" >&2
    exit 0
fi

if [[ "$AUTO_APPROVE" == "false" ]]; then
    echo
    echo "About to apply the above plan to project: $PROJECT_ID (region: $REGION)"
    echo "This will CREATE real GCP resources. Ctrl-C now if unsure."
    read -r -p "Type 'yes' to continue: " answer
    if [[ "$answer" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo "→ terraform apply..." >&2
terraform apply -input=false tfplan

echo "✓ Done. Apply complete for $PROJECT_ID ($REGION)." >&2