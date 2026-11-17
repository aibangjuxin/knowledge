---
name: gke-asm-lifecycle
description: GKE Service Mesh (Cloud Service Mesh / ASM) install, upgrade, uninstall, and verification lifecycle. Use when tasked with installing/upgrading/uninstalling ASM or CSM on a GKE cluster, verifying whether ASM is currently installed (read-only checks), running pre-uninstall safety procedures, or generating a runbook for any destructive mesh operation. Covers both managed CSM (controlplanerevision/mdp-controller) and in-cluster (istiod) paths.
---

# GKE Service Mesh Lifecycle

## When to Load This Skill

- Verifying whether ASM/CSM is installed on a GKE cluster (read-only, safe to run)
- Installing or upgrading ASM (managed or in-cluster control plane)
- **Uninstalling** ASM (any path) — destructive, see "Runbook-First" pattern
- Authoring a runbook for any destructive mesh operation
- Diagnosing mesh-related issues during install/upgrade/uninstall
- Reviewing mesh architecture decisions (in-cluster vs managed, sidecar vs proxyless)

## Knowledge Base (User-Specific Doc Index)

The user maintains a substantial ASM knowledge base at `/Users/lex/git/gcp/asm/`. **This skill is a navigation layer over that base** — load the relevant doc directly rather than re-deriving from upstream docs.

### By Lifecycle Stage

| Stage | Doc | Size | Notes |
|---|---|---|---|
| **Setup / Install** | `google-ams-setup.md` | 85 KB | **Main install reference.** Most complete walkthrough. |
| | `How-to-setup-istio-nosidecar.md` | 33 KB | No-sidecar pattern (Gateway + HTTPRoute, no istio-proxy) |
| | `requirement.md` | 4 KB | Pre-flight requirements |
| **Version selection** | `asm-version.md` | 5.2 KB | Version compatibility matrix |
| | `asm-think.md` | 3.3 KB | Reasoning notes on version choices |
| **Uninstall** | `how-to-uninstall-service-mesh.md` | 20 KB | **Canonical runbook** (read this first) |
| **Troubleshooting** | `debug-gw-pod-start.md` | 7.4 KB | Gateway Pod start failures |
| | `how-to-resolve-grpc-config.md` | 17 KB | gRPC + mesh config issues |
| | `status.md` | 20 KB | Current status snapshot |
| **Testing** | `e2e-testing.md` | 48 KB | E2E test suite |
| **Architecture** | `gateways-type.md` | 19 KB | Gateway type comparison |
| | `summary.md` / `summary-gemini.md` | 6 / 4 KB | High-level summaries |
| **Sub-areas** | `dp/` | 8 files | Dataplane-specific (sidecar config) |
| | `netpol/` | 5 files | Network Policy integration |
| | `tls/` | 27 files | mTLS / certificate config |
| | `diagram/` | 4 files | Architecture diagrams |

### By Topic Sub-Area

- **Sidecar injection** → `dp/` + `How-to-setup-istio-nosidecar.md`
- **Network Policy** → `netpol/`
- **mTLS / certificates** → `tls/`
- **Gateway API / Ingress** → `gateways-type.md`

## Official Source-of-Truth Docs

When the user's knowledge base conflicts with upstream, **upstream wins** (the user updates their notes from upstream):

- **Uninstall**: https://docs.cloud.google.com/service-mesh/docs/uninstall (last updated 2026-06-01)
- **Install (managed)**: https://cloud.google.com/service-mesh/docs/managed/provision-managed-control-plane
- **Install (in-cluster)**: https://cloud.google.com/service-mesh/docs/in-cluster/install
- **Upgrade**: https://cloud.google.com/service-mesh/docs/upgrade
- **Fleet / Membership**: https://cloud.google.com/anthos/fleet-management/docs

## Critical Patterns

### Runbook-First Destructive Ops (MANDATORY for uninstall/upgrade)

**Pattern**: For any destructive mesh operation, **produce the full runbook first, then ask before executing.**

1. **Stage the runbook** with verification (read-only) → pre-flight safety → main ops → verification after
2. **Save as markdown** in the user's knowledge base (e.g., `/Users/lex/git/gcp/asm/<name>.md`)
3. **Present to user with explicit go/no-go options**:
   - "Run stage 1 only (read-only verification)"
   - "Run all stages"
   - "I'll run it myself, you standby"
4. **Wait for explicit consent** before mutating the cluster

**Why**: Memory may contain prior constraints (e.g., "test cluster, do not log in casually"). User may have changed their mind, but you should surface the conflict — never silently override a prior safety note.

**Template structure** (15-stage pattern, see `how-to-uninstall-service-mesh.md` for canonical example):

| Stage | Purpose | Risk |
|---|---|---|
| 0 | Pre-flight (tools, auth, variables) | None |
| 1 | **Verification (read-only)** — 10+ checks | Zero |
| 2 | Pre-uninstall safety (downgrade mTLS, remove AuthzPolicy) | Very low |
| 3 | Disable fleet auto-management | Per-membership, reversible |
| 4 | Disable namespace sidecar injection | None |
| 5 | **Restart workloads to remove sidecars** | **Disruptive** |
| 6 | Delete webhooks | Low |
| 7 | Delete controlplanerevision (managed only) | Medium |
| 8 | `istioctl uninstall --purge` (in-cluster only) | Medium |
| 9 | Delete namespaces (`istio-system` / `asm-system`) | Medium (can stick) |
| 10 | Disable fleet mesh feature (fleet-wide, irreversible) | High |
| 11 | Cleanup managed data plane + **submit Support case** | Medium |
| 12 | Cleanup CNI residuals (configmap + daemonset) | Low |
| 13 | Cleanup Traffic Director (snk) | Low |
| 14 | Final 8-item verification (read-only) | Zero |
| 15 | RBAC cleanup + archive runbook | Low |

Each stage must have an explicit checkpoint in the runbook execution log table.

### Verify-Before-Mutate (Always)

Before any uninstall/upgrade step, **always run a read-only verification pass first**. The 10-item checklist:

1. `kubectl get ns | grep -E 'istio-system|asm-system'`
2. `kubectl get pods -n istio-system`
3. `kubectl get crd | grep -E 'controlplanerevision|dataplanecontrol'`
4. `kubectl get controlplanerevision -n istio-system`
5. `gcloud container fleet memberships list` + `gcloud container hub mesh describe`
6. `kubectl get ns --show-labels | grep -E 'istio-injection|istio.io/rev='`
7. `kubectl get pods -A -o json | jq '...containers[].name | select(=="istio-proxy")...'`
8. `kubectl get daemonset -n kube-system | grep -E 'istio-cni|snk'`
9. `kubectl get configmap -n kube-system | grep istio-cni-plugin-config`
10. `kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep istio`

Summary decision matrix:

| Check | In-cluster | Managed | Not Installed |
|---|---|---|---|
| `istio-system` ns | ✅ | ✅ | ❌ |
| `istiod-*` Pod | ✅ | ✅ | ❌ |
| `controlplanerevision` CR | ❌ | ✅ | ❌ |
| `mdp-controller` (kube-system) | ❌ | ✅ | ❌ |
| `istio.io/rev=` ns labels | maybe | maybe | ❌ |
| Pods with `istio-proxy` | maybe | maybe | ❌ |

### Managed vs In-Cluster Path Branching

**The single most important question** when uninstalling/upgrading: is this managed CSM or in-cluster ASM?

```bash
# Quick detector (run from bastion via IAP — see gcp-iap-tunnel skill)
kubectl get controlplanerevision -n istio-system 2>/dev/null
# Has output → managed CSM
# Empty + has istiod pods → in-cluster
# Empty + no istio-system ns → not installed
```

Each path has different steps:
- **Managed CSM**: stage 7 (controlplanerevision), stage 11 (mdp-controller + dataplanecontrol CR + Support case required)
- **In-cluster**: stage 8 (istioctl uninstall --purge), no Support case needed

### Managed CSM Cleanup: Support Case OR `gcloud hub mesh disable`

For Managed CSM uninstall, the cloud-side cleanup is non-negotiable — without it:
- `istio-system` namespace gets repeatedly recreated
- Network Endpoint Groups (NEGs) are orphaned
- Uninstall falls back to "fail open" mode

There are **two paths** to signal "this cluster is done with CSM":

| Path | When to use | Reversible? | Speed |
|---|---|---|---|
| **Google Cloud Support case** (stage 11.4) | Prod fleets, multi-cluster, when fleet feature must stay enabled | Yes (Support can re-enable) | Days (Support SLA) |
| **`gcloud container hub mesh disable`** (stage 10) | Dev clusters, single-cluster fleets, when you're OK to lose fleet-level mesh feature | **No (irreversible)** | Immediate |

**`gcloud container hub mesh disable` details**:
```bash
# Disable the mesh feature for the entire FLEET HOST PROJECT
gcloud container hub mesh disable --project $FLEET_PROJECT_ID
# After this: gcloud container hub mesh describe returns "Service Mesh Feature is not enabled"
# This stops the Google fleet feature controller from recreating CRDs (see CRITICAL pitfall below)
```

**When to pick which**:
- **Dev cluster, single fleet, no prod peers in same fleet host project** → use `gcloud hub mesh disable` (self-service, immediate, no human in the loop)
- **Prod cluster, multi-cluster fleet, other clusters use CSM** → submit Support case (or `gcloud fleet memberships unregister <cluster>` first to scope the impact, then disable)
- **Mixed fleet with other prod projects** → ALWAYS Support case (the `gcloud hub mesh disable` would affect prod peers)

The Support case must include: project ID, cluster ID, uninstall timestamp, runbook URL, desired cleanup window.

### Use IAP-Tunneled Bastion for Cluster Access

Cluster operations should run through a bastion via `gcloud compute ssh --tunnel-through-iap`. See **gcp-iap-tunnel** skill for:
- Output filtering (`grep -v 'WARNING:.*NumPy\|setlocale'`)
- Region vs zone mixing
- **Network troubleshooting when kubectl hangs — see "PREFERRED Fix: Re-fetch kubeconfig with --internal-ip"** (this is the standard fix for managed-CSM uninstall on a private cluster with authorized networks)
- First-call latency
- **Safety-block patterns to avoid** (don't manually `kubectl --server=...` rewrite; use gcloud-native flags instead)

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Runbook executed before user approval | Cluster mutated without consent | Always runbook-first, explicit go/no-go |
| Forgot to downgrade STRICT mTLS | Apps break during uninstall | Stage 2.1 — drop PeerAuthentication to PERMISSIVE first |
| Deleted namespaces with workloads still injecting | Restart loop, sidecars stuck | Stage 5 — restart workloads BEFORE deleting ns |
| istioctl not on bastion | `command not found` during stage 8 | Download: `curl -L https://istio.io/downloadIstio \| sh -` (only for in-cluster uninstall) |
| `kubectl get ns` from bastion times out 90s+ | Network path broken | `gcloud get-credentials --internal-ip` (see gcp-iap-tunnel "PREFERRED Fix" section) |
| `--zone` used for regional cluster | Empty results | Use `--region` for regional clusters (auto-detect pattern in gke-cluster-lifecycle skill) |
| Forgot cleanup for managed CSM | istio-system / CRDs come back | Stage 10 OR Support case (see "Managed CSM Cleanup" section above) |
| `cluster.x.x` endpoint is private IP | Bastion can't reach it | `gcloud get-credentials --internal-ip` (preferred) OR add bastion NAT IP to masterAuthorizedNetworksConfig |
| **🔴 CRD auto-recreation by Google fleet controller (Managed CSM)** | After deleting `controlplanerevisions.mesh.cloud.google.com` and `dataplanecontrols.mesh.cloud.google.com`, they reappear within 30s with new `CREATED` timestamps | **Order matters**: do `gcloud container hub mesh disable` (stage 10) BEFORE stage 11.5 (delete CRDs). Otherwise mdp-controller is gone but the higher-level Google fleet feature controller keeps re-installing them. Verify with a 30s sleep + re-check after final delete. |
| **`image: auto` placeholder in gateway deployment** | After removing injection label and rolling out, new Pod stuck `ErrImagePull: image "auto"` | This is **expected behavior** during uninstall — `image: auto` is a literal placeholder that the sidecar injector webhook replaces at admission time. Once injection is disabled, kubelet tries to pull the literal `auto:latest` and fails. **Don't try to fix it** — the namespace will be deleted in stage 9 anyway. The OLD pod keeps running until then, so no traffic impact. |
| **Support case prompt says it requires cluster ID, but I have cluster NAME** | Support form rejects "cluster name" input | Cluster ID (numeric) ≠ Cluster Name (string). Get ID with: `gcloud container clusters describe $NAME --format="value(id)"` |
| **Tenant workloads in `istio-injection=disabled` namespace** | Look like they need sidecar handling but don't | They have no sidecars — restart, mTLS, AuthzPolicy all NO-OP. Verify with `kubectl get pods -n <ns> -o jsonpath='{.items[*].spec.containers[*].name}'` — if no `istio-proxy`, safe to skip stage 5. |
| **Fleet membership name ≠ cluster name** | `gcloud container fleet mesh update --memberships <NAME>` fails with "membership not found" | Membership name is what `gcloud container fleet memberships list` shows, often different from cluster name (e.g., cluster `dev-lon-cluster-xxxxxx` registered as membership `aibang-master`). Discover first: `gcloud container fleet memberships list --project=$FLEET_PROJECT_ID` |

## Stage Order Gotcha: Stage 10 Before Stage 11.5

The canonical 15-stage table lists stage 10 (disable fleet mesh) AFTER stage 11.5 (delete CRDs) because the official Google doc puts them in that order. **In practice this order is wrong for managed CSM**. The correct order is:

```
stage 11.1  delete mdp-controller
stage 11.3  delete dataplanecontrol CRs
stage 11.5  delete managed CSM CRDs        ← will be RECREATED
stage 10    disable fleet mesh feature     ← stop the recreator
stage 11.5  RE-delete managed CSM CRDs     ← now they stay gone
```

Or equivalently, just do stage 10 before stage 11.5 in the first pass. The official doc order assumes a Support case will handle the cloud-side cleanup, which stops the recreator. If you use the self-service `gcloud hub mesh disable` path instead, do it BEFORE the final CRD delete.

**Verification**: after deleting CRDs the second time, sleep 30s and re-check. If they're still gone, the recreator is stopped.

## Reference Files

- `references/2026-06-03-uninstall-session-notes.md` — Real session notes from a Managed CSM uninstall on a private GKE cluster (IAP-tunneled bastion, regional, ISTIOD, nosidecar tenant). Captures the 7 most important discoveries: (1) the CRD auto-recreation trap and its root cause, (2) the `gcloud get-credentials --internal-ip` workflow with the authorized-networks allowlist trap, (3) the `image: auto` placeholder behavior during rollout, (4) nosidecar-mode = 0-disruption uninstall, (5) `gcloud hub mesh disable` vs Support case decision matrix, (6) the final 8-item verification with 30s sleep, (7) cross-references to companion skills.

## Related Skills

- **gcp-iap-tunnel** — SSH to bastion via IAP (essential for cluster access)
- **gke-cluster-lifecycle** — Cluster version/upgrade lifecycle (adjacent concerns)
- **architectrue** — Production architecture partner; this skill is mesh-specific companion
