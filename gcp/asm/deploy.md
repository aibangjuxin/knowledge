# ASM on GKE 部署与流量路径细化

> 目标：基于当前仓库里的 ASM / PSC / Gateway 文档，整理出一个适合你当前场景的 V1 实施说明。
>
> 本文聚焦：
> 1. 理解 Anthos Service Mesh on GKE 的核心 flow
> 2. 在 `abjx-int` namespace 部署一个 simple API
> 3. 在该 namespace 内放置独立网关 `abjx-int-gw`
> 4. 让 `VirtualService` 绑定到 `abjx-int-gw`
> 5. 说明 Deployment / Service / Gateway / VirtualService / 证书 / 健康检查之间的关系

---

## 1. Goal and Constraints

### 1.1 你的目标

- create namespace: `abjx-int`
- deploy `abjx health check API` in this namespace
- each rt namespace has one gateway
- for `abjx-int` namespace, gateway name should be `abjx-int-gw`
- the `VirtualService` should apply on `abjx-int-gw`

### 1.2 我从这个目录读出来的结论

基于当前目录下的 `asm.md`、`cloud-service-mesh*.md`、`master-project-setup-mesh.md`、`qwen-cross-project-mesh.md`、`kilo-minimax-cross-project-mesh.md`、`expose-mesh.md`、`istio-egress/*`，可以归纳出下面这些对你最重要的点：

1. ASM 在你这个仓库里的定位，不是替代外部 API Gateway，而是做 mesh 内部治理。
2. 对 tenant/master 或跨项目入口，更推荐 `PSC -> ILB -> Mesh Gateway -> Mesh 内服务`。
3. V1 不要一上来全局 `STRICT mTLS`，否则非 mesh 客户端流量很容易被打断。
4. 更稳妥的做法是：
   - 入口边界在 Gateway 上做 host/path/TLS/JWT/AuthZ
   - mesh 内部服务之间再逐步开启 `STRICT mTLS`
5. Gateway、Gateway Deployment、Gateway Service、Gateway CR、VirtualService 是不同层的对象，必须分清。

---

## 2. Recommended Architecture (V1)

复杂度：`Moderate`

### 2.1 推荐 V1 模型

对 `abjx-int`，建议采用 namespace 内独立 gateway 的模型：

```mermaid
graph LR
    Client["Client / PSC Consumer / Internal Caller"]
    ILB["Internal LB or Cluster Internal Access"]
    GWSVC["Service: abjx-int-gw"]
    GWPOD["Gateway Pod: abjx-int-gw"]
    GWCR["Gateway CR"]
    VS["VirtualService"]
    SVC["Service: abjx-health-check-api"]
    POD["Pod: abjx-health-check-api + istio-proxy"]
    APP["App Container"]

    Client --> ILB
    ILB --> GWSVC
    GWSVC --> GWPOD
    GWPOD --> GWCR
    GWCR --> VS
    VS --> SVC
    SVC --> POD
    POD --> APP
```

### 2.2 这条 flow 到底怎么理解

请求链路分 4 层：

1. 网络入口层
   - 客户端先到 `abjx-int-gw` 对应的 Service
   - 如果要给 PSC 用，这个 Service 一般是 `LoadBalancer + Internal`
   - 如果只是集群内验证，也可以先用 `ClusterIP`

2. 网关工作负载层
   - `abjx-int-gw` Deployment/Pod 是实际跑 Envoy 的地方
   - 它接流量，监听 80/443/15021 等端口

3. Istio 配置层
   - `Gateway` CR 声明监听哪些 host/port
   - `VirtualService` 声明匹配哪些 path/host，然后转发到哪个 Kubernetes Service

4. 后端服务层
   - `abjx-health-check-api` 是普通 K8s Deployment
   - namespace 开启 ASM sidecar 注入后，Pod 会有 `istio-proxy`
   - 从 gateway 到 sidecar，再到 app，就是 mesh 数据面流量

### 2.3 关键对象关系

| 资源 | 作用 | 你这里的建议 |
|---|---|---|
| `Namespace` | 隔离租户/运行时资源 | `abjx-int` |
| `istio.io/rev` label | 开启 sidecar 注入 | 只打到目标 namespace |
| `Deployment` | 跑 API Pod | `abjx-health-check-api` |
| `Service` | 给 API 提供稳定访问入口 | `abjx-health-check-api` |
| `Gateway Deployment` | 跑 gateway envoy | `abjx-int-gw` |
| `Gateway Service` | 暴露 gateway 端口 | `abjx-int-gw` |
| `Gateway` CR | 定义 host/port/tls 监听规则 | `abjx-int-gw` |
| `VirtualService` | 绑定 gateway 并转发到后端 Service | `abjx-health-check-api-vs` |
| `Secret` | 存 TLS 证书 | `abjx-int-gw-tls` |
| `PeerAuthentication` | 控制 namespace 内 mTLS 模式 | V1 先谨慎使用 |

---

## 3. Trade-offs and Alternatives

### 3.1 为什么推荐“每个 rt namespace 一个 gateway”

优点：

- 边界清晰，`abjx-int` 的入口、证书、路由、授权都在自己 namespace
- blast radius 更小
- 后续每个 runtime namespace 可以独立演进

缺点：

- gateway 数量会增加
- 每个 namespace 都要管理 gateway 副本、资源、证书
- 比共享一个平台级 gateway 更耗资源

### 3.2 V1 不建议做的事

- 不建议直接把 mesh-wide `PeerAuthentication` 设成 `STRICT`
- 不建议一开始就叠加 JWT、AuthorizationPolicy、DestinationRule、Canary 全套
- 不建议把证书、入口、业务路由全混在一个“大而全”的 namespace 外部网关里

### 3.3 V1 建议

先完成这个顺序：

1. `abjx-int` namespace 创建
2. API Deployment + Service
3. `abjx-int-gw` Deployment + Service
4. `Gateway` + `VirtualService`
5. 先跑 HTTP
6. 再补 HTTPS / TLS Secret
7. 最后再决定 namespace 内是否启用 `STRICT mTLS`

---

## 4. Implementation Steps

## 4.1 Step 1: 确认 ASM revision

先确认你集群里实际可用的 revision，不要直接假设就是 `asm-managed`：

```bash
kubectl get mutatingwebhookconfigurations | grep -E "istio|asm|mesh"
kubectl get pods -A | grep -E "istiod|asm"
```

如果你的环境 revision 的确是 `asm-managed`，再继续下面的 label。

---

## 4.2 Step 2: 创建 namespace `abjx-int`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: abjx-int
  labels:
    istio.io/rev: asm-managed
```

说明：

- 这里假设你的 ASM revision 是 `asm-managed`
- 这个 label 的意义是让 `abjx-int` 里的业务 Pod 自动注入 sidecar
- 如果 gateway 也希望放在同一个 namespace，并且采用 injected gateway 模式，也可以复用这个 namespace

应用：

```bash
kubectl apply -f 00-namespace-abjx-int.yaml
```

---

## 4.3 Step 3: 部署 `abjx-health-check-api`

这里给一个最小可跑的 health check API 示例。镜像先用通用 hello-app 占位，你后面替换成自己的 `abjx health check API` 镜像即可。

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
        image: gcr.io/google-samples/hello-app:1.0
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
  - name: http
    port: 80
    targetPort: 8080
```

说明：

- Service 名称我直接用 `abjx-health-check-api`
- `port.name` 必须明确成 `http`，方便 Istio 正确识别协议
- 副本先用 2，避免单 Pod 风险

---

## 4.4 Step 4: 部署 namespace 专属 gateway `abjx-int-gw`

这里采用“每个 rt namespace 一个 gateway”的模型。

### 4.4.1 Gateway Service

如果这个 gateway 未来需要给 PSC / 内部 ILB 用，可以直接定义成内部 LoadBalancer。  
如果你现在只是先在集群里验证，先改成 `ClusterIP` 也可以。

```yaml
apiVersion: v1
kind: Service
metadata:
  name: abjx-int-gw
  namespace: abjx-int
  annotations:
    networking.gke.io/load-balancer-type: "Internal"
spec:
  type: LoadBalancer
  selector:
    istio: abjx-int-gw
  ports:
  - name: status-port
    port: 15021
    targetPort: 15021
  - name: http2
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8443
```

### 4.4.2 Gateway Deployment

下面这个清单表达的是“给 `abjx-int` 建一个独立 gateway workload”。  
不同 ASM 版本的网关安装方式会有差异，所以这份 YAML 更适合作为你仓库里的实施模板，而不是无条件原样套用到所有集群。

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

生产补充建议：

- 给 `abjx-int-gw` 加 `PDB`
- 给 `abjx-int-gw` 加 `HPA`
- 尽量分散到不同 node / zone
- 如果你们已经有专门的 gateway node pool，给它加 `nodeSelector` 和 `tolerations`

---

## 4.5 Step 5: `Gateway` CR 定义监听规则

这是 Istio `Gateway` 资源，不是 K8s Service。

先给 HTTP 版本：

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
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "abjx-int.internal.example.com"
```

说明：

- `metadata.name` 就叫 `abjx-int-gw`
- `selector` 必须匹配 gateway workload 的 label：`istio: abjx-int-gw`
- host 改成你真实要暴露的 FQDN

---

## 4.6 Step 6: `VirtualService` 绑定 `abjx-int-gw`

这是你要求里最关键的一条：`VirtualService` 要 apply 在 `abjx-int-gw` 上。

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
  - abjx-int-gw
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

关键点：

- `gateways: [abjx-int-gw]` 就表示这个路由只绑定这个 gateway
- `host` 最好写全限定服务名，排障更直接
- 如果后续你需要按 path 拆到多个 API，可以继续在这里扩

---

## 4.7 Step 7: 证书与 TLS

这部分必须拆成两层理解。

### 4.7.1 外部到 Gateway 的 TLS

这是 north-south TLS。

如果你要让客户端通过 HTTPS 访问 `abjx-int-gw`，需要：

1. 准备服务证书和私钥
2. 在 `abjx-int` namespace 创建 TLS Secret
3. 在 `Gateway` 的 `servers.tls` 中引用这个 secret

创建 Secret：

```bash
kubectl create -n abjx-int secret tls abjx-int-gw-tls \
  --key=tls.key \
  --cert=tls.crt
```

HTTPS Gateway 示例：

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
      credentialName: abjx-int-gw-tls
    hosts:
    - "abjx-int.internal.example.com"
```

这里的含义是：

- TLS 在 gateway 终止
- gateway 后面再按 HTTP 路由到 `VirtualService`

### 4.7.2 Gateway 到后端 Pod 的 mTLS

这是 mesh 内部 east-west mTLS。

这一层通常不需要你手动给每个 workload 发证书。  
ASM/Istio 的工作负载身份证书是控制面自动签发和轮转的。

所以：

- 你需要自己管理的是 gateway 对外暴露的服务证书
- 你通常不需要自己手动生成 sidecar 间 mTLS 证书

### 4.7.3 V1 的 mTLS 建议

V1 建议如下：

- 不做全局 `STRICT`
- 先确保 gateway -> backend 路由跑通
- 如果 `abjx-int` 内所有服务都已经 sidecar 注入，再考虑：

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: abjx-int
spec:
  mtls:
    mode: STRICT
```

风险提醒：

- 如果 namespace 里还有没注入 sidecar 的 Pod，`STRICT` 很容易把流量打挂
- 所以这一步要放在验证完成之后

---

## 4.8 Step 8: 可选的高可用资源

### 4.8.1 Gateway PDB

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: abjx-int-gw-pdb
  namespace: abjx-int
spec:
  minAvailable: 1
  selector:
    matchLabels:
      istio: abjx-int-gw
```

### 4.8.2 API PDB

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: abjx-health-check-api-pdb
  namespace: abjx-int
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: abjx-health-check-api
```

---

## 5. Full Minimal Manifest Set

如果你想按最小集一次性组织文件，建议拆成：

```text
00-namespace-abjx-int.yaml
10-abjx-health-check-api.yaml
20-abjx-int-gw-service.yaml
21-abjx-int-gw-deployment.yaml
30-abjx-int-gateway.yaml
40-abjx-health-check-api-virtualservice.yaml
50-abjx-int-peerauthentication.yaml        # 可选，后启用
60-abjx-int-gw-pdb.yaml                    # 可选
61-abjx-health-check-api-pdb.yaml          # 可选
```

应用顺序：

```bash
kubectl apply -f 00-namespace-abjx-int.yaml
kubectl apply -f 10-abjx-health-check-api.yaml
kubectl apply -f 20-abjx-int-gw-service.yaml
kubectl apply -f 21-abjx-int-gw-deployment.yaml
kubectl apply -f 30-abjx-int-gateway.yaml
kubectl apply -f 40-abjx-health-check-api-virtualservice.yaml
```

---

## 6. Validation and Rollback

## 6.1 验证 sidecar 注入

```bash
kubectl get pods -n abjx-int
kubectl get pod -n abjx-int <api-pod-name> -o jsonpath='{.spec.containers[*].name}'
```

预期：

- API Pod 里能看到 `app` 和 `istio-proxy`

---

## 6.2 验证 gateway Pod 和 Service

```bash
kubectl get pods -n abjx-int -l istio=abjx-int-gw
kubectl get svc abjx-int-gw -n abjx-int
kubectl get gateway abjx-int-gw -n abjx-int -o yaml
kubectl get virtualservice abjx-health-check-api-vs -n abjx-int -o yaml
```

预期：

- gateway Pod 正常 Running
- `abjx-int-gw` Service 有 ClusterIP 或 ILB IP
- Gateway selector 和 Deployment label 对得上
- VirtualService 的 `gateways` 指向 `abjx-int-gw`

---

## 6.3 验证路由

如果是 HTTP：

```bash
curl -H 'Host: abjx-int.internal.example.com' http://<GW_IP>/health
```

如果是 HTTPS：

```bash
curl -k -H 'Host: abjx-int.internal.example.com' https://<GW_IP>/health
```

---

## 6.4 验证 gateway 健康检查

GKE ILB 常见会看 gateway 的健康端口，建议保留 `15021`。

可以检查：

```bash
kubectl get svc abjx-int-gw -n abjx-int -o yaml
kubectl logs -n abjx-int -l istio=abjx-int-gw -c istio-proxy --tail=100
```

如果后续接 PSC / ILB，`15021` 的就绪探针路径通常要保证可用。

---

## 6.5 Istio 配置一致性检查

```bash
istioctl analyze -n abjx-int
```

重点检查：

- Gateway selector 是否匹配到 workload
- VirtualService host/gateway 是否一致
- Service port name 是否符合协议约定

---

## 6.6 回滚策略

最小回滚顺序：

1. 先删除 `VirtualService`
2. 再删除 `Gateway`
3. 再删除 gateway Deployment / Service
4. API 保持不动

如果 sidecar 注入本身引发问题：

```bash
kubectl label namespace abjx-int istio.io/rev-
kubectl rollout restart deployment -n abjx-int
```

注意：

- 这会让重建后的 Pod 不再注入 sidecar
- 如果你已经依赖 gateway -> sidecar 的 mesh 能力，回滚前先确认影响面

---

## 7. Reliability and Cost Optimizations

### 7.1 可靠性建议

- gateway 至少 `2 replicas`
- API 至少 `2 replicas`
- 给 gateway 和 API 都加 `PDB`
- 如果是生产入口，建议 HPA
- 如果有专用 node pool，把 gateway 与普通 workload 分离

### 7.2 成本建议

- 不要给每个 namespace 盲目上大规格 gateway
- 小流量 namespace 可以先从 `2 replicas + 小 requests` 开始
- sidecar 会增加 CPU/Memory，要把这部分算进容量

---

## 8. Handoff Checklist

- [ ] 已确认集群 ASM revision
- [ ] 已创建 `abjx-int` namespace
- [ ] 已为 `abjx-int` 打上正确 `istio.io/rev`
- [ ] 已部署 `abjx-health-check-api` Deployment 和 Service
- [ ] 已部署 `abjx-int-gw` Deployment 和 Service
- [ ] 已创建 `Gateway`：`abjx-int-gw`
- [ ] 已创建 `VirtualService`，并绑定到 `abjx-int-gw`
- [ ] 已验证 `/health` 能从 gateway 正常打到 API
- [ ] 如需 HTTPS，已创建 `abjx-int-gw-tls` Secret
- [ ] 如需内部 mTLS，已确认 namespace 内 workload 全部已注入 sidecar 后再启用 `STRICT`

---

## 9. One-Screen Summary

你现在这个 simple API deployment，在 ASM 里的最小闭环可以概括成一句话：

`abjx-int` namespace 开 sidecar 注入 -> 部署 `abjx-health-check-api` -> 在同 namespace 部署独立 gateway workload `abjx-int-gw` -> 用 `Gateway` CR 定义 host/port -> 用 `VirtualService` 绑定 `abjx-int-gw` 并把流量转到 `abjx-health-check-api` -> 如果需要 HTTPS，再给 gateway 挂 `credentialName` 对应的 TLS Secret。

最容易搞混的点只有两个：

1. `abjx-int-gw` 既可以指 gateway workload，也可以指 `Gateway` CR 的名字，但它们不是同一个资源类型。
2. 对外 HTTPS 证书是你自己管的；mesh 内 sidecar 间 mTLS 证书通常由 ASM 自动管理。



这是一个非常专业且符合 生产隔离（Production Isolation） 原理的思路。
在 Istio/ASM 架构中，将 Gateway 基础设施 与 业务 Runtime 拆分到不同的 Namespace，不仅逻辑清晰，还能实现权限的精细化管理（例如：SRE 负责 Gateway 运维，开发负责 VS 路由和业务 HPA）。
根据你的需求，我为你整理了跨 Namespace 拆分的资源分布清单及核心配置文件示例。
1. 资源分布图 (Architecture Distribution)
我们将资源划分为两个 Namespace：
 * abjx-int-gw (Gateway 层)：负责负载均衡、TLS 终止、外部流量入口。
 * abjx-int (Runtime 层)：负责业务代码、水平扩展（HPA）、内部路由逻辑。
| 资源分类 | 资源类型 (Kind) | 资源名称示例 | 部署位置 (Namespace) |
|---|---|---|---|
| 基础设施层 | Namespace | abjx-int-gw | - |
|  | Service (LoadBalancer) | abjx-int-gw-svc | abjx-int-gw |
|  | Deployment (Envoy) | abjx-int-gw-deploy | abjx-int-gw |
|  | Gateway (CR) | abjx-int-gw | abjx-int-gw |
|  | Secret (TLS 证书) | abjx-int-cert | abjx-int-gw |
| 业务运行层 | Namespace | abjx-int | - |
|  | Deployment | abjx-health-check-api | abjx-int |
|  | Service (ClusterIP) | abjx-health-check-api | abjx-int |
|  | HPA | abjx-api-hpa | abjx-int |
|  | VirtualService | abjx-api-vs | abjx-int |
2. 关键点：VirtualService 放在哪里？
答案：放在业务 Namespace (abjx-int)。
理由：
 * 解耦：VirtualService 定义的是业务的路由规则（比如 /v1 去哪，/v2 去哪）。把它放在业务空间，业务团队可以随代码一起更新路由，而不需要去动 Gateway 基础设施空间。
 * 绑定方式：在 VirtualService 内部，通过 gateways 字段跨空间引用 Gateway 资源即可。
3. 核心代码实现 (Implementation Snippets)
A. Gateway 配置 (在 abjx-int-gw 下)
这是你的入口定义，它监听端口并声明自己属于哪个网关负载。
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: abjx-int-gw
  namespace: abjx-int-gw # 注意在这里
spec:
  selector:
    istio: abjx-int-gw # 匹配该空间下的网关 Pod 标签
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "api.example.com" # 或者是 "*"

B. VirtualService 配置 (在 abjx-int 下)
这是最关键的一步，注意 gateways 字段的写法。
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: abjx-health-check-api-vs
  namespace: abjx-int # 放在业务空间
spec:
  hosts:
  - "api.example.com"
  gateways:
  - abjx-int-gw/abjx-int-gw # 关键：Namespace/GatewayName 跨空间引用
  http:
  - match:
    - uri:
        prefix: /health
    route:
    - destination:
        host: abjx-health-check-api.abjx-int.svc.cluster.local # 全限定域名最稳妥
        port:
          number: 8080

4. 为什么这样拆分逻辑更清晰？
 * 证书隔离：如果你有 SSL 证书，Secret 只需存在 abjx-int-gw 下，业务空间 abjx-int 根本看不见证书私钥，安全性更高。
 * HPA 专注业务：你在 abjx-int 下做的所有 HPA 和资源限制（Resource Quota）只针对业务 Pod，不会因为网关流量激增导致业务空间的配额被耗尽。
 * 多租户扩展：假设以后你有了第二个业务 abjx-dev，你依然可以复用 abjx-int-gw 空间的网关，只需在 abjx-dev 空间新建一个 VS 绑定过去即可。
5. 部署建议
 * Label 管理：确保 abjx-int 命名空间开启了 ASM 注入标签（istio.io/rev=...），而 abjx-int-gw 空间不需要注入（因为它本身就是网关）。
 * 验证命令：部署后使用 istioctl analyze --all-namespaces 检查是否有跨空间引用的报错。
按照这个结构，你的逻辑就完全闭环了：网关管大门，业务管屋里。

