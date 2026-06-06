# Tenant Runbook Template (K8s Gateway API + ListenerSet Multi-Tenant)

Ready-to-clone template for documenting a new tenant deployment in the K8s Gateway API + ListenerSet multi-tenant pattern. Captures the full structure (15 sections) used in `gateway-2.0/k8s-gateway/07-verify/tenant-namespace-newapi-team1-appdev-aibang.md`.

**Usage**: copy this file to the runbook's verify/ dir, replace all `<placeholder>` values, and add the 4-5 YAML files (also templated) to the runbook's runtime/ dir.

---

```markdown
# tenant-namespace-<name>-<team>-<base-domain>

> **场景**: 在已存在的 `<team>` 租户 namespace 下，从零部署一个新 API 服务 `<name>`，
> 入口域名 `<name>.<team>.<base-domain>`，**后端协议 HTTPS 443**（如需明文 HTTP，去掉 setcap + cert mount + DR 改 DISABLE），对接既有 **ListenerSet 多租户 Gateway** 模式。
>
> **本 runbook 的实际参照**:
> - Gateway: `<gateway-ns>/<gateway-name>`（<path-to-gateway-yaml>）
> - ListenerSet: `<listenerset-ns>/<listenerset-name>`（<path-to-listenerset-yaml>）
> - 现有 sibling backend `<sibling-name>`: <path-to-sibling>（**HTTPS backend + DR SIMPLE + cert mount** 模式参考）
>
> **验证脚本**: `<path-to-verify-script>` — 链路深探 + E2E URL 自动生成 + 可选 `--validate` curl。
> 命名默认值取自该脚本（`GATEWAY_NS=<gateway-ns>`, `GATEWAY_NAME=<gateway-name>`, `DEFAULT_SCHEME=https`），
> tenant NS 由 FQDN 第 2 段智能推断。

---

## 0. 答案摘要（TL;DR）

**你需要做的工作 = 4-5 个 YAML 资源**（4 个 K8s 资源 + 1 个 ConfigMap），全部直接落在 `<team>` namespace 下:

| # | 资源 | 名称 | 命名空间 | 必需? | 落点 |
|---|------|------|----------|--------|------|
| 1 | `Service` | `<name>` | `<team>` | ✅ 必需 | `<path>/<name>-service.yaml` |
| 2 | `Deployment` | `<name>` | `<team>` | ✅ 必需 | `<path>/<name>-deployment.yaml` |
| 2a | `ConfigMap` | `<name>-nginx-config` | `<team>` | ✅ 必需 | `<path>/<name>-deployment.yaml`（同文件） |
| 3 | `HTTPRoute` | `<name>-route` | `<team>` | ✅ 必需 | `<path>/<name>-httproute.yaml` |
| 4 | `DestinationRule` | `<name>-dr` | `<team>` | 🟡 推荐 | `<path>/<name>-destinationrule.yaml` |

**不需要你创建的**（平台/共享层）:

| 资源 | 路径 | 备注 |
|------|------|------|
| `Namespace` `<team>` | n/a | **已存在**，必须带 label `<selector-key>: <selector-value>`（见 §2.1）|
| `ListenerSet` `<listenerset-ns>/<listenerset-name>` | <path> | **已存在** |
| `Gateway` `<gateway-ns>/<gateway-name>` | <path> | **已存在** |
| TLS Secret `<listenerset-ns>/<tls-secret-name>` | <path> | **已存在**，但 `<name>` 在 `<team>` NS 也要 mount，**必须先复制到 `<team>` NS**（见 §2.4）|

**所有 yaml apply 完后**，再用 `<verify-script-path>` 验证即可，预期 HTTP 200。

### 0.1 命名假设表（**全部已与 runbook 实际对齐**）

| 资源 | 假设值 | 来源 | 验证方法 |
|------|--------|------|----------|
| Gateway | `<gateway-ns>/<gateway-name>` | <path> | `kubectl get gateway -n <gateway-ns>` |
| ListenerSet | `<listenerset-ns>/<listenerset-name>` | <path> | `kubectl get listenerset -n <listenerset-ns>` |
| ListenerSet hostname | `*.<team>.<base-domain>` | 上述 yaml 中 `spec.listeners[*].hostname` | 查 yaml |
| ListenerSet sectionName | `https` | 上述 yaml 中 `spec.listeners[*].name=https` | 查 yaml |
| tenant NS | `<team>` | FQDN 第 2 段推断 | `kubectl get ns <team>` |
| **tenant NS 必备 label** | `<selector-key>: <selector-value>` | ListenerSet 的 `allowedRoutes.namespaces.selector` 强制要求 | `kubectl get ns <team> -o yaml` |
| Service port | `443 → 443` | 跟现有 `<sibling-name>` 完全一致 | HTTPRoute `backendRefs.port=443` |
| 应用镜像 | `nginxinc/nginx-unprivileged:1.27-alpine` | 必须支持 HTTPS | 跟 `<sibling-name>` 同镜像 |
| 挂载的 TLS cert | `<team>/<tls-secret-name>` | 跟 ListenerSet 引用同一份 wildcard cert | 跨 NS 复制见 §2.4 |

> 💡 **最关键的三条**:
> 1. `<team>` NS **必须**带 label `<selector-key>: <selector-value>`，否则 ListenerSet 的 `allowedRoutes.namespaces.selector` 不会放行新 HTTPRoute。
> 2. **TLS Secret 必须先复制到 `<team>` NS**，否则 Pod 启动会卡 `ContainerCreating`（`MountVolume.SetUp failed: secret not found`）—— K8s Secret 是 namespace-scoped 的，**ReferenceGrant 解决不了**这个。
> 3. `ListenerSet` 的 `spec.listeners[*].hostname` 必须是 `*.<team>.<base-domain>` 这种通配，否则 HTTPRoute 会被 listener 拒绝 → curl 404。

---

## 1. 链路全景

```
Internet
   │  https://<name>.<team>.<base-domain>/
   ▼
┌──────────────────────────────────────────────────┐
│ GCP Internal HTTPS Load Balancer (ILB)          │
│   SNI: *.<team>.<base-domain> → backend service  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ Gateway: <gateway-ns>/<gateway-name>             │
│   class: istio                                  │
└──────────────────┬───────────────────────────────┘
                   │  (被 ListenerSet 扩展)
                   ▼
┌──────────────────────────────────────────────────┐
│ ListenerSet: <listenerset-ns>/<listenerset-name>│
│   section: https                                │
│   hostname: *.<team>.<base-domain>              │
│   tls: Terminate → Secret(<tls-secret-name>)     │
│   allowedRoutes.namespaces.selector:            │
│     <selector-key>: "<selector-value>"  ← 关键  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ HTTPRoute: <team>/<name>-route                  │
│   parentRef: ListenerSet                        │
│   hostnames: [<name>.<team>.<base-domain>]       │
│   rules: PathPrefix / → backendRef <name>:443    │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ Service: <team>/<name> (ClusterIP)               │
│   port 443 → targetPort 443 (HTTPS)             │
│   appProtocol: https                            │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ Deployment: <team>/<name>                       │
│   replicas: 2                                   │
│   image: nginxinc/nginx-unprivileged:1.27-alpine│
│   containerPort: 443                            │
│   listen 443 ssl (setcap cap_net_bind_service)  │
│   cert mounted: <tls-secret-name>               │
│   location / → "Hello, world! (<name> on 443)"  │
│   location /healthz → "ok"                      │
│   probes: HTTPS /healthz on 443                  │
└──────────────────────────────────────────────────┘
```

---

## 2. 前提条件检查（apply 前必查）

### 2.1 Namespace 存在 + 带必备 label

```bash
kubectl get ns <team>
kubectl get ns <team> -o jsonpath='{.metadata.labels.<selector-key>}'
# 期望输出: <selector-value>
# 如果为空, 加上:
#   kubectl label ns <team> <selector-key>=<selector-value>
```

> **为什么这条是 blocker**: 见 ListenerSet yaml 末尾的 `spec.allowedRoutes.namespaces.selector.matchLabels`。
> 如果 NS 没这个 label, ListenerSet 直接拒绝 HTTPRoute, `status.parents[].conditions[Accepted]` = False, reason = `NotAllowedByListeners`。

### 2.2 ListenerSet 存在 + Accepted

```bash
kubectl get listenerset -n <listenerset-ns> <listenerset-name> \
  -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'
# 期望: True
kubectl get listenerset -n <listenerset-ns> <listenerset-name> \
  -o jsonpath='{.spec.listeners[*].hostname}'
# 期望: *.<team>.<base-domain>
```

### 2.3 Gateway 存在 + Programmed

```bash
kubectl get gateway -n <gateway-ns> <gateway-name> \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# 期望: True
```

### 2.4 ⭐ TLS Secret 必须先复制到 `<team>` NS（**最常踩的坑**）

K8s Secret 是 namespace-scoped 的, Pod 只能 mount **同 namespace** 的 Secret。
ReferenceGrant **不**解决这个问题（它只管 Gateway API 资源跨 NS 引 Service/Secret 的授权）。

```bash
kubectl get secret <tls-secret-name> -n <listenerset-ns> -o json \
  | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields) | .metadata.namespace = "<team>"' \
  | kubectl apply -f -

# 验证: 两个 NS 各有一份
kubectl get secret <tls-secret-name> -n <listenerset-ns>
kubectl get secret <tls-secret-name> -n <team>
```

> 两份 Secret 互相独立, 任何 cert 轮换都要同步。详见 runbook 关于 cert-manager/external-secrets 的说明。

---

## 3. 完整 YAML 配置

> 所有 yaml 文件已落到 `<path>/<name>-*.yaml`, 可直接 `kubectl apply -f`。

### 3.1 Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <name>
  namespace: <team>
  labels:
    app: <name>
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

### 3.2 Deployment + ConfigMap (multi-doc)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <name>
  namespace: <team>
spec:
  replicas: 2
  selector:
    matchLabels:
      app: <name>
  template:
    metadata:
      labels:
        app: <name>
    spec:
      containers:
        - name: <name>
          image: nginxinc/nginx-unprivileged:1.27-alpine
          ports:
            - name: https
              containerPort: 443
          volumeMounts:
            - { name: tls-certs, mountPath: /etc/nginx/certs, readOnly: true }
            - { name: nginx-config, mountPath: /etc/nginx/conf.d, readOnly: true }
          args:
            - /bin/sh
            - -c
            - |
              apk add --no-cache libcap 2>/dev/null
              setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx 2>/dev/null
              nginx -g 'daemon off;'
          readinessProbe:
            httpGet: { path: /healthz, port: https, scheme: HTTPS }
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet: { path: /healthz, port: https, scheme: HTTPS }
            initialDelaySeconds: 10
            periodSeconds: 10
          startupProbe:
            httpGet: { path: /healthz, port: https, scheme: HTTPS }
            initialDelaySeconds: 0
            periodSeconds: 5
            failureThreshold: 12
          securityContext:
            runAsNonRoot: true
            runAsUser: 101
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
              add:  ["NET_BIND_SERVICE"]
      volumes:
        - name: tls-certs
          secret: { secretName: <tls-secret-name> }
        - name: nginx-config
          configMap: { name: <name>-nginx-config }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: <name>-nginx-config
  namespace: <team>
data:
  default.conf: |
    server {
        listen 443 ssl;
        server_name _;
        ssl_certificate     /etc/nginx/certs/tls.crt;
        ssl_certificate_key /etc/nginx/certs/tls.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        location / {
            default_type text/plain;
            return 200 "Hello, world! (<name> on 443, hostname: $hostname, ssl: on)\n";
            add_header X-Backend-Server $hostname always;
        }
        location /healthz {
            default_type text/plain;
            return 200 "ok\n";
        }
    }
```

### 3.3 HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <name>-route
  namespace: <team>
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: <listenerset-name>
      namespace: <listenerset-ns>
      sectionName: https
  hostnames:
    - <name>.<team>.<base-domain>
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - { name: <name>, port: 443, weight: 1 }
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - { name: X-Tenant, value: <team> }
              - { name: X-Gateway-Source, value: <listenerset-name> }
              - { name: X-Backend-Protocol, value: https }
```

### 3.4 DestinationRule (推荐)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: <name>-dr
  namespace: <team>
spec:
  host: <name>.<team>.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      insecureSkipVerify: true  # cert 是自签 wildcard; CA 签发时去掉
    connectionPool:
      tcp: { connectTimeout: 5s, maxConnections: 100 }
      http: { h2UpgradePolicy: DEFAULT, maxRequestsPerConnection: 10, idleTimeout: 60s }
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

---

## 4. 部署步骤

### 4.1 一行 apply (推荐)

```bash
cd <runbook-root>

# 0) ⭐ 先把 TLS Secret 复制到 <team> NS
kubectl get secret <tls-secret-name> -n <listenerset-ns> -o json \
  | jq 'del(.metadata.namespace,.metadata.uid,.metadata.resourceVersion,.metadata.creationTimestamp,.metadata.managedFields) | .metadata.namespace = "<team>"' \
  | kubectl apply -f -

# 1) apply 4 个新资源
kubectl apply -f <path>/<name>-service.yaml
kubectl apply -f <path>/<name>-deployment.yaml      # 包含 Deployment + ConfigMap
kubectl apply -f <path>/<name>-httproute.yaml
kubectl apply -f <path>/<name>-destinationrule.yaml
```

### 4.2 期望输出

```
secret/<tls-secret-name> created (or configured)
service/<name> created
deployment.apps/<name> created
configmap/<name>-nginx-config created
httproute.gateway.networking.k8s.io/<name>-route created
destinationrule.networking.istio.io/<name>-dr created
```

---

## 5. 验证流程 (5 层, 由浅入深)

### 5.1 资源就绪性检查 (30 秒)
### 5.2 集群内连通性 (HTTPS 直连 Pod)
### 5.3 Gateway 链路探查 (用 verify script)
### 5.4 端到端流量测试 (3 种方法: DNS / SNI / IP+Host)
### 5.5 失败模式速查

> 详细命令见具体 runbook. 每层都要跑, 失败模式表覆盖 6-10 种典型 symptom.

---

## 6. 反推说明 (为什么是这 4-5 个 YAML)

| 脚本 step | 反向: 你需要 apply 的资源 |
|-----------|---------------------------|
| Step 1: find HTTPRoute | §3.3 HTTPRoute |
| Step 2: HTTPRoute.parentRefs | 由已存在的 ListenerSet 满足 |
| Step 3: backendRefs | §3.1 Service |
| Step 4: DestinationRule | §3.4 DR (可选) |
| Step 5: Service.selector | §3.2 Deployment pod labels |
| Step 6: Deployment spec | §3.2 Deployment + ConfigMap |

---

## 7. 与现有 `<sibling-name>` 的对比

| 维度 | `<sibling-name>` (现有) | `<name>` (本文) | 备注 |
|------|-------------------------|-----------------|------|
| tenant NS | `<sibling-ns>` | `<team>` | 唯一真正的差异 |
| FQDN | `<sibling-fqdn>` | `<name>.<team>.<base-domain>` | 都被通配覆盖 |
| 镜像 | `nginx-unprivileged` | `nginx-unprivileged` | **完全相同** |
| Service port | 443 → 443 | 443 → 443 | **完全相同** |
| DR tls.mode | SIMPLE + insecureSkipVerify | SIMPLE + insecureSkipVerify | **完全相同** |
| 挂 TLS cert | ✅ | ✅ | **完全相同** |
| Secret 跨 NS 复制 | ✅ | ✅ | **都需要** (Pod mount Secret) |

---

## 8. 常见定制点

- 8.1 改 FQDN
- 8.2 改 namespace
- 8.3 加多 listener (gRPC)
- 8.4 加 mTLS (生产环境)
- 8.5 加流量切分 (金丝雀)
- 8.6 加 header 路由

---

## 9. 一次性删除 (清理)

```bash
kubectl delete -f <path>/<name>-httproute.yaml
kubectl delete -f <path>/<name>-destinationrule.yaml
kubectl delete -f <path>/<name>-deployment.yaml
kubectl delete -f <path>/<name>-service.yaml
kubectl delete secret <tls-secret-name> -n <team>   # 平台层源不删
```

---

## 10. 关于 ReferenceGrant (为什么不需要)

[同 template — HTTPRoute→ListenerSet 跨 NS 由 allowedRoutes 控制, HTTPRoute→Service 同 NS, Pod mount Secret 由 Secret duplicate 解决]

---

## 11. 附录: 完整文件清单

| 资源 | 文件 | 落点 |
|------|------|------|
| Service | `<name>-service.yaml` | `<path>/` |
| Deployment | `<name>-deployment.yaml` | `<path>/` |
| ConfigMap | `<name>-deployment.yaml` (同文件) | `<path>/` |
| HTTPRoute | `<name>-httproute.yaml` | `<path>/` |
| DestinationRule | `<name>-destinationrule.yaml` | `<path>/` |

---

## 12. 快速清单 (apply 前 1 分钟扫一眼)

- [ ] `<team>` NS 存在
- [ ] `<team>` NS 有 label `<selector-key>: <selector-value>`
- [ ] ListenerSet Accepted=True
- [ ] Gateway Programmed=True
- [ ] TLS Secret 源存在
- [ ] **TLS Secret 副本已 apply 到 `<team>` NS**
- [ ] 4 个 yaml 文件 apply 成功
- [ ] `<verify-script>` 输出 HTTP 200
```

---

## Notes for Customization

When cloning this template, replace all `<placeholder>` values:

| Placeholder | Example value | Source |
|-------------|---------------|--------|
| `<name>` | `newapi` | Tenant service name |
| `<team>` | `team1` | Tenant namespace name (also FQDN 2nd segment) |
| `<base-domain>` | `appdev.aibang` | Wildcard cert base domain |
| `<gateway-ns>` / `<gateway-name>` | `abjx-gw-int` | From `03-gateway/*.yaml` |
| `<listenerset-ns>` / `<listenerset-name>` | `abjx-listenerset-int` / `team1-listenerset` | From `05-listenerset/*.yaml` |
| `<selector-key>` / `<selector-value>` | `gateway-access` / `ajbx-int` | From ListenerSet's `allowedRoutes.namespaces.selector` |
| `<tls-secret-name>` | `abjx-lex-eg-secret-team1-tls` | From `04-secrets/*.yaml` |
| `<sibling-name>` | `app` | Existing working tenant in `06-runtime/` |
| `<sibling-ns>` | `110139-int` | Existing tenant's NS |
| `<sibling-fqdn>` | `app.team1.appdev.aibang` | Existing tenant's FQDN |
| `<verify-script-path>` | `07-verify/k8s-gateway-fqdn-minimax-eng.sh` | The chain inspector script |
| `<path>` | `06-runtime/` | Where the new yaml files live in the runbook |
| `<runbook-root>` | `/Users/lex/git/gcp/gateway-2.0/k8s-gateway` | The runbook's repo path |

## When to Add Sections (vs Drop from Template)

The 15-section structure is the **default for new tenant runbooks**. Drop sections when:
- No sibling tenant exists → drop §7 (vs sibling comparison)
- No DR (e.g., dev/staging) → drop §3.4 from yaml list, mention in §8.4 instead
- HTTP backend (rare) → drop the TLS cert / DR SIMPLE / ConfigMap nginx config

Add sections when:
- Multiple sibling tenants → §7 becomes a comparison table with N columns
- Multiple GatewayClasses → add §12 comparing
- Production setup → add §13 cert rotation / secret sync
