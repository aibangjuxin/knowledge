# ResourceSet — Canonical Schema

> **ResourceSet** is a single declarative YAML file describing the full infra
> footprint of one GCP project in one region. It serves two roles:
>
> 1. **Template for new projects** — copy it, change a few values, run
>    `scripts/apply-from-resourceset.sh` to materialize a matching project.
> 2. **Source of truth / drift baseline** — `scripts/introspect-project.sh`
>    re-dumps the live GCP project back into the same schema, so you can
>    diff against the canonical YAML.
>
> Schema version: **1.0** (see `metadata.schema_version`).

---

## 1. Top-level shape

```yaml
metadata:    # required — identity & provenance
project:     # required — GCP project metadata
network:     # required — VPC + subnets + NAT
gke:         # optional  — GKE cluster (omit if project has no GKE)
services:    # optional  — workloads on the cluster (Nginx/Squid/MIG/...)
backend:     # required — Terraform state bucket + prefix
addons:      # optional  — cert-manager / cloud-armor / monitoring / secrets
```

| Section    | Required | Notes                                                         |
|------------|----------|---------------------------------------------------------------|
| metadata   | ✅        | Always present; drives the YAML filename                      |
| project    | ✅        | What the GCP project looks like                               |
| network    | ✅        | Every GCP project has a VPC + at least one subnet             |
| gke        | ⚠️        | Omit if the project has no GKE cluster (e.g. pure MIG)        |
| services   | ⚠️        | Omit if the project has only infra (no in-cluster workloads)  |
| backend    | ✅        | Where TF state lives — never optional                        |
| addons     | ❌        | Free-form map; keys: cert_manager / cloud_armor / monitoring / secret |

---

## 2. `metadata` — identity & provenance

```yaml
metadata:
  schema_version: "1.0"           # required, must equal "1.0" today
  project_id: "aibang-uk-prd-001" # required, GCP project_id (matches project.id)
  region: "europe-west2"          # required, primary region for this env
  source: "introspect"            # required, one of: introspect | manual | merge
  generated_at: "2026-06-27T12:00:00Z"  # required, ISO-8601 UTC
  generated_by: "scripts/introspect-project.sh gcp/aibang-uk-prd-001 europe-west2"  # optional, free-form
  notes: "UK production, mirrors HK with smaller footprint"  # optional, free-form
```

**Validation rules:**

- `schema_version` must match a known version (currently `"1.0"`).
- `project_id` must equal `project.id` (cross-checked by `apply-from-resourceset.sh`).
- `region` must be a valid GCP region (validated against a built-in list).
- `source` must be one of `introspect` (script-generated), `manual` (hand-written),
  `merge` (script + manual fixes). Used to flag auto-regenerated fields.

**Filename rule:** `resourceset/<region>/<project_id>.yaml`.
The script uses `metadata.project_id` + `metadata.region` to write the file in
the right place. The filename is canonical — don't rename without renaming
the project.

---

## 3. `project` — GCP project metadata

```yaml
project:
  id: "aibang-uk-prd-001"           # required, GCP project_id
  name: "aibang-uk-prd"             # required, display name (≤30 chars)
  billing_account: "012345-6789AB-CDEF01"  # required, billing account ID
  folder_id: "folders/9876543210"   # optional, "folders/<numeric>" or null
  parent: "folders/9876543210"      # required (folder or org), same as folder_id today
  services:                          # required, APIs to enable
    - compute.googleapis.com
    - container.googleapis.com
    - servicenetworking.googleapis.com
    - cloudresourcemanager.googleapis.com
  labels:                            # optional, key/value pairs (≤64 pairs)
    env: "prd"
    region: "europe-west2"
    owner: "platform-team"
```

**Validation rules:**

- `id` matches regex `^[a-z][-a-z0-9]{4,28}[a-z0-9]$` (GCP project_id rules).
- `name` ≤ 30 chars.
- `services` must be a non-empty list of valid `*.googleapis.com` service names.
- `labels` keys ≤ 63 chars, values ≤ 63 chars, both `^[a-z0-9_-]+$` (lowercase only).
- `parent` is `"folders/<id>"` or `"organizations/<id>"`.

---

## 4. `network` — VPC + subnets + NAT

```yaml
network:
  vpc_name: "aibang-uk-prd-vpc"      # required
  vpc_cidr: "10.10.0.0/16"           # required, RFC-1918 range
  routing_mode: "REGIONAL"           # optional, default REGIONAL; or GLOBAL
  subnets:                           # required, ≥1
    - name: "gke-nodes"
      cidr: "10.10.0.0/20"
      region: "europe-west2"
      purpose: "GKE"                 # GKE | GCE | REGIONAL_MANAGED_PROXY | PSC_PROXY
      private_google_access: true
      secondary_ranges:               # optional, for GKE pod/service ranges
        pods: "10.20.0.0/14"
        services: "10.24.0.0/20"
    - name: "proxy-only"
      cidr: "10.10.32.0/28"
      region: "europe-west2"
      purpose: "PSC_PROXY"
    - name: "mig"
      cidr: "10.10.48.0/20"
      region: "europe-west2"
      purpose: "GCE"
  cloud_nat: true                    # optional, default false
  cloud_router: "aibang-uk-prd-router"  # required if cloud_nat=true
  private_google_access: true        # optional, default false (set per-subnet)
```

**Validation rules:**

- `vpc_cidr` must be RFC-1918.
- All subnet CIDRs must fit inside `vpc_cidr`.
- Subnet `purpose` must be one of: `GKE` | `GCE` | `REGIONAL_MANAGED_PROXY`
  | `PSC_PROXY` | `INTERNAL_HTTPS_LOAD_BALANCER`.
- For `purpose: GKE`, `secondary_ranges.pods` and `secondary_ranges.services`
  are required.
- `cloud_router` required iff `cloud_nat: true`.
- Subnet names must be unique within the VPC.

---

## 5. `gke` — Kubernetes cluster (omit if no GKE)

```yaml
gke:
  cluster_name: "aibang-uk-prd-gke"   # required
  region: "europe-west2"              # required, usually == metadata.region
  machine_type: "n2-standard-8"       # required
  min_nodes: 3                        # required, ≥1
  max_nodes: 20                       # required, ≥ min_nodes
  enable_private_nodes: true          # required, strongly recommended true
  enable_private_endpoint: false      # required, true = master is private
  master_ipv4_cidr: "172.16.0.0/28"   # required (private cluster)
  pod_ipv4_cidr: "10.20.0.0/14"       # required if gke-nodes has secondary_range.pods
  service_ipv4_cidr: "10.24.0.0/20"   # required
  release_channel: "REGULAR"          # optional, default REGULAR; or STABLE | RAPID | NONE
  enable_workload_identity: true      # required, strongly recommended true
  maintenance_start_time: "2026-01-01T03:00:00Z"  # optional, RFC-5545
  network_tags:                       # optional
    - "gke-node"
  labels:
    env: "prd"
```

**Validation rules:**

- `master_ipv4_cidr` must be `/28` and outside all subnet CIDRs.
- `pod_ipv4_cidr` and `service_ipv4_cidr` must not overlap any subnet CIDR.
- `min_nodes` ≥ 1, `max_nodes` ≥ `min_nodes`.
- If `enable_private_endpoint: true`, `master_ipv4_cidr` is mandatory.

---

## 6. `services` — workloads on the cluster

A list of in-cluster workloads (Gateways, Deployments, MIGs). Each entry is a
typed component:

```yaml
services:
  - name: "nginx-gateway"
    type: "nginx"                     # nginx | squid | gateway | mig
    namespace: "nginx"                # required
    replicas: 3                       # optional, default 1
    config:                           # optional, free-form key/value
      upstream: "http://squid.squid.svc.cluster.local:3128"
      image: "nginx:1.27"
      resources:
        cpu: "500m"
        memory: "512Mi"
  - name: "squid-proxy"
    type: "squid"
    namespace: "squid"
    replicas: 2
    config:
      listen_port: 3128
      allowed_networks: "10.10.0.0/16"
  - name: "api-mig"
    type: "mig"
    namespace: null                   # MIGs are outside the cluster
    config:
      machine_type: "n2-standard-4"
      instance_template: "aibang-api-tmpl"
      target_size: 3
```

**Validation rules:**

- `type` must be one of: `nginx` | `squid` | `gateway` | `mig` | `cloudrun` |
  `cloudfunction`.
- `namespace` required for in-cluster types, `null` for `mig` / `cloudrun`.
- `name` must be unique across the file.
- `config` is free-form; each `type` has its own expected keys (documented
  per type in `references/service-types.md`).

---

## 7. `backend` — Terraform state location

```yaml
backend:
  bucket: "terraform-state-uk-prd-001"   # required
  prefix: "gke/europe-west2"             # required, "namespace/key" style
```

**Convention:**

- Bucket: `terraform-state-<region>-<env>` (e.g. `terraform-state-uk-prd`).
- Prefix: `<stack>/<region>` (e.g. `gke/europe-west2`).
- Bucket is created by `scripts/init-backend.sh` (see `references/state-and-backend.md`).

---

## 8. `addons` — optional capabilities

Free-form key/value per addon. Each key corresponds to a module:

```yaml
addons:
  cert_manager:
    domains:
      - "example.com"
      - "*.example.com"
    dns_challenge: true
  cloud_armor:
    policies:
      - name: "default-deny"
        rules:
          - priority: 1000
            action: "deny(403)"
            match:
              versioned_expr: "SRC_IPS_V1"
              config:
                src_ip_ranges: ["1.2.3.0/24"]
  monitoring:
    notification_channels:
      - "projects/PROJECT_ID/notificationChannels/dev-team"
    alerts:
      - name: "high-cpu"
        threshold: 0.85
        duration: "300s"
  secret:
    secrets:
      - name: "db-password"
        source: "sm://db-password"        # SM path
```

**Convention:** each key under `addons` mirrors the corresponding Terraform
module name in `modules/`. Adding a new addon = adding a new key here + adding
the corresponding `module {}` block in the env's `main.tf`.

---

## 9. Schema evolution

When changing the schema:

1. Bump `schema_version` in `metadata` (e.g. `1.0` → `1.1`).
2. Add an entry to `references/schema-changelog.md` with date + breaking/added.
3. Update `scripts/introspect-project.sh` to emit the new shape.
4. Update existing YAMLs in `resourceset/**` to the new shape via
   `scripts/migrate-resourceset.sh` (to be authored with each breaking change).
5. Bump the validator's accepted version list in
   `scripts/validate-resourceset.py`.

**Backward compatibility rule:** minor version (1.0 → 1.1) may add optional
fields. Major version (1.x → 2.0) may rename / remove fields.

---

## 10. Quick reference — which YAML field maps to which TF variable

| YAML key                       | Terraform variable                                | Required? |
|--------------------------------|---------------------------------------------------|-----------|
| `project.id`                   | `var.project_id`                                  | ✅         |
| `project.name`                 | `var.project_name`                                | ✅         |
| `project.billing_account`      | `var.billing_account`                             | ✅         |
| `project.folder_id`            | `var.folder_id`                                   | ⚠️         |
| `project.services[]`           | `var.apis` (in `modules/project-bootstrap`)       | ✅         |
| `network.vpc_name`             | `var.vpc_name` (in `modules/network`)             | ✅         |
| `network.vpc_cidr`             | `var.vpc_cidr`                                    | ✅         |
| `network.subnets[]`            | `var.subnets` (map of objects)                    | ✅         |
| `network.cloud_nat`            | `var.enable_cloud_nat`                            | ⚠️         |
| `gke.cluster_name`             | `var.cluster_name`                                | ✅ (if gke)|
| `gke.region`                   | `var.region` (gke module)                         | ✅ (if gke)|
| `gke.machine_type`             | `var.machine_type`                                | ✅ (if gke)|
| `gke.min_nodes` / `max_nodes`  | `var.min_nodes` / `var.max_nodes`                 | ✅ (if gke)|
| `gke.master_ipv4_cidr`         | `var.master_ipv4_cidr`                            | ✅ (if gke)|
| `gke.pod_ipv4_cidr`            | `var.pod_ipv4_cidr`                               | ✅ (if gke)|
| `gke.service_ipv4_cidr`        | `var.service_ipv4_cidr`                           | ✅ (if gke)|
| `services[]`                   | `module.<name>.config` (passed to workload modules) | ⚠️       |
| `backend.bucket` / `prefix`    | `backend "gcs" { bucket = ... prefix = ... }`     | ✅         |
| `addons.cert_manager`          | `var.cert_manager_config`                         | ❌         |

This mapping is the contract that `scripts/apply-from-resourceset.sh` uses to
generate `terraform.tfvars` from the YAML. If you add a YAML field, add the
TF variable mapping here in the same commit.