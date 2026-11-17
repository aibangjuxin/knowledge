# tenant-namespace-newapi-team1-appdev-aibang

> **场景**：在已存在的 `team1` 租户 namespace 下，从零部署一个新 API 服务 `newapi`，
> 入口域名 `newapi.team1.appdev.aibang`，对接既有 ListenerSet 模式多租户 Gateway。
> **基准（唯一参考）**：[k8s-gateway-fqdn-minimax.sh](./k8s-gateway-e2e/k8s-gateway-fqdn-minimax.sh) — 所有命名默认值取自脚本里的环境变量默认（`GATEWAY_NS=infrastructure`、`GATEWAY_NAME=central-gateway`、`DEFAULT_SCHEME=https`），tenant NS 由 FQDN 第 2 段智能推断。
> **验证工具**：同上脚本（链路探查 & E2E URL 构建器）。

---

## 0. 答案摘要（TL;DR）

**你需要做的工作 = 4 个 YAML 资源**，按以下顺序 apply 即可让流程跑通：

| # | 资源 | 名称 | 命名空间 | 必需？ |
|---|------|------|----------|--------|
| 1 | `Service` | `newapi` | `team1` | ✅ 必需 |
| 2 | `Deployment` | `newapi` | `team1` | ✅ 必需 |
| 3 | `HTTPRoute` | `newapi-route` | `team1` | ✅ 必需 |
| 4 | `DestinationRule` | `newapi-dr` | `team1` | 🟡 推荐（生产环境必加） |

**不需要你创建的**（用户已确认/由平台团队维护）：

| 资源 | 路径 | 备注 |
|------|------|------|
| `Namespace` | `team1` | 已存在 |
| `ListenerSet` | `team1/team1-listeners` | 已存在，假设 `sectionName=https`、`hostname=*.team1.appdev.aibang` |
| `Gateway` | `infrastructure/central-gateway` | 已存在，`gatewayClassName: istio` |
| TLS Secret | `team1/*.appdev.aibang` 证书 | 由 ListenerSet 引用，平台或租户团队已创建 |

**所有 4 个 yaml apply 完后**，再用 `k8s-gateway-fqdn-minimax.sh` 验证即可，预期 HTTP 200。

### 0.1 命名假设表（脚本默认 vs 惯例假设）

| 资源 | 假设值 | 来源 | 验证方法 |
|------|--------|------|----------|
| Gateway | `infrastructure/central-gateway` | 脚本环境变量默认 `GATEWAY_NS` + `GATEWAY_NAME` | `kubectl get gateway -n infrastructure` |
| GatewayClass | `istio` | 脚本第 318 行匹配 `P_KIND == "Gateway"` 后从 status 拿 IP | `kubectl get gatewayclass` |
| ListenerSet | `team1/team1-listeners` | **惯例假设**（用户确认 ListenerSet 已存在，未指定具体名） | `kubectl get listenerset -n team1` 取实际名 |
| ListenerSet hostname | `*.team1.appdev.aibang` | **反推**：要 match `newapi.team1.appdev.aibang` 必须有这个通配 | `kubectl get listenerset -n team1 <actual-name> -o yaml` |
| ListenerSet sectionName | `https` | **惯例假设**（terminating TLS 场景最常见） | 同上 yaml 查 `spec.listeners[*].name` |
| listener protocol | `HTTPS` (port 443) | 脚本第 353 行只识别 `HTTPS`/`TLS`/`HTTP` | 同上 yaml |
| tenant NS | `team1` | 脚本第 218 行 `awk -F. '{print $2}'` 从 FQDN 第 2 段推断 | `kubectl get ns team1` |
| Service 端口 | `80 → 8080` | K8s 惯例（Service port 80 走标准 HTTP，对外是 Gateway 终结 TLS） | HTTPRoute 写什么 service port 就用什么 |
| 应用镜像 | `gcr.io/google-samples/hello-app:1.0` | 最小可跑通样例（脚本对 probe path 没有要求，只要返回 200） | 替换为真实镜像 |

> 💡 **最关键的两条**：
> 1. `ListenerSet 实际名` 和 `sectionName` 必须用 `kubectl get listenerset -n team1 -o yaml` 查实，下游 HTTPRoute 的 `parentRefs` 才能写对。
> 2. `ListenerSet.hostname` 必须是能覆盖 `newapi.team1.appdev.aibang` 的通配，否则 HTTPRoute 会被 listener 拒绝 → curl 404。

---

## 1. 链路全景

```
Internet
   │  https://newapi.team1.appdev.aibang/
   ▼
┌──────────────────────────────────────────────────┐
│ GCP External HTTPS Load Balancer (GCLB)         │
│   SNI: *.team1.appdev.aibang → backend service  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ Gateway: infrastructure/central-gateway         │
│   class: istio                                  │
│   (汇聚所有团队 listener)                          │
└──────────────────┬───────────────────────────────┘
                   │  (被 ListenerSet 扩展)
                   ▼
┌──────────────────────────────────────────────────┐
│ ListenerSet: team1/team1-listeners              │
│   section: https                                │
│   hostname: *.team1.appdev.aibang               │
│   tls: Terminate → Secret(team1/*.appdev.aibang)│
└──────────────────┬───────────────────────────────┘
                   │  (HTTPRoute parentRef → ListenerSet)
                   ▼
┌──────────────────────────────────────────────────┐
│ HTTPRoute: team1/newapi-route                   │
│   hostnames: [newapi.team1.appdev.aibang]       │
│   rules: PathPrefix / → backendRef newapi:80    │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ Service: team1/newapi (ClusterIP)               │
│   port 80 → targetPort 8080                     │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│ Deployment: team1/newapi                        │
│   replicas: 2                                   │
│   container: gcr.io/google-samples/hello-app:1.0│
│   containerPort: 8080                           │
│   probes: GET / on 8080                         │
└──────────────────────────────────────────────────┘
```

---

## 2. 前提条件检查（apply 前先验）

```bash
# 1. Namespace 存在
kubectl get ns team1

# 2. ListenerSet 存在且 Accept=True
kubectl get listenerset -n team1 team1-listeners -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'
# 期望输出: True

# 3. Gateway 存在且 Programmed=True
kubectl get gateway -n infrastructure central-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
# 期望输出: True

# 4. TLS 证书 Secret 存在（如果 ListenerSet 引用了）
kubectl get secret -n team1 -l 'gateway.tenant.com/cert-for=team1.appdev.aibang'
# 或者直接看 ListenerSet 引用了哪个：
kubectl get listenerset -n team1 team1-listeners -o jsonpath='{.spec.listeners[*].tls.certificateRefs[*].name}'
```

> ⚠️ **如果其中任何一步失败**：平台层（Gateway、ListenerSet、Namespace、TLS Secret）由平台/共享层团队管理，本文不负责。请先确认这些前置资源到位（用 `kubectl get` 验一遍）。

---

## 3. 完整 YAML 配置（按 apply 顺序）

> 所有文件默认放在 `./newapi-team1-appdev/` 目录下，可单独 apply，也可一次 apply 全部。

### 3.1 Service — `service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: newapi
  namespace: team1
  labels:
    app: newapi
    app.kubernetes.io/name: newapi
    app.kubernetes.io/part-of: team1-appdev
  annotations:
    description: "Backend service for newapi.team1.appdev.aibang"
spec:
  type: ClusterIP              # Gateway API 链路只需 ClusterIP
  selector:
    app: newapi                # ← 必须与 Deployment pod template labels 一致
  ports:
    - name: http
      port: 80                 # ← HTTPRoute backendRef.port 引用的端口
      targetPort: 8080         # ← 与 Deployment containerPort 一致
      protocol: TCP
      appProtocol: http        # 提示 Gateway 协议类型
```

### 3.2 Deployment — `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: newapi
  namespace: team1
  labels:
    app: newapi
    app.kubernetes.io/name: newapi
    app.kubernetes.io/part-of: team1-appdev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: newapi
  template:
    metadata:
      labels:
        app: newapi              # ← 与 Service selector 一致
        app.kubernetes.io/name: newapi
    spec:
      containers:
        - name: newapi
          # 轻量 HTTP echo server: 8080 端口，访问 / 返回 "Hello, world!"
          # 替换为你的真实镜像即可
          image: gcr.io/google-samples/hello-app:1.0
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
          # 三个 probe 都打 /，hello-app 返回 200，链路可被探测到
          # 真实应用请用专门的 healthz endpoint
          readinessProbe:
            httpGet:
              path: /
              port: http
              scheme: HTTP
            initialDelaySeconds: 2
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /
              port: http
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          startupProbe:
            httpGet:
              path: /
              port: http
              scheme: HTTP
            initialDelaySeconds: 0
            periodSeconds: 5
            timeoutSeconds: 2
            failureThreshold: 12   # 允许 60s 启动
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 10001
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
```

> 💡 **镜像备选**（如果集群无法访问 `gcr.io`）：
> ```yaml
> image: nginxinc/nginx-unprivileged:1.27-alpine   # 同样 8080 端口，访问 / 返回 200
> ```
> 或者用本地 Harbor / Artifact Registry 镜像替换。

### 3.3 HTTPRoute — `httproute.yaml`

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: newapi-route
  namespace: team1
  labels:
    app: newapi
    app.kubernetes.io/part-of: team1-appdev
spec:
  # ⭐ 关键: parentRef 是 ListenerSet (不是 Gateway)
  # Gateway 本身不直接定义 *.team1.appdev.aibang，由 ListenerSet 提供
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: team1-listeners     # ← 假设的 ListenerSet 名称
      namespace: team1
      # sectionName 选填: 如果 ListenerSet 有多个 listener (如 https/grpc)
      # 必须指明绑定哪一个。常见命名: https / http / grpc
      sectionName: https

  # 实际对外服务的 FQDN，必须能被 ListenerSet 的 hostname 通配符覆盖
  hostnames:
    - newapi.team1.appdev.aibang

  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
          method: GET
        - path:
            type: PathPrefix
            value: /
          method: POST
      # 任何 method 都可访问也可以不写 method 字段:
      # matches:
      #   - path:
      #       type: PathPrefix
      #       value: /

      backendRefs:
        - name: newapi            # ← Service 名称
          port: 80                # ← Service port (不是 targetPort)
          weight: 1

      # 可选: 添加租户标识 header，方便后端审计
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - name: X-Tenant
                value: team1
              - name: X-Gateway-Source
                value: team1-listeners
```

### 3.4 DestinationRule — `destinationrule.yaml`（🟡 推荐）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: newapi-dr
  namespace: team1
  labels:
    app: newapi
spec:
  # 短名（仅在 team1 ns 内）即可；脚本会同时匹配 4 种 host 形式
  host: newapi.team1.svc.cluster.local
  trafficPolicy:
    # hello-app 没有 Sidecar，所以 Gateway → newapi 之间走明文 HTTP
    # 如果 newapi 注入了 Sidecar，改成 ISTIO_MUTUAL
    tls:
      mode: DISABLE
    connectionPool:
      tcp:
        connectTimeout: 5s
        maxConnections: 100
      http:
        h2UpgradePolicy: DEFAULT
        maxRequestsPerConnection: 10
        idleTimeout: 60s
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
```

---

## 4. 部署步骤（4 步走）

```bash
# 0. 进入工作目录（建议把所有 yaml 放一起）
mkdir -p ~/k8s-yaml/newapi-team1-appdev && cd ~/k8s-yaml/newapi-team1-appdev
# 把上面 4 个 yaml 内容分别保存到 service.yaml / deployment.yaml / httproute.yaml / destinationrule.yaml

# 1. 逐个 apply（看清楚每个的输出）
kubectl apply -f service.yaml
# service/newapi created

kubectl apply -f deployment.yaml
# deployment.apps/newapi created

kubectl apply -f httproute.yaml
# httproute.gateway.networking.k8s.io/newapi-route created

kubectl apply -f destinationrule.yaml
# destinationrule.networking.istio.io/newapi-dr created

# 或者一次性 apply:
# kubectl apply -f service.yaml,deployment.yaml,httproute.yaml,destinationrule.yaml
```

---

## 5. 验证流程（5 个层次，从快到深）

### 5.1 资源就绪性检查（30 秒内完成）

```bash
# Service
kubectl get svc -n team1 newapi
# 期望: TYPE=ClusterIP, PORT=80/TCP

# Pod 启动 & Ready
kubectl get pods -n team1 -l app=newapi
# 期望: 2/2 Running, READY 列都是 1/1

# HTTPRoute binding
kubectl get httproute -n team1 newapi-route \
  -o jsonpath='{.status.parents[?(@.parentRef.name=="team1-listeners")].conditions[?(@.type=="Accepted")].status}'
# 期望输出: True
```

### 5.2 集群内连通性测试（绕过 Gateway）

```bash
# 在 team1 内起一个临时 pod 测 Service
kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl:8.10.1 -n team1 -- \
  curl -sS -w "\nHTTP %{http_code}\n" http://newapi.team1.svc.cluster.local/
# 期望: 返回 "Hello, world!" + HTTP 200
```

### 5.3 Gateway 链路探查（推荐用 minimax 脚本）

```bash
cd ~/git/knowledge/cloud/k8s/k8s-gateway/k8s-gateway-e2e

# 关键参数: FQDN + tenant NS
./k8s-gateway-fqdn-minimax.sh newapi.team1.appdev.aibang team1

# 加 --validate 直接 curl 验证
./k8s-gateway-fqdn-minimax.sh newapi.team1.appdev.aibang team1 --validate
```

**期望输出节选**：
```
🛰️  K8s Gateway FQDN 链路深度勘测工具 (MiniMax 增强版)
  目标域名:      newapi.team1.appdev.aibang
  租户命名空间:  team1
  Gateway:       infrastructure/central-gateway
────────────────────────────────────────────────────────────────────────────────────────

# Step 1 / 6 — HTTPRoute 智能发现
[OK]    匹配到 1 个 HTTPRoute
    • team1/newapi-route
      hostnames: newapi.team1.appdev.aibang

# HTTPRoute: team1/newapi-route
...
    • ListenerSet team1/team1-listeners sectionName=https
...
# Step 3 / 6 — Rules / Matches / Backends
  ⚡ Rule[0]
    Matches:
      • type=PathPrefix       path=/                     headers=<no-headers>      query=<no-qs>        method=GET
    → BackendRef: Service team1/newapi:80 (weight=1)
      DestinationRule: team1/newapi-dr (host=newapi.team1.svc.cluster.local)
      Service: type=ClusterIP clusterIP=10.x.x.x apigateway=<none>
        • selector: app=newapi
        • port=80 → targetPort=8080 protocol=TCP appProtocol=http
      Deployment: team1/newapi ready=2/2
        HTTP Probes:
          • container=newapi             readiness  path=/                       port=http  scheme=HTTP
          • container=newapi             liveness   path=/                       port=http  scheme=HTTP
          • container=newapi             startup    path=/                       port=http  scheme=HTTP

# Step 8 / 6 — E2E 汇总
  全部唯一 URL 列表 (1):
    https://newapi.team1.appdev.aibang/
```

### 5.4 端到端流量测试（外部 HTTPS 流量）

#### 方法 A：本地 DNS 已配置（或在 VPN 内）
```bash
curl -k -v --max-time 10 "https://newapi.team1.appdev.aibang/"
# 期望: HTTP 200, body "Hello, world!\n"
```

#### 方法 B：SNI 绕过 DNS（最常用，跳过证书校验）
```bash
# 从脚本输出里取 GATEWAY_IP=<ILB IP>
GATEWAY_IP="<从 kubectl get gateway -n infrastructure central-gateway -o jsonpath='{.status.addresses[0].value}' 拿>"

curl -k -v --max-time 10 \
  --resolve "newapi.team1.appdev.aibang:443:${GATEWAY_IP}" \
  "https://newapi.team1.appdev.aibang/"
```

#### 方法 C：IP 直连 + Host 头（内网跨网段调试）
```bash
curl -k -v --max-time 10 \
  -H "Host: newapi.team1.appdev.aibang" \
  "https://${GATEWAY_IP}/"
```

### 5.5 失败模式速查

| 现象 | 原因 | 修复 |
|------|------|------|
| `kubectl get httproute` 没有 `team1/newapi-route` | apply 失败 | 检查 `kubectl describe httproute -n team1 newapi-route` |
| HTTPRoute status.parents Accepted=False | ListenerSet 不接受此 hostname | 检查 `kubectl get listenerset -n team1 team1-listeners -o yaml` 中 `spec.listeners[*].hostname` 是否能 match `newapi.team1.appdev.aibang` |
| `404` from curl | ListenerSet hostname pattern 不匹配 | ListenerSet 应该是 `*.team1.appdev.aibang`，否则 HTTPRoute 会被 listener 拒绝 |
| `502 Bad Gateway` from curl | 后端 Pod 没 Ready | 检查 `kubectl get pods -n team1 -l app=newapi` |
| `503 Service Unavailable` | Envoy EDS 还没发现 endpoint | 等 10-30s，istiod 下发 xDS 需时间 |
| `TLS handshake error` | ListenerSet 引用 Secret 错 | `kubectl get secret -n team1 <cert-name>` 确认存在 |
| curl 命令直接走 Gateway IP 还是连不上 | GCLB 后端 Service 选错 | `kubectl get svc -n infrastructure -l gateway.istio.io/managed-by=istio` |

---

## 6. 反推说明（为什么是这 4 个 YAML）

把脚本 `k8s-gateway-fqdn-minimax.sh` 探查的 5 段链路倒过来，就是"我要创建什么"的答案：

```
脚本链路                                反向: 你需要 apply 的资源
─────────────────                     ─────────────────────────────
Step 1: 找 HTTPRoute                 ← 3.3 HTTPRoute (newapi-route)
Step 2: HTTPRoute.parentRefs         ← 由已存在的 ListenerSet/Gateway 满足
Step 3: HTTPRoute.rules.backendRefs  ← 3.1 Service (newapi)
Step 4: DestinationRule (可选)        ← 3.4 DestinationRule (newapi-dr)
Step 5: Service.selector              ← 3.2 Deployment.pod.labels (app=newapi)
Step 6: Deployment spec (image, ports, probes) ← 3.2 Deployment
```

**没你事儿的部分**（平台/共享层）：
- Gateway `infrastructure/central-gateway` — 平台团队管
- ListenerSet `team1/team1-listeners` — 假设已存在
- TLS Secret — ListenerSet 引用，平台或上一任 team1 admin 管
- 入口 GCLB — 由 Gateway Controller (istio/ASM) 自动 reconcile

---

## 7. 常见定制点

### 7.1 改 FQDN
修改 `httproute.yaml` 的 `spec.hostnames` 和 `service.yaml` 的 metadata 即可。

### 7.2 改 namespace（比如 `team2-appdev`）
替换所有 `namespace: team1` → `namespace: team2`，并把 ListenerSet 引用改为对应 team 的。

### 7.3 加多 listener（比如 TCP gRPC）
如果 ListenerSet 有 `https` 和 `grpc` 两个 listener，HTTPRoute 的 `parentRefs` 需要指定 `sectionName: https` 或 `grpc`。同一 FQDN 也可以加第二条 HTTPRoute 用 `sectionName: grpc`。

### 7.4 加 mTLS（生产环境）
- Deployment 加 `istio-injection: enabled` 命名空间标签
- DestinationRule `tls.mode` 改为 `ISTIO_MUTUAL`
- 真实应用镜像替换 hello-app

### 7.5 加流量切分
HTTPRoute 的 `backendRefs` 可以加多条带不同 `weight`：
```yaml
backendRefs:
  - name: newapi
    port: 80
    weight: 90
  - name: newapi-v2
    port: 80
    weight: 10
```

### 7.6 加 header 路由
HTTPRoute 的 `matches.headers` 配合：
```yaml
matches:
  - path:
      type: PathPrefix
      value: /
    headers:
    - name: x-api-version
      value: v2
backendRefs:
  - name: newapi-v2
    port: 80
```

---

## 8. 一次性删除（清理）

```bash
kubectl delete -f httproute.yaml,destinationrule.yaml,deployment.yaml,service.yaml

# 或者按反向顺序:
kubectl delete httproute newapi-route -n team1
kubectl delete destinationrule newapi-dr -n team1
kubectl delete deployment newapi -n team1
kubectl delete service newapi -n team1
```

> ⚠️ 不会影响 ListenerSet / Gateway / Namespace — 那些是平台层或共享资源。

---

## 9. 附录：完整文件清单

| 文件 | 资源 | 行数 (估) |
|------|------|-----------|
| `service.yaml` | Service `newapi` | ~22 |
| `deployment.yaml` | Deployment `newapi` (2 副本, hello-app) | ~58 |
| `httproute.yaml` | HTTPRoute `newapi-route` (ListenerSet 绑定) | ~35 |
| `destinationrule.yaml` | DestinationRule `newapi-dr` (连接策略) | ~25 |
| **合计** | | **~140 行 YAML** |

apply 完毕 + minimax 脚本 `--validate` 通过 = 整个流程跑通。
