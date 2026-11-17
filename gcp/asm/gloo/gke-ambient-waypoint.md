# GKE Ambient + Waypoint 安装与校正文档（企业版可用）

> 结论先说：**这条路径在你的 GKE 企业版环境里是可行的**。  
> 但原文把 **Gloo Platform APIs / Gloo Mesh Gateway CRD** 和 **Ambient 所要求的 Istio Ambient + Kubernetes Gateway API** 混用了，**不能原样照装**。  
> 我已经按当前更稳妥的生产路径重写为一份可执行版本。

---

## 1. Goal and Constraints

### 目标
- 在 GKE 上部署 **Ambient Mesh（ztunnel + Waypoint）**
- 使用 **企业版能力**，支持后续多集群扩展
- 保留你现有的外部入口思路：`GLB / Cloud Armor / PSC / Nginx` 不强制重构
- Mesh 层优先采用 **Gloo 管理平面 + Solo Enterprise for Istio**

### 结论
- **可行**：GKE Standard + 企业版 License + Ambient + Waypoint 没问题
- **推荐实现方式**：
  1. 用 `gloo-platform` 安装管理面
  2. 用 **Solo distribution of Istio** 安装 ambient 组件
  3. 用 **Kubernetes Gateway API** 和 `istio-waypoint` 部署 waypoint
- **不建议**：用 `RouteTable / VirtualGateway / Waypoint(kind)` 作为 ambient 的主配置模型

### 复杂度
- 单集群：`Moderate`
- 多集群联邦：`Advanced`

---

## 2. 推荐架构（V1）

```text
Internet
  |
  v
GCP External Load Balancer + Cloud Armor
  |
  v
Ingress Gateway (Gloo Gateway / kgateway, optional)
  |
  v
Ambient Mesh
  |- istiod
  |- istio-cni
  |- ztunnel (DaemonSet)
  |- waypoint (Gateway API, per namespace / per service)
  |
  v
Application Pods (no sidecar)
```

### 控制面拆分
- **Gloo management plane**：负责管理、洞察、多集群联邦能力
- **Solo Enterprise for Istio**：负责 ambient mesh 本身
- **Gateway API**：负责 ambient 下的 waypoint 与入口路由

### 为什么这是 V1
- 贴近 Solo 官方当前文档
- 不把 ambient 和旧式 sidecar/gateway CRD 体系混装
- 后续扩成多集群时，不需要推翻单集群做法

---

## 3. 原文的关键问题

### 可以保留的判断
- “企业版可以在 GKE 上跑 ambient + waypoint”  
  这个判断是对的。
- “后续可以做多集群”  
  这个方向也是对的。

### 必须修正的地方
1. **安装管理面 chart 错了**
   - 原文用了 `glooe/gloo-ee`
   - 现在更稳妥的管理面安装路径是 `gloo-platform/gloo-platform`

2. **ambient 不是通过 `MeshConfig ambient.enabled` 这样启用**
   - ambient 的核心组件是 `istiod + istio-cni + ztunnel`
   - 需要按 Solo / Istio 的 ambient 安装路径部署

3. **waypoint 资源模型写错了**
   - 原文写成了自定义 `kind: Waypoint`
   - 正确做法是使用 **Gateway API 的 `Gateway`**，`gatewayClassName: istio-waypoint`

4. **ambient 加入方式写错了**
   - 原文通过“禁用 sidecar 注入”来表达 ambient
   - 正确做法是给 namespace 打标签：`istio.io/dataplane-mode=ambient`

5. **路由模型混用了两套体系**
   - 原文后半段使用 `Upstream / VirtualGateway / RouteTable / TrafficPolicy / AccessPolicy`
   - 这些更偏 Gloo Gateway / Gloo Mesh Gateway 侧能力
   - ambient 主路径下，**应优先使用 Gateway API / HTTPRoute / waypoint**

6. **GKE 节点 OS 判断不对**
   - 原文说“非 COS”
   - GKE 官方当前仍把 `cos_containerd` 作为推荐节点 OS；不能把 COS 写成不推荐

---

## 4. Trade-offs and Alternatives

### 推荐方案
**Gloo management plane + Solo Enterprise for Istio ambient + Gateway API**

优点：
- 和官方 ambient 路径一致
- 升级路径清晰
- 后续多集群能力自然衔接
- 不需要 sidecar 注入

代价：
- 需要理解 `Gateway API` 与传统 `VirtualService` 的差别
- 入口网关与 mesh 路由边界要明确

### 可选方案 A
**继续 sidecar 模式**

适合：
- 你已有大量 `VirtualService / DestinationRule / AuthorizationPolicy`
- 现网不想动流量模型

不适合：
- 目标是降低 sidecar 成本
- 目标是未来做 ambient 标准化

### 可选方案 B
**只上 ambient，不接 Gloo 管理面**

适合：
- 纯单集群 PoC

问题：
- 少了多集群治理、洞察、企业支撑

---

## 5. 实施步骤

## 5.1 环境变量

```bash
export GCP_PROJECT_ID="your-project"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="ambient-prod-1"

export GLOO_VERSION="2.13.0"
export GLOO_MESH_LICENSE_KEY="<your-enterprise-license>"

export MGMT_CLUSTER="${GKE_CLUSTER_NAME}"
export MGMT_CONTEXT="gke_${GCP_PROJECT_ID}_${GCP_REGION}_${GKE_CLUSTER_NAME}"

export ISTIO_VERSION="1.27.0"
export ISTIO_IMAGE="${ISTIO_VERSION}-solo"
export REPO_KEY="<solo-repo-key>"
export REPO="us-docker.pkg.dev/gloo-mesh/istio-${REPO_KEY}"
export HELM_REPO="us-docker.pkg.dev/gloo-mesh/istio-helm-${REPO_KEY}"

export MGMT_NAMESPACE="gloo-mesh"
export ISTIO_NAMESPACE="istio-system"
export APP_NAMESPACE="team-a-runtime"
```

说明：
- `GLOO_VERSION`、`ISTIO_VERSION` 必须按你当前企业版支持矩阵选，不要再写死 `2.1.0`
- 这份文档按 **2026-04-25** 的仓库校正，建议实际安装前再对一次企业订阅版本

---

## 5.2 创建 GKE 集群

```bash
gcloud container clusters create ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION} \
  --release-channel=regular \
  --machine-type=e2-standard-4 \
  --num-nodes=3 \
  --enable-autoscaling \
  --min-nodes=3 \
  --max-nodes=6 \
  --enable-autoupgrade \
  --enable-autorepair \
  --enable-ip-alias \
  --workload-pool=${GCP_PROJECT_ID}.svc.id.goog

gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} \
  --project=${GCP_PROJECT_ID} \
  --location=${GCP_REGION}
```

### GKE 侧建议
- 模式：`GKE Standard`
- 节点 OS：优先默认 `cos_containerd`
- 节点池至少 3 个节点，避免 waypoint / ztunnel / istiod 和业务争抢

### 验证

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl config current-context
```

---

## 5.3 安装 Gloo 管理面

### 1) 添加 Helm 仓库

```bash
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update
```

### 2) 安装 CRDs

```bash
helm upgrade -i gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace=${MGMT_NAMESPACE} \
  --create-namespace \
  --version=${GLOO_VERSION} \
  --kube-context ${MGMT_CONTEXT}
```

### 3) 生成管理面 profile

```bash
curl https://storage.googleapis.com/gloo-platform/helm-profiles/${GLOO_VERSION}/mgmt-server.yaml > /tmp/mgmt-plane.yaml
```

### 4) 安装管理面

```bash
helm upgrade -i gloo-platform gloo-platform/gloo-platform \
  --namespace=${MGMT_NAMESPACE} \
  --version=${GLOO_VERSION} \
  --values /tmp/mgmt-plane.yaml \
  --set common.cluster=${MGMT_CLUSTER} \
  --set licensing.glooMeshLicenseKey=${GLOO_MESH_LICENSE_KEY}
```

### 5) 验证

```bash
kubectl get pods -n ${MGMT_NAMESPACE}
meshctl check --kubecontext ${MGMT_CONTEXT}
```

### 生产建议
- relay 连接使用 **BYO mTLS 证书**
- 不建议生产直接用 self-signed

---

## 5.4 安装 Ambient 所需 Gateway API CRD

```bash
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

### 验证

```bash
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get crd httproutes.gateway.networking.k8s.io
```

---

## 5.5 安装 Solo Enterprise for Istio Ambient 组件

### 1) `base`

```bash
helm upgrade --install istio-base oci://${HELM_REPO}/base \
  --namespace ${ISTIO_NAMESPACE} \
  --create-namespace \
  --version ${ISTIO_IMAGE} \
  -f - <<EOF
defaultRevision: ""
profile: ambient
EOF
```

### 2) `istiod`

```bash
helm upgrade --install istiod oci://${HELM_REPO}/istiod \
  --namespace ${ISTIO_NAMESPACE} \
  --version ${ISTIO_IMAGE} \
  -f - <<EOF
global:
  hub: ${REPO}
  tag: ${ISTIO_IMAGE}
  proxy:
    clusterDomain: cluster.local
pilot:
  cni:
    enabled: true
    namespace: ${ISTIO_NAMESPACE}
meshConfig:
  accessLogFile: /dev/stdout
  defaultConfig:
    proxyMetadata:
      ISTIO_META_DNS_AUTO_ALLOCATE: "true"
license:
  value: ${GLOO_MESH_LICENSE_KEY}
EOF
```

### 3) `istio-cni`

```bash
helm upgrade --install istio-cni oci://${HELM_REPO}/cni \
  --namespace ${ISTIO_NAMESPACE} \
  --version ${ISTIO_IMAGE} \
  -f - <<EOF
ambient:
  dnsCapture: true
excludeNamespaces:
  - ${ISTIO_NAMESPACE}
  - kube-system
global:
  hub: ${REPO}
  tag: ${ISTIO_IMAGE}
profile: ambient
EOF
```

### 4) `ztunnel`

```bash
helm upgrade --install ztunnel oci://${HELM_REPO}/ztunnel \
  --namespace ${ISTIO_NAMESPACE} \
  --version ${ISTIO_IMAGE} \
  -f - <<EOF
configValidation: true
enabled: true
env:
  L7_ENABLED: "true"
hub: ${REPO}
istioNamespace: ${ISTIO_NAMESPACE}
namespace: ${ISTIO_NAMESPACE}
profile: ambient
proxy:
  clusterDomain: cluster.local
tag: ${ISTIO_IMAGE}
terminationGracePeriodSeconds: 29
variant: distroless
EOF
```

### 验证

```bash
kubectl get pods -n ${ISTIO_NAMESPACE}
kubectl get ds -n ${ISTIO_NAMESPACE} ztunnel
```

预期：
- `istiod` Running
- `istio-cni-*` Running
- `ztunnel` 为每节点一个 Pod

---

## 5.6 把命名空间加入 Ambient

```bash
kubectl create namespace ${APP_NAMESPACE}

kubectl label namespace ${APP_NAMESPACE} \
  istio.io/dataplane-mode=ambient --overwrite
```

### 验证

```bash
kubectl get ns ${APP_NAMESPACE} --show-labels
```

**注意**
- 这里不是靠 `istio-injection=disabled` 来表达 ambient
- `ambient` 的正确加入方式是 `istio.io/dataplane-mode=ambient`

---

## 5.7 部署 Waypoint

### 推荐方式
用 `istioctl waypoint apply`，或者直接下发 `Gateway API`

### 方式 A：用 `istioctl`

```bash
istioctl waypoint apply -n ${APP_NAMESPACE} --enroll-namespace
```

这条命令会：
- 创建 waypoint
- 给 namespace 打上 `istio.io/use-waypoint=waypoint`

### 方式 B：显式创建 Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: waypoint
  namespace: team-a-runtime
  labels:
    istio.io/waypoint-for: service
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
```

应用：

```bash
kubectl apply -f waypoint.yaml
kubectl label namespace ${APP_NAMESPACE} istio.io/use-waypoint=waypoint --overwrite
```

### 验证

```bash
kubectl get gateway -n ${APP_NAMESPACE}
kubectl get deploy,svc -n ${APP_NAMESPACE} | grep waypoint
```

---

## 5.8 部署测试应用

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: team-a-runtime
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
          name: http
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: team-a-runtime
spec:
  selector:
    app: httpbin
  ports:
  - name: http
    port: 80
    targetPort: 80
```

应用后验证：

```bash
kubectl get pods -n ${APP_NAMESPACE}
kubectl get pod -n ${APP_NAMESPACE} -l app=httpbin \
  -o jsonpath='{.items[0].spec.containers[*].name}'
```

预期：
- Pod 只有业务容器
- **没有 `istio-proxy` sidecar**

---

## 5.9 Ingress 与路由建议

### 关键原则
- Ambient 下，**入口和网格内部路由要分层**
- 外部入口可以继续用：
  - GCP GLB + Cloud Armor
  - Gloo Gateway / kgateway
  - 你现有 Nginx / PSC 结构

### Ambient 内部优先路由模型
- `Gateway`
- `HTTPRoute`
- `ReferenceGrant`（跨命名空间时）
- Waypoint 负责 L7 处理

### 不建议作为 ambient 主路径的资源
- `VirtualGateway`
- `RouteTable`
- `Upstream`
- `TrafficPolicy`
- 自定义 `Waypoint` 资源

这些资源不是完全不能用，但**不应该作为 ambient 安装闭环的基础文档**。

---

## 6. Validation and Rollback

## 6.1 安装完成后的最小验证

```bash
kubectl get pods -n ${MGMT_NAMESPACE}
kubectl get pods -n ${ISTIO_NAMESPACE}
kubectl get ds -n ${ISTIO_NAMESPACE} ztunnel
kubectl get gateway -n ${APP_NAMESPACE}
meshctl check --kubecontext ${MGMT_CONTEXT}
```

## 6.2 Ambient 验证

```bash
kubectl get ns -L istio.io/dataplane-mode,istio.io/use-waypoint
kubectl get pods -n ${APP_NAMESPACE}
```

看点：
- namespace 带 `istio.io/dataplane-mode=ambient`
- namespace 或 service 带 `istio.io/use-waypoint`
- workload 无 sidecar

## 6.3 回滚策略

### 仅回滚 waypoint
```bash
kubectl label namespace ${APP_NAMESPACE} istio.io/use-waypoint-
kubectl delete gateway waypoint -n ${APP_NAMESPACE}
```

### 退出 ambient
```bash
kubectl label namespace ${APP_NAMESPACE} istio.io/dataplane-mode-
```

### 卸载 ambient 组件
```bash
helm uninstall ztunnel -n ${ISTIO_NAMESPACE}
helm uninstall istio-cni -n ${ISTIO_NAMESPACE}
helm uninstall istiod -n ${ISTIO_NAMESPACE}
helm uninstall istio-base -n ${ISTIO_NAMESPACE}
```

### 卸载 Gloo 管理面
```bash
helm uninstall gloo-platform -n ${MGMT_NAMESPACE}
helm uninstall gloo-platform-crds -n ${MGMT_NAMESPACE}
```

---

## 7. Reliability and Cost Optimizations

### 高可用
- 节点数至少 3
- `istiod` 至少 2 副本
- 业务 waypoint 建议 2 副本
- 节点池跨 zone

### 零停机
- waypoint 滚动升级前先看 PDB
- ztunnel 升级会影响长连接，安排维护窗口
- ingress gateway 和 waypoint 不要同时做大版本升级

### 成本
- ambient 的核心价值就是去掉 sidecar 常驻成本
- waypoint 只对需要 L7 的 namespace / service 开
- 不要“全命名空间一刀切”启用 waypoint，除非你真的需要 L7 观测和策略

### 安全
- 管理面 relay 用 BYO mTLS
- 工作负载身份统一走 SPIFFE/SPIRE 或 Solo 支持路径
- 外围仍建议保留 Cloud Armor / WAF，不要把入口防护完全压到 mesh 内

---

## 8. Handoff Checklist

- [ ] GKE Standard 集群已创建并启用 Workload Identity
- [ ] `gloo-platform-crds` 与 `gloo-platform` 已安装
- [ ] Gateway API CRD 已安装
- [ ] `istiod / istio-cni / ztunnel` 已运行
- [ ] 目标 namespace 已加 `istio.io/dataplane-mode=ambient`
- [ ] waypoint 已通过 `Gateway` 或 `istioctl waypoint apply` 创建
- [ ] 测试服务已接入且无 sidecar
- [ ] `meshctl check` 通过
- [ ] 已定义回滚步骤

---

## 9. 本次修正点总结

### 你最关心的结论
- **企业版 GKE 上安装 ambient + waypoint 没问题**
- **原文不适合直接执行**
- **我已经把它改成适合 GKE 企业版的版本**

### 区别点在哪里
1. **管理面安装路径改了**
   - 从 `glooe/gloo-ee`
   - 改成 `gloo-platform/gloo-platform`

2. **ambient 启用方式改了**
   - 不再写 `MeshConfig ambient.enabled`
   - 改成实际安装 `istiod + istio-cni + ztunnel`

3. **waypoint 资源改了**
   - 不再用 `kind: Waypoint`
   - 改成 `Gateway API + gatewayClassName: istio-waypoint`

4. **工作负载加入方式改了**
   - 不再靠“禁用 sidecar 注入”表达 ambient
   - 改成 `istio.io/dataplane-mode=ambient`

5. **路由模型改了**
   - 不再把 `RouteTable / VirtualGateway / Upstream` 当 ambient 主路径
   - 改成 `Gateway / HTTPRoute / waypoint`

6. **GKE 节点 OS 描述改了**
   - 删除“非 COS”这种错误前提
   - 改成遵循 GKE 官方推荐

---

## 10. 参考

- [Solo Enterprise for Istio ambient install](https://docs.solo.io/gloo-mesh/main/ambient/setup/install/manual/)
- [Solo multicluster ambient requirements](https://docs.solo.io/gloo-mesh/latest/ambient/setup/multicluster/default/manual/)
- [Gloo management plane install](https://docs.solo.io/gloo-mesh-enterprise/main/setup/install/enterprise_installation/)
- [Gloo Platform CRD note for ambient](https://docs.solo.io/gloo-mesh-enterprise/main/reference/helm/gloo_platform_crds_helm_values_reference/)
- [Istio waypoint configuration](https://istio.io/latest/docs/ambient/usage/waypoint/)
- [GKE node images](https://cloud.google.com/kubernetes-engine/docs/concepts/node-images)
