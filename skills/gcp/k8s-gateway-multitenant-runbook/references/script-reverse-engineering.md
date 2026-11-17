# Verification Script → Runbook (Reverse-Engineering Pattern)

The protocol for turning a verification shell script (chain inspector) into a deployment runbook (builder). Captures the algorithm, the inverse-mapping table, and a worked example from the `app` → `newapi` migration.

## When to Use

You have a working multi-tenant K8s Gateway API stack, a verification shell script that probes the chain, and you need to onboard a new tenant. The script tells you what should exist; the runbook tells you how to create it.

## The Algorithm

### Step 1: Read the SH script exhaustively

For each "Step N" in the script, write down:
- What resource does it probe? (HTTPRoute, ListenerSet, Gateway, Service, Deployment, etc.)
- What does it expect to find? (Name, namespace, conditions, status)
- What does `404 NotFound` / `{}` mean? (The resource doesn't exist → user needs to create it)

### Step 2: Build the inverse-mapping table

For each "Step N", decide: is this "you need to create" or "platform team owns it"?

| Script behavior | Inverse action | Goes where in runbook |
|------------------|----------------|----------------------|
| `kubectl get httproute` and find 1 by hostname | "Create HTTPRoute" | §3.X HTTPRoute section |
| `kubectl get gateway <name>` returns the platform Gateway | "Platform team owns" | §0 "Do not create" table |
| `kubectl get listenerset <name>` returns the platform ListenerSet | "Platform team owns" | §0 "Do not create" table |
| `kubectl get service <name>` returns the backend | "Create Service" | §3.X Service section |
| `kubectl get deployment <name>` returns the backend workload | "Create Deployment" | §3.X Deployment section |
| `kubectl get destinationrule <name>` returns the DR | "Create DR (optional)" | §3.X DestinationRule section |
| `kubectl get secret <name>` returns the TLS cert | "Either platform team owns, OR you duplicate to tenant NS" | §0 / §2 preconditions |

### Step 3: Identify the 4-YAML minimum (or 5 if HTTPS backend)

For a new tenant, the standard resources are:
1. Service
2. Deployment (+ ConfigMap if HTTPS)
3. HTTPRoute
4. DestinationRule (optional, recommended)

### Step 4: Map every "user must do" to a runbook section

The runbook structure (see `templates/tenant-runbook.md`):
- §0 TL;DR table — summary of what to create
- §1 chain diagram — visualize the chain the script probes
- §2 preconditions — `kubectl get` for every "platform owns" thing
- §3 YAMLs — full content of the 4-5 resources
- §4 deploy steps — `kubectl apply` sequence
- §5 verification — 5 layers, including the SH script itself in §5.3

### Step 5: Add a "Reverse-engineering" section to the runbook

Show the inverse-mapping table explicitly. This is the "proof" that the runbook is complete:

```markdown
## 6. Reverse-Engineering (why these 4-5 YAMLs)

| Script step | Inverse: you need to create |
|-------------|------------------------------|
| Step 1: find HTTPRoute | §3.3 HTTPRoute |
| Step 2: HTTPRoute.parentRefs | already exists (platform ListenerSet) |
| Step 3: backendRefs | §3.1 Service |
| Step 4: DestinationRule | §3.4 DR (optional) |
| Step 5: Service.selector | §3.2 Deployment pod labels |
| Step 6: Deployment spec | §3.2 Deployment |
```

This makes the runbook self-validating: a reader can grep the script, find the inverse, and confirm the runbook covers it.

## Worked Example: `app` → `newapi`

The user's runbook at `gateway-2.0/k8s-gateway/06-runtime/app` (existing tenant `app` in `110139-int`) was the model. The new `newapi` tenant (in `team1` NS) was reverse-engineered from the same `k8s-gateway-fqdn-minimax-eng.sh` script.

**The script's chain for `newapi.team1.appdev.aibang`:**

```
Step 1: Find HTTPRoute matching FQDN
  → expect: team1/newapi-route
Step 2: HTTPRoute.parentRefs
  → expect: ListenerSet abjx-listenerset-int/team1-listenerset sectionName=https
Step 3: backendRefs
  → expect: Service team1/newapi:443
Step 4: DestinationRule lookup
  → expect: team1/newapi-dr (optional)
Step 5: Service.selector match → Deployment.pod.labels
  → expect: app=newapi
Step 6: Deployment spec
  → expect: nginx-unprivileged, containerPort 443, HTTPS probes /healthz
```

**Inverse mapping for `newapi`:**

```yaml
# 1. Service team1/newapi:443
apiVersion: v1
kind: Service
metadata:
  name: newapi
  namespace: team1
spec:
  selector: { app: newapi }
  ports:
    - { name: https, port: 443, targetPort: 443, appProtocol: https }

# 2. Deployment + ConfigMap (multi-doc)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: newapi
  namespace: team1
spec:
  template:
    spec:
      containers:
        - name: newapi
          image: nginxinc/nginx-unprivileged:1.27-alpine
          ports: [{ name: https, containerPort: 443 }]
          volumeMounts:
            - { name: tls-certs, mountPath: /etc/nginx/certs }
            - { name: nginx-config, mountPath: /etc/nginx/conf.d }
          # ... probes, args (setcap + nginx), securityContext
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: newapi-nginx-config
  namespace: team1
data:
  default.conf: |
    server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/certs/tls.crt;
        ssl_certificate_key /etc/nginx/certs/tls.key;
        # ...
    }

# 3. HTTPRoute team1/newapi-route
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: newapi-route
  namespace: team1
spec:
  parentRefs:
    - { kind: ListenerSet, name: team1-listenerset, namespace: abjx-listenerset-int, sectionName: https }
  hostnames: [newapi.team1.appdev.aibang]
  rules:
    - matches: [{ path: { type: PathPrefix, value: / } }]
      backendRefs: [{ name: newapi, port: 443, weight: 1 }]

# 4. DestinationRule team1/newapi-dr (optional, recommended)
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: newapi-dr
  namespace: team1
spec:
  host: newapi.team1.svc.cluster.local
  trafficPolicy:
    tls: { mode: SIMPLE, insecureSkipVerify: true }
```

**What the script's "exists" steps imply — i.e., platform team owns**:
- Gateway `abjx-gw-int/abjx-gw-int`
- ListenerSet `abjx-listenerset-int/team1-listenerset`
- TLS Secret source `abjx-listenerset-int/abjx-lex-eg-secret-team1-tls` (platform owns; you duplicate to tenant NS)

## Pitfall: Don't Transcribe, Explain Intent

The script's output is **formatted for chain inspection**. The runbook's content is **formatted for someone building the chain**. These are inverse perspectives.

Bad runbook section (transcription):
> "Step 3: backendRef Service team1/newapi:443 (weight=1)"

Good runbook section (intent):
> "3.1 Service: ClusterIP, port 443→443, appProtocol=https, selector `app: newapi` — the HTTPRoute backendRefs this on port 443 (HTTPS). The script's Step 3 will verify this Service exists with port=443."

The first is a script output. The second is a deployment instruction with cross-reference back to the script.

## Pitfall: The Script's "Doesn't Exist" Path

The script's exit code / error messages tell you what the user did wrong:
- "No HTTPRoute found" → user forgot to apply §3.3
- "Service team1/newapi not found" → user forgot §3.1
- "BackendRef not resolved" → user has wrong namespace/port in §3.3

Capture these in the runbook's **Failure Modes** table (§5.5). The failure modes table is the inverse-mapping "test the runbook against the script's negative cases."

## Anti-Pattern: Runbook Without Reverse-Engineering Section

A runbook that just lists 4 YAMLs without explaining "why these 4" is brittle. When someone asks "why not 5? why not a different DR mode?", the runbook needs to point at the script. The reverse-engineering section is what makes the runbook **defensible** — it shows the work that led to the design choice.
