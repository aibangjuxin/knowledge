# K8s Gateway ListenerSet 租户 API 上线模式

> 基于 GKE + Istio (ASM) + K8s Gateway API + ListenerSet 多租户架构
> 工作量计算与 4-YAML 最小化部署
>
> 配套：[tenant-namespace-k8s-gateway.md](../../../../git/knowledge/cloud/k8s/k8s-gateway/tenant-namespace-k8s-gateway.md)
> 实例：[tenant-namespace-newapi-team1-appdev-aibang.md](../../../../git/knowledge/cloud/k8s/k8s-gateway/tenant-namespace-newapi-team1-appdev-aibang.md)
> 验证工具：`k8s-gateway-fqdn-minimax.sh`（E2E 链路探查 & curl 命令生成器）

---

## 1. 架构背景：什么是你管的、什么不是你管的

```
平台团队（不是你管）                租户团队（你管）
───────────────────                ────────────────
infrastructure/Gateway            team<NS>/Namespace + Labels
infrastructure/ingressgateway     team<NS>/ListenerSet
GCLB (External HTTPS LB)          team<NS>/Service
cert-manager / Secret Provider    team<NS>/Deployment
                                  team<NS>/HTTPRoute
TLS Secret (Wildcard for team)    team<NS>/DestinationRule (可选)
```

**核心约束**：
- 你的 ListenerSet 必须已存在（hostname 模式如 `*.team1.appdev.aibang`）
- 你的 Namespace 必须已存在且带 `gateway.tenant.com/allowed: "true"` 标签
- 你的 HTTPRoute `parentRefs` 引用的是 **ListenerSet**（不是 Gateway）

---

## 2. 反向工程：给定 FQDN，逆推需要的工作

> 这是本模式的核心 insight：脚本 `k8s-gateway-fqdn-minimax.sh` 探查的 5 段链路，反向就是你需要 apply 的资源。

### 2.1 FQDN → Namespace 推断规则

```
FQDN 第 2 段 = tenant 命名空间 (TEAM)

示例：
  newapi.team1.appdev.aibang      → team1
  api.team2.uk.aibang.local       → team2
  app.team1-int.uk.aibang.local   → team1-int
```

### 2.2 链路反向映射

| 脚本探查的链路 (Step N) | 反向：你需要 apply 的资源 |
|------------------------|---------------------------|
| Step 1: 找 HTTPRoute | `HTTPRoute` yaml |
| Step 2: HTTPRoute.parentRefs | 由已存在的 ListenerSet 满足（**不归你管**） |
| Step 3: HTTPRoute.rules.backendRefs | `Service` yaml（backendRef 引用的目标） |
| Step 4: DestinationRule (可选) | `DestinationRule` yaml |
| Step 5: Service.selector | `Deployment.spec.template.metadata.labels` |
| Step 6: Deployment spec | `Deployment` yaml |

### 2.3 4 个 YAML 资源（按 apply 顺序）

| # | 资源 | 名称约定 | 命名空间 | 必需 |
|---|------|----------|----------|------|
| 1 | `Service` | `<API>` | `<TEAM>` | ✅ |
| 2 | `Deployment` | `<API>` | `<TEAM>` | ✅ |
| 3 | `HTTPRoute` | `<API>-route` | `<TEAM>` | ✅ |
| 4 | `DestinationRule` | `<API>-dr` | `<TEAM>` | 🟡 推荐 |

**不需要创建的**：Namespace、ListenerSet、Gateway、TLS Secret、GCLB

---

## 3. 关键反推假设（apply 前必须确认）

| 假设 | 默认值 | 如何验证 | 错配时的影响 |
|------|--------|----------|--------------|
| **tenant NS 必备 label** | `gateway-access: <value>` (具体值看 ListenerSet `allowedRoutes.selector.matchLabels`) | `kubectl get ns <TEAM> -o jsonpath='{.metadata.labels.gateway-access}'` | **#1 静默失败**：HTTPRoute `status.parents[].conditions[Accepted]=False, reason=NotAllowedByListeners` |
| ListenerSet 名 | `<TEAM>-listeners` (e.g. `team1-listeners`) | `kubectl get listenerset -n <LISTENER_NS>` | HTTPRoute 报 `NoMatchingParent` |
| ListenerSet sectionName | `https` | `kubectl get listenerset -n <LISTENER_NS> -o yaml` 看 `spec.listeners[*].name` | HTTPRoute 仅绑定指定 section |
| ListenerSet hostname 模式 | `*.<TEAM>.<app>.<tld>` (e.g. `*.team1.appdev.aibang`) | 同上，看 `spec.listeners[*].hostname` | HTTPRoute 被 listener 拒绝（`NoMatchingListenerHostname`） |
| Gateway 命名空间 | `infrastructure` (旧 2 NS 布局) / `abjx-gw-int` (新 3 NS 布局) | `kubectl get gateway -A` | — |
| Gateway 名称 | `central-gateway` / `abjx-gw-int` | 同上 | HTTPRoute.status.parents 不会出现 |
| GatewayClass | `istio` | `kubectl get gatewayclass` | Gateway 不被 Programmed |
| TLS Secret 存在 | 与 ListenerSet hostname 通配匹配的通配证书 | `kubectl get secret -n <LISTENER_NS>` | 503 / TLS handshake error |

> ⚠️ **这 8 个假设中任何一个错配，HTTPRoute 都能 apply 成功但 status.parents 显示 Accepted=False**。apply 后必须查 status，否则无法发现错误。
>
> **特别注意 tenant NS label**：脚本 `k8s-gateway-fqdn-minimax.sh` 不会验证这个标签，它只检查 NS 存在。ListenerSet 的 `allowedRoutes.namespaces.selector` 是**唯一**的强制关卡。如果缺 label，curl 会得到 `404 Not Found`（不是 `NoMatchingListenerHostname`，因为 listener hostname pattern 本身是 OK 的），是更隐蔽的错。

### 3.1 ⚠️ 缺 tenant NS label 是 #1 静默失败

**症状**：
```bash
kubectl get httproute -n team1 newapi-route -o yaml
# status:
#   parents:
#   - conditions:
#     - lastTransitionTime: ...
#       message: 'No listeners match this route'
#       reason: NotAllowedByListeners
#       status: "False"
#       type: Accepted
```

**根因**：HTTPRoute `parentRef` 指向的 ListenerSet 设置了 `spec.allowedRoutes.namespaces.selector.matchLabels: { gateway-access: ajbx-int }`，但 `team1` NS 缺这个 label。

**修复**：
```bash
kubectl label ns team1 gateway-access=ajbx-int
# 然后 HTTPRoute 大约 5s 内会自动 reconcile，Accepted 转 True
```

**为什么这个错配最隐蔽**：
- apply 不报错（资源都合法）
- curl 报 404（看起来像 hostname 不匹配，但 hostname pattern 其实是 OK 的）
- minimax 脚本不会检测（脚本只验证 NS 存在，不验证 NS 标签）
- 唯一的检测手段是 `kubectl get httproute -o yaml` 看 `status.parents[].conditions`

---

## 4. 4-YAML 最小集（带可搜索占位符）

> 占位符：`<TEAM>`、`<API>`、`<FQDN>`、`<LISTENER_SECTION>`、`<IMAGE>`
> 用 `sed` 或 IDE 全局替换后再 apply

### 4.1 Service 模板

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <API>
  namespace: <TEAM>
  labels:
    app: <API>
spec:
  type: ClusterIP
  selector:
    app: <API>                  # ← 必须与 Deployment pod labels 一致
  ports:
    - name: http
      port: 80                  # ← HTTPRoute backendRef.port 引用此端口
      targetPort: 8080          # ← 与 Deployment containerPort 一致
      protocol: TCP
      appProtocol: http
```

### 4.2 Deployment 模板

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <API>
  namespace: <TEAM>
  labels:
    app: <API>
spec:
  replicas: 2
  selector:
    matchLabels:
      app: <API>
  template:
    metadata:
      labels:
        app: <API>              # ← 与 Service selector 一致
    spec:
      containers:
        - name: <API>
          image: <IMAGE>        # 替换为你的真实镜像
          ports:
            - name: http
              containerPort: 8080
          # 三个 probe 都打 /，hello-app 返回 200
          # 真实应用请用专门的 /healthz endpoint
          readinessProbe:
            httpGet: {path: /, port: http, scheme: HTTP}
            initialDelaySeconds: 2
            periodSeconds: 5
          livenessProbe:
            httpGet: {path: /, port: http, scheme: HTTP}
            initialDelaySeconds: 10
            periodSeconds: 10
          startupProbe:
            httpGet: {path: /, port: http, scheme: HTTP}
            periodSeconds: 5
            failureThreshold: 12
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 500m, memory: 256Mi}
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
```

### 4.3 HTTPRoute 模板

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <API>-route
  namespace: <TEAM>
spec:
  # ⭐ 关键: parentRef 是 ListenerSet (不是 Gateway)
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: ListenerSet
      name: <TEAM>-listeners
      namespace: <TEAM>
      sectionName: <LISTENER_SECTION>   # 通常是 https
  hostnames:
    - <FQDN>                # 必须能被 ListenerSet 的 hostname 通配符覆盖
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: <API>
          port: 80          # ← Service port
          weight: 1
      filters:
        - type: RequestHeaderModifier
          requestHeaderModifier:
            add:
              - {name: X-Tenant, value: <TEAM>}
```

### 4.4 DestinationRule 模板

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: <API>-dr
  namespace: <TEAM>
spec:
  host: <API>.<TEAM>.svc.cluster.local
  trafficPolicy:
    # tls.mode 选择: 取决于后端协议 + 是否有 sidecar
    #   - DISABLE:        后端明文 HTTP, 无 sidecar (新服务默认)
    #   - SIMPLE:         后端 HTTPS, 无 sidecar (自签 cert 加 insecureSkipVerify: true)
    #   - ISTIO_MUTUAL:   mesh 内 mTLS, 后端有 sidecar
    # 决策矩阵见 §4.6
    tls:
      mode: <TLS_MODE>
      # 仅 SIMPLE 时需要: 自签 cert 加 insecureSkipVerify: true
      # insecureSkipVerify: true
    connectionPool:
      tcp: {connectTimeout: 5s, maxConnections: 100}
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

### 4.5 ReferenceGrant 决策矩阵（什么时候需要 ReferenceGrant）

**核心规则**：ReferenceGrant 在**被引用方所在的 namespace** 创建，**显式授权**其他 NS 的资源来引用它。

| 引用方向 | 是否需要 ReferenceGrant | ReferenceGrant 落点 |
|---------|-------------------------|---------------------|
| HTTPRoute (NS-A) → Service (NS-A) | ❌ 同 NS | — |
| **HTTPRoute (NS-A) → Service (NS-B)** | ✅ **需要** | NS-B 创建 ReferenceGrant，allow NS-A |
| HTTPRoute (NS-A) → Gateway (NS-B) | ❌ 由 Gateway 的 `allowedRoutes.namespaces` 控制 |
| HTTPRoute (NS-A) → ListenerSet (NS-B) | ❌ 由 ListenerSet 的 `allowedRoutes.namespaces` 控制 |
| Gateway (NS-A) → Secret (NS-A) | ❌ 同 NS |
| **Gateway (NS-A) → Secret (NS-B)** | ✅ **需要** | NS-B 创建 ReferenceGrant |
| TLSRoute (NS-A) → Service (NS-B) | ✅ **需要** | NS-B 创建 ReferenceGrant |

**本模式 (4-YAML 最小集) 的链路分析**：
```
HTTPRoute (tenant-NS) → ListenerSet (listener-NS)   ❌ 不需要 (由 ListenerSet.allowedRoutes 控制)
HTTPRoute (tenant-NS) → Service (tenant-NS)         ❌ 同 NS
```
**结论：标准 4-YAML 模式不需要 ReferenceGrant**。

**需要 ReferenceGrant 的场景**（future extension）：
```yaml
# 场景: team1 想引用 common-shared NS 的 redis
# 在 common-shared NS 创建:
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-team1-to-ref-services
  namespace: common-shared
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: team1
  to:
    - group: ""           # core group for Service
      kind: Service
```

### 4.6 DestinationRule `tls.mode` 决策矩阵

| 后端协议 | 后端 sidecar | `tls.mode` | 其他字段 | 典型场景 |
|---------|-------------|------------|----------|---------|
| **HTTP (明文)** | 无 | `DISABLE` | — | 新服务默认，hello-app, nginx 平文本 |
| **HTTPS** | 无 | `SIMPLE` | `insecureSkipVerify: true` (自签 cert) | 自签 cert 后端 |
| **HTTPS** | 无 | `SIMPLE` | `caCertificates: ...` (真实 CA) | 生产 CA 签发的 cert |
| **任意** | **有** (istio-proxy) | `ISTIO_MUTUAL` | — | 完整 mesh mTLS |
| TCP / gRPC | — | `DISABLE` | — | 裸 TCP 服务 |

**判断步骤**：
1. **后端容器 listen 443 还是 80？** → 决定 `SIMPLE` vs `DISABLE`
2. **后端 Pod 有 `istio-proxy` 容器吗？** → 决定 `ISTIO_MUTUAL` vs `SIMPLE`/`DISABLE`
3. **HTTPS 后端的 cert 是自签还是 CA 签？** → 决定 `insecureSkipVerify` vs `caCertificates`

**最常见的三种组合**：
- 新服务，明文 HTTP：`mode: DISABLE` (新 newapi 走这个)
- 自签 cert 测 E2E TLS：`mode: SIMPLE` + `insecureSkipVerify: true` (原 `app` 走这个)
- 完整 mesh：`mode: ISTIO_MUTUAL` (生产)

### 4.7 ⚠️ 重要: Service 端口的 `appProtocol` 字段

Service `spec.ports[].appProtocol` 字段告诉 Gateway 后端是什么协议，影响 Envoy 集群配置：

| 后端 | `appProtocol` | 为什么 |
|------|---------------|--------|
| HTTP | `http` | Envoy 用 HTTP/1.1 或 HTTP/2 plaintext 上游集群 |
| HTTPS | `https` | Envoy 用 TLS 上游集群，但**仍然需要 DR `tls.mode: SIMPLE`** 才能握手 |
| gRPC | `grpc` | Envoy 启用 gRPC 框架解析 |

**常见错误**：HTTPS 后端但 `appProtocol: http` → Envoy 用 plaintext 握手 → TLS 错误。**始终跟后端真实协议对齐**。

### 4.8 "与既有 working example 对比"元模式

**触发场景**：tenant NS 里已经有别的 service 在跑，新服务要复用相同架构。

**做法**（部署前）：
1. 找出同 NS 或同 ListenerSet 下**最近的工作样例**（如 `app` 已在 `110139-int` 跑通）
2. 列出 11 个维度的对比（NS / FQDN / 引用对象 / 后端协议 / 镜像 / Service port / DR mode / 挂 cert / Probe scheme / ReferenceGrant / 跨 NS Secret）
3. **显式标注每个维度的差异**，避免 apply 时漏改

**示例对比表**（节选）：

| 维度 | `app` (working) | `newapi` (new) | 差异点 |
|------|----------------|----------------|--------|
| tenant NS | `110139-int` | `team1` | 新 NS |
| FQDN | `app.team1.appdev.aibang` | `newapi.team1.appdev.aibang` | 替换子域名 |
| 引用 ListenerSet | `abjx-listenerset-int/team1-listenerset` | 同 | 共享 |
| **后端协议** | **HTTPS 443** | **HTTP 80** | **关键差异** |
| 镜像 | nginx-unprivileged (HTTPS) | hello-app (HTTP only) | 替换 |
| DR tls.mode | SIMPLE + insecureSkipVerify | DISABLE | 改 mode |
| 挂 TLS cert | ✅ 需要 | ❌ 不需要 | 删 volumeMount |
| Probe scheme | HTTPS | HTTP | 改 scheme |
| ReferenceGrant | ❌ 同 NS | ❌ 同 NS | 一致 |
| 跨 NS Secret | ✅ (110139-int) | ❌ | 删 Secret copy 步骤 |

**收益**：部署前能立刻看到"newapi 比 app 少了哪些步骤，多了哪些步骤"，apply 时不会漏改。

---

## 5. 5 层验证流程（从快到深）

### 5.1 资源就绪（30 秒）

```bash
kubectl get svc,deploy,pods,httproute -n <TEAM> -l app=<API>
# Service:  ClusterIP, 80→8080
# Pods:     2/2 Running, 1/1 Ready
# HTTPRoute status.parents[].conditions[?(@.type=="Accepted")].status == "True"
```

### 5.2 集群内连通（绕过 Gateway）

```bash
kubectl run curl-test --rm -it --restart=Never \
  --image=curlimages/curl:8.10.1 -n <TEAM> -- \
  curl -sS -w "\nHTTP %{http_code}\n" http://<API>.<TEAM>.svc.cluster.local/
```

### 5.3 Gateway 链路探查（用 minimax 脚本）

```bash
cd ~/git/knowledge/cloud/k8s/k8s-gateway/k8s-gateway-e2e
./k8s-gateway-fqdn-minimax.sh <FQDN> <TEAM>
# 加 --validate 直接 curl:
./k8s-gateway-fqdn-minimax.sh <FQDN> <TEAM> --validate
```

**期望链路输出**：
```
• team1/newapi-route
  hostnames: newapi.team1.appdev.aibang
• ListenerSet team1/team1-listeners sectionName=https
  listener=https protocol=HTTPS port=443
• BackendRef: Service team1/newapi:80
  Service type=ClusterIP selector=app=newapi port=80→targetPort=8080
  Deployment team1/newapi ready=2/2
    HTTP Probes: container=newapi readiness/liveness/startup path=/ port=http
```

### 5.4 外部 HTTPS 流量（3 种 curl 方法）

```bash
GATEWAY_IP=$(kubectl get gateway -n infrastructure central-gateway \
  -o jsonpath='{.status.addresses[0].value}')

# 方法 A: 本地 DNS 已就绪
curl -k -v --max-time 10 "https://<FQDN>/"

# 方法 B: SNI 绕过 DNS (最常用)
curl -k -v --max-time 10 \
  --resolve "<FQDN>:443:${GATEWAY_IP}" \
  "https://<FQDN>/"

# 方法 C: IP 直连 + Host 头 (内网跨网段调试)
curl -k -v --max-time 10 \
  -H "Host: <FQDN>" \
  "https://${GATEWAY_IP}/"
```

### 5.5 失败模式速查表

| 现象 | 根因 | 修复 |
|------|------|------|
| **HTTPRoute.status.parents[Accepted]=False, reason=`NotAllowedByListeners`** | **tenant NS 缺 ListenerSet 要求的 label** | `kubectl label ns <TEAM> <key>=<value>` (具体 label 查 ListenerSet yaml) |
| HTTPRoute.status.parents[Accepted]=False, reason=`NoMatchingListenerHostname` | ListenerSet 拒绝（hostname 不匹配 或 sectionName 错） | 查 ListenerSet `spec.listeners[*].hostname` 和 `name` |
| HTTPRoute.status.parents[Accepted]=False, reason=`NoMatchingParent` | parentRef 指向的 ListenerSet/Gateway 不存在 | `kubectl get listenerset,gateway -A` |
| `kubectl get httproute` 没记录 | apply 失败 | `kubectl describe httproute -n <TEAM> <API>-route` |
| `404` from curl | ListenerSet hostname pattern 不覆盖此 FQDN | 改 ListenerSet hostname 为更宽的通配 |
| `502 Bad Gateway` | 后端 Pod 没 Ready | `kubectl get pods -n <TEAM> -l app=<API>` |
| `503 Service Unavailable` | Envoy EDS 还没发现 endpoint | 等 10-30s，istiod 下发 xDS 需时间 |
| `TLS handshake error` | ListenerSet 引用 Secret 不存在 | `kubectl get secret -n <LISTENER_NS> <cert-name>` |
| `upstream connect error` from Envoy | DR `tls.mode: SIMPLE` 但后端是 HTTP | 改 DR `tls.mode: DISABLE`，或改后端启 HTTPS |
| `connection refused` (no TLS) | DR `tls.mode: DISABLE` 但后端是 HTTPS | 改 DR `tls.mode: SIMPLE` + `insecureSkipVerify: true` |
| curl 直接走 GATEWAY_IP 也连不上 | GCLB 后端 Service 选错 | `kubectl get svc -n <GATEWAY_NS> -l gateway.istio.io/managed-by=istio` |

---

## 6. 常见定制点

| 需求 | 修改点 |
|------|--------|
| 改 FQDN | HTTPRoute `spec.hostnames` + metadata labels |
| 改 Namespace | 所有 `namespace: <TEAM>` + ListenerSet 引用名 |
| 加多 listener (HTTPS + gRPC) | HTTPRoute 拆两条，分别 `sectionName: https` / `sectionName: grpc` |
| 加 mTLS | Deployment 加 `istio-injection: enabled` 命名空间标签 + DR `tls.mode: ISTIO_MUTUAL` |
| 加流量切分 (蓝绿/金丝雀) | HTTPRoute `backendRefs` 加多条带不同 `weight` |
| 加 header 路由 | HTTPRoute `matches.headers: [{name: x-api-version, value: v2}]` |
| 加超时 | HTTPRoute `rules[].timeouts` + DR `trafficPolicy.timeout` (见 `k8s-gateway-timeout` 子主题) |
| 跨 Namespace backend | HTTPRoute `backendRefs[].namespace: <other-team>` + 在被引用方 NS 创建 ReferenceGrant (见 §4.5) |
| 换协议 (HTTP ↔ HTTPS) | 镜像 + Service port + DR `tls.mode` 三处联动改 (见 §4.6 决策矩阵 + §4.8 对比模式) |
| 补 NS 必备 label | `kubectl label ns <TEAM> <key>=<value>` (具体 label 查 ListenerSet) |

---

## 7. 反模式（要避免的坑）

| 反模式 | 后果 |
|--------|------|
| HTTPRoute parentRef 直接引用 Gateway（而不是 ListenerSet） | 绕过租户隔离；如果 Gateway 没有这个 hostname，会被拒绝 |
| Service port = containerPort（不分离） | 后续改容器端口要改 HTTPRoute + Service |
| Deployment selector 写宽松（如只 `app: <API>` 但多个 deploy 共用） | 路由会随机打到错误的 Pod |
| 不用 startupProbe，readiness 短周期 | Pod 启动期 502 风暴（因为还没 listen） |
| DestinationRule host 用短名（`newapi`）且在跨 NS 引用 | 短名解析为本 NS，跨 NS 失败；务必用 FQDN |
| TLS Secret 改名前没同步 ListenerSet `certificateRefs` | 503 / TLS 错误且无明显日志 |
| 一次性 apply 完就再也不查 `status.parents` | 上面 7 个错配里 5 个都会静默通过 apply，必须主动查 status |

---

## 8. 与 minimax 脚本的协同

`k8s-gateway-fqdn-minimax.sh` 是 **事后验证** 工具（链路探查 + curl 验证）。

本模式是 **事前规划** 工具（从 FQDN 推出需要的 YAML）。

**协同工作流**：
1. 用本模式生成 4 个 YAML → apply
2. 用 minimax 脚本 `--validate` 验证：
   - 自动逆推 ListenerSet、Service、Deployment
   - 自动生成 SNI `curl` 命令
   - 期望 HTTP 200，否则按 5.5 速查表修复

---

## 9. 一句话总结

> 在 ListenerSet 多租户架构下，给定一个 FQDN `*.team1.appdev.aibang`，
> **租户团队的工作 = 4 个 YAML**（Service + Deployment + HTTPRoute + DestinationRule），
> 反向逻辑就是 minimax 脚本正向探查的 5 段链路。
> apply 后必须查 `status.parents`，否则 7 个常见错配会静默通过。
