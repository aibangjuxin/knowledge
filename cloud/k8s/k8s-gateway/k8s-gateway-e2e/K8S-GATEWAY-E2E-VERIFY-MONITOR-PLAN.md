# K8s Gateway API — E2E Verification & Monitoring Plan

> **目标**：对已部署的 K8s Gateway API 环境进行端到端验证，并建立持续监控体系
> **参考架构**：`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/`
> **输出路径**：`/Users/lex/workspace/k8s-gateway-e2e/`

---

## 1. 验证阶段总览

```
┌─────────────────────────────────────────────────────────────────┐
│                    E2E Verification Flow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Phase 0: Pre-flight Checks                                      │
│  ├─ 0.1 CRD & Controller Readiness                              │
│  ├─ 0.2 GatewayClass / Gateway / ListenerSet existence          │
│  └─ 0.3 Istiod + Kong DP health                                │
│                                                                  │
│  Phase 1: Control Plane (CRUD + Binding)                        │
│  ├─ 1.1 Gateway → ListenerSet binding                           │
│  ├─ 1.2 HTTPRoute → ListenerSet attachment (allowedRoutes)       │
│  ├─ 1.3 Cross-namespace reference (ReferenceGrant)              │
│  └─ 1.4 Invalid binding rejection (security enforcement)       │
│                                                                  │
│  Phase 2: Data Plane (Traffic)                                   │
│  ├─ 2.1 Flow 1 — Direct Container routing                       │
│  ├─ 2.2 Flow 2 — Kong DP routing                               │
│  └─ 2.3 Health check (ILB HC + pod readiness)                   │
│                                                                  │
│  Phase 3: NetworkPolicy Isolation                               │
│  ├─ 3.1 Tenant NS default-deny enforcement                     │
│  ├─ 3.2 Cross-namespace blocked (illegal traversal)            │
│  └─ 3.3 Gateway NS egress whitelisting                          │
│                                                                  │
│  Phase 4: Timeout & Resilience                                  │
│  ├─ 4.1 HTTPRoute timeouts field presence                       │
│  ├─ 4.2 DestinationRule timeout override                        │
│  └─ 4.3 Timeout error injection + 504 verification            │
│                                                                  │
│  Phase 5: Monitoring Baseline                                    │
│  └─ 5.1 Envoy metrics + access logs + alerting rules           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Phase 0 — Pre-flight Checks

### 0.1 CRD & Controller Readiness

```bash
#!/usr/bin/env bash
# verify-preflight.sh — Run from infra jump host with kubectl指向 prod cluster
set -euo pipefail

CLUSTER="${1:-prod}"
NAMESPACES=("abjx-gw-int" "kong-apw-kong-int" "istio-system" "infrastructure" "listenersets")

echo "=== [0.1] Gateway API CRDs ==="
for crd in gatewayclasses gateways listenersets httproutes grpcroutes tcproutes referencegrants; do
  if kubectl get crd "$crd" >/dev/null 2>&1; then
    echo "[PASS] CRD exists: $crd"
  else
    echo "[FAIL] CRD missing: $crd"
  fi
done

echo "=== [0.2] GatewayClass ==="
kubectl get gatewayclass

echo "=== [0.3] Controller Pod Running ==="
kubectl get pods -n istio-system -l app=istiod --no-headers | awk '{print $2}' | while read ready rest; do
  [[ "$ready" =~ ^([0-9]+)/\1$ ]] && echo "[PASS] istiod running: $ready" || echo "[WARN] istiod not ready: $ready"
done

echo "=== [0.4] Kong DP Ready ==="
kubectl get pods -n kong-apw-kong-int -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
```

### 0.2 Gateway / ListenerSet Existence

```bash
echo "=== [0.5] Gateway in infrastructure ns ==="
kubectl get gateway -n infrastructure -o wide

echo "=== [0.6] All ListenerSets ==="
kubectl get listenersets --all-namespaces

echo "=== [0.7] Tenant Namespaces with tenant label ==="
kubectl get namespaces -l 'tenant' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

**Pass Criteria**:
- All CRDs present
- At least 1 `GatewayClass` accepted
- Gateway status = `Accepted`
- All expected ListenerSets present
- All tenant namespaces labeled (`tenant: <name>`)

---

## 3. Phase 1 — Control Plane (Binding Verification)

### 1.1 Gateway → ListenerSet Binding

```bash
echo "=== [1.1] Gateway Listener Status ==="
kubectl get gateway -n infrastructure -o jsonpath='{range .status.listeners[*]}{
  .name}{"\t"}{.attachedRoutes}{"\t"}{.conditions[*].type}{"\t"}{.conditions[*].status}{"\n"}{end}'

echo "=== [1.2] ListenerSet Bound Routes Count ==="
kubectl get listenersets --all-namespaces -o jsonpath='{range .items[*]}{
  .metadata.namespace}{"/"}{.metadata.name}{"\t"}{.status.conditions[*].type}{"\t"}{.status.conditions[*].status}{"\n"}{end}'
```

**Pass**: Gateway listener `attachedRoutes > 0` and condition `Accepted`

### 1.2 HTTPRoute Attachment (allowedRoutes + parentRefs)

```bash
#!/usr/bin/env bash
# verify-httproute-binding.sh
set -euo pipefail

TENANT_NS="${1:-}"
[[ -z "$TENANT_NS" ]] && echo "Usage: $0 <tenant-namespace>" && exit 1

echo "=== [1.3] HTTPRoutes in $TENANT_NS ==="
kubectl get httproute -n "$TENANT_NS" -o wide

echo "=== [1.4] HTTPRoute parentRefs status ==="
kubectl get httproute -n "$TENANT_NS" -o jsonpath='{range .items[*]}{
  .metadata.name}{"\n"}{range .status.parents[*]}{
    .parentRef.name}{"/"}{.parentRef.sectionName}{"\t"}{.conditions[*].type}{"\t"}{.conditions[*].status}{"\n"}{end}{"\n"}{end}'
```

**Pass**: Each HTTPRoute `status.parents[].conditions[].type = "Accepted"` and `status = "True"`

### 1.3 Cross-Namespace ReferenceGrant

```bash
echo "=== [1.5] ReferenceGrants (cross-ns refs) ==="
kubectl get referencegrants --all-namespaces

echo "=== [1.6] HTTPRoute backendRefs resolving cross-ns ==="
# For each HTTPRoute, check if backendRefs are resolvable
kubectl get httproute -n "$TENANT_NS" -o jsonpath='{range .items[*]}{
  .metadata.name}{": "}{range .spec.rules[*]}{range .backendRefs[*]}{
    .kind}{"/"}{.name}{"\n"}{end}{end}{end}'
```

### 1.4 Invalid Binding Rejection (Security Enforcement Test)

```bash
#!/usr/bin/env bash
# verify-illegal-binding-rejected.sh
# Attempt to bind HTTPRoute from non-allowed namespace — should be rejected
set -euo pipefail

cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: test-illegal-route
  namespace: default   # not in allowedRoutes — should be rejected
spec:
  parentRefs:
    - name: <gateway-name>
      namespace: infrastructure
      sectionName: https
  hostnames:
    - "evil.default.example.com"
  rules:
    - backendRefs:
        - name: nonexistent-svc
          port: 8080
EOF
# Expected: rejected with "namespace not in allowedRoutes" or similar
```

---

## 4. Phase 2 — Data Plane (Traffic Verification)

### 2.1 Flow 1 — Direct Container Routing

```bash
#!/usr/bin/env bash
# verify-flow1-direct.sh
set -euo pipefail

TENANT_NS="${1:-}"
GATEWAY_IP="${2:-$(kubectl get svc -n infrastructure -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}')}"

echo "=== [2.1a] ILB IP: $GATEWAY_IP ==="

echo "=== [2.1b] Direct Container Health ==="
# Use a known direct-container tenant; adjust as needed
curl -sv --max-time 10 \
  "https://${GATEWAY_IP}/health" \
  -H "Host: direct.${TENANT_NS}.example.com" 2>&1 | grep -E '< HTTP|Connected|correct'

echo "=== [2.1c] Backend Pod Reached Directly ==="
# Check Envoy stats for upstream host
kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
  curl -s localhost:15000/stats | grep -E 'upstream.*health_status'
```

### 2.2 Flow 2 — Kong DP Routing

```bash
#!/usr/bin/env bash
# verify-flow2-kong.sh
set -euo pipefail

TENANT_NS="${1:-}"
GATEWAY_IP="${2:-$(kubectl get svc -n infrastructure -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}')}"

echo "=== [2.2a] Kong-protected Route ==="
curl -sv --max-time 10 \
  "https://${GATEWAY_IP}/api/v1/protected" \
  -H "Host: kong.${TENANT_NS}.example.com" \
  -H "X-Kong-Request-ID: $(uuidgen)" 2>&1 | grep -E '< HTTP|X-Kong'

echo "=== [2.2b] Kong DP Upstream Selected ==="
kubectl exec -n kong-apw-kong-int deploy/kong -c kong -- \
  curl -s localhost:8001/status | jq '.database.modifications'
```

### 2.3 Health Check Verification

```bash
echo "=== [2.3a] ILB Health Check — Gateway Pod ==="
# GCP LB HC should hit Envoy port 15021
kubectl get pods -n abjx-gw-int -l app=envoy -o jsonpath='{range .items[*]}{
  .metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

echo "=== [2.3b] Envoy admin /healthz ==="
kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
  curl -s localhost:15021/healthz | head -1

echo "=== [2.3c] GCP LB Backend Service Health ==="
# Via GCP CLI — requires gcloud auth
gcloud compute backend-services get-health \
  "$(kubectl get svc -n infrastructure -o jsonpath='{.items[0].metadata.annotations.cloud.google.com/backend-config}')" \
  --region="$(gcloud config get-value compute/region)" 2>/dev/null || echo "[SKIP] gcloud not configured"
```

---

## 5. Phase 3 — NetworkPolicy Isolation

### 3.1 Tenant NS default-deny Enforcement

```bash
#!/usr/bin/env bash
# verify-netpol-isolation.sh
set -euo pipefail

TENANT_NS="${1:-}"

echo "=== [3.1a] NetPol in Gateway NS ==="
kubectl get netpol -n abjx-gw-int -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

echo "=== [3.1b] NetPol in Tenant NS ==="
kubectl get netpol -n "$TENANT_NS" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'

echo "=== [3.1c] Verify default-deny-all present ==="
for ns in abjx-gw-int "$TENANT_NS"; do
  if kubectl get netpol default-deny-all -n "$ns" >/dev/null 2>&1; then
    echo "[PASS] default-deny-all exists in $ns"
  else
    echo "[FAIL] default-deny-all MISSING in $ns"
  fi
done
```

### 3.2 Cross-Namespace Blocked

```bash
#!/usr/bin/env bash
# verify-cross-ns-blocked.sh
# From a tenant pod, try to reach another tenant's pod — should be blocked
set -euo pipefail

TENANT_A="${1:-team-a}"
TENANT_B="${2:-team-b}"

# Pick a pod in tenant A (apigateway: NONE label)
POD_A=$(kubectl get pod -n "$TENANT_A" -l apigateway=NONE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[[ -z "$POD_A" ]] && echo "[SKIP] No NONE pod in $TENANT_A" && exit 0

# Get a pod IP in tenant B
POD_B_IP=$(kubectl get pod -n "$TENANT_B" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)
[[ -z "$POD_B_IP" ]] && echo "[SKIP] No pod in $TENANT_B" && exit 0

echo "=== [3.2] Testing $TENANT_A pod -> $TENANT_B pod ($POD_B_IP) ==="
kubectl exec -n "$TENANT_A" "$POD_A" -- \
  curl -s --connect-timeout 5 "$POD_B_IP:8080" 2>&1 | head -5
# Expected: connection timeout (blocked by default-deny)
```

### 3.3 Gateway NS Egress Whitelisting

```bash
echo "=== [3.3a] Gateway egress to Kong DP ==="
# Verify egress from abjx-gw-int to kong-apw-kong-int is allowed
kubectl get netpol default-allow-gw-egress-to-kong -n abjx-gw-int -o yaml | grep -E 'namespaceSelector|ports'

echo "=== [3.3b] Gateway egress to tenant namespaces (ingress: int) ==="
kubectl get netpol default-allow-gw-to-no-gw-rt -n abjx-gw-int -o yaml | grep -E 'namespaceSelector|ports'

echo "=== [3.3c] Verify GCP HC IPs whitelisted ==="
kubectl get netpol default-allow-gcp-hc-ingress -n abjx-gw-int -o yaml | grep -E '35.191|130.211'
```

---

## 6. Phase 4 — Timeout & Resilience

### 4.1 HTTPRoute Timeout Fields

```bash
echo "=== [4.1] HTTPRoutes with timeouts configured ==="
kubectl get httproute --all-namespaces -o jsonpath='{range .items[*]}{
  .metadata.namespace}{"/"}{.metadata.name}{"\t"}{.spec.rules[*].timeouts.request}{"\t"}{.spec.rules[*].timeouts.backendTimeout}{"\n"}{end}'
```

**Pass**: At least the primary routes have explicit `timeouts.request` and `timeouts.backendTimeout`

### 4.2 DestinationRule Timeout Override

```bash
echo "=== [4.2] DestinationRules with explicit timeout ==="
kubectl get destinationrule --all-namespaces -o jsonpath='{range .items[*]}{
  .metadata.namespace}{"/"}{.metadata.name}{"\t"}{.spec.trafficPolicy.timeout}{"\t"}{.spec.trafficPolicy.connectTimeout}{"\n"}{end}'
```

### 4.3 Timeout Error Injection

```bash
#!/usr/bin/env bash
# verify-timeout-504.sh
set -euo pipefail

TENANT_NS="${1:-}"
GATEWAY_IP="${2:-}"

echo "=== [4.3] Testing backend timeout (expect 504) ==="
# Call an endpoint with a very short backendTimeout to trigger 504
curl -sv --max-time 15 \
  "https://${GATEWAY_IP}/delay/10" \
  -H "Host: app.${TENANT_NS}.example.com" 2>&1 | grep -E '< HTTP|504|UT|timeout'

echo "=== [4.4] Check Envoy UT response flag ==="
kubectl logs -n "$TENANT_NS" -l apigateway=NONE -c istio-proxy \
  --tail=50 2>/dev/null | grep -E 'UT|504|Gateway Timeout' || echo "[CHECK] Look at Envoy access logs manually"
```

---

## 7. Phase 5 — Monitoring Baseline

### 5.1 Envoy Metrics Scraping

```bash
echo "=== [5.1] Envoy metrics endpoint accessible ==="
kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
  curl -s localhost:15000/stats/prometheus | grep -E '^envoy_' | head -20

echo "=== [5.2] Key metrics to track ==="
# List critical metrics for dashboard
cat <<'EOF'
## Critical Metrics for K8s Gateway Monitoring

| Metric | Envoy Counter/Gauge | Description |
|--------|-------------------|-------------|
| upstream_rq_timeout | Counter | Upstream timeout events (UT flag) |
| upstream_rq_504 | Counter | 504 Gateway Timeout count |
| listener.listener_<port>.downstream_cx_total | Counter | Total connections per port |
| cluster.<svc>.upstream_rq_total | Counter | Total requests per upstream cluster |
| cluster.<svc>.upstream_cx_connect_timeout | Counter | Connection timeout events |
| listener.ssl.fail_verify_error | Counter | TLS handshake failures |
| route.vhost.<name>.vcluster.<cluster>.not_found | Counter | Route not found (404 from Envoy) |

## Grafana Dashboard Panels (Recommended)
1. **Request Rate** — `irate(envoy_cluster_upstream_rq_total[5m])`
2. **Error Rate (5xx)** — `sum(rate(envoy_cluster_upstream_rq_5xx[5m]))`
3. **Upstream Timeout Rate** — `sum(rate(envoy_cluster_upstream_rq_timeout[5m]))`
4. **p99 Latency** — `histogram_quantile(0.99, rate(envoy_cluster_upstream_response_time_bucket[5m]))`
5. **Active Connections** — `envoy_listener_downstream_cx_active`
EOF
```

### 5.2 Access Log Schema (Istio/Envoy)

```bash
echo "=== [5.3] Envoy access log format ==="
kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
  curl -s localhost:15000/logging 2>/dev/null | jq '.log_format' || echo "[CHECK] Envoy admin logging endpoint"

cat <<'EOF'
## Recommended Access Log Fields (JSON format)
{
  "authority": "%RESPONSE_FLAGS%",      # UT/UC/UF flags
  "method": "%REQ(:METHOD)%",
  "path": "%UPSTREAM_CLUSTER%",
  "response_duration_ms": "%DURATION%",
  "response_code": "%RESPONSE_CODE%",
  "upstream_host": "%UPSTREAM_HOST%",
  "upstream_transport_failure": "%UPSTREAM_TRANSPORT_FAILURE_REASON%",
  "x-request-id": "%REQ(X-REQUEST-ID)%"
}
EOF
```

### 5.3 Alerting Rules (Prometheus)

```yaml
# /Users/lex/workspace/k8s-gateway-e2e/alerts-k8s-gateway.yaml
groups:
  - name: k8s-gateway-alerts
    rules:
      - alert: GatewayHighTimeoutRate
        expr: |
          sum(rate(envoy_cluster_upstream_rq_timeout[5m]))
          / sum(rate(envoy_cluster_upstream_rq_total[5m])) > 0.01
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "K8s Gateway upstream timeout rate > 1%"
          description: "Timeout rate is {{ $value | humanizePercentage }}"

      - alert: GatewayHighErrorRate
        expr: |
          sum(rate(envoy_cluster_upstream_rq_5xx[5m]))
          / sum(rate(envoy_cluster_upstream_rq_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "K8s Gateway 5xx error rate > 5%"

      - alert: GatewayListenerDown
        expr: |
          kube_gateway_status_condition{
            condition="Ready",status="true"
          } == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Gateway listener is not Ready"

      - alert: ListenerSetRouteCountMismatch
        expr: |
          abs(
            kube_listenerset_attached_routes - on(gateway) group_left(gateway_class)
            kube_gateway_attached_routes
          ) > 10
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "ListenerSet attached routes diverges from Gateway count"
```

### 5.4 Monitoring Check Script

```bash
#!/usr/bin/env bash
# verify-monitoring.sh — Run periodically as cron or health check
set -euo pipefail

GATEWAY_NS="infrastructure"
GATEWAY_NAME="${GATEWAY_NAME:-central-gateway}"

echo "=== [5.4a] Gateway Status ==="
kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NS" \
  -o jsonpath='{range .status.conditions[*]}{
    .type}{": "}{.status}{"\n"}{end}'

echo "=== [5.4b] Envoy Cluster Health ==="
kubectl exec -n abjx-gw-int deploy/abjx-gw-int -- \
  curl -s localhost:15000/clusters | grep -E '^cluster_manager' | head -5

echo "=== [5.4c] Recent 504s in Envoy logs ==="
kubectl logs -n abjx-gw-int deploy/abjx-gw-int --tail=200 --since=5m \
  2>/dev/null | grep -c '504\|UT\|timeout' || echo "0 timeout events"

echo "=== [5.4d] Kong DP Health ==="
kubectl get pods -n kong-apw-kong-int -o jsonpath='{range .items[*]}{
  .metadata.name}{"\t"}{.status.phase}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'
```

---

## 8. Verification Checklist Summary

| Phase | Check | Expected Result | Pass Criteria |
|-------|-------|----------------|--------------|
| 0.1 | CRDs present | All 7 CRDs `Established` | All pass |
| 0.2 | GatewayClass accepted | `Accepted=True` | |
| 0.3 | istiod + Kong DP running | All pods `Running/Ready` | |
| 1.1 | Gateway listeners attached | `attachedRoutes > 0` | |
| 1.2 | HTTPRoute parents Accepted | All `Accepted=True` | |
| 1.3 | ReferenceGrant for cross-ns | Present for all cross-ns backends | |
| 1.4 | Illegal binding rejected | Error message returned | |
| 2.1 | Flow 1 direct container | HTTP 200 + correct response | |
| 2.2 | Flow 2 Kong DP | HTTP 200 via Kong | |
| 2.3 | ILB health check | Backend healthy in GCP | |
| 3.1 | default-deny-all present | Both NS have it | |
| 3.2 | Cross-ns blocked | Connection timeout | |
| 3.3 | GCP HC IPs whitelisted | `35.191.0.0/16` + `130.211.0.0/22` in netpol | |
| 4.1 | HTTPRoute timeouts set | Explicit `request` + `backendTimeout` | |
| 4.2 | DestinationRule timeout | `trafficPolicy.timeout > 0` | |
| 4.3 | 504 on timeout injection | HTTP 504 returned | |
| 5.1 | Envoy metrics scraping | Metrics endpoint returns data | |
| 5.2 | Access log configured | JSON log format enabled | |
| 5.3 | Alerting rules deployed | PrometheusRules present | |

---

## 9. Known Issues & Pitfalls

| Issue | Symptom | Fix |
|-------|---------|-----|
| **GCP HC blocked** | All Envoy nodes marked unhealthy, 504s | Ensure `default-allow-gcp-hc-ingress` netpol includes `35.191.0.0/16` + `130.211.0.0/22` on port 15021 |
| **DNS failure inside Gateway pod** | Envoy crash loop | Verify `default-allow-dns` netpol in `abjx-gw-int` allows port 53 to `kube-system/kube-dns` |
| **HTTPRoute not binding** | `AttachedRoutes=0` | Check tenant NS has correct label matching `allowedRoutes.namespaces.selector` |
| **504 on long API calls** | Timeout after ~5s | Envoy default `timeout=5s` — set `DestinationRule trafficPolicy.timeout` explicitly |
| **SNAT hides real client IP** | `externalTrafficPolicy: Cluster` on ILB | This is expected; `X-Forwarded-For` or `proxyProtocol` must be configured upstream |
| **ListenerSet CRD apply fails** | GKE version too old | ListenerSet requires GKE >= 1.35.3-gke.1389000 (ref: `knowledge/cloud/k8s/k8s-gateway/`) |
| **istiod → Gateway xDS failing** | Envoy gets no route config | Verify `default-allow-istiod` netpol; check istiod logs for `Failed to push` |

---

## 10. Quick Run

```bash
# Full pre-flight + Phase 1-2 verification
./verify-preflight.sh prod
./verify-httproute-binding.sh <tenant-namespace>
./verify-flow1-direct.sh <tenant-namespace> <GATEWAY_IP>
./verify-flow2-kong.sh <tenant-namespace> <GATEWAY_IP>

# NetworkPolicy isolation check
./verify-netpol-isolation.sh <tenant-namespace>
./verify-cross-ns-blocked.sh team-a team-b

# Monitoring baseline
./verify-monitoring.sh
```

---

*Plan version: v1.0 — 2026-05-31*
*Generates: E2E verify scripts + monitoring baseline YAML*
