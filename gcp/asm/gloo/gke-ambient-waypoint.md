# GKE Ambient + Waypoint 安装与验证（基于 Gloo Mesh 企业版）

> **文档定位**：在 GKE 上采用 "Istio + Gloo Mesh 企业版" 实现多集群 Service Mesh，优先使用 Ambient（ztunnel）+ Waypoint 模式。文档综合现有 Gloo 资料，提供可落地的 step-by-step 操作与配置示例。

---

## 1. 目标与约束

- **核心需求**：
  - 多集群服务网格，Gloo Mesh 作为管理层（推荐企业版）
  - 新集群优先使用 Ambient（ztunnel）+ Waypoint
  - 保持端到端 TLS、域名不变、Host/SNI 不变
  - 兼容现有 Nginx 与 PSC 架构

- **不变项（与之前设计一致）**：
  - 入口层：GCP GLB + Cloud Armor + PSC NEG
  - 生产者（Producer）：Service Attachment + ILB（不变）
  - 客户端到 Nginx 的 TLS 与证书（不变）
  - Pod 内部业务保持 HTTP，由 Sidecar 处理加密（不变）

- **变化项（仅限 mesh 层）**：
  - 控制面从 ASM Istiod 迁移到 Gloo Mesh 管理面
  - Gateway Pod 替换为 Gloo Gateway
  - 路由资源从 VirtualService 迁移到 RouteTable/VirtualGateway
  - 可选：启用 Ambient 模式（ztunnel）卸载数据面代理

---

## 2. 环境与先决条件

### 2.1 所需权限
- GCP 项目 Owner 或具备以下角色：
  - roles/container.admin
  - roles/iam.serviceAccountAdmin
  - roles/compute.networkAdmin

### 2.2 工具版本
| 工具 | 最低版本 |
|------|----------|
| gcloud | 400.0.0+ |
| kubectl | 1.28+ |
| helm | 3.12+ |
| meshctl | 2.x（对应 Gloo Mesh EE） |
| istioctl | 1.19+（可选，用于诊断） |

### 2.3 环境变量（示例）
```bash
export GCP_PROJECT_ID="your-gcp-project"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="gloo-gke-cluster"
export GLOO_EE_VERSION="2.0.0"          # 请替换为最新 EE 版本
export LICENSE_KEY="<YOUR_LICENSE_KEY>"

export MGMT_NAMESPACE="gloo-mesh"
export GATEWAY_NAMESPACE="gloo-gateway"
export WORKLOAD_NAMESPACE="team-a-runtime"
```

---

## 3. 创建 GKE 集群

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
  --labels="env=prod,app=gloo-gateway,mesh=gloo" \
  --workload-pool=${GCP_PROJECT_ID}.svc.id.goog
```

> **关键标志说明**：
> - `--enable-ip-alias`：VPC-native 集群（推荐，便于 PSC 与多集群）
> - `--workload-pool`：启用 Workload Identity（可选但推荐）
> - `--enable-intra-node-visibility`：允许 Pod 直连（有助于调试与 east-west 流量）

---

## 4. 配置 kubectl 上下文

```bash
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}

kubectl cluster-info
# 确认 current-context 为 gke_${GCP_PROJECT_ID}_${GCP_REGION}_${GKE_CLUSTER_NAME}
```

---

## 5. 安装 Gloo Mesh 企业版（管理面）

### 5.1 安装 meshctl CLI

```bash
curl -sL https://run.solo.io/meshctl/install | sh
sudo mv $HOME/.gloo-mesh/bin/meshctl /usr/local/bin/
meshctl version  # 应显示 2.x
```

### 5.2 添加 Gloo Platform Helm 仓库

```bash
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm
helm repo update
```

### 5.3 创建命名空间

```bash
kubectl create namespace ${MGMT_NAMESPACE}
kubectl create namespace ${GATEWAY_NAMESPACE}
kubectl create namespace ${WORKLOAD_NAMESPACE}
kubectl create namespace istio-system
```

### 5.4 安装 Gloo Mesh 管理面（含 License）

```bash
helm install gloo-platform glooe/gloo-ee \
  --namespace ${MGMT_NAMESPACE} \
  --create-namespace \
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
  telemetryCollector:
    enabled: true
  glooUi:
    enabled: true
  istiod:
    enabled: true
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
```

> **注意**：确保 `license_key` 有效；安装过程可能需要几分钟，请耐心等待所有 Pod 处于 Running 状态。

### 5.5 验证管理面安装

```bash
kubectl get pods -n ${MGMT_NAMESPACE}
# 预期包含：gloo, gloo-agent, gloo-ui, gloo-telemetry-collector, istiod-xxx

meshctl check
# 应显示全部 OK
```

---

## 6. 安装并配置 Gloo Gateway（替代 ASM Ingress Gateway）

### 6.1 选择部署模式
- **方案 A（推荐生产）**：通过 Helm 安装，LoadBalancer 类型 Service
- **方案 B（快速验证）**：使用 glooctl install gateway enterprise（适用于 PoC）

这里使用 Helm 方案（与生产一致）：

```bash
helm install gloo-gateway glooe/gloo-gateway \
  --namespace ${GATEWAY_NAMESPACE} \
  --create-namespace \
  --version ${GLOO_EE_VERSION} \
  --set-string license_key="${LICENSE_KEY}" \
  --set glooGateway.gatewayProxies.gatewayProxy.service.type=LoadBalancer \
  --set glooGateway.gatewayProxies.gatewayProxy.service.annotations."service\.beta\.kubernetes\.io/gcp-load-balancer-type"="External" \
  --set glooGateway.gatewayProxies.gatewayProxy.deployment.replicas=2 \
  --wait --timeout 5m
```

### 6.2 验证 Gateway Pod

```bash
kubectl get pods -n ${GATEWAY_NAMESPACE}
# 预期：2 个 gloo-gateway + 1 个 istiod（若共享）或独立 istiod

kubectl get svc -n ${GATEWAY_NAMESPACE}
# 预期：gloo-gateway-proxy LoadBalancer，有一个外部 IP（可能需等待 1-3 分钟）
```

### 6.3 获取外部 IP

```bash
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway IP: ${GATEWAY_IP}"

# 若为空，等待并重试
while [ -z "${GATEWAY_IP}" ]; do
  echo "Waiting for LoadBalancer IP..."
  sleep 10
  export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
done
```

---

## 7. 在 GKE 中启用 Ambient（ztunnel）模式

Gloo Mesh 支持两种数据面模式：
- **Sidecar 模式**：传统，每个 Pod 注入 Envoy
- **Ambient 模式**：轻量，ztunnel 在节点级拦截流量

### 7.1 确认 GKE 版本与特性支持
- 需要 GKE 1.25+ 以获得最佳 ztunnel 支持
- 确保节点镜像包含 ztunnel（通常 GKE Standard 包含）

### 7.2 安装或配置 ztunnel（可选）
在 GKE 上，Ambient 模式通常由节点代理自动处理。若需自定义，可通过 DaemonSet 部署 ztunnel（参考 Gloo 文档）。

**简易示例（默认启用）**：
```bash
# 若使用标准 GKE + Gloo Mesh EE，Ambient 通常在集群注册时自动协商
# 可通过 MeshConfig 启用
cat <<EOF | kubectl apply -f -
apiVersion: mesh.gloo.solo.io/v1
kind: MeshConfig
metadata:
  name: default
  namespace: ${MGMT_NAMESPACE}
spec:
  ambient:
    enabled: true
  sidecar:
    autoInject: disabled  # 禁用自动 Sidecar 注入
EOF
```

> **提示**：若已存在 Sidecar 注入标签 `istio-injection=enabled`，建议在 workload 命名空间上移除，避免冲突。

---

## 8. 部署示例后端服务（HTTPbin 作为演示）

### 8.1 创建命名空间与部署

```bash
kubectl create namespace ${WORKLOAD_NAMESPACE} \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label namespace ${WORKLOAD_NAMESPACE} istio-injection=disabled --overwrite

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: ${WORKLOAD_NAMESPACE}
  labels:
    app: httpbin
spec:
  replicas: 2
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      containers:
      - name: httpbin
        image: kennethreitz/httpbin:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: ${WORKLOAD_NAMESPACE}
spec:
  selector:
    app: httpbin
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF
```

### 8.2 验证 Sidecar 未注入（Ambient 模式）

```bash
kubectl get pods -n ${WORKLOAD_NAMESPACE} -o jsonpath='{.items[0].spec.containers[*].name}'
# 应输出：httpbin（无 istio-proxy）
```

---

## 9. 创建 Gloo Mesh 上层路由资源

> 注意：Gloo Mesh 使用 `VirtualGateway`、`RouteTable`、`TrafficPolicy` 等 CRD 替代 Istio 的 Gateway、VirtualService、DestinationRule。

### 9.1 创建 Upstream（指向 K8s Service）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gloo.solo.io/v1
kind: Upstream
metadata:
  name: httpbin-upstream
  namespace: ${MGMT_NAMESPACE}
spec:
  kube:
    serviceName: httpbin
    serviceNamespace: ${WORKLOAD_NAMESPACE}
    servicePort: 80
EOF
```

### 9.2 创建 VirtualGateway（TLS 终止，与之前一致）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.gloo.solo.io/v2
kind: VirtualGateway
metadata:
  name: runtime-gateway
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
      number: 443
    tls:
      mode: SIMPLE
      secretName: wildcard-abjx-appdev-aibang-cert  # 替换为你的证书 Secret
    allowedRouteTables:
    - host: "*.abjx.appdev.aibang"
EOF
```

> **说明**：证书 Secret 应在 `gloo-gateway` 命名空间或通过引用方式存在。若使用与之前相同的证书，确保已创建或引用正确。

### 9.3 创建 RouteTable（路由规则）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.gloo.solo.io/v2
kind: RouteTable
metadata:
  name: httpbin-routes
  namespace: ${MGMT_NAMESPACE}
spec:
  hosts:
  - "*.abjx.appdev.aibang"
  virtualGateways:
  - name: runtime-gateway
    namespace: ${GATEWAY_NAMESPACE}
  http:
  - name: route-to-httpbin
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
```

### 9.4 可选：创建 TrafficPolicy（mTLS 与策略）

```bash
cat <<EOF | kubectl apply -f -
apiVersion: trafficcontrol.policy.gloo.solo.io/v2
kind: TrafficPolicy
metadata:
  name: httpbin-mtls-policy
  namespace: ${MGMT_NAMESPACE}
spec:
  applyToDestinations:
  - selector:
      name: httpbin-upstream
      namespace: ${MGMT_NAMESPACE}
  policy:
    tls:
      mode: SIMPLE
      sni: api1.abjx.appdev.aibang  # 保持业务域名为 SNI
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 100
        http2MaxRequests: 1000
    loadBalancer:
      roundRobin: {}
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
EOF
```

> **说明**：若未显式创建，流量仍可通行；上述策略用于强化安全与可靠性。

---

## 10. 验证端到端访问

### 10.1 获取网关 IP

```bash
export GATEWAY_IP=$(kubectl get svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Gateway IP: ${GATEWAY_IP}"
```

### 10.2 测试请求（使用 Host 头模拟域名）

```bash
# 若使用通配域证书，可尝试：
curl -v -H "Host: api1.abjx.appdev.aibang" https://${GATEWAY_IP}/get

# 或测试根路径
curl -v -H "Host: any.abjx.appdev.aibang" https://${GATEWAY_IP}/
```

### 10.3 预期结果
- 返回 JSON 响应，包含 `"url": "https://<upstream-ip>/get"` 等字段
- 响应头中包含 `X-Request-Id` 等 Envoy 注入头（确认流量经过 Gloo Gateway）
- TLS 握手成功，且证书的 SAN 覆盖请求域名

---

## 11. 排错与诊断

### 11.1 常见问题检查表
| 问题现象 | 检查命令 |
|----------|----------|
| 网关无外部 IP | `kubectl describe svc -n ${GATEWAY_NAMESPACE} gloo-gateway-proxy` |
| 404 路由不匹配 | `kubectl get routetable -n ${MGMT_NAMESPACE}` |
| mTLS 握手失败 | `kubectl logs -n ${MGMT_NAMESPACE} <gloo-pod> -c gloo` |
| Upstream 未就绪 | `kubectl get upstream -n ${MGMT_NAMESPACE}` |

### 11.2 诊断命令
```bash
# 查看 Gloo Gateway 日志
kubectl logs -n ${GATEWAY_NAMESPACE} -l app=gloo-gateway --tail=50 -f

# 查看 Gloo 控制面日志
kubectl logs -n ${MGMT_NAMESPACE} deployment/gloo --tail=50

# envoy admin dump（需 port-forward）
kubectl port-forward -n ${GATEWAY_NAMESPACE} <gateway-pod> 15000:15000 &
curl http://localhost:15000/clusters
```

---

## 12. 多集群扩展建议（未来）

- 使用 Gloo Mesh 的 `Workspace` 隔离不同团队/业务
- 通过 `Federation` 功能跨集群注册 Upstream
- 在 Secondary 集群注册相同的 VirtualGateway/RouteTable，实现流量切换或 DR

---

## 13. 清理与卸载

```bash
# 删除路由资源
kubectl delete routetable,upstream,virtualgateway -n ${MGMT_NAMESPACE}

# 删除工作负载命名空间（可选）
kubectl delete namespace ${WORKLOAD_NAMESPACE}

# 卸载 Gloo Gateway
helm uninstall gloo-gateway -n ${GATEWAY_NAMESPACE}
kubectl delete namespace ${GATEWAY_NAMESPACE}

# 卸载 Gloo Mesh（谨慎操作）
helm uninstall gloo-platform -n ${MGMT_NAMESPACE}
kubectl delete namespace ${MGMT_NAMESPACE}
```

---

## 14. 参考链接
- [Gloo Mesh 官方文档](https://docs.solo.io/gloo-mesh-enterprise/)
- [Gloo Gateway 文档](https://docs.solo.io/gloo-mesh-gateway/)
- [Istio 与 Gloo 对照表](https://docs.solo.io/gloo-mesh-enterprise/latest/reference/istio-resources-mapping/)
- [Ambient 模式概览](https://docs.solo.io/gloo-mesh-enterprise/latest/ambient/introduction/)

---

*文档版本：适用于 Gloo Mesh EE 2.x，GKE 1.25+*
*更新日期：2026-04-17*