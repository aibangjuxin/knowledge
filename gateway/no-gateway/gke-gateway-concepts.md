# GKE Gateway Concepts

> Reference for GKE Gateway (Gateway API) architecture, traffic management, and operational patterns for the no-gateway API routing layer.

---

## 1. What is GKE Gateway

GKE Gateway is an implementation of the **Kubernetes Gateway API** running on Google Kubernetes Engine. It provides a Kubernetes-native way to manage inbound (and outbound) traffic using `Gateway`, `HTTPRoute`, and related CRDs — replacing the older Ingress beta API.

Unlike Kong (which runs as a data-plane inside the cluster), GKE Gateway's control plane is managed by Google and the data plane runs on **Cloud Load Balancer (GLB)** — traffic enters through Google's global edge network before reaching GKE pods.

---

## 2. Architecture Overview

```
Client
  │
  ▼
┌──────────────────────────────────────────────┐
│  Google Cloud Load Balancer (GLB)             │
│  ☁️ TLS termination · Cloud Armor · WAF      │
└──────────────────────────────────────────────┘
  │
  ▼
┌──────────────────────────────────────────────┐
│  Nginx L7 Reverse Proxy                       │
│  🔄 Path-based routing + Header injection     │
│      /team-a/*  → X-Gateway-Mode: "kong"     │
│      /team-b/*  → proxy_pass ILB_IP:443      │
└──────────────────────────────────────────────┘
  │
  ├─── X-Gateway-Mode: kong ──▶ Kong Gateway DP
  │                                │
  │                           upstream backend
  │
  └─── X-Gateway-Mode: nogateway ──▶ GKE Gateway (ILB)
                                      │
                               ┌─────┴─────┐
                               ▼           ▼
                         HTTPRoute    HTTPRoute
                         (team-b)     (team-c)
                               │           │
                               ▼           ▼
                         Service      Service
                         (ClusterIP)  (ClusterIP)
                               │           │
                               ▼           ▼
                          Pods         Pods
```

---

## 3. Key CRD Components

### 3.1 Gateway

The top-level entry point. Defines the listener (port, protocol, TLS) and binds to a GKE-managed load balancer.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: abjx-common-gateway
  namespace: tenant-team-b
spec:
  gatewayClassName: gke-l7-regional-external-managed
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    allowedRoutes:
      namespaces:
        from: same
    # TLS config here or via TLSRoute
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: same
```

**GatewayClass names on GKE:**

| Class | Use Case |
|-------|----------|
| `gke-l7-global-external-managed` | Global external HTTPS (anycast) |
| `gke-l7-regional-external-managed` | Regional external HTTPS |
| `gke-l7-rilb` | Regional internal load balancer (ILB) — **used for no-gateway path** |
| `gke-l7-global-internal-managed` | Global internal (rare) |

The no-gateway flow uses **`gke-l7-rilb`** because Nginx proxies to the Gateway's internal IP (ILB), not the public GLB.

---

### 3.2 HTTPRoute

Defines routing rules: which paths go to which backend services, with optional weighted traffic splitting for canary releases.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-name-type-ri-sb-samples-route
  namespace: tenant-team-b
spec:
  parentRefs:
  - name: abjx-common-gateway
    sectionName: https
  hostnames:
  - "dev.goole.cloud.uk.aibang"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /api-name-type-ri-sb-samples
    backendRefs:
    - name: api-name-type-ri-sb-samples-v1
      port: 443
      weight: 80
    - name: api-name-type-ri-sb-samples-v2
      port: 443
      weight: 20
```

**Key fields:**

| Field | Purpose |
|-------|---------|
| `parentRefs` | Bind this route to a Gateway (or specific listener) |
| `hostnames` | Match incoming requests by Host header |
| `rules[].matches` | Path matching (Prefix, Exact, Regex) |
| `rules[].backendRefs` | One or more backend Services + optional weights |
| `weight` | Traffic split (relative, not percentage) |

---

### 3.3 Service (Backend)

Standard Kubernetes Service — the CRD doesn't create these, HTTPRoute references them.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-name-type-ri-sb-samples-v1
  namespace: tenant-team-b
  labels:
    version: "2025-11-19"
spec:
  ports:
  - name: https
    port: 443
    targetPort: 8443
  selector:
    app: api-name-type-ri-sb-samples
    version: "2025-11-19"
```

> On GKE with container-native LB (default on VPC-native), Service ports create **NEGs (Network Endpoint Groups)** that the GLB targets directly — pods are reached without iptables DNAT.

---

### 3.4 HealthCheckPolicy

GKE-specific CRD (`networking.gke.io/v1`) to configure health checks at the GLB/backend level (not pod-level readinessProbe).

```yaml
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: internal-hc-policy
  namespace: tenant-team-b
spec:
  default:
    config:
      type: HTTP
      httpHealthCheck:
        port: 8080
        requestPath: /healthz
      checkIntervalSec: 5
      timeoutSec: 3
      healthyThreshold: 2
      unhealthyThreshold: 2
  targetRef:
    group: ""
    kind: Service
    name: api-name-type-ri-sb-samples-v1
```

> Without a HealthCheckPolicy, GLB uses its own defaults. Explicit health checks prevent 502s during rolling updates — GLB won't send traffic to pods that haven't passed the configured threshold.

---

### 3.5 BackendConfig

GKE-specific CRD for attaching Cloud Armor, CDN, connection draining, etc. to the backend service.

```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: my-backend-config
  namespace: tenant-team-b
spec:
  securityPolicy:
    name: my-cloud-armor-policy
  connectionDraining:
    drainingTimeoutSec: 600
```

```yaml
# Attach BackendConfig to Service via annotation
apiVersion: v1
kind: Service
metadata:
  annotations:
    cloud.google.com/backend-config: '{"default": "my-backend-config"}'
  name: api-name-type-ri-sb-samples-v1
  namespace: tenant-team-b
spec:
  ports:
  - port: 443
    targetPort: 8443
  selector:
    app: api-name-type-ri-sb-samples
```

---

## 4. No-Gateway Traffic Flow

### 4.1 End-to-End Request Path

```
1. Client → HTTPS request to dev.goole.cloud.uk.aibang/api-name-type-ri-sb-samples
2. GLB → TLS termination, Cloud Armor WAF check
3. GLB → routes to Nginx L7 (GCE instance group) based on URL map
4. Nginx → path /api-name-type-ri-sb-samples matches HTTPRoute
           → injects X-Gateway-Mode: "nogateway"
           → proxy_pass https://<ILB_IP>/api-name-type-ri-sb-samples
5. ILB (gke-l7-rilb) → receives HTTPS on port 443
6. Gateway listener → evaluates HTTPRoute bindings for this namespace
7. HTTPRoute → matches host + path, selects backendRefs
8. Service → load balances across pods (container-native NEG)
9. Pod → receives request on targetPort 8443
```

### 4.2 Nginx Configuration Pattern

```nginx
# /etc/nginx/conf.d/nogtw/team-b-api.conf
upstream gke_gateway {
    server 10.100.0.50:443;  # GKE Gateway ILB IP
    keepalive 32;
}

server {
    listen 80;
    server_name dev.goole.cloud.uk.aibang;

    location /api-name-type-ri-sb-samples {
        proxy_pass https://gke_gateway/api-name-type-ri-sb-samples;
        proxy_set_header Host "dev.goole.cloud.uk.aibang";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Gateway-Mode "nogateway";
        proxy_set_header X-Request-ID $request_id;
        proxy_http_version 1.1;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
    }
}
```

### 4.3 Internal TLS Setup

Pods use internal certificates (Google-manged or self-signed) for mTLS at the Service layer.

```yaml
# Pod spec mounts TLS secret
spec:
  containers:
  - name: app
    ports:
    - containerPort: 8443
    volumeMounts:
    - name: tls-cert
      mountPath: /etc/tls
      readOnly: true
  volumes:
  - name: tls-cert
    secret:
      secretName: api-name-tls
```

> For the no-gateway path, TLS is typically terminated at the pod (targetPort), not at the Service. The Gateway handles HTTPS listener; pods receive plain HTTP or mutual TLS depending on configuration.

---

## 5. Gateway vs Kong Paths

| Aspect | Gateway (no-gateway) | Kong (gateway) |
|--------|---------------------|----------------|
| Entry point | ILB IP (10.100.0.50) | Kong Service/Ingress |
| Routing | HTTPRoute CRD | Deck declarative config |
| Traffic splitting | HTTPRoute weights | Kong plugins / canary |
| Auth/Rate limit | Custom middleware in pod | Kong plugins |
| TLS | Gateway listener + pod certs | Kong TLS passthrough or termination |
| Ops complexity | Lower (Google-managed LB) | Higher (self-managed data plane) |
| Visibility | Cloud Logging + Metrics | Kong Dashboard + Logging |
| Use case | Internal APIs, no auth overlay | External APIs needing auth/rate-limit |

---

## 6. Namespace Isolation Model

Each tenant team lives in its own namespace. The Gateway is referenced per-namespace; HTTPRoute `allowedRoutes.namespaces.from: same` restricts cross-namespace routing.

```
tenant-team-b (namespace)
  └── Gateway: abjx-common-gateway
  └── HTTPRoute: api-route
  └── Service: api-svc-v1, api-svc-v2
  └── Deployment: api-app-v1, api-app-v2
  └── Secret: api-tls (internal cert)
  └── HealthCheckPolicy: hc-policy

tenant-team-c (namespace)
  └── Gateway: abjx-common-gateway  (shared, same class)
  └── HTTPRoute: other-route
  └── Service: other-svc
```

> A single `gke-l7-rilb` Gateway can serve multiple namespaces via `allowedRoutes.namespaces.from: same`. Each namespace manages its own HTTPRoute; Gateway itself is owned by the namespace where the Gateway CRD lives.

---

## 7. Version Management & Canary

HTTPRoute supports weighted backendRefs for canary releases without any additional CRD.

```
Phase 1: 100% → v1
Phase 2: 80%  → v1,  20% → v2  (observe)
Phase 3: 50%  → v1,  50%  → v2  (validate)
Phase 4: 0%   → v1, 100%  → v2  (switch)
Phase 5: remove v1 backendRef, delete old Service/Deployment
```

Commands to update weight live in CI/CD scripts — see `verify-gke-gateway.sh` in the no-gateway repo for automation patterns.

---

## 8. Security Controls

### 8.1 mTLS (Pod-to-Pod)

GKE Gateway does not enforce mTLS automatically. Options:

- **Compute Engine mesh**: enables automatic mTLS between pods in the same cluster
- **Istio**: full service mesh with Strict mode
- **Cilium**: eBPF-based network policy + mTLS

### 8.2 Cloud Armor (WAF)

Attach to the backend via BackendConfig:

```yaml
spec:
  securityPolicy:
    name: my-armor-policy  # Pre-created via gcloud
```

### 8.3 RBAC for Gateway Resources

```bash
# Prevent developers from modifying Gateway/HTTPRoute in tenant namespace
kubectl auth can-i update httproute -n tenant-team-b  # should be no
```

Use **RoleBinding** to restrict who can create/modify Gateway and HTTPRoute CRDs; cluster admins own the GatewayClass.

---

## 9. Troubleshooting Checklist

| Symptom | Likely Cause | Check |
|---------|-------------|-------|
| 502 Bad Gateway | Pod not ready / health check failing | `kubectl describe healthcheckpolicy` + pod readiness |
| 404 No matching route | HTTPRoute not bound to Gateway | `kubectl get httproute -n <ns>` + `parentRefs` |
| 503 Service Unavailable | All endpoints unhealthy | `kubectl get endpoints -n <ns>` |
| Traffic not splitting | HTTPRoute weight not applying | Verify `backendRefs[].weight` values |
| TLS errors | Certificate not propagated | Check Gateway listener TLS config + Secret |
| Nginx timeout | ILB IP unreachable from Nginx | Firewall rules, VPC routing, ILB health |

---

## 10. Reference Files

| File | Purpose |
|------|---------|
| `explorer-no-gateway.md` | Original requirements — no-gateway pattern motivation |
| `no-gateway-design.md` | Architecture decision: path-based routing, header injection |
| `no-gateway-gkegateway-flow.md` | Full flow diagram with Kong + GKE Gateway branches |
| `glb-path.md` | GLB URL-map design: two backend pools + path分流 |
| `HealthCheckPolicy.md` | GKE health check CRD usage for rolling updates |
| `Gateway-API-allowedRoutes.md` | allowedRoutes limits: namespace vs pod selectors |
| `no-gateway-path-flow.md` | HTTPRoute version canary lifecycle + gantt |
| `verify-gke-gateway.sh` | Operational script for Gateway verification |