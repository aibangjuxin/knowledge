# Cross-NS Reference Pitfalls (K8s Gateway API + ListenerSet)

The single largest source of bugs in K8s Gateway API multi-tenant runbooks. The 7 reference patterns below cover every cross-NS edge case you'll hit. The user's `k8s-gateway/03-§3` documents the worst one (Pod mount Secret); the rest are derived from K8s Gateway API spec + Istio behavior.

## The 7 Cross-NS Reference Patterns

| # | Reference direction | Needs ReferenceGrant? | Why / Mechanism | Pitfall? |
|---|---------------------|------------------------|------------------|----------|
| 1 | HTTPRoute (NS-A) → Service (NS-A) | ❌ No | Same NS | No |
| 2 | HTTPRoute (NS-A) → Service (NS-B) | ✅ **Yes** | Gateway API spec: cross-NS Service reference requires ReferenceGrant in NS-B (the Service's NS) | **Common miss** — people forget ReferenceGrant is in the **target's** NS, not source |
| 3 | HTTPRoute (NS-A) → Gateway (NS-B) | ❌ No (uses Gateway's `allowedRoutes`) | Gateway's `spec.allowedRoutes.namespaces.from` (All / Same / Selector / None) governs which NSs can attach HTTPRoutes | "Same" vs "Selector" confusion |
| 4 | HTTPRoute (NS-A) → ListenerSet (NS-B) | ❌ No (uses ListenerSet's `allowedRoutes`) | ListenerSet's `spec.allowedRoutes.namespaces.selector.matchLabels` is the gatekeeper. Tenant NS must have matching label. | **Most missed precond in runbooks** — if tenant NS lacks label, HTTPRoute `Accepted=False, reason=NotAllowedByListeners` |
| 5 | Gateway (NS-A) → Secret (NS-A) | ❌ No | Same NS | No |
| 6 | Gateway (NS-A) → Secret (NS-B) | ✅ **Yes** | K8s Gateway API: Gateway/ListenerSet cross-NS Secret ref needs ReferenceGrant in NS-B | Often missed when centralizing TLS certs in a "certs" NS |
| 7 | **Pod (NS-A) → Secret (NS-B) mount** | ❌ **ReferenceGrant does NOT apply** | K8s Secret is **namespace-scoped at the kubelet level**. Pod can only mount Secret in its own NS. ReferenceGrant only governs Gateway API resources (HTTPRoute, ListenerSet) referencing Service/Secret. **Fix: duplicate the Secret into the Pod's NS.** | **The biggest source of confusion in runbooks** — see §"The Secret Duplicate Pitfall" below |

## The Secret Duplicate Pitfall (Pattern #7)

Symptom:
```
Warning  FailedMount  MountVolume.SetUp failed for volume "tls-certs" :
  secret "abjx-lex-eg-secret-team1-tls" not found
```
Pod stuck in `ContainerCreating` forever.

Root cause: the wildcard TLS cert Secret lives in `abjx-listenerset-int` (the listenerset NS) because the ListenerSet references it for TLS termination. The backend Pod in `team1` (tenant NS) wants to mount the same Secret as the nginx server cert. But Pods can only mount Secrets in their own NS.

**The fix (immediate, what to do now):**

```bash
# jq to strip the source-NS metadata fields, retarget to tenant NS
kubectl get secret abjx-lex-eg-secret-team1-tls -n abjx-listenerset-int -o json \
  | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields) | .metadata.namespace = "team1"' \
  | kubectl apply -f -
```

Both copies are now independent. **Any cert rotation must update both copies** (use cert-manager or external-secrets for sync — see alternatives below).

**The "why" you have to explain in the runbook**: this is the #1 mistake in runbooks. People see ReferenceGrant as the answer to "cross-NS reference" and assume it covers Secret mounts. **ReferenceGrant is a Gateway API concept, not a kubelet/Pod-volume concept.** They live in different layers.

**Alternatives for production (mention in runbook's failure modes):**

| Option | Description | Trade-off |
|--------|-------------|-----------|
| **A: cert-manager + ClusterIssuer** | One source, cert-manager auto-distributes to all "approved" NSs | RBAC complexity, adds a dependency |
| **B: external-secrets-operator** | Sync Secret from a backend (GCP Secret Manager, Vault, etc.) to multiple NSs | Adds operator; needs backend config |
| **C: Reloader + "shared" NS** | Mount the Secret from a "shared" NS | **Does not work** — Pods cannot mount cross-NS Secret at all |
| **D: Direct copy (this skill's recommendation for dev)** | `kubectl get ... -o json \| jq ...` | Simple, dev clusters fine. Manual sync on rotation. **What the runbook should default to for non-prod.** |

**Caveat for the runbook**: the duplicate copy is a maintenance burden. If certs rotate weekly, this is a footgun. Note in the runbook that production should migrate to option A or B.

## The Tenant NS Label Precondition (Pattern #4)

Symptom: HTTPRoute applied, but `kubectl get httproute -n <tenant> <name> -o jsonpath='{.status.parents[].conditions[?(@.type=="Accepted")].status}'` returns `False`.

Root cause: tenant NS lacks the label that ListenerSet's `allowedRoutes.namespaces.selector.matchLabels` requires.

**The fix:**
```bash
kubectl label ns <tenant> gateway-access=ajbx-int
```

**Why this must be in runbook preconditions**: it's a 30-second check, but if you skip it, the failure mode is "HTTPRoute is valid, applied successfully, but not bound" — which looks like a ListenerSet problem and wastes hours of debugging.

**The kubectl command to verify in preconditions**:
```bash
kubectl get ns <tenant> -o jsonpath='{.metadata.labels.gateway-access}'
# expected: ajbx-int
```

## ReferenceGrant: When, Where, and the "From" Semantics

ReferenceGrant is created in the **target** NS (not source). E.g., HTTPRoute in `team1` referencing Service in `common-shared` needs ReferenceGrant in `common-shared`:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-team1-to-ref-services
  namespace: common-shared           # ← TARGET NS, not source
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: team1               # ← SOURCE NS
  to:
    - group: ""                      # core group for Service
      kind: Service
```

Common mistakes:
- ReferenceGrant in the **wrong** NS (typically the source NS, not target)
- `from.kind` not matching (using `TCPRoute` for an HTTPRoute reference)
- `from.group` wrong (HTTPRoute is in `gateway.networking.k8s.io`, Service is in core `""`)

## "Same" vs "Selector" in `allowedRoutes.namespaces`

The Gateway API's `allowedRoutes.namespaces` can be:

| Value | What HTTPRoutes can attach |
|-------|------------------------------|
| `from: All` | Any NS — wide-open, avoid in multi-tenant |
| `from: Same` | Only HTTPRoutes in the same NS as the Gateway/ListenerSet |
| `from: Selector` | HTTPRoutes in NSs matching the selector's matchLabels |
| `from: None` | None — Gateway has no routes (weird) |

The user's runbook uses **`from: Selector` with `matchLabels: gateway-access: ajbx-int`**. The ListenerSet becomes the multi-tenant gatekeeper, and tenant NSs opt-in via the label.

## Pitfall Summary (for runbook "Failure Modes" section)

| Symptom | Pattern | Fix |
|---------|---------|-----|
| `HTTPRoute Accepted=False, reason=NotAllowedByListeners` | #4 — tenant NS label missing | `kubectl label ns <tenant> gateway-access=ajbx-int` |
| `HTTPRoute Accepted=True` but `ResolvedRefs=False` | #2 — cross-NS Service, no ReferenceGrant | Add ReferenceGrant in service's NS |
| `Pod ContainerCreating, FailedMount: secret not found` | #7 — cross-NS Secret mount | Duplicate Secret to tenant NS (jq command above) |
| `TLS handshake error` on Gateway → backend hop | DR mode wrong | For HTTPS backend with self-signed cert, use `tls.mode: SIMPLE + insecureSkipVerify: true` |
| `HTTPRoute Accepted=False, reason=NoMatchingParent` | #3 or #4 — Gateway/ListenerSet doesn't exist or doesn't allow this NS | Verify Gateway/ListenerSet exists; check allowedRoutes |
| `ImagePullBackOff: gcr.io` | Backend image not pullable from cluster | Use GAR-hosted image or `nginxinc/nginx-unprivileged:1.27-alpine` |

## Verification Script Expectations

The user's `k8s-gateway-fqdn-minimax-eng.sh` infers tenant NS from FQDN 2nd segment:

```bash
# From the script
CANDIDATE_NS="$(echo "$INPUT_FQDN" | awk -F. '{print $2}')"
# e.g., newapi.team1.appdev.aibang → "team1"
```

**This means the FQDN's 2nd segment MUST equal the tenant NS**. If the runbook uses `team1` NS but FQDN `newapi.something-else.appdev.aibang`, the script will scan cluster-wide and may pick the wrong HTTPRoute. **Always match FQDN 2nd segment to tenant NS** in runbook design.
