# ASM No-mTLS Sidecar 配置部分

> 适用环境：GKE + Google Cloud Service Mesh (ASM) / Anthos Service Mesh
> 核心变更：禁用 Sidecar 间 mTLS，改用本地证书做 Pod 内 HTTPS 加密
> 文档目的：提供具体 CRD 配置清单

---

## 一、Gateway CR（内网 Gateway）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: istio-ingressgateway-int
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway-int
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*.internal.example.com"
    tls:
      mode: SIMPLE                # 单向TLS，Gateway侧终止
      credentialName: istio-ingressgateway-int-certs
---
# TLS Secret（需要提前创建）
apiVersion: v1
kind: Secret
metadata:
  name: istio-ingressgateway-int-certs
  namespace: istio-system
type: kubernetes.io/tls
data:
  tls.crt: <BASE64_ENCODED_CERT>
  tls.key: <BASE64_ENCODED_KEY>
```

---

## 二、DestinationRule（禁用 mTLS，改用本地 HTTPS）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: abjx-health-check-api
  namespace: abjx-int
spec:
  host: abjx-health-check-api.abjx-int.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE                # 不用 ISTIO_MUTUAL，改用 SIMPLE
      # 不需要 clientCertificate / privateKey，App Sidecar 不做双向认证
    port:
      number: 8443               # App Sidecar 监听端口
```

---

## 三、PeerAuthentication（关闭 mTLS）

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: abjx-int
spec:
  mtls:
    mode: DISABLE                 # 关闭 mTLS，Pod 间不走 mTLS
```

---

## 四、VirtualService（路由配置）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: abjx-health-check-api-vs
  namespace: abjx-int
spec:
  hosts:
  - "abjx-health-check-api.internal.example.com"
  gateways:
  - istio-system/istio-ingressgateway-int   # 绑定到内网 Gateway
  http:
  - match:
    - uri:
        prefix: /health
    route:
    - destination:
        host: abjx-health-check-api.abjx-int.svc.cluster.local
        port:
          number: 8443            # 指向 App Sidecar 的 HTTPS 端口
```

---

## 五、AuthorizationPolicy（降级版：基于 namespace 而非 principals）

```yaml
# 允许来自 Gateway Namespace 的流量
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-from-gateway
  namespace: abjx-int
spec:
  action: ALLOW
  rules:
  - from:
    - source:
        namespaces:
        - istio-system        # 只允许来自 istio-system 的流量
---
# 或者更宽松的版本：允许同 namespace 内所有流量
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-internal
  namespace: abjx-int
spec:
  action: ALLOW
  rules:
  - from:
    - source:
        namespaces:
        - abjx-int             # 允许同 namespace 内调用
    - source:
        namespaces:
        - istio-system         # 允许 Gateway namespace
```

---

## 六、AuthorizationPolicy（严格模式：默认拒绝 + 白名单）

```yaml
# 默认拒绝所有
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-health-check-deny-all
  namespace: abjx-int
spec:
  selector:
    matchLabels:
      app: abjx-health-check-api
  action: DENY
  rules:
  - {}                         # 空规则 = 默认拒绝所有
---
# 只允许 Gateway namespace
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: api-health-check-allow-gateway
  namespace: abjx-int
spec:
  selector:
    matchLabels:
      app: abjx-health-check-api
  action: ALLOW
  rules:
  - from:
    - source:
        namespaces:
        - istio-system
```

---

## 七、NetworkPolicy（namespace 间网络隔离）

```yaml
# 允许 App Pod 接收来自 Gateway Namespace 的流量
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-gateway-namespace
  namespace: abjx-int
spec:
  podSelector:
    matchLabels:
      app: abjx-health-check-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: istio-system
    ports:
    - protocol: TCP
      port: 8443                # App Sidecar HTTPS 端口
---
# 允许同 namespace 内 Pod 间通信（可选）
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: abjx-int
spec:
  podSelector: {}                # 匹配所有 Pod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}            # 同 namespace 内任意 Pod
    ports:
    - protocol: TCP
      port: 8443
---
# 禁止出口到外部（可选）
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-egress
  namespace: abjx-int
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress: []                    # 空 = 禁止所有出口
```

---

## 八、App Deployment（Sidecar + 本地证书挂载）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: abjx-health-check-api
  namespace: abjx-int
spec:
  replicas: 2
  selector:
    matchLabels:
      app: abjx-health-check-api
  template:
    metadata:
      labels:
        app: abjx-health-check-api
    spec:
      containers:
      - name: app
        image: your-app-image:latest
        ports:
        - containerPort: 8080   # App 监听端口
        volumeMounts:
        - name: certs
          mountPath: /etc/certs
          readOnly: true
        env:
        - name: SERVER_PORT
          value: "8080"
      volumes:
      - name: certs
        secret:
          secretName: app-local-certs   # 你的本地证书 Secret
      # Sidecar 会通过 ASM 自动注入
```

---

## 九、Gateway Deployment（内网 Gateway）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istio-ingressgateway-int
  namespace: istio-system
spec:
  replicas: 2
  selector:
    matchLabels:
      istio: ingressgateway-int
  template:
    metadata:
      labels:
        istio: ingressgateway-int
      annotations:
        inject.istio.io/templates: gateway
    spec:
      containers:
      - name: istio-proxy
        image: auto
        ports:
        - containerPort: 443
        - containerPort: 8443
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 1000m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: istio-ingressgateway-int
  namespace: istio-system
spec:
  type: ClusterIP               # 内部访问，不需要 LoadBalancer
  selector:
    istio: ingressgateway-int
  ports:
  - name: https
    port: 443
    targetPort: 8443
  - name: status-port
    port: 15021
    targetPort: 15021
```

---

## 十、Namespace 标记

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: abjx-int
  labels:
    istio.io/rev: asm-managed   # 启用 ASM sidecar 注入
```

---

## 配置变更速查

| 资源 | 原来值 | 新值 |
|------|--------|------|
| Gateway tls.mode | ISTIO_MUTUAL | SIMPLE |
| DestinationRule tls.mode | ISTIO_MUTUAL | SIMPLE |
| PeerAuthentication mtls.mode | STRICT | DISABLE |
| AuthorizationPolicy source | principals | namespaces |

---

## 迁移回 mTLS 只需改动

| 资源 | 改回 mTLS |
|------|-----------|
| PeerAuthentication | `mtls.mode: STRICT` 或删除 |
| DestinationRule | `tls.mode: ISTIO_MUTUAL` |
| AuthorizationPolicy | `namespaces` 改回 `principals` |