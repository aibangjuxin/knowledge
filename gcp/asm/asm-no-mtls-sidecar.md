# ASM 仅作为内部网关、后端使用自管 HTTPS 的配置方案

> 适用环境：GKE + Google Cloud Service Mesh / ASM，Istio sidecar 数据面  
> 目标：保留集群内 Istio Gateway 的路由能力，但不使用 Gateway 到 Runtime Pod 之间的 mesh mTLS；后端应用继续监听 HTTPS `8443`，证书由业务或平台本地 Secret 管理。  
> 结论：可行，但这是安全能力降级方案。它不是 Service Mesh mTLS 的等价替代。

---

## 1. 目标和约束

你当前稳定状态是：

| 段 | 路径 | 加密方式 | 负责人 |
|---|---|---|---|
| 1 | Client -> Istio Gateway | 域名证书，`SIMPLE` | 平台手动创建 TLS Secret |
| 2 | Gateway sidecar -> App sidecar | SPIFFE mTLS | istiod 自动签发和轮转 |
| 3 | App sidecar -> App container | Pod 内明文 HTTP | sidecar localhost 转发 |

现在想迁移到：

| 段 | 路径 | 加密方式 | 负责人 |
|---|---|---|---|
| 1 | Client -> Istio Gateway | 域名证书，`SIMPLE` | 平台手动创建 TLS Secret |
| 2 | Istio Gateway -> Runtime Service | 普通 HTTPS，`DestinationRule tls.mode: SIMPLE` | Gateway Envoy 发起 TLS |
| 3 | Runtime Pod 内 | App container 自己终止 HTTPS `8443` | 业务或平台 Secret |

关键约束：

- Gateway namespace 仍然启用 Cloud Service Mesh，并部署独立内部 Gateway，例如 `istio-ingressgateway-int`。
- Runtime namespace 可以不注入 sidecar，这是最清晰的迁移模式。
- 如果 Runtime namespace 继续注入 sidecar，也必须明确它只做透明 TCP 转发，不能再依赖 mesh mTLS 身份和 L7 HTTP 授权能力。
- App 监听的是 HTTPS `8443`，证书不是 istiod 颁发的 SPIFFE 证书，而是本地 Secret。

---

## 2. 架构判断

### 推荐 V1：Gateway 在 Mesh 内，Runtime 不注入 Sidecar

```text
Client
  -> HTTPS 443
Istio Gateway Pod in istio-ingressgateway-int
  -> Gateway Envoy TLS origination, DestinationRule SIMPLE
Runtime Service team-a-service.team-a-runtime.svc.cluster.local:8443
  -> App container terminates local HTTPS cert
```

这是最符合你迁移目标的版本：

- Istio Gateway 仍负责入口 TLS 终止、Host/path 路由、重试、超时、基础流量治理。
- Runtime Pod 不进入 mesh，不需要 `PeerAuthentication` 和 sidecar 注入。
- Gateway 到 App 的加密由普通 HTTPS 完成。
- Runtime 的安全边界主要依赖 Kubernetes `NetworkPolicy`、App 本地 TLS 证书校验、Gateway 路由和应用层认证。

### 可行但不推荐：Runtime 继续注入 Sidecar

Runtime 继续注入 sidecar 时，流量会变成：

```text
Gateway Envoy -> HTTPS -> Runtime inbound sidecar -> opaque TCP -> App HTTPS 8443
```

这个模式可以跑，但能力边界要写清楚：

- `PeerAuthentication DISABLE` 只是关闭接收侧 mesh mTLS，不等于建立了新的身份认证。
- `AuthorizationPolicy` 不能再使用 `principals` 做强身份，因为没有 SPIFFE mTLS。
- App HTTPS 被业务容器终止，sidecar 看不到 HTTP path/header/JWT，不能做 L7 AuthorizationPolicy。
- 如果仍保留 sidecar，主要价值只剩透明代理、基础 TCP 策略和部分遥测，复杂度大于收益。

### 不建议：Runtime 注入 Sidecar + `PERMISSIVE`

`PERMISSIVE` 是过渡态，不是目标态。它允许 mTLS 和明文同时进入，容易让不带 sidecar 的 Pod 绕过 mesh 身份边界。除非短期灰度迁移，否则不要作为平台默认值。

---

## 3. 原文档需要修正的点

| 原配置点 | 问题 | 修正 |
|---|---|---|
| Runtime namespace 仍启用 sidecar，同时 `PeerAuthentication DISABLE` | 等于保留了 sidecar 成本，但放弃最关键的 mesh mTLS 身份能力 | V1 建议 Runtime 不注入 sidecar；如果必须注入，只作为透明 TCP 过渡 |
| `AuthorizationPolicy source.namespaces` 用来替代 `principals` | 没有 mTLS 时，source principal/namespace 不能作为可靠身份边界 | 用 `NetworkPolicy` 做 namespace/pod 级网络边界；AuthPolicy 只保留有限 TCP 条件或不部署 |
| App 是 HTTPS 时仍期望 L7 AuthorizationPolicy | sidecar 看不到被 App TLS 加密后的 HTTP | 不再使用 path/header/method/JWT 等 L7 AuthPolicy |
| `DestinationRule tls.mode: SIMPLE` 说成 App sidecar 监听端口 | `SIMPLE` 是客户端 Envoy 到后端服务发起普通 TLS，不是 App sidecar 监听 | 明确为 Gateway Envoy TLS origination 到 Service `8443` |
| `deny-egress` 空规则 | 会阻断 DNS、证书拉取、外部依赖、监控上报，容易误伤 | 只作为高安全场景模板，必须配套 allow DNS / control plane / 必要外联 |

---

## 4. 资源分工

| 资源 | V1 是否需要 | 作用 |
|---|---:|---|
| `Namespace` | 需要 | Gateway namespace 启用 mesh；Runtime namespace 默认不注入 sidecar |
| `Deployment` / `Service` | 需要 | Gateway Deployment 和业务 HTTPS Runtime |
| `Gateway` | 需要 | 终止外部或内部入口 HTTPS |
| `VirtualService` | 需要 | Host/path 路由到 Runtime Service `8443` |
| `DestinationRule` | 需要 | 让 Gateway Envoy 对 Runtime Service 发起普通 TLS |
| `PeerAuthentication` | Runtime 不注入时不需要 | 无 sidecar 时不会生效 |
| `AuthorizationPolicy` | Runtime 不注入时不需要 | 无 sidecar 时不会生效；不要假设它能保护无 sidecar Pod |
| `NetworkPolicy` | 强烈需要 | Runtime namespace 的 L3/L4 强边界 |
| App TLS Secret | 需要 | Runtime App 自己终止 HTTPS |

---

## 5. 最小可落地配置

完整示例文件已放在：

```text
gcp/asm/no-mtls-sidecar-yamls/
```

架构流程图：

```text
gcp/asm/no-mtls-sidecar-yamls/05-architecture-flow.html
```

相关深入探索文档：

```text
gcp/asm/DestinationRule.md   # DestinationRule 深度解析，TLS 模式、使用场景、与 PeerAuthentication 的区别
```

建议按这个顺序部署：

```bash
kubectl apply -f gcp/asm/no-mtls-sidecar-yamls/00-namespaces.yaml
kubectl apply -f gcp/asm/no-mtls-sidecar-yamls/01-gateway.yaml
kubectl apply -f gcp/asm/no-mtls-sidecar-yamls/02-runtime-app.yaml
kubectl apply -f gcp/asm/no-mtls-sidecar-yamls/03-istio-routing.yaml
kubectl apply -f gcp/asm/no-mtls-sidecar-yamls/04-networkpolicy.yaml
```

也可以使用：

```bash
kubectl apply -k gcp/asm/no-mtls-sidecar-yamls
```

---

## 6. 核心 YAML 说明

### 6.1 Namespace

Gateway namespace 启用 mesh 注入，Runtime namespace 显式禁用注入：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: istio-ingressgateway-int
  labels:
    istio.io/rev: asm-managed
---
apiVersion: v1
kind: Namespace
metadata:
  name: team-a-runtime
  labels:
    istio-injection: disabled
```

如果你的 ASM revision 不是 `asm-managed`，需要改成实际 revision：

```bash
kubectl get mutatingwebhookconfiguration -o name | grep istio
kubectl get ns --show-labels | grep istio.io/rev
```

### 6.2 Gateway

Gateway 使用域名证书做入口 TLS 终止：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: team-a-gateway
  namespace: istio-ingressgateway-int
spec:
  selector:
    app: istio-ingressgateway-int
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: team-a-gateway-tls
    hosts:
    - "*.team-a.appdev.aibang"
```

### 6.3 Runtime App

业务容器直接监听 HTTPS `8443`，挂载本地 TLS Secret：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: team-a-service
  namespace: team-a-runtime
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: team-a-service
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      containers:
      - name: app
        image: your-app-image:latest
        ports:
        - containerPort: 8443
          name: https-app
        volumeMounts:
        - name: app-tls
          mountPath: /etc/tls
          readOnly: true
      volumes:
      - name: app-tls
        secret:
          secretName: team-a-app-local-tls
```

Service 端口名称建议使用 `https-` 或 `tls-` 前缀，避免被 Istio 当成明文 HTTP 解析：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: team-a-service
  namespace: team-a-runtime
spec:
  selector:
    app: team-a-service
  ports:
  - name: https-app
    port: 8443
    targetPort: 8443
```

### 6.4 VirtualService + DestinationRule

`VirtualService` 负责 HTTP 路由；`DestinationRule` 负责让 Gateway Envoy 到后端服务使用普通 TLS：

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: team-a-vs
  namespace: team-a-runtime
spec:
  hosts:
  - "*.team-a.appdev.aibang"
  gateways:
  - istio-ingressgateway-int/team-a-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: team-a-service.team-a-runtime.svc.cluster.local
        port:
          number: 8443
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team-a-service-tls
  namespace: team-a-runtime
spec:
  host: team-a-service.team-a-runtime.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: team-a-service.team-a-runtime.svc.cluster.local
```

证书校验说明：

- 如果 App 使用公有 CA 或被 Gateway Envoy 信任的企业 CA，可以保留服务端证书校验。
- 如果 App 使用自签名或私有 CA，需要把 CA 证书提供给 Gateway Envoy，并在 `DestinationRule` 使用 `caCertificates`。这通常要求文件存在于 Gateway proxy 容器内，平台化成本较高。
- 如果临时无法分发 CA，只能使用不校验证书的后端 HTTPS，这会降级为“加密但不认证后端身份”，生产上不建议长期使用。

### 6.5 NetworkPolicy

Runtime namespace 必须默认拒绝入站，只允许 Gateway namespace 的 Gateway Pod 访问业务端口：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: team-a-runtime
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-istio-ingressgateway-int
  namespace: team-a-runtime
spec:
  podSelector:
    matchLabels:
      app: team-a-service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: istio-ingressgateway-int
      podSelector:
        matchLabels:
          app: istio-ingressgateway-int
    ports:
    - protocol: TCP
      port: 8443
```

如果业务 Pod 还需要出站访问 DNS、数据库、SaaS 或监控系统，不要直接套用空 `egress: []`。先列清依赖，再逐项 allow。

---

## 7. AuthorizationPolicy 和 PeerAuthentication 怎么处理

### Runtime 不注入 sidecar

不要创建 Runtime 侧 `PeerAuthentication` 和 `AuthorizationPolicy`：

- Pod 没有 sidecar，`PeerAuthentication` 不会拦截任何连接。
- Pod 没有 sidecar，`AuthorizationPolicy` 不会执行。
- 安全边界改由 `NetworkPolicy`、App TLS、应用认证和 Gateway 入口规则承担。

### Runtime 继续注入 sidecar的过渡写法

只在短期迁移时使用：

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: disable-mesh-mtls-for-https-app
  namespace: team-a-runtime
spec:
  selector:
    matchLabels:
      app: team-a-service
  mtls:
    mode: DISABLE
```

可选的 `AuthorizationPolicy` 只能做非常有限的 TCP 级限制，不要写 `principals` 或 `namespaces` 当作强身份控制：

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-tcp-8443-only
  namespace: team-a-runtime
spec:
  selector:
    matchLabels:
      app: team-a-service
  action: ALLOW
  rules:
  - to:
    - operation:
        ports: ["8443"]
```

这条规则只能表达“允许访问 8443”，不能表达“只有某个 Gateway 身份可以访问”。真正的来源限制仍要靠 `NetworkPolicy`。

---

## 8. 迁移步骤

1. 创建独立 Gateway namespace，例如 `istio-ingressgateway-int`，启用 ASM revision 注入。
2. 部署内部 Istio Gateway Deployment / Service，确认 Gateway Pod 已注入或使用 gateway injection template。
3. 在 Gateway namespace 创建入口 TLS Secret，例如 `team-a-gateway-tls`。
4. Runtime namespace 显式禁用 sidecar 注入，或在 Deployment 上标记 `sidecar.istio.io/inject: "false"`。
5. Runtime App 监听 HTTPS `8443`，挂载 `team-a-app-local-tls`。
6. 创建 `Gateway`、`VirtualService`、`DestinationRule tls.mode: SIMPLE`。
7. 创建 Runtime 入站 `NetworkPolicy`，只允许 Gateway namespace 的 Gateway Pod 到 `8443`。
8. 灰度验证单个 host/path，再逐步迁移更多 API。

---

## 9. 验证

### 9.1 基础资源

```bash
kubectl get pod,svc -n istio-ingressgateway-int
kubectl get gateway,virtualservice,destinationrule -A | grep team-a
kubectl get pod,svc,networkpolicy -n team-a-runtime
```

### 9.2 确认 Runtime 未注入 sidecar

```bash
kubectl get pod -n team-a-runtime -l app=team-a-service -o jsonpath='{range .items[*]}{.metadata.name}{" containers="}{.spec.containers[*].name}{"\n"}{end}'
```

输出中不应出现 `istio-proxy`。

### 9.3 从 Gateway 验证后端 HTTPS

```bash
GW_POD="$(kubectl get pod -n istio-ingressgateway-int -l app=istio-ingressgateway-int -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n istio-ingressgateway-int "$GW_POD" -c istio-proxy -- \
  curl -vk https://team-a-service.team-a-runtime.svc.cluster.local:8443/health
```

### 9.4 验证 NetworkPolicy 阻断非 Gateway 来源

```bash
kubectl run np-test -n team-a-runtime --rm -it --restart=Never --image=curlimages/curl -- \
  curl -vk --connect-timeout 5 https://team-a-service.team-a-runtime.svc.cluster.local:8443/health
```

预期：非白名单来源被拒绝或超时。

### 9.5 入口验证

```bash
curl -vk --resolve api.team-a.appdev.aibang:443:<GATEWAY_IP> \
  https://api.team-a.appdev.aibang/health
```

---

## 10. 回滚到 Mesh mTLS

回滚目标是恢复：

```text
Gateway sidecar -> App sidecar = ISTIO_MUTUAL
App container = HTTP
```

需要同步改动：

| 资源 | 回滚动作 |
|---|---|
| Runtime Namespace | 启用 `istio.io/rev=<revision>` 或 `istio-injection=enabled` |
| App Deployment | 移除 `sidecar.istio.io/inject: "false"` |
| App 端口协议 | 改回 HTTP，Service port name 使用 `http-*` |
| DestinationRule | 删除 `tls.mode: SIMPLE`，或改为 `ISTIO_MUTUAL` |
| PeerAuthentication | Runtime namespace 设为 `STRICT` |
| AuthorizationPolicy | 恢复基于 Gateway service account principal 的 allow 规则 |
| NetworkPolicy | 保持 Gateway namespace 到业务端口的 L4 放行 |

---

## 11. 最终建议

如果这个方案是为了迁移兼容，建议采用：

```text
Gateway namespace: 启用 ASM
Runtime namespace: 不启用 sidecar
Gateway -> Runtime: HTTPS 8443，DestinationRule SIMPLE
Runtime 入站边界: NetworkPolicy allow gateway namespace/pod only
Runtime 身份认证: 应用层认证或证书校验，不依赖 Istio AuthorizationPolicy
```

这个方式可以落地，也便于迁移。但它牺牲了 Cloud Service Mesh 最有价值的三件事：

- SPIFFE 工作负载身份
- 自动 mTLS 证书轮转
- 基于 workload identity 的 AuthorizationPolicy

所以它适合作为迁移过渡或兼容遗留 HTTPS workload 的方案，不建议作为长期平台默认模型。长期目标仍应回到 `Gateway -> Runtime sidecar` 的 `STRICT mTLS`，业务容器保持 HTTP，由 mesh 承担传输加密和工作负载身份。
