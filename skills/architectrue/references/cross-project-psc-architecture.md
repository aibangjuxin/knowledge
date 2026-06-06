---
name: cross-project-psc-architecture
description: Cross-project GCP architecture via PSC NEG (Tenant/Producer split) — Regional External/Internal HTTPS LB chain anchored to a regional PSC NEG, with proxy-only subnet purpose migration, Shared VPC IAM gotchas, and restricted-environment bypass insight
---

# Cross-Project PSC NEG Architecture

## Pattern

A Project (Tenant) hosts a Regional External or Internal HTTPS Load Balancer as the entry point. Backend is a **PSC NEG** (type=`PRIVATE_SERVICE_CONNECT`) that bridges to B Project's Service Attachment over a Google-internal tunnel — no VPC Peering required, producer controls access via allowlist.

```
External / VPC Client
  → LB (Tenant, regional, scheme=EXTERNAL_MANAGED or INTERNAL_MANAGED)
  → URL Map (regional) → Backend Service (regional, matching scheme)
  → PSC NEG (regional, type=PRIVATE_SERVICE_CONNECT)
  → [GCP internal tunnel, SNAT'd via Producer's PSC NAT subnet]
  → B Project Service Attachment → ILB → Backend
```

**Source-of-truth docs in user's knowledge tree**:
- `gcp/asm/3.md` — overview + Producer (B Project) side resources
- `gcp/asm/3-tenant-project.md` — comprehensive Tenant side resource guide (940 lines, 3 scripts)
- `gcp/cross-project/psc-firewall.md` — Producer-side backend VM firewall rules
- `gcp/cross-project/cross-project-psc-architecture.{html,svg}` — dark-themed SVG architecture diagram (visual reference)
- `gcp/lb/refer-lb-create.sh` — reverse-extract tool for understanding existing LB chains
- `gcp/ingress/public-ingress/public-ingress-tenant-project-psc.md` — concrete 1468-line implementation guide for both Public + Internal two-mode pattern in restricted enterprise environments

## 5 Critical Gotchas (all trip up first-time implementers)

### Gotcha 1: PSC NEG forces the entire LB chain to be **regional**

A Backend Service referencing a regional PSC NEG cannot be `global`. The whole chain follows:

| Resource | Scope | `--load-balancing-scheme` |
|---|---|---|
| Health Check | regional | n/a |
| PSC NEG | regional (always) | n/a |
| Backend Service | regional | `EXTERNAL_MANAGED` / `INTERNAL_MANAGED` |
| URL Map | regional | n/a |
| Target HTTPS Proxy | regional | n/a |
| Forwarding Rule | regional | matches Backend Service |

**Wrong** (from the original 3.md): `gcloud compute backend-services create ... --global --protocol=HTTPS` — fails with `Network Endpoint Group ... is in region X but backend service is in region Y`.

**Right**:
```bash
gcloud compute backend-services create ${POC}-bs \
  --region=${REGION} \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTPS \
  --health-checks=${POC}-hc \
  --health-checks-region=${REGION}   # ← must be explicit
```

### Gotcha 2: Regional External HTTPS LB **mandatorily** requires a Proxy-only Subnet

Without it, Forwarding Rule creation fails with:
> `Invalid value for field 'resource.IPAddress': ... 'The load balancing scheme EXTERNAL_MANAGED requires a proxy-only subnet'`

```bash
gcloud compute networks subnets create ${PROXY_SUBNET} \
  --project=${HOST_PROJECT} \
  --network=${VPC_NETWORK} \
  --region=${REGION} \
  --range=10.0.2.0/24 \
  --purpose=REGIONAL_MANAGED_PROXY \
  --role=ACTIVE
```

| Flag | Required value | Why |
|---|---|---|
| `--purpose` | `REGIONAL_MANAGED_PROXY` | marks subnet as LB-proxy-only, business VMs cannot use it |
| `--role` | `ACTIVE` | one ACTIVE per region/VPC (vs BACKUP for HA configs) |
| `--range` | ≥ /26 | GCP minimum; production should be /23 ~ /20 |

> ⚠️ Consumer subnet (for PSC NEG) is a **separate** ordinary subnet — do NOT confuse the two. The proxy-only subnet serves Envoy, the consumer subnet serves PSC NEG IP allocation.

### Gotcha 3: Reference resources on regional gcloud commands need explicit `-region` flags

When creating a regional resource that **references** another resource, gcloud defaults to looking up the **global** version unless you explicitly pass the matching region flag. This is silent — it only fails at runtime as "not found".

```bash
# ❌ Default looks for global url-map, fails with "url map not found"
gcloud compute target-https-proxies create ${POC}-proxy \
  --url-map=${POC}-um

# ✅ Explicit region match
gcloud compute target-https-proxies create ${POC}-proxy \
  --region=${REGION} \
  --url-map=${POC}-um \
  --url-map-region=${REGION}        # ← mandatory
  --ssl-certificates=${POC}-cert    # global cert, no -region needed

gcloud compute forwarding-rules create ${POC}-fr \
  --region=${REGION} \
  --target-https-proxy=${POC}-proxy \
  --target-https-proxy-region=${REGION}   # ← mandatory
  --address=${POC}-glb-ip \
  --address-region=${REGION}              # ← mandatory
  --ports=443
```

**Mnemonic**: any time you see a `-proxy`, `-map`, `-address` reference on a regional command, add the matching `-region` flag. Same applies to backend services' `--health-checks-region`.

### Gotcha 4: Shared VPC IAM granularity — `--network` vs `--subnetwork` on PSC NEG

PSC NEG creation validates IAM. In Shared VPC, IAM can be granted at two granularities:

| Granularity | Command | Effect |
|---|---|---|
| **Network level** | `gcloud projects add-iam-policy-binding HOST ... roles/compute.networkUser` | Service Project can use ALL subnets in the network |
| **Subnet level** | `gcloud compute networks subnets add-iam-policy-binding SUBNET ... roles/compute.networkUser` | Service Project can only use the specific subnet |

**The trap**: when creating PSC NEG, gcloud's behavior differs:

- Specifying `--network` triggers a **network-level** IAM check. If your IAM is subnet-level only → **FAIL** with `Permission denied`.
- Specifying only `--subnetwork` triggers a **subnet-level** IAM check. If your IAM is on that subnet → **PASS**.

**Workaround when IAM is subnet-level**:
```bash
# Either: omit --network entirely
gcloud compute network-endpoint-groups create ${POC}-neg \
  --region=${REGION} \
  --network-endpoint-type=PRIVATE_SERVICE_CONNECT \
  --psc-target-service=${SERVICE_ATTACHMENT_URI} \
  --subnetwork=${CONSUMER_SUBNET}     # ← only -subnetwork

# Or: pre-elevate to network-level IAM (if org allows)
gcloud projects add-iam-policy-binding ${HOST_PROJECT} \
  --member="serviceAccount:${TENANT_PROJECT}@appspot.gserviceaccount.com" \
  --role="roles/compute.networkUser"
```

### Gotcha 5: Proxy-only Subnet `purpose` migration is mandatory for new LB types

Many enterprise environments have an existing proxy-only subnet created when Regional Internal L7 LB was the only option, with `--purpose=INTERNAL_HTTPS_LOAD_BALANCER`. GCP has since standardized on `REGIONAL_MANAGED_PROXY` for **all** managed proxy LBs (Regional External, Regional Internal, Cross-region Internal).

**The trap**:
- Console UI will silently let you proceed then error at Forwarding Rule creation with `The load balancing scheme EXTERNAL_MANAGED requires a proxy-only subnet`
- The existing `INTERNAL_HTTPS_LOAD_BALANCER` subnet **does not satisfy** the new purpose check
- This is the most common org-environment failure mode

**Check current purpose**:
```bash
gcloud compute networks subnets describe ${PROXY_SUBNET} \
  --project=${HOST_PROJECT} --region=${REGION} \
  --format="value(purpose,role)"
# INTERNAL_HTTPS_LOAD_BALANCER → must migrate
# REGIONAL_MANAGED_PROXY        → directly usable
```

**Migrate (low-risk; existing LB traffic is not interrupted)**:
```bash
# Backup first
gcloud compute networks subnets describe ${PROXY_SUBNET} \
  --project=${HOST_PROJECT} --region=${REGION} > proxy-subnet-backup.json

# Migrate
gcloud compute networks subnets update ${PROXY_SUBNET} \
  --project=${HOST_PROJECT} --region=${REGION} \
  --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE

# Rollback if anything breaks
gcloud compute networks subnets update ${PROXY_SUBNET} \
  --project=${HOST_PROJECT} --region=${REGION} \
  --purpose=INTERNAL_HTTPS_LOAD_BALANCER --role=ACTIVE
```

> Requires `compute.networkAdmin` on the Host Project — Service Project users cannot perform this.

## Restricted-Environment Bypass Insight

> **Org policies that restrict `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` are automatically irrelevant in any PSC NEG scenario.**

The corollary of Gotcha #1 (PSC NEG forces the entire LB chain to be regional) is:
- The LB scheme can only be `EXTERNAL_MANAGED` (Regional External), `INTERNAL_MANAGED` (Regional Internal), or `INTERNAL` (Regional L4) — never `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS`
- Any `constraints/compute.restrictLoadBalancingCreation` org policy denying Global External LB types **does not need an exception**
- The practical implication: in restricted enterprise environments, **Regional External/Internal HTTPS LB + PSC NEG is the only viable GLB-like architecture** — and it's actually the right one anyway

**When this matters**: a common pattern is an org that already disabled Global GLBs for cost/security reasons but still needs public ingress. PSC NEG bridges them — the LB is regional but the backend is cross-project, giving you "Global GLB semantics with Regional LB constraints" for free.

**Related insight — `--allow-global-access` flag on Producer's ILB is also unneeded** in the same-region case (it only matters when Producer's region differs from Tenant's). See `gcp/psa-psc/psc-cross-region.md` for the cross-region Global Access detail.

## 4-Way LB Type Decision Matrix (Public/Internal × Global/Regional)

When the user says "I need a GLB" in a PSC NEG scenario, the first question to ask is "Public or Internal?" then "Global or Regional?" — yielding 4 candidate LB types. The full matrix exposes what's actually feasible:

| # | LB Type | Public/Internal? | IP Type | PSC NEG Compatible? | Affected by `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` Org Policy? | Requires Proxy-only Subnet? | Verdict |
|---|---|---|---|---|---|---|---|
| **A** | Regional External Application LB | **Public** (anycast, PREMIUM tier) | External IP | ✅ Yes | ❌ **No** (regional) | ✅ Yes (purpose=`REGIONAL_MANAGED_PROXY`) | ⭐⭐⭐⭐⭐ **Recommended** — public ingress |
| **B** | Regional Internal Application LB | **Internal** (VPC-only) | Internal IP | ✅ Yes | ❌ **No** | ✅ Yes | ⭐⭐⭐⭐ **Recommended** — internal ingress |
| **C** | Global External Application LB | **Public** (anycast) | Global Anycast IP | ❌ **No** — PSC NEG is regional, hangs from regional backend service. Fails: `Network Endpoint Group ... is in region X but backend service is in region Y` | ✅ **Yes** (and likely blocked by your org policy anyway) | ✅ Yes | ❌ **Infeasible** in PSC NEG scenarios, blocked by both API design AND org policy |
| **D** | Cross-region Internal Application LB | **Internal** (multi-region Anycast) | Internal IP (anycast) | ⚠️ **Theoretically** — but the LB is global-ish, the backend service is still regional, and the `--load-balancing-scheme=INTERNAL_MANAGED` cross-region is a special GCP primitive; mixing with PSC NEG adds complexity | ❌ No | ✅ Yes | ⭐⭐ — only for cross-region HA / DR, complexity rarely justified |

**Reachability table (when `GLOBAL_EXTERNAL_MANAGED_HTTP_HTTPS` is org-blocked)**:
- A — feasible
- B — feasible
- C — doubly blocked (org + PSC NEG)
- D — feasible but rarely useful

**Engineering consequence**: in any PSC NEG scenario, the answer is always A or B (or both for dual-mode). The user's framing of "I need a GLB" should be translated to "I need a Regional External/Internal LB" without argument. Do not spend time investigating "is Global GLB available" — even if it were unblocked, PSC NEG would prevent using it.

The **"Two-Mode (Public / Internal) Symmetric Pattern"** section below covers A + B in detail with the 3-difference table and dual-mode script template.

## Global Access flag distinction (cross-region Producer)

When the user asks "do I need to enable Global Access?", the answer depends on whether Tenant and Producer are in the same region:

| Same region? | Producer ILB `--allow-global-access` | Consumer PSC Endpoint `--allow-psc-global-access` |
|---|---|---|
| Yes (typical) | ❌ Not needed | ❌ Not needed |
| No, different regions | ✅ **Required** on Producer's ILB forwarding rule | ✅ **Required** on Consumer's PSC endpoint (if any) |
| No, but only LB bridge (PSC NEG) | ✅ **Required** on Producer's ILB; Consumer side needs no extra config | n/a (PSC NEG is auto-routed) |

**The two flags are easily confused** — different name, different side, different routing target:

- `--allow-global-access` — on the **ILB Forwarding Rule** (Producer side). Allows cross-region traffic to reach the Service Attachment.
- `--allow-psc-global-access` — on the **PSC Endpoint Forwarding Rule** (Consumer side, when using PSC Endpoint instead of PSC NEG). Allows the PSC endpoint IP to be reached from cross-region VMs or on-prem.

In a PSC NEG scenario with regional LB bridge, **only the first flag matters**; the second is irrelevant because PSC NEG is not a PSC Endpoint.

## Two-Mode (Public / Internal) Symmetric Pattern

When the requirement is **both** a public-facing and an internal-facing LB bridged to the same PSC NEG (or a pair of Service Attachments), the two LBs share 10 of 13 resource classes. Only 3 differ:

| # | Resource | Public (EXTERNAL_MANAGED) | Internal (INTERNAL_MANAGED) |
|---|---|---|---|
| 3 | Static IP | `--network-tier=PREMIUM --ip-version=IPV4` | `--subnet=${CONSUMER_SUBNET} --purpose=GCE_ENDPOINT --address-type=INTERNAL` |
| 7 | Backend Service | `--load-balancing-scheme=EXTERNAL_MANAGED` | `--load-balancing-scheme=INTERNAL_MANAGED` |
| 12 | Forwarding Rule | `--load-balancing-scheme=EXTERNAL_MANAGED --network-tier=PREMIUM --ports=443` | `--load-balancing-scheme=INTERNAL_MANAGED --network=${VPC_NETWORK} --subnet=${CONSUMER_SUBNET} --ports=443` |

**Engineering pattern**: a single bash script with an `LB_SCHEME` env var switching between the two. The user-facing command is the same; only the environment variable differs.

```bash
# Public (default)
bash create-public-internal-lb.sh

# Internal
LB_SCHEME=INTERNAL_MANAGED bash create-public-internal-lb.sh
```

See `templates/cross-project-psc-architecture/create-public-internal-lb.sh` for the canonical implementation.

### Cloud Armor binding (mandatory pattern across both modes)

Cloud Armor **must** be attached to the **backend service**, not the forwarding rule or URL map. The CLI flag on `forwarding-rules update --security-policy=...` does not exist; the silent-fail path is creating the policy but never binding it.

```bash
# 1. Create policy (global resource)
gcloud compute security-policies create ${POC}-armor \
  --project=${TENANT_PROJECT} --description="PSC-protected LB"

# 2. Add rules (rate limit, geo, WAF — order matters, lowest priority first)
gcloud compute security-policies rules create 1000 \
  --project=${TENANT_PROJECT} --security-policy=${POC}-armor \
  --expression="true" --action=rate-based-ban \
  --rate-limit-threshold-count=200 \
  --rate-limit-threshold-interval-sec=60 --ban-duration-sec=600

# 3. BIND to backend service (the only valid attach point)
gcloud compute backend-services update ${POC}-bs \
  --project=${TENANT_PROJECT} --region=${REGION} \
  --security-policy=${POC}-armor
```

**Capability matrix** (Cloud Armor support varies by LB type):

| Capability | EXTERNAL_MANAGED | INTERNAL_MANAGED |
|---|---|---|
| Rate limiting | ✅ | ✅ |
| Header / method / URL path matchers | ✅ | ✅ |
| Named IP / IP range allow/deny | ✅ | ✅ |
| Geographic restriction | ✅ | ❌ (private IP clients have no region code) |
| Preconfigured WAF rules | ✅ | ❌ |
| Custom WAF (SQLi/XSS) | ✅ | ❌ |
| Adaptive Protection | ✅ | ❌ |
| Bot management | ✅ | ❌ |

> If an Internal LB truly needs WAF, use External LB with a private-VPC fronted entry point, or deploy a WAF proxy in B Project.

## Resource Inventory Template (13 classes)

| # | Resource | Scope | gcloud key flags |
|---|---|---|---|
| 1 | Consumer Subnet | regional | `--purpose` default (PRIVATE) |
| 2 | **Proxy-only Subnet** | regional | `--purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE` (see Gotcha #5 for migration) |
| 3 | Static IP | regional | Public: `--network-tier=PREMIUM`; Internal: `--subnet=X --address-type=INTERNAL` |
| 4 | SSL Certificate | **global** | (Google-managed) `--domains=...` or (self-managed) `--certificate + --private-key` |
| 5 | Health Check | regional | `--protocol=HTTP --port=80 --request-path=/healthz` |
| 6 | **PSC NEG** | regional | `--network-endpoint-type=PRIVATE_SERVICE_CONNECT --psc-target-service=...` |
| 7 | Backend Service | regional | `--load-balancing-scheme={EXTERNAL_MANAGED,INTERNAL_MANAGED} --protocol=HTTPS` |
| 8 | add-backend | regional | `--network-endpoint-group + --network-endpoint-group-region` |
| 9 | Cloud Armor Policy (opt) | **global** | See "Cloud Armor binding" section above for full command sequence; **bind to backend service, not forwarding rule** |
| 10 | URL Map | regional | `--default-service=BS` |
| 11 | Target HTTPS Proxy | regional | `--url-map=UM --url-map-region=R --ssl-certificates=CERT` |
| 12 | Forwarding Rule | regional | Public: `--target-https-proxy=... --target-https-proxy-region=R --ports=443 --network-tier=PREMIUM`; Internal: same + `--network=... --subnet=...` |
| 13 | Firewall Rule | regional | (only needed for IAP SSH debug; PSC NEG health check traffic is internal) |

> **Global-only**: SSL cert (4) and Cloud Armor Policy (9). Everything else is regional.

## Service Attachment Approval Flow

PSC NEG creation succeeds but `pscConnectionId` is empty → Service Attachment hasn't approved the Tenant Project. Check and fix:

```bash
# Tenant side: empty pscConnectionId?
gcloud compute network-endpoint-groups describe ${POC}-neg \
  --region=${REGION} --format="json" | jq '.pscConnectionId'

# Producer side: list connected endpoints
gcloud compute service-attachments describe ${PRODUCER_SA} \
  --project=${PRODUCER_PROJECT} --region=${REGION} \
  --format="json" | jq '.connectedEndpoints'

# If empty, either:
#   (a) Service Attachment was created with --connection-preference=ACCEPT_MANUAL
#       → Producer must approve (in console: PSC → Service Attachment → Connected endpoints → Approve)
#   (b) --consumer-accept-list didn't include ${TENANT_PROJECT}
#       → Producer must re-create with --consumer-accept-list=${TENANT_PROJECT}=N
```

## Reverse-Extract Workflow (when starting from an existing reference LB)

Use `gcp/lb/refer-lb-create.sh` to discover the resource shape of an existing MIG-based LB, then translate to PSC NEG:

```bash
# 1. Run the reverse-extract on a reference project with a working LB
bash /Users/lex/git/knowledge/gcp/lb/refer-lb-create.sh <MIG_NAME> \
  --project <REFERENCE_PROJECT> --region ${REGION} --prefix ref

# 2. From the output, capture these values:
#    - port-name (e.g., "https", "http")
#    - health check protocol/port/path
#    - named ports on MIG (matches port-name)
#    - load-balancing-scheme (EXTERNAL_MANAGED vs INTERNAL_MANAGED)
#    - protocol (HTTPS vs HTTP vs HTTP2)

# 3. Use these values as defaults in templates/cross-project-psc-architecture/create-tenant-lb.sh
#    → swap the MIG-based backend add for network-endpoint-group add
#    → swap the reference project for the tenant project
#    → swap the URL/IP target for the Service Attachment URI
```

## Diagnostic Commands

```bash
# PSC NEG health
gcloud compute network-endpoint-groups get-health ${POC}-neg \
  --project=${TENANT_PROJECT} --region=${REGION}

# Backend service → NEG backends
gcloud compute backend-services describe ${POC}-bs \
  --project=${TENANT_PROJECT} --region=${REGION} \
  --format="json" | jq '.backends'

# Health check passing through to producer
gcloud compute backend-services get-health ${POC}-bs \
  --project=${TENANT_PROJECT} --region=${REGION} --format="json"

# Forwarding rule actual state
gcloud compute forwarding-rules describe ${POC}-fr \
  --project=${TENANT_PROJECT} --region=${REGION} \
  --format="json" | jq '{IPAddress, portRange, target, loadBalancingScheme}'

# Real HTTPS probe
curl -sk -o /dev/null -w "%{http_code}\n" https://${GLB_IP}/
```

## Cleanup Order (forwarding rule → everything else, reverse of creation)

```bash
gcloud compute forwarding-rules delete ${POC}-fr --region=${REGION} --quiet
gcloud compute target-https-proxies delete ${POC}-proxy --region=${REGION} --quiet
gcloud compute url-maps delete ${POC}-um --region=${REGION} --quiet
gcloud compute backend-services delete ${POC}-bs --region=${REGION} --quiet
gcloud compute network-endpoint-groups delete ${POC}-neg --region=${REGION} --quiet
gcloud compute health-checks delete ${POC}-hc --region=${REGION} --quiet
gcloud compute security-policies delete ${POC}-armor --quiet                # global (if attached)
gcloud compute ssl-certificates delete ${POC}-cert --quiet                  # global
gcloud compute addresses delete ${POC}-glb-ip --region=${REGION} --quiet
# Host Project subnets — leave or delete depending on reuse
gcloud compute networks subnets delete proxy-only-subnet \
  --project=${HOST_PROJECT} --region=${REGION} --quiet
```

## Templates Provided

- `templates/cross-project-psc-architecture/create-tenant-lb.sh` — idempotent create all 13 resources (single-mode, External)
- `templates/cross-project-psc-architecture/verify-tenant-lb.sh` — 3-layer verify: resource existence + association + real HTTPS traffic
- `templates/cross-project-psc-architecture/cleanup-tenant-lb.sh` — reverse-order delete
- `templates/cross-project-psc-architecture/create-public-internal-lb.sh` — **dual-mode** create (Public / Internal) via `LB_SCHEME` env var; includes Cloud Armor binding and proxy-only subnet purpose migration logic
- `templates/cross-project-psc-architecture/verify-public-internal-lb.sh` — dual-mode verify; respects `LB_SCHEME` to skip external curl for Internal IP
- `templates/cross-project-psc-architecture/cleanup-public-internal-lb.sh` — dual-mode cleanup

## See also (environment-specific applications)

- `references/cross-project-psc-environment-aibang.md` — concrete application of this pattern to the user's `aibang-12345678-ajbx-dev` project: europe-west2 / dev-lon-cluster-xxxxxx GKE / IAP-tunneled bastion, with 12-class inventory and three idempotent scripts (`setup-public-ingress.sh` / `verify-public-ingress.sh` / `cleanup-public-ingress.sh`). Includes the "IAP bastion + Private GKE Master Authorized Networks" workflow that lets the operator run all `gcloud` commands against the GKE cluster from a Mac without exposing the Master to the public internet.
- `references/same-project-psc-test-setup.md` — **same-project variant** for when you have only one GCP project and need to test PSC NEG patterns (typical POC). Documents the fundamental limitation that Regional `EXTERNAL_MANAGED` Backend Service cannot attach a PSC NEG when both consumer and producer share the same project + VPC (the documented GCP error: "EXTERNAL MANAGED Backend Service in scope REGION can not use Private Service Connect network endpoint group that is in producer network and targets Service Attachment"), the 4 workarounds (2-VPC variant, no-PSC direct, GKE Standalone NEG, "illusion of different networks"), and 9 operational gotchas (no-address MIG needs Cloud NAT for apt, regional MIG uses `--instance-group-region` not `-zone`, PSC NEG cannot have backend-service health check, Cloud Armor rate limit needs `--conform-action`/`--exceed-action`, etc.). Includes a Python stdlib HTTPS server recipe that bypasses the no-apt-on-no-address-VM problem.
