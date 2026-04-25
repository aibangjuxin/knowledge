# GKE Ambient + Waypoint 安装与验证（基于 Gloo Mesh 企业版）

> **文档定位**：在 GKE 上采用 "Istio + Gloo Mesh 企业版" 实现多集群 Service Mesh，优先使用 Ambient（ztunnel）+ Waypoint 模式。文档综合现有 Gloo 资料，提供可落地的 step-by-step 操作与配置示例。

---

## 1. 目标与约束

### 核心需求
- 多集群服务网格，Gloo Mesh 作为管理层（推荐企业版）
- 新集群优先使用 Ambient（ztunnel）+ Waypoint
- 保持端到端 TLS、域名不变、Host/SNI 不变
- 兼容现有 Nginx 与 PSC 架构

### 不变项（与之前设计一致）
- 入口层：GCP GLB + Cloud Armor + PSC NEG
- 生产者（Producer）：Service Attachment + ILB（不变）
- 客户端到 Nginx 的 TLS 与证书（不变）
- Pod 内部业务保持 HTTP，由 Sidecar 或 Waypoint 处理加密（不变）

### 变化项（仅限 mesh 层）
- 控制面从 ASM Istiod 迁移到 Gloo Mesh 管理面
- Gateway Pod 替换为 Gloo Gateway
- 路由资源从 VirtualService 迁移到 RouteTable/VirtualGateway
- 可选：启用 Ambient 模式（ztunnel）卸载数据面代理，Waypoint 处理 L7 策略

---

## 2. 环境与先决条件

### 2.1 所需权限
GCP 项目 Owner 或具备以下角色：
- `roles/container.admin`（Kubernetes Engine Admin）
- `roles/iam.serviceAccountAdmin`（Service Account Admin）
- `roles/compute.networkAdmin`（Compute Network Admin）

### 2.2 工具版本

| 工具 | 最低版本 | 说明 |
| --- | --- | --- |
| gcloud | 400.0.0+ | GCP CLI |
| kubectl | 1.28+ | Kubernetes CLI |
| helm | 3.12+ | Helm 包管理器 |
| meshctl | 2.x | Gloo Mesh EE CLI |
| istioctl | 1.19+ | Istio 诊断（可选） |

### 2.3 环境变量（示例）

```bash
# GCP 配置
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-gke-cluster"

# Gloo 配置
export GLOO_EE_VERSION="2.1.0"  # 请替换为最新 EE 版本
export LICENSE_KEY="<YOUR_LICENSE_KEY>"

# 命名空间配置
export MGMT_NAMESPACE="gloo-mesh"
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="team-a-runtime"
```

### 2.4 GKE 版本要求

- **GKE 1.25+**：推荐，获得最佳 ztunnel 与 Ambient 支持
- **GKE 1.28+**：生产环境推荐版本
- 节点池：使用 Standard 节点池（非 Container-Optimized OS）

---

## 3. 创建 GKE 集群

### 3.1 创建命令

```bash
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.28 \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --min-nodes=3 \
  --max-nodes=6 \
  --enable-autoscaling \
  --enable-autoupgrade \
  --enable-autorepair \
  --disk-size=100 \
  --disk-type=pd-balanced \
  --network=default \
  --subnetwork=default \
  --enable-ip-alias \
  --enable-intra-node-visibility \
  --workload-pool=${GCP_PROJECT_ID}.svc.id.goog \
  --labels="env=prod,app=gloo-gateway,mesh=gloo"
```

### 3.2 关键标志说明

| 标志 | 说明 |
| --- | --- |
| `--enable-ip-alias` | VPC-native 集群（推荐，便于 PSC 与多集群） |
| `--enable-intra-node-visibility` | 允许 Pod 直连（有助于调试与 east-west 流量） |
| `--workload-pool` | 启用 Workload Identity（可选但推荐，用于安全地绑定 GCP SA） |
| `--enable-autoscaling` | 根据负载自动扩缩节点 |
| `--machine-type=e2-standard-4` | 4 vCPU, 16GB RAM（适合管理面 + 网关 + 工作负载） |

### 3.3 验证集群

```bash
# 获取凭证
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

# 验证连接
kubectl cluster-info

# 确认上下文
kubectl config current-context
# 预期：gke_${GCP_PROJECT_ID}_${GCP_REGION}_${GKE_CLUSTER_NAME}

# 查看节点
kubectl get nodes
```

---

## 4. 安装 Gloo Mesh 企业版（管理面）

### 4.1 安装 meshctl CLI

```bash
# 下载并安装 meshctl
curl -sL https://run.solo.io/meshctl/install | sh

# 移动到 PATH
sudo mv $HOME/.gloo-mesh/bin/meshctl /usr/local/bin/

# 验证版本
meshctl version
# 预期输出：
# {
#   "meshctl": "2.1.0",
#   "gloo-mesh-enterprise": "2.1.0"
# }
```

### 4.2 添加 Gloo Platform Helm 仓库

```bash
# 添加 Enterprise 仓库
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm

# 添加 Platform 仓库（用于 gloo-platform-crds）
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts

# 更新本地缓存
helm repo update

# 验证仓库
helm search repo glooe/gloo-ee --versions | head -5
```

### 4.3 创建命名空间

```bash
# 创建所需命名空间
kubectl create namespace ${MGMT_NAMESPACE}          # Gloo Mesh 管理面
kubectl create namespace ${GATEWAY_NAMESPACE}       # Gloo Gateway
kubectl create namespace ${WORKLOAD_NAMESPACE}      # 业务工作负载
kubectl create namespace istio-system               # Istio 控制面

# 验证
kubectl get namespaces
```

### 4.4 安装 CRDs（必须先于管理面）

```bash
# 安装 Gloo Platform CRDs
helm install gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace ${MGMT_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_EE_VERSION} \
  --wait

# 验证 CRDs
kubectl get crds | grep solo.io | head -10
# 预期：virtualgateways.networking.gloo.solo.io, routetables.networking.gloo.solo.io 等
```

### 4.5 安装 Gloo Mesh 管理面

```bash
# 安装 Gloo Mesh Enterprise 管理面
helm install gloo-platform glooe/gloo-ee \
  --namespace ${MGMT_NAMESPACE} \
  --version ${GLOO_EE_VERSION} \
  --set-string license_key="${LICENSE_KEY}" \
  --values - <<EOF
# 全局设置
global:
  extensions:
    enabled:
      - enterprise

# 管理服务器
gloo:
  mgmtServer:
    enabled: true
    replicaCount: 1
    resources:
      requests:
        cpu: 500m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi

# Gloo Agent（必须在管理服务器之后启动）
  glooAgent:
    enabled: true
    relay:
      serverAddress: gloo-mesh-mgmt-server.${MGMT_NAMESPACE}.svc.cluster.local:9900
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# 遥测收集器
  telemetryCollector:
    enabled: true
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# Gloo UI
  glooUi:
    enabled: true
    replicaCount: 1
    service:
      type: ClusterIP
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# Istio 控制面（由 Gloo Mesh 管理）
  istiod:
    enabled: true
    replicaCount: 1
    global:
      proxy:
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# 等待安装完成（通常 3-5 分钟）
kubectl wait --for=condition=Ready pods --all -n ${MGMT_NAMESPACE} --timeout=300s
```

### 4.6 验证管理面安装

```bash
# 检查所有 Pod 状态
kubectl get pods -n ${MGMT_NAMESPACE}

# 预期输出：
# NAME                                    READY   STATUS    RESTARTS   AGE
# gloo-mesh-agent-xxxxx                   1/1     Running   0          2m
# gloo-mesh-mgmt-server-xxxxx             1/1     Running   0          2m
# gloo-mesh-ui-xxxxx                      1/1     Running   0          2m
# gloo-telemetry-collector-xxxxx          1/1     Running   0          2m
# istiod-xxxxx                            1/1     Running   0          2m

# 运行健康检查
meshctl check

# 预期输出：
# ✓ Gloo Mesh management plane is healthy
# ✓ Gloo Mesh agent is connected
# ✓ Istiod is running
# ✓ License is valid
```

### 4.7 可选：访问 Gloo Mesh UI

```bash
# Port-forward 到 UI
kubectl port-forward -n ${MGMT_NAMESPACE} svc/gloo-mesh-ui 8080:8080 &

# 浏览器打开 http://localhost:8080
# 默认无认证（生产环境应配置 RBAC）
```

---

## 5. 安装并配置 Gloo Gateway（替代 ASM Ingress Gateway）

### 5.1 部署 Gloo Gateway

```bash
# 安装 Gloo Gateway（使用 Helm，与生产环境一致）
helm install gloo-gateway glooe/gloo-gateway \
  --namespace ${GATEWAY_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_EE_VERSION} \
  --set-string license_key="${LICENSE_KEY}" \
  --values - <<EOF
# 启用 Gloo Gateway
glooGateway:
  enabled: true

  # Gateway Proxy 配置
  gatewayProxies:
    gatewayProxy:
      # Service 类型：LoadBalancer（GCP 自动创建外部 LB）
      service:
        type: LoadBalancer
        annotations:
          service.beta.kubernetes.io/gcp-load-balancer-type: "External"
      # 副本数（生产至少 2）
      deployment:
        replicas: 2
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 1Gi
      # 高可用：反亲和性
      podTemplate:
        terminationGracePeriodSeconds: 30
        affinity:
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app: gloo-gateway
                topologyKey: kubernetes.io/hostname

# 集成 Istio（用于 mTLS）
istio:
  enabled: true
  istiod:
    enabled: true

# 禁用 Portal Server（不需要开发者门户）
glooPortalServer:
  enabled: false
EOF

# 等待安装完成
kubectl wait --for=condition=Ready pods -l app=gloo-gateway -n ${GATEWAY_NAMESPACE} --timeout=300s
```

### 5.2 验证 Gateway Pod

```bash
# 检查 Pod 状态
kubectl get pods -n ${GATEWAY_NAMESPACE}

# 预期输出：
# NAME                             READY   STATUS    RESTARTS   AGE
# gloo-gateway-xxxxx               1/1     Running   0          2m
# gloo-gateway-xxxxx               1/1     Running   0          2m
# istiod-xxxxx                     1/1     Running   0          2m

# 检查 Service（应有外部 IP）
kubectl get svc -n ${GATEWAY_NAMESPACE}

# 预期输出：
# NAME                  TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)                        AGE
# gloo-gateway-proxy    LoadBalancer   10.x.x.x      34.x.x.x       8080:3xxxx/TCP,8443:3xxxx/TCP  3m
# istiod                ClusterIP      10.x.x.x      <none>         15010/TCP,15012/TCP,15014/TCP  3m
```

### 5.3 获取外部 IP

```bash
# 获取 LoadBalancer 外部 IP
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "Gateway LoadBalancer IP: ${GATEWAY_IP}"

# 若为空，等待 IP 分配（通常 1-3 分钟）
if [ -z "${GATEWAY_IP}" ]; then
  echo "Waiting for LoadBalancer IP assignment..."
  kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -w
fi

# 保存备用
echo "export GATEWAY_IP=${GATEWAY_IP}" >> ~/.bashrc
```

---

## 6. 在 GKE 中启用 Ambient（ztunnel）+ Waypoint 模式

> **这是本文档的核心差异化能力**：相比传统 Sidecar 注入，Ambient 模式通过节点级 ztunnel 拦截流量，配合 Waypoint Proxy 处理 L7 策略，大幅降低资源开销并简化升级。

### 6.1 Ambient vs Sidecar 模式对比

| 特性 | Sidecar 模式 | Ambient 模式 |
| --- | --- | --- |
| 代理位置 | 每个 Pod 内注入 | 节点级 DaemonSet |
| 资源消耗 | 每个 Pod 一个代理进程 | 共享节点级代理 |
| 升级影响 | 需重启所有 Pod | 仅需重启 ztunnel DaemonSet |
| L7 策略 | Sidecar 直接处理 | Waypoint Proxy 处理 |
| 适用场景 | 精细控制、低延迟 | 大规模集群、成本优化 |

### 6.2 Ambient 架构说明

```
┌─────────────────────────────────────────────────────────────┐
│ Worker Node                                                 │
│                                                             │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐  │
│  │  Pod A      │     │  Pod B      │     │  Pod C      │  │
│  │  (无 Sidecar)│     │  (无 Sidecar)│     │  (无 Sidecar)│  │
│  └──────┬──────┘     └──────┬──────┘     └──────┬──────┘  │
│         │                   │                   │         │
│         └───────────────────┼───────────────────┘         │
│                             │                             │
│                    ┌────────▼────────┐                    │
│                    │   ztunnel       │                    │
│                    │   (节点级)       │                    │
│                    │   捕获所有流量   │                    │
│                    └────────┬────────┘                    │
│                             │                             │
│                    ┌────────▼────────┐                    │
│                    │  Waypoint Proxy │                    │
│                    │  (按需部署)      │                    │
│                    │  处理 L7 策略   │                    │
│                    └─────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

### 6.3 启用 Ambient 模式

```bash
# 方法：通过 Gloo Mesh MeshConfig 启用 Ambient
cat <<EOF | kubectl apply -f -
apiVersion: mesh.gloo.solo.io/v1
kind: MeshConfig
metadata:
  name: default
  namespace: ${MGMT_NAMESPACE}
spec:
  # Ambient 模式配置
  ambient:
    enabled: true
    ztunnel:
      # ztunnel 配置
      config:
        # 性能参数
        concurrency: 2
  # 禁用水 sidcar 自动注入（Ambient 模式不需要）
  sidecar:
    autoInject: disabled
EOF

# 验证 MeshConfig
kubectl get meshconfig -n ${MGMT_NAMESPACE}
kubectl describe meshconfig default -n ${MGMT_NAMESPACE}
```

### 6.4 部署 Waypoint Proxy（处理 L7 策略）

Waypoint 是 Ambient 模式下处理 L7 策略的组件，类似 Sidecar 的 L7 代理能力。

```bash
# 通过 Gloo Mesh 创建 Waypoint
# Waypoint 按 Workspace 或服务自动部署

# 示例：为 team-a-runtime 命名空间创建 Waypoint
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.gloo.solo.io/v1
kind: Waypoint
metadata:
  name: team-a-waypoint
  namespace: ${WORKLOAD_NAMESPACE}
  labels:
    # 标记为由 Gloo Mesh 管理
    app.kubernetes.io/managed-by: gloo-mesh
spec:
  # 指向要代理的工作负载
  workloadSelectors:
  - namespace: ${WORKLOAD_NAMESPACE}
    # 或使用标签选择器
    # labels:
    #   app: team-a-backend
  # 副本数（高可用）
  replicas: 2
  # 允许的输入端口
  ports:
  - name: http
    port: 15088
    protocol: TCP
EOF

# 验证 Waypoint 部署
kubectl get waypoint -n ${WORKLOAD_NAMESPACE}
kubectl get pods -n ${WORKLOAD_NAMESPACE} -l "app.kubernetes.io/name=team-a-waypoint"

# 预期：Waypoint 以 Deployment 形式部署，副本数为 2
```

### 6.5 验证 Ambient 模式

```bash
# 1. 检查 ztunnel DaemonSet 是否运行
kubectl get daemonset -n istio-system
# 预期输出：
# NAME    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# ztunnel   3         3         3       3            3

# 2. 检查 Pod 是否无 Sidecar（每个 Pod 只有 1 个容器）
kubectl get pods -n ${WORKLOAD_NAMESPACE} -o jsonpath='{.items[*].spec.containers[*].name}'
# 预期输出：httpbin（无 istio-proxy 容器）

# 3. 检查 Waypoint 是否存在
kubectl get waypoint -A

# 4. 通过 meshctl 验证
meshctl ambient check
# 或
meshctl check
```

### 6.6 Ambient 模式下的流量路由

```
外部流量 → Gloo Gateway → ztunnel（节点级）→ Waypoint → Pod
                                      ↓
                              L7 策略（L7 Authorization,
                              Retry, Timeout, etc.）
```

**注意**：Ambient 模式下，mTLS 仍然由 ztunnel 处理，但 L7 策略（如 AuthorizationPolicy、VirtualService 的 L7 规则）由 Waypoint 执行。

---

## 7. 部署示例后端服务

### 7.1 创建命名空间（禁用 Sidecar 注入）

```bash
# 创建命名空间，明确禁用 istio-injection
kubectl create namespace ${WORKLOAD_NAMESPACE}

# 确认无自动注入（Ambient 模式不需要）
kubectl label namespace ${WORKLOAD_NAMESPACE} \
  istio-injection=disabled --overwrite

# 验证标签
kubectl get namespace ${WORKLOAD_NAMESPACE} --show-labels
```

### 7.2 部署 HTTPbin 示例

```bash
# 部署 HTTPbin（轻量 HTTP 测试服务）
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: ${WORKLOAD_NAMESPACE}
  labels:
    app: httpbin
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
        version: v1
    spec:
      # Ambient 模式：无需 serviceAccount
      containers:
      - name: httpbin
        image: kennethreitz/httpbin:latest
        ports:
        - containerPort: 80
          name: http
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
        livenessProbe:
          httpGet:
            path: /status/200
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /status/200
            port: 80
          initialDelaySeconds: 3
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: ${WORKLOAD_NAMESPACE}
  labels:
    app: httpbin
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: httpbin
EOF
```

### 7.3 验证部署

```bash
# 检查 Pod 状态（应为 1/1，无 Sidecar）
kubectl get pods -n ${WORKLOAD_NAMESPACE}

# 预期输出：
# NAME                      READY   STATUS    RESTARTS   AGE
# httpbin-xxxxx-xxxxx       1/1     Running   0          1m
# httpbin-xxxxx-xxxxx       1/1     Running   0          1m

# 确认无 Sidecar 容器
kubectl get pod -n ${WORKLOAD_NAMESPACE} -l app=httpbin \
  -o jsonpath='{.items[0].spec.containers[*].name}'
# 预期：仅输出 "httpbin"（无 istio-proxy）

# 检查 Service
kubectl get svc -n ${WORKLOAD_NAMESPACE}

# 预期输出：
# NAME      TYPE        CLUSTER-IP    PORT(S)   AGE
# httpbin   ClusterIP   10.x.x.x      80/TCP    1m
```

---

## 8. 创建 Gloo Mesh 上层路由资源

> **核心概念**：Gloo Mesh 使用高阶 CRD（VirtualGateway、RouteTable、TrafficPolicy）替代标准 Istio CRD，提供更简洁的抽象和更丰富的功能（如 RouteTable delegation）。

### 8.1 创建 Upstream（指向 K8s Service）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: httpbin-upstream
  namespace: ${MGMT_NAMESPACE}
  labels:
    app: httpbin
spec:
  kube:
    serviceName: httpbin
    serviceNamespace: ${WORKLOAD_NAMESPACE}
    servicePort: 80
EOF

# 验证 Upstream 状态
kubectl get upstream -n ${MGMT_NAMESPACE} httpbin-upstream

# 预期：
# NAME               TYPE      STATUS   DETAILS
# httpbin-upstream   Kubernetes  Accepted  svc name: httpbin, svc namespace: team-a-runtime, port: 80
```

### 8.2 创建 VirtualGateway（替代 Istio Gateway，定义入口监听器）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: runtime-gateway
  namespace: ${GATEWAY_NAMESPACE}
spec:
  # 关联到 Gloo Gateway Pod
  workloads:
  - selector:
      labels:
        app: gloo-gateway
      namespace: ${GATEWAY_NAMESPACE}
  # 监听器配置
  listeners:
  - http: {}
    port:
      number: 443
    # TLS 终止配置（与之前 ASM 配置一致）
    tls:
      mode: SIMPLE                    # 单向 TLS，Gateway 终止
      secretName: wildcard-abjx-appdev-aibang-cert  # 引用你的证书 Secret
    # 允许绑定哪些 RouteTable
    allowedRouteTables:
    - host: "*.abjx.appdev.aibang"    # 支持通配符
---
# HTTP 监听器（用于测试）
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: runtime-gateway-http
  namespace: ${GATEWAY_NAMESPACE}
spec:
  workloads:
  - selector:
      labels:
        app: gloo-gateway
      namespace: ${GATEWAY_NAMESPACE}
  listeners:
  - http: {}
    port:
      number: 80
    allowedRouteTables:
    - host: "*"
EOF

# 验证
kubectl get virtualgateway -n ${GATEWAY_NAMESPACE}
```

### 8.3 创建 RouteTable（替代 Istio VirtualService，定义路由规则）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: httpbin-routes
  namespace: ${MGMT_NAMESPACE}
  labels:
    # 可用于 delegation（路由委托）
    team: platform
spec:
  # 匹配哪些域名
  hosts:
  - "*.abjx.appdev.aibang"
  # 绑定到哪个 VirtualGateway
  virtualGateways:
  - name: runtime-gateway
    namespace: ${GATEWAY_NAMESPACE}
  # HTTP 路由规则
  http:
  # 路由 1：/get 路径
  - name: route-get
    matchers:
    - uri:
        prefix: /get
    forwardTo:
      destinations:
      - ref:
          name: httpbin-upstream
          namespace: ${MGMT_NAMESPACE}
        port:
          number: 80
        # 可选：权重（用于金丝雀发布）
        # weight: 90
  # 路由 2：根路径
  - name: route-root
    matchers:
    - uri:
        prefix: /
    forwardTo:
      destinations:
      - ref:
          name: httpbin-upstream
          namespace: ${MGMT_NAMESPACE}
        port:
          number: 80
EOF

# 验证
kubectl get routetable -n ${MGMT_NAMESPACE}

# 查看详情
kubectl get routetable -n ${MGMT_NAMESPACE} httpbin-routes -o yaml
```

### 8.4 创建 TrafficPolicy（替代 Istio DestinationRule，定义流量策略）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: trafficcontrol.policy.gloo.solo.io/v2
kind: TrafficPolicy
metadata:
  name: httpbin-traffic-policy
  namespace: ${MGMT_NAMESPACE}
spec:
  # 作用于哪些目标（这里选择前面定义的 Upstream）
  applyToDestinations:
  - selector:
      name: httpbin-upstream
      namespace: ${MGMT_NAMESPACE}
  policy:
    # TLS 配置（保持业务域名作为 SNI）
    tls:
      mode: SIMPLE        # 向后端发起 TLS
      sni: api1.abjx.appdev.aibang
    # 连接池配置
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
        maxRequestsPerConnection: 100
    # 负载均衡
    loadBalancer:
      simple: ROUND_ROBIN
    # 异常检测（熔断）
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
      minHealthPercent: 50
EOF

# 验证
kubectl get trafficpolicy -n ${MGMT_NAMESPACE}
```

### 8.5 可选：创建 AccessPolicy（替代 Istio AuthorizationPolicy）

```bash
# 默认拒绝所有入站流量
cat <<EOF | kubectl apply -f -
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: deny-all
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  # 空 spec = 拒绝所有
---
# 放行来自 Gateway 的流量
apiVersion: security.policy.gloo.solo.io/v2
kind: AccessPolicy
metadata:
  name: allow-from-gateway
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  # 作用于哪些工作负载
  applyToWorkloads:
  - selector:
      labels:
        app: httpbin
  config:
    # mTLS 模式
    authn:
      tlsMode: STRICT     # 强制 mTLS
    # L7 授权
    authz:
      # 仅允许来自特定 ServiceAccount 的流量
      allowedClients:
      - serviceAccountSelector:
          name: gloo-gateway-sa
          namespace: ${GATEWAY_NAMESPACE}
      # 允许的端口
      allowedPorts:
      - port: 80
EOF

# 注意：在 Ambient 模式下，AccessPolicy 由 Waypoint 执行
```

---

## 9. 验证端到端访问

### 9.1 获取网关 IP

```bash
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway IP: ${GATEWAY_IP}"

# 如果使用 HTTP（端口 80）测试
export GATEWAY_HTTP_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway HTTP IP: ${GATEWAY_HTTP_IP}"
```

### 9.2 HTTP 测试（端口 80）

```bash
# 测试根路径
curl -s http://${GATEWAY_IP}/

# 测试 /get 端点
curl -s http://${GATEWAY_IP}/get

# 预期：返回 httpbin 的 JSON 响应
```

### 9.3 HTTPS 测试（端口 443，使用 Host 头）

```bash
# 测试 HTTPS + Host 头
curl -s -k -H "Host: api1.abjx.appdev.aibang" \
  https://${GATEWAY_IP}/get

# -k：跳过证书验证（测试用）
# -v：详细输出，可查看 TLS 握手

# 更详细的测试
curl -v -H "Host: api1.abjx.appdev.aibang" \
  https://${GATEWAY_IP}/get 2>&1 | head -30
```

### 9.4 预期结果

**成功时的输出**：
```json
{
  "args": {},
  "headers": {
    "Accept": "*/*",
    "Host": "api1.abjx.appdev.aibang",
    "User-Agent": "curl/8.x",
    "X-Forwarded-For": "xxx.xxx.xxx.xxx",
    "X-Request-Id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  },
  "origin": "xxx.xxx.xxx.xxx",
  "url": "https://api1.abjx.appdev.aibang/get"
}
```

**关键验证点**：
- `X-Request-Id`：确认流量经过 Envoy
- `X-Forwarded-For`：确认原始客户端 IP（可能因 GCP LB 而变化）
- TLS 握手成功，无证书错误（使用正确证书时）

### 9.5 Pod 内部通信测试（验证 mTLS）

```bash
# 在 Waypoint 中执行 curl（验证 mTLS）
kubectl exec -n ${WORKLOAD_NAMESPACE} deploy/team-a-waypoint -c waypoint -- \
  curl -s http://httpbin.${WORKLOAD_NAMESPACE}:80/get

# 预期：返回 JSON（说明 Waypoint → Pod 流量正常）
```

---

## 10. 排错与诊断

### 10.1 常见问题与解决方案

| 问题现象 | 检查命令 | 解决方案 |
| --- | --- | --- |
| Gateway LoadBalancer IP 为空 | `kubectl describe svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy` | 等待 3-5 分钟，或检查 GCP 配额 |
| 404 路由未匹配 | `kubectl get routetable -n ${MGMT_NAMESPACE}` | 确认 hosts 和 matchers 配置正确 |
| 503 Service Unavailable | `kubectl get upstream -n ${MGMT_NAMESPACE}` | 确认 Upstream 状态为 Accepted |
| mTLS 握手失败 | `kubectl logs -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --tail=50` | 确认 PeerAuthentication 为 STRICT |
| Ambient ztunnel 未运行 | `kubectl get daemonset -n istio-system` | 检查节点是否支持 ztunnel |
| RouteTable 未绑定 | `kubectl describe virtualgateway -n ${GATEWAY_NAMESPACE}` | 确认 allowedRouteTables 配置 |

### 10.2 诊断命令速查

```bash
# ─── Gloo Mesh 健康检查 ─────────────────────
meshctl check                              # 完整健康检查
meshctl ambient check                      # Ambient 特定检查

# ─── 资源状态 ─────────────────────────────
kubectl get virtualgateway,routetable,trafficpolicy,upstream -n ${MGMT_NAMESPACE}
kubectl get accesspolicy -n ${WORKLOAD_NAMESPACE}

# ─── 资源详情 ─────────────────────────────
kubectl describe virtualgateway runtime-gateway -n ${GATEWAY_NAMESPACE}
kubectl describe routetable httpbin-routes -n ${MGMT_NAMESPACE}
kubectl describe upstream httpbin-upstream -n ${MGMT_NAMESPACE}

# ─── Pod 日志 ─────────────────────────────
kubectl logs -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --tail=100 -f
kubectl logs -n ${MGMT_NAMESPACE} deployment/gloo-mesh-mgmt-server --tail=100
kubectl logs -n ${WORKLOAD_NAMESPACE} -l app=httpbin --tail=50

# ─── Envoy 诊断 ─────────────────────────────
# Port-forward 到 Envoy admin
kubectl port-forward -n ${GATEWAY_NAMESPACE} deploy/gloo-gateway 15000:15000 &
curl http://localhost:15000/server_info          # 服务信息
curl http://localhost:15000/clusters             # 集群配置
curl http://localhost:15000/listeners            # 监听器配置
curl http://localhost:15000/routes               # 路由配置

# ─── Ambient 特定 ─────────────────────────────
kubectl get daemonset -n istio-system            # ztunnel DaemonSet
kubectl get waypoint -A                          # Waypoint 列表
kubectl describe waypoint team-a-waypoint -n ${WORKLOAD_NAMESPACE}

# ─── Istio 诊断 ─────────────────────────────
istioctl proxy-status                           # 代理状态
istioctl proxy-config cluster <pod-name> -n ${WORKLOAD_NAMESPACE}
istioctl proxy-config endpoint <pod-name> -n ${WORKLOAD_NAMESPACE}
```

### 10.3 查看 Envoy 配置（验证路由翻译）

```bash
# 查看 Gloo 翻译后的 Istio 资源
kubectl get virtualservice -n ${MGMT_NAMESPACE}
kubectl get gateway -n ${MGMT_NAMESPACE}

# 查看详细配置
kubectl get virtualservice -n ${MGMT_NAMESPACE} -o yaml
kubectl get gateway -n ${MGMT_NAMESPACE} -o yaml
```

---

## 11. 多集群扩展（未来）

### 11.1 添加第二个集群到 Gloo Mesh

```bash
# 在第二个集群上执行（假设已安装 Gloo Agent）
meshctl cluster register \
  --cluster-name=cluster-2 \
  --mgmt-context=cluster-1-gke \
  --remote-context=cluster-2-gke \
  --agent-server-address=gloo-mesh-mgmt-server.${MGMT_NAMESPACE}.svc.cluster.local:9900
```

### 11.2 Workspace 隔离多租户

```bash
# 为不同团队创建 Workspace
cat <<EOF | kubectl apply -f -
apiVersion: admin.gloo.solo.io/v2
kind: Workspace
metadata:
  name: team-a-workspace
  namespace: ${MGMT_NAMESPACE}
spec:
  workloadClusters:
  - name: gke-cluster-1
    namespaces:
    - name: team-a-runtime
    - name: team-a-gateway
EOF
```

### 11.3 Federation（跨集群服务发现）

```bash
# 通过 Federation 暴露服务到其他集群
cat <<EOF | kubectl apply -f -
apiVersion: networking.gloo.solo.io/v2
kind: Federation
metadata:
  name: httpbin-federation
  namespace: ${MGMT_NAMESPACE}
spec:
  upstream:
    ref:
      name: httpbin-upstream
      namespace: ${MGMT_NAMESPACE}
  # 导出到的集群
  exportTo:
  - clusters:
    - cluster-2
EOF
```

---

## 12. 完整 YAML 文件参考

### 12.1 一键安装脚本（完整版）

```bash
#!/bin/bash
# install-gloo-ambient.sh - GKE + Gloo Mesh + Ambient 完整安装

set -e

# ─── 配置 ─────────────────────────────────
export GCP_PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project}"
export GCP_REGION="${GCP_REGION:-us-central1}"
export GKE_CLUSTER_NAME="${GKE_CLUSTER_NAME:-gloo-ambient-cluster}"
export GLOO_EE_VERSION="${GLOO_EE_VERSION:-2.1.0}"
export LICENSE_KEY="${LICENSE_KEY:-<YOUR_LICENSE_KEY>}"
export MGMT_NAMESPACE="${MGMT_NAMESPACE:-gloo-mesh}"
export GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-gloo-gateway}"
export WORKLOAD_NAMESPACE="${WORKLOAD_NAMESPACE:-team-a-runtime}"

echo "=== GKE + Gloo Mesh + Ambient 安装脚本 ==="
echo "项目: ${GCP_PROJECT_ID}"
echo "区域: ${GCP_REGION}"
echo "集群: ${GKE_CLUSTER_NAME}"
echo "Gloo 版本: ${GLOO_EE_VERSION}"

# ─── Step 1: 创建 GKE 集群 ─────────────────────
echo "[1/8] 创建 GKE 集群..."
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --cluster-version=1.28 \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --enable-autoscaling \
  --enable-ip-alias \
  --workload-pool=${GCP_PROJECT_ID}.svc.id.goog \
  --labels="env=prod,mesh=gloo"

# ─── Step 2: 配置 kubectl ─────────────────────
echo "[2/8] 配置 kubectl 上下文..."
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

# ─── Step 3: 安装工具 ─────────────────────
echo "[3/8] 安装 meshctl 和添加 Helm 仓库..."
curl -sL https://run.solo.io/meshctl/install | sh
sudo mv $HOME/.gloo-mesh/bin/meshctl /usr/local/bin/
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

# ─── Step 4: 创建命名空间 ─────────────────────
echo "[4/8] 创建命名空间..."
kubectl create namespace ${MGMT_NAMESPACE}
kubectl create namespace ${GATEWAY_NAMESPACE}
kubectl create namespace ${WORKLOAD_NAMESPACE}

# ─── Step 5: 安装 Gloo Mesh 管理面 ─────────────────────
echo "[5/8] 安装 Gloo Mesh 管理面..."
helm install gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace ${MGMT_NAMESPACE} --create-namespace \
  --version ${GLOO_EE_VERSION} --wait

helm install gloo-platform glooe/gloo-ee \
  --namespace ${MGMT_NAMESPACE} \
  --version ${GLOO_EE_VERSION} \
  --set-string license_key="${LICENSE_KEY}" \
  --values - <<EOF
gloo:
  mgmtServer:
    enabled: true
  glooAgent:
    enabled: true
    relay:
      serverAddress: gloo-mesh-mgmt-server.${MGMT_NAMESPACE}.svc.cluster.local:9900
  glooUi:
    enabled: true
  telemetryCollector:
    enabled: true
  istiod:
    enabled: true
EOF

# ─── Step 6: 安装 Gloo Gateway ─────────────────────
echo "[6/8] 安装 Gloo Gateway..."
helm install gloo-gateway glooe/gloo-gateway \
  --namespace ${GATEWAY_NAMESPACE} --create-namespace \
  --version ${GLOO_EE_VERSION} \
  --set-string license_key="${LICENSE_KEY}" \
  --set glooGateway.gatewayProxies.gatewayProxy.service.type=LoadBalancer \
  --set glooGateway.gatewayProxies.gatewayProxy.deployment.replicas=2

# ─── Step 7: 等待就绪 ─────────────────────
echo "[7/8] 等待组件就绪..."
kubectl wait --for=condition=Ready pods --all -n ${MGMT_NAMESPACE} --timeout=300s
kubectl wait --for=condition=Ready pods -l app=gloo-gateway -n ${GATEWAY_NAMESPACE} --timeout=300s

# ─── Step 8: 验证安装 ─────────────────────
echo "[8/8] 验证安装..."
meshctl check

echo ""
echo "=== 安装完成 ==="
echo "Gateway IP: $(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "管理面: kubectl get pods -n ${MGMT_NAMESPACE}"
echo "网关: kubectl get pods -n ${GATEWAY_NAMESPACE}"
echo "访问 UI: kubectl port-forward -n ${MGMT_NAMESPACE} svc/gloo-mesh-ui 8080:8080"
```

---

## 13. 清理与卸载

```bash
# 删除路由资源
kubectl delete routetable,upstream,virtualgateway,trafficpolicy -n ${MGMT_NAMESPACE} --all
kubectl delete accesspolicy -n ${WORKLOAD_NAMESPACE} --all
kubectl delete waypoint -n ${WORKLOAD_NAMESPACE} --all

# 删除工作负载
kubectl delete deployment,svc httpbin -n ${WORKLOAD_NAMESPACE}

# 卸载 Gloo Gateway
helm uninstall gloo-gateway -n ${GATEWAY_NAMESPACE}
kubectl delete namespace ${GATEWAY_NAMESPACE}

# 卸载 Gloo Mesh 管理面
helm uninstall gloo-platform -n ${MGMT_NAMESPACE}
kubectl delete namespace ${MGMT_NAMESPACE}

# 删除集群（谨慎操作）
# gcloud container clusters delete ${GKE_CLUSTER_NAME} \
#   --project=${GCP_PROJECT_ID} \
#   --location=${GCP_REGION}
```

---

## 14. 参考链接

- [Gloo Mesh 官方文档](https://docs.solo.io/gloo-mesh-enterprise/)
- [Gloo Gateway 文档](https://docs.solo.io/gloo-mesh-gateway/)
- [Gloo Mesh Ambient 模式](https://docs.solo.io/gloo-mesh-enterprise/latest/ambient/introduction/)
- [Istio 与 Gloo 资源对照表](https://docs.solo.io/gloo-mesh-enterprise/latest/reference/istio-resources-mapping/)
- [Gloo Platform Helm Chart](https://storage.googleapis.com/gloo-ee-helm)
- [GKE 文档](https://cloud.google.com/kubernetes-engine/docs)

---

*文档版本：适用于 Gloo Mesh EE 2.x，GKE 1.25+*
*更新日期：2026-04-25*