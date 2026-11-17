---
name: k8s-gateway-multitenant-runbook
description: Author or update K8s Gateway API + ListenerSet multi-tenant runbooks for GKE. Covers cross-NS rules (ReferenceGrant vs allowedRoutes selector vs Secret duplicate), HTTPS backend with self-signed cert (nginx-unprivileged + setcap + DR SIMPLE), and the protocol for reverse-engineering a verification shell script into a deployable markdown runbook. Use when adding a new tenant to an existing multi-tenant Gateway setup, when switching backend protocol (HTTP↔HTTPS↔mTLS), when documenting a deployed multi-tenant HTTPS ingress stack, or when onboarding a new team to the `*.team.appdev.aibang` ListenerSet pattern.
---

# K8s Gateway API + ListenerSet Multi-Tenant Runbook

Author and maintain runbooks for K8s Gateway API + ListenerSet multi-tenant HTTPS ingress on GKE. Captures the protocol, cross-NS rules, HTTPS backend pattern, verification-script reverse-engineering technique, and runbook structure conventions.

## When to Load

- Adding a new tenant / service to an existing 1 Gateway + N ListenerSet setup
- Writing a new runbook for an already-deployed K8s Gateway API multi-tenant stack
- Updating a runbook when backend protocol changes (HTTP → HTTPS, plain → mTLS)
- Onboarding a new team to the `*.team.appdev.aibang` ListenerSet pattern
- Reverse-engineering a verification shell script into a deployable markdown runbook
- Reviewing a runbook for cross-NS pitfall coverage (especially Secret mount, ReferenceGrant confusion)

Do NOT load for:
- Mesh install/upgrade/uninstall → use `gke-asm-lifecycle` instead
- General GKE architecture decisions → use `architectrue`
- K8s Gateway API design choices (which GatewayClass, which Gateway controller) → use `architectrue`

## Mental Model: 1 Gateway + N ListenerSets

The pattern that makes the runbook meaningful:

```
┌──────────────────────────────────────────────────────────────┐
│ Platform team owns:                                          │
│  • 1 Gateway  (abjx-gw-int/abjx-gw-int)                     │
│  • 1 ILB      (auto-reconciled by gatewayClass=istio)        │
│  • N ListenerSets  (1 per team, e.g. team1-listenerset)      │
│  • Wildcard TLS Secret in listenerset NS                     │
│                                                              │
│ Each tenant team owns:                                       │
│  • Own tenant NS  (label: gateway-access=<selector-value>)  │
│  • Own HTTPRoute  (parentRefs → ListenerSet in shared NS)    │
│  • Own Service    (ClusterIP)                                │
│  • Own Deployment (HTTPS backend, mounts cert duplicate)     │
│  • Own DestinationRule (DR SIMPLE for self-signed cert)     │
│  • Own ConfigMap (nginx https config)                        │
└──────────────────────────────────────────────────────────────┘
```

**Cost story** (the why): 1 ILB instead of N. 1 Gateway control plane instead of N. New tenants just add a ListenerSet or attach to an existing one with their own HTTPRoute — no new GCP-managed load balancer.

## The 4-YAML Minimum for a New Tenant

For a new tenant (e.g., `newapi` in `team1` NS) attaching to an existing ListenerSet, the standard 4-5 resource set is:

| # | Resource | File convention | Purpose |
|---|----------|----------------|---------|
| 1 | `Service` (ClusterIP, 443→443, appProtocol: https) | `<name>-service.yaml` | Backend ClusterIP |
| 2 | `Deployment` (nginx-unprivileged + setcap + cert mount) | `<name>-deployment.yaml` | Pod spec |
| 2a | `ConfigMap` (nginx `listen 443 ssl` config) | inline in `<name>-deployment.yaml` (separated by `---`) | nginx config |
| 3 | `HTTPRoute` (parentRef: ListenerSet, hostname, filters) | `<name>-httproute.yaml` | K8s Gateway API route |
| 4 | `DestinationRule` (tls.mode: SIMPLE + insecureSkipVerify) | `<name>-destinationrule.yaml` | istio DR for HTTPS backend |

**Naming convention**: use `<name>-<resource>.yaml` prefix to avoid conflicts with sibling tenants (e.g., `app-deployment.yaml` vs `newapi-deployment.yaml`).

**Deployment 2-doc pattern** (matches existing runbook): Deployment + ConfigMap in the same file separated by `---`. kubectl handles multi-doc natively.

## CRITICAL: Cross-NS Reference Rules

This is the **#1 source of runbook errors and confusion**. The user got bitten by it in `k8s-gateway/03-§3` of the existing runbook. Always get this right in the runbook's "Preconditions" and "Failure modes" sections.

| Reference direction | Needs ReferenceGrant? | Why |
|--------------------|------------------------|-----|
| HTTPRoute (NS-A) → Service (NS-A) | ❌ No | Same NS, no cross-NS reference |
| HTTPRoute (NS-A) → Service (NS-B) | ✅ **Yes** | Create ReferenceGrant in NS-B allowing HTTPRoute from NS-A |
| HTTPRoute (NS-A) → Gateway (NS-B) | ❌ **No** (not ReferenceGrant) | Controlled by Gateway's `spec.allowedRoutes.namespaces` |
| HTTPRoute (NS-A) → ListenerSet (NS-B) | ❌ **No** (not ReferenceGrant) | Controlled by ListenerSet's `spec.allowedRoutes.namespaces.selector` |
| Gateway (NS-A) → Secret (NS-A) | ❌ No | Same NS |
| Gateway (NS-A) → Secret (NS-B) | ✅ **Yes** | Cross-NS Secret reference needs ReferenceGrant |
| **Pod (NS-A) → Secret (NS-A) mount** | N/A (same NS, normal) | Pod can only mount Secret in its own NS |
| **Pod (NS-A) → Secret (NS-B) mount** | ❌ **ReferenceGrant does NOT help** | K8s Secret is namespace-scoped; ReferenceGrant only governs Gateway API resources (HTTPRoute, ListenerSet) referencing Service/Secret. **The only fix is to duplicate the Secret into the Pod's NS** using `kubectl get secret -n <src> -o json \| jq '...\| .metadata.namespace = "<dst>"' \| kubectl apply -f -` |

**The ListenerSet "selector" pattern** (the most common in this user's setup):
- ListenerSet has `spec.allowedRoutes.namespaces.selector.matchLabels: gateway-access: "ajbx-int"`
- Tenant NS must have label `gateway-access: ajbx-int` for HTTPRoute to be accepted
- If HTTPRoute `status.parents[].conditions[Accepted] = False, reason=NotAllowedByListeners` → missing label, run `kubectl label ns <tenant> gateway-access=ajbx-int`

**The "Pod mount Secret needs duplicate" pitfall** (the most-confused rule):
- Wildcard TLS cert lives in listenerset NS (`abjx-listenerset-int/abjx-lex-eg-secret-team1-tls`)
- Backend Pod in tenant NS (`team1`) wants to mount the same cert as nginx server cert
- Pod cannot mount cross-NS Secret. ReferenceGrant does not apply (it governs Gateway API resources, not Pod mounts).
- **Fix**: duplicate the Secret to the tenant NS using the jq pattern. Both copies must be kept in sync if certs rotate. See `references/cross-ns-pitfalls.md` for the full pattern and alternatives (cert-manager, external-secrets).

## HTTPS Backend with Self-Signed Cert Pattern

The full canonical pattern when the backend is HTTPS 443 with a self-signed wildcard cert (matching the `app` sample in `06-runtime/`):

### Service
```yaml
apiVersion: v1
kind: Service
metadata:
  name: <name>
  namespace: <tenant-ns>
spec:
  type: ClusterIP
  selector:
    app: <name>
  ports:
    - name: https
      port: 443
      targetPort: 443
      protocol: TCP
      appProtocol: https
```

### Deployment + ConfigMap (multi-doc, separated by `---`)
- Image: `nginxinc/nginx-unprivileged:1.27-alpine` (non-root UID 101)
- `securityContext.runAsUser: 101`, `capabilities.add: [NET_BIND_SERVICE]`
- `args`: `apk add --no-cache libcap 2>/dev/null && setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx && nginx -g 'daemon off;'`
- Volume mounts: `tls-certs` (Secret, readOnly) + `nginx-config` (ConfigMap, readOnly)
- Probes: `httpGet.path: /healthz, port: https, scheme: HTTPS`
- ConfigMap: `default.conf` with `listen 443 ssl; ssl_certificate /etc/nginx/certs/tls.crt; ssl_certificate_key /etc/nginx/certs/tls.key;`

### HTTPRoute
- `parentRefs[0]`: `kind: ListenerSet, name: <team>-listenerset, namespace: <listenerset-ns>, sectionName: https`
- `hostnames: [<subdomain>.<team>.<base-domain>]`
- `backendRefs[0].port: 443`
- `filters[0]`: `RequestHeaderModifier` adding `X-Tenant: <team>`, `X-Gateway-Source: <listenerset>`, `X-Backend-Protocol: https`

### DestinationRule
- `host: <name>.<tenant-ns>.svc.cluster.local`
- `trafficPolicy.tls.mode: SIMPLE`
- `trafficPolicy.tls.insecureSkipVerify: true` (because cert is self-signed; remove for CA-signed certs)
- Include `connectionPool` and `outlierDetection` blocks for production-grade settings

## Protocol: Verification Script → Runbook (Reverse-Engineering)

When a shell script like `k8s-gateway-fqdn-minimax-eng.sh` exists for chain inspection, the runbook's job is to **describe the inverse — how to create what the script inspects**.

**Algorithm**:
1. **Read the SH script step-by-step**. For each "Step N" the script does, ask: "What resources does this step probe? What would `404 NotFound` mean here?"
2. **Map each SH step to a "you need to create" in the runbook**:
   - `Step 1: Find HTTPRoute` → "3.3 HTTPRoute" in runbook
   - `Step 2: HTTPRoute.parentRefs` → "already exists (ListenerSet/Gateway in platform team scope)"
   - `Step 3: HTTPRoute.rules.backendRefs` → "3.1 Service"
   - `Step 4: DestinationRule` → "3.4 DestinationRule" (optional but recommended)
   - `Step 5: Service.selector` → "3.2 Deployment.pod.labels"
   - `Step 6: Deployment spec` → "3.2 Deployment"
3. **Identify "platform team owns" vs "you need to create"**. Anything in the script that returns "exists with X" without you creating it → mark as "platform-managed" in the runbook's "Do not create" table.
4. **Add a "Reverse-engineering" section** to the runbook that shows the SH→MD mapping table. This is the "proof" that the runbook is complete.

**Pitfall**: Don't just transcribe the script output format into the runbook — explain the **intent** (what does the script's Step N mean for someone deploying this). The script is an inspector; the runbook is a builder. The two perspectives are inverse.

## Runbook Structure Convention

The standard structure for a new-tenant runbook (use `templates/tenant-runbook.md`):

1. **Title + TL;DR (bilingual: 中文 + English)** — what & why in one sentence
2. **TL;DR table** — 4-5 resources needed, with file paths and required/optional marker
3. **Naming assumption table** — every name used in the runbook (Gateway, ListenerSet, NS, cert), with the source of truth (which yaml in the runbook) and how to verify
4. **Chain diagram (ASCII art)** — full request flow from internet to backend
5. **Preconditions** — every kubectl get needed before apply, with expected output
6. **YAMLs** — full content inline (for reading) + standalone files in the topic dir (for apply)
7. **Deploy steps** — apply commands with expected output
8. **5-layer verification** — quick resource check → cluster-internal connectivity → gateway chain probe (using the SH script) → external E2E → failure modes
9. **Reverse-engineering section** — SH script → MD mapping table
10. **"vs existing X" comparison** — what's the same as / different from a sibling tenant's runbook
11. **Customization points** — FQDN, NS, listener sectionName, mTLS, traffic split, header routing
12. **Cleanup** — delete commands
13. **ReferenceGrant analysis** — when needed, when not, and the Secret-duplicate pitfall
14. **Appendix** — file inventory (where each yaml lives, what's pre-existing, what needs to be hand-duplicated)
15. **Quick checklist** — 7-10 checkboxes for "apply in 1 minute"

## Pitfalls

### ReferenceGrant vs allowedRoutes selector confusion
The most-asked question when adding a new tenant. The rule of thumb:
- HTTPRoute → Gateway/ListenerSet cross-NS → **allowedRoutes selector** (no ReferenceGrant)
- HTTPRoute → Service cross-NS → **ReferenceGrant** (in service's NS)
- Pod mount Secret cross-NS → **duplicate Secret** (ReferenceGrant doesn't apply)

If the runbook's failure modes table doesn't cover all three, it's incomplete.

### Tenant NS must have the selector label
The ListenerSet's `allowedRoutes.namespaces.selector.matchLabels` is the gatekeeper. If the tenant NS lacks the label, HTTPRoute `status.parents[].conditions[Accepted]` becomes `False, reason=NotAllowedByListeners` — and the user will spend hours debugging what looks like a HTTPRoute syntax problem. The runbook's preconditions MUST include the label check (`kubectl get ns <tenant> -o jsonpath='{.metadata.labels.gateway-access}'`).

### Section name mismatch
HTTPRoute `parentRefs[].sectionName` must match one of the ListenerSet's `spec.listeners[].name`. Common mistakes: `sectionName: http` when ListenerSet has only `https`, or omitting `sectionName` when the ListenerSet has multiple listeners (`https` and `grpc`). Always grep the ListenerSet yaml for `name:` and pick the right one.

### DR for HTTPS backend with self-signed cert
Defaulting to `tls.mode: DISABLE` is a bug if the backend is HTTPS — it tries to send plain HTTP to an HTTPS port. The correct pattern for self-signed wildcard cert is `tls.mode: SIMPLE + insecureSkipVerify: true`. For CA-signed certs, drop `insecureSkipVerify` and set `credentialName` if needed.

### nginx-unprivileged needs setcap for port 443
The default nginx-unprivileged image runs as UID 101 with no caps. To bind 443, you need `setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx` in the container's args, AND `securityContext.capabilities.add: [NET_BIND_SERVICE]`. Skipping either yields `bind: permission denied` at startup, which the pod logs will show but is easy to miss if you only look at `kubectl get pods`.

### `gcr.io` image pull failure in restricted clusters
The default `gcr.io/google-samples/hello-app:1.0` may not be pullable from GKE clusters without `roles/artifactregistry.reader` for the GCR repo, or in regions where GCR is restricted. Have an alternative ready: `nginxinc/nginx-unprivileged:1.27-alpine` (works for HTTPS 443 with the setcap pattern), or a GAR-hosted image. The runbook should mention this in the deployment YAML comments.

### Verification script expects specific name format
Most verification scripts (including the user's `k8s-gateway-fqdn-minimax-eng.sh`) use FQDN 2nd segment to infer tenant NS. If the runbook uses a different NS name, the script will fail. Always check the script's default assumptions match the runbook.

## Templates & References

- `templates/tenant-runbook.md` — full 15-section runbook structure with all YAMLs inline as placeholders, ready to clone and customize
- `references/cross-ns-pitfalls.md` — deep dive on the 7 cross-NS reference patterns, with the 4-quadrant decision matrix and the Secret-duplicate jq command
- `references/script-reverse-engineering.md` — step-by-step algorithm for turning a verification SH into a runbook MD, with worked example from the `app` → `newapi` migration
- `references/architecture-one-liner.md` — the "1 X + N Y" formula and bilingual TL;DR pattern for explaining the architecture to non-engineers
- `scripts/copy-secret-cross-ns.sh` — ready-to-run helper for the cross-NS Secret duplicate (the most common pitfall workaround)

## Related Skills

- `gke-asm-lifecycle` — ASM/CSM install/upgrade/uninstall (adjacent: the K8s Gateway API here is provided by `istio` gatewayClass, see in-cluster install path in that skill)
- `gcp-iap-tunnel` — when bastion access is needed to apply these manifests to a private GKE cluster
- `architectrue` — broader GKE/GCP architecture decisions; this skill is the runbook-authoring companion
- `directory-tree-restructure` — when adding a new tenant requires restructuring the runbook directory (00-prereqs/, 01-platform/, ..., 06-runtime/, 07-verify/)
