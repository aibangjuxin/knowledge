文档已成功读取。你的目标非常清晰，我基于此生成一份精炼、结构完整的实施文档：

---

# ASM on GKE — `abjx-int` Namespace 部署实施说明 (V1)

## 目标

| 目标 | 说明 |
|------|------|
| 创建 namespace | `abjx-int` |
| 部署 health check API | `abjx-health-check-api` in `abjx-int` |
| 每个 rt namespace 独立网关 | gateway 与 namespace 一一对应 |
| 网关命名规范 | `abjx-int` → `abjx-int-gw` |
| VirtualService 绑定 | 绑定到 `abjx-int-gw` |

---

## 1. 架构总览

```mermaid
graph TD
    Client[Client / PSC Consumer]
    ILB[Internal LoadBalancer]
    GWSVC[Service: abjx-int-gw]
    GWPOD[Gateway Pod: abjx-int-gw\nEnvoy]
    GWCR[Gateway CR: abjx-int-gw]
    VS[VirtualService: abjx-health-check-api-vs]
    SVC[Service: abjx-health-check-api]
    POD[Pod: abjx-health-check-api\n+ istio-proxy]
    APP[App Container: /health]

    Client --> ILB
    ILB --> GWSVC
    GWSVC --> GWPOD
    GWPOD --> GWCR
    GWCR --> VS
    VS --> SVC
    SVC --> POD
    POD --> APP
```

---

## 2. 关键对象一览

| 资源类型 | 名称 | Namespace | 说明 |
|----------|------|-----------|------|
| `Namespace` | `abjx-int` | - | 租户隔离 |
| `Deployment` | `abjx-health-check-api` | `abjx-int` | 业务 API |
| `Service` | `abjx-health-check-api` | `abjx-int` | 暴露 API 端口 |
| `Deployment` | `abjx-int-gw` | `abjx-int` | Gateway Envoy 工作负载 |
| `Service` | `abjx-int-gw` | `abjx-int` | 暴露 Gateway 端口（ILB 或 ClusterIP） |
| `Gateway` CR | `abjx-int-gw` | `abjx-int` | 定义 host/port/TLS 监听 |
| `VirtualService` | `abjx-health-check-api-vs` | `abjx-int` | 路由规则，绑定到 `abjx-int-gw` |
| `Secret` | `abjx-int-gw-tls` | `abjx-int` | TLS 证书（HTTPS 时启用） |

---

## 3. 部署流程

```mermaid
graph TD
    A[Step 1: 确认 ASM revision]
    B[Step 2: 创建 namespace abjx-int]
    C[Step 3: 部署 API Deployment + Service]
    D[Step 4: 部署 Gateway Deployment + Service]
    E[Step 5: 创建 Gateway CR]
    F[Step 6: 创建 VirtualService]
    G[Step 7: 验证路由]
    H[Step 8: 可选 - TLS + mTLS]

    A --> B --> C --> D --> E --> F --> G --> H
```

---

## 4. 详细实施清单

### Step 1: 确认 ASM revision

```bash
kubectl get mutatingwebhookconfigurations | grep -E "istio|asm|mesh"
kubectl get pods -A | grep -E "istiod|asm"
```

> ⚠️ 以下示例使用 `asm-managed`，请替换为你集群实际的 revision 标签值。

---

### Step 2: 创建 Namespace（`00-namespace-abjx-int.yaml`）

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: abjx-int
  labels:
    istio.io/rev: asm-managed
```

```bash
kubectl apply -f 00-namespace-abjx-int.yaml
```

---

### Step 3: 部署 API（`10-abjx-health-check-api.yaml`）

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
        image: gcr.io/google-samples/hello-app:1.0  # 替换为你的镜像
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: abjx-health-check-api
  namespace: abjx-int
spec:
  selector:
    app: abjx-health-check-api
  ports:
  - name: http      # 必须命名为 http，Istio 协议识别依赖此字段
    port: 80
    targetPort: 8080
```

```bash
kubectl apply -f 10-abjx-health-check-api.yaml
```

---

### Step 4: 部署 Gateway Service（`20-abjx-int-gw-service.yaml`）

```yaml
apiVersion: v1
kind: Service
metadata:
  name: abjx-int-gw
  namespace: abjx-int
  annotations:
    networking.gke.io/load-balancer-type: "Internal"  # 内部 ILB；集群内验证可改 ClusterIP
spec:
  type: LoadBalancer
  selector:
    istio: abjx-int-gw
  ports:
  - name: status-port   # GKE ILB 健康检查依赖此端口
    port: 15021
    targetPort: 15021
  - name: http2
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8443
```

### Step 4b: 部署 Gateway Workload（`21-abjx-int-gw-deployment.yaml`）

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: abjx-int-gw
  namespace: abjx-int
spec:
  replicas: 2
  selector:
    matchLabels:
      istio: abjx-int-gw
  template:
    metadata:
      labels:
        istio: abjx-int-gw
      annotations:
        inject.istio.io/templates: gateway
        sidecar.istio.io/inject: "true"
    spec:
      containers:
      - name: istio-proxy
        image: auto
        ports:
        - containerPort: 15021
        - containerPort: 8080
        - containerPort: 8443
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 1000m
            memory: 512Mi
```

```bash
kubectl apply -f 20-abjx-int-gw-service.yaml
kubectl apply -f 21-abjx-int-gw-deployment.yaml
```

---

### Step 5: 创建 Gateway CR（`30-abjx-int-gateway.yaml`）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: abjx-int-gw          # CR 名称与 gateway workload 对齐
  namespace: abjx-int
spec:
  selector:
    istio: abjx-int-gw       # 必须匹配 Gateway Pod 的 label
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "abjx-int.internal.example.com"  # 替换为真实 FQDN
```

```bash
kubectl apply -f 30-abjx-int-gateway.yaml
```

---

### Step 6: 创建 VirtualService（`40-abjx-health-check-api-vs.yaml`）

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: abjx-health-check-api-vs
  namespace: abjx-int
spec:
  hosts:
  - "abjx-int.internal.example.com"
  gateways:
  - abjx-int-gw              # 绑定到 abjx-int-gw Gateway CR
  http:
  - match:
    - uri:
        prefix: /health
    route:
    - destination:
        host: abjx-health-check-api.abjx-int.svc.cluster.local
        port:
          number: 80
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: abjx-health-check-api.abjx-int.svc.cluster.local
        port:
          number: 80
```

```bash
kubectl apply -f 40-abjx-health-check-api-vs.yaml
```

---

### Step 7（可选）: TLS 配置

#### 7.1 创建 TLS Secret

```bash
kubectl create -n abjx-int secret tls abjx-int-gw-tls \
  --key=tls.key \
  --cert=tls.crt
```

#### 7.2 更新 Gateway CR 支持 HTTPS

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: abjx-int-gw
  namespace: abjx-int
spec:
  selector:
    istio: abjx-int-gw
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: abjx-int-gw-tls   # 对应 Secret 名称
    hosts:
    - "abjx-int.internal.example.com"
```

> ℹ️ **说明**：外部→Gateway 的 TLS 由你自己管理；Gateway→Pod 之间的 mTLS 由 ASM 控制面自动签发轮转，无需手动干预。

---

### Step 8（可选）: namespace 内启用 STRICT mTLS

```yaml
# 50-abjx-int-peerauthentication.yaml
# ⚠️ 仅在确认所有 Pod 都已注入 sidecar 后再启用
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: abjx-int
spec:
  mtls:
    mode: STRICT
```

---

## 5. 验证命令

```bash
# 1. 确认 sidecar 注入
kubectl get pods -n abjx-int
kubectl get pod -n abjx-int <pod-name> -o jsonpath='{.spec.containers[*].name}'
# 期望：app istio-proxy

# 2. 确认 gateway 状态
kubectl get pods -n abjx-int -l istio=abjx-int-gw
kubectl get svc abjx-int-gw -n abjx-int
kubectl get gateway abjx-int-gw -n abjx-int -o yaml
kubectl get virtualservice abjx-health-check-api-vs -n abjx-int -o yaml

# 3. 验证路由（HTTP）
GW_IP=$(kubectl get svc abjx-int-gw -n abjx-int -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -H 'Host: abjx-int.internal.example.com' http://${GW_IP}/health

# 4. 验证路由（HTTPS）
curl -k -H 'Host: abjx-int.internal.example.com' https://${GW_IP}/health

# 5. Istio 配置一致性检查
istioctl analyze -n abjx-int
```

---

## 6. 文件清单与应用顺序

```bash
# 文件组织
00-namespace-abjx-int.yaml
10-abjx-health-check-api.yaml
20-abjx-int-gw-service.yaml
21-abjx-int-gw-deployment.yaml
30-abjx-int-gateway.yaml
40-abjx-health-check-api-vs.yaml
50-abjx-int-peerauthentication.yaml   # 可选，确认全注入后启用

# 应用顺序
kubectl apply -f 00-namespace-abjx-int.yaml
kubectl apply -f 10-abjx-health-check-api.yaml
kubectl apply -f 20-abjx-int-gw-service.yaml
kubectl apply -f 21-abjx-int-gw-deployment.yaml
kubectl apply -f 30-abjx-int-gateway.yaml
kubectl apply -f 40-abjx-health-check-api-vs.yaml
```

---

## 7. Handoff Checklist

- [ ] 已确认集群 ASM revision 标签（如 `asm-managed`）
- [ ] 已创建 `abjx-int` namespace 并打上 `istio.io/rev`
- [ ] 已部署 `abjx-health-check-api` Deployment + Service，port.name 为 `http`
- [ ] 已部署 `abjx-int-gw` Deployment + Service，label 为 `istio: abjx-int-gw`
- [ ] 已创建 `Gateway` CR，selector 与 Deployment label 对齐
- [ ] 已创建 `VirtualService`，`gateways` 字段指向 `abjx-int-gw`
- [ ] 已通过 `curl` 验证 `/health` 路由可达
- [ ] 如需 HTTPS，已创建 `abjx-int-gw-tls` Secret
- [ ] 如需 mTLS，已确认 namespace 内所有 Pod 均已注入 sidecar

---

## 8. 最容易踩的坑

| 问题 | 原因 | 解法 |
|------|------|------|
| Gateway 无流量 | `selector` 与 Pod label 不一致 | 检查 `istio: abjx-int-gw` |
| VirtualService 不生效 | `gateways` 字段写错 | 确认是 `abjx-int-gw` 而非其他 |
| Service port 协议错误 | `port.name` 未写 `http` | 补上 `name: http` |
| mTLS 打断流量 | 部分 Pod 未注入 sidecar | 先 PERMISSIVE，再 STRICT |
| GKE ILB 健康检查失败 | 未暴露 `15021` 端口 | Service 中保留 `status-port: 15021` |


我仔细看了一下原文档里的架构图部分，发现有一个问题需要指出。

原文档里的 flow 图用的是 Mermaid `graph LR`，但我在生成文档时把它渲染成了一个 Visualizer 组件（上面那个"Loading"的地方）。让我重新审查整个 flow 的逻辑正确性。

---

## Flow 正确性审查

### 原文档的 flow

```
Client → ILB → GWSVC → GWPOD → GWCR → VS → SVC → POD → APP
```

### 问题分析

这个 flow **逻辑上有误**，`GWCR` 和 `VS` 的位置描述容易误导人：

| 步骤 | 原文描述 | 实际情况 |
|------|----------|----------|
| `GWPOD → GWCR` | 流量从 Pod 流向 CR | ❌ CR 不是流量路径上的节点，它是**配置对象** |
| `GWCR → VS` | CR 转发给 VS | ❌ VS 也是配置对象，不是流量转发节点 |

### 正确的理解

```
Gateway CR  ──(配置)──► Gateway Pod（Envoy）
VirtualService ──(配置)──► Gateway Pod（Envoy）路由规则
```

**实际数据面流量**只有这条链：

```
Client → ILB → Gateway Service(GWSVC) → Gateway Pod(Envoy) → API Service(SVC) → API Pod
```

**控制面配置**是两条独立的线：

```
Gateway CR    ──► 告诉 Envoy 监听哪个 host/port/TLS
VirtualService ──► 告诉 Envoy 匹配哪个 path，转发到哪个后端
```来分别画出**数据面流量**和**控制面配置**的正确关系图：---

## 结论：原文档 Flow 的问题

原文档里这段描述：

```
GWPOD → GWCR → VS → SVC
```

**逻辑上不准确**，`GWCR` 和 `VS` 不是流量路径上的转发节点，它们是 Istio 配置对象，由 `istiod` 解析后通过 xDS 协议下发给 Envoy。

### 正确理解

| 层面 | 路径 | 说明 |
|------|------|------|
| **数据面（实际流量）** | `Client → ILB → Gateway Service → Gateway Pod (Envoy) → API Service → API Pod` | 真正的报文走向 |
| **控制面（配置）** | `Gateway CR + VirtualService → istiod → xDS → Envoy` | 告诉 Envoy 怎么处理流量 |

### 你的部署步骤顺序是对的

你文档里的 Step 1~8 部署顺序完全正确，我在这里补充一个关键确认点：

```bash
# 确认 Gateway CR 的 selector 与 Deployment label 一致
kubectl get gateway abjx-int-gw -n abjx-int -o jsonpath='{.spec.selector}'
kubectl get pods -n abjx-int -l istio=abjx-int-gw

# 确认 VirtualService 已绑定到正确 gateway
kubectl get virtualservice abjx-health-check-api-vs -n abjx-int \
  -o jsonpath='{.spec.gateways}'

# 用 istioctl 做一次全面检查
istioctl analyze -n abjx-int
```

整体架构和配置逻辑是对的，原文档的 flow 图只是表达方式容易误导，实际意图是正确的。