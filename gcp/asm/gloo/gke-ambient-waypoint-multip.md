# GKE Ambient + Waypoint 多集群企业版实施版

> 适用场景：**一个管理集群 + 两个及以上 GKE workload 集群**，采用 **企业版 License**，目标是形成后续可扩展的多集群 ambient mesh 基线。

---

## 1. Goal and Constraints

### 目标
- 在多个 GKE 集群之间建立 ambient mesh
- 使用企业版能力完成多集群联邦
- 入口仍可保留你现有 `GLB / Cloud Armor / PSC / Nginx` 架构
- 为后续跨集群服务发现、东西向治理、统一观测做准备

### 约束
- 一个 **management cluster**
- 两个或以上 **workload clusters**
- workload cluster 运行 ambient mesh
- multicluster ambient 需要企业版许可

### 复杂度
- `Advanced`

---

## 2. Recommended Architecture (V1)

```text
Management Cluster
  |- gloo-platform management plane
  |- relay / telemetry / UI

Workload Cluster A
  |- istiod
  |- istio-cni
  |- ztunnel
  |- east-west gateway
  |- waypoint
  |- app pods

Workload Cluster B
  |- istiod
  |- istio-cni
  |- ztunnel
  |- east-west gateway
  |- waypoint
  |- app pods
```

### V1 原则
- 管理面和 workload 面分离
- 每个 workload cluster 独立安装 ambient 组件
- 每个 cluster 保留 east-west gateway
- 先完成 cluster link，再做跨集群路由

---

## 3. Trade-offs and Alternatives

### 推荐方案
**Dedicated management cluster + multicluster ambient**

优点：
- 故障域更清晰
- 管理面不与业务抢资源
- 后续扩第三个、第四个集群更自然

代价：
- 证书、连通性、版本矩阵更复杂
- 升级顺序要受控

### 不建议
- 把管理面放在某个关键业务集群里长期承载多集群治理
- 没做 east-west gateway 就直接期待跨集群 ambient 自动互通

---

## 4. 实施前的环境规划

## 4.1 集群命名

```bash
export GCP_PROJECT_ID="your-project"
export GCP_REGION="us-central1"

export MGMT_CLUSTER="gloo-mgmt-prod"
export REMOTE_CLUSTER1="ambient-workload-a"
export REMOTE_CLUSTER2="ambient-workload-b"

export MGMT_CONTEXT="gke_${GCP_PROJECT_ID}_${GCP_REGION}_${MGMT_CLUSTER}"
export REMOTE_CONTEXT1="gke_${GCP_PROJECT_ID}_${GCP_REGION}_${REMOTE_CLUSTER1}"
export REMOTE_CONTEXT2="gke_${GCP_PROJECT_ID}_${GCP_REGION}_${REMOTE_CLUSTER2}"
```

## 4.2 版本变量

```bash
export GLOO_VERSION="2.13.0"
export GLOO_MESH_LICENSE_KEY="<your-enterprise-license>"

export ISTIO_VERSION="1.27.0"
export ISTIO_IMAGE="${ISTIO_VERSION}-solo"
export REPO_KEY="<solo-repo-key>"
export REPO="us-docker.pkg.dev/gloo-mesh/istio-${REPO_KEY}"
export HELM_REPO="us-docker.pkg.dev/gloo-mesh/istio-helm-${REPO_KEY}"

export MGMT_NAMESPACE="gloo-mesh"
export ISTIO_NAMESPACE="istio-system"
```

---

## 5. Implementation Steps

## 5.1 创建三个集群

### 管理集群

```bash
gcloud container clusters create ${MGMT_CLUSTER} \
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
```

### workload 集群

```bash
for CLUSTER in ${REMOTE_CLUSTER1} ${REMOTE_CLUSTER2}; do
  gcloud container clusters create ${CLUSTER} \
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
done
```

---

## 5.2 安装 Gloo 管理面到 management cluster

```bash
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

helm upgrade -i gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace=${MGMT_NAMESPACE} \
  --create-namespace \
  --version=${GLOO_VERSION} \
  --kube-context ${MGMT_CONTEXT}

curl https://storage.googleapis.com/gloo-platform/helm-profiles/${GLOO_VERSION}/mgmt-server.yaml > /tmp/mgmt-plane.yaml

helm upgrade -i gloo-platform gloo-platform/gloo-platform \
  --namespace=${MGMT_NAMESPACE} \
  --version=${GLOO_VERSION} \
  --kube-context ${MGMT_CONTEXT} \
  --values /tmp/mgmt-plane.yaml \
  --set common.cluster=${MGMT_CLUSTER} \
  --set licensing.glooMeshLicenseKey=${GLOO_MESH_LICENSE_KEY}
```

### 生产要求
- relay / telemetry 用 BYO cert
- 管理集群建议独立 node pool 承载管理面

---

## 5.3 在 workload 集群安装 Gloo agent

### CRDs

```bash
for CTX in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}; do
  helm upgrade -i gloo-platform-crds gloo-platform/gloo-platform-crds \
    --namespace=${MGMT_NAMESPACE} \
    --create-namespace \
    --version=${GLOO_VERSION} \
    --kube-context ${CTX} \
    --set installIstioOperator=false
done
```

### agent profile

```bash
curl https://storage.googleapis.com/gloo-platform/helm-profiles/${GLOO_VERSION}/agent.yaml > /tmp/data-plane.yaml
```

### 安装 agent

> 这里的 `glooAgent.relay.serverAddress` 和 telemetry endpoint 需要替换成你 management plane 可达地址。

```bash
helm upgrade -i gloo-platform gloo-platform/gloo-platform \
  --namespace ${MGMT_NAMESPACE} \
  --kube-context ${REMOTE_CONTEXT1} \
  --version ${GLOO_VERSION} \
  --values /tmp/data-plane.yaml \
  --set common.cluster=${REMOTE_CLUSTER1} \
  --set glooAgent.relay.serverAddress=<mgmt-server-address> \
  --set telemetryCollector.config.exporters.otlp.endpoint=<telemetry-gateway-address>

helm upgrade -i gloo-platform gloo-platform/gloo-platform \
  --namespace ${MGMT_NAMESPACE} \
  --kube-context ${REMOTE_CONTEXT2} \
  --version ${GLOO_VERSION} \
  --values /tmp/data-plane.yaml \
  --set common.cluster=${REMOTE_CLUSTER2} \
  --set glooAgent.relay.serverAddress=<mgmt-server-address> \
  --set telemetryCollector.config.exporters.otlp.endpoint=<telemetry-gateway-address>
```

---

## 5.4 安装 Gateway API CRD 到所有 workload 集群

```bash
for CTX in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}; do
  kubectl --context ${CTX} apply --server-side -f \
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
done
```

---

## 5.5 在每个 workload 集群安装 ambient 组件

### base

```bash
for CTX in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}; do
  helm upgrade --install istio-base oci://${HELM_REPO}/base \
    --namespace ${ISTIO_NAMESPACE} \
    --create-namespace \
    --kube-context ${CTX} \
    --version ${ISTIO_IMAGE} \
    -f - <<EOF
defaultRevision: ""
profile: ambient
EOF
done
```

### istiod

```bash
for CTX in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}; do
  helm upgrade --install istiod oci://${HELM_REPO}/istiod \
    --namespace ${ISTIO_NAMESPACE} \
    --kube-context ${CTX} \
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
license:
  value: ${GLOO_MESH_LICENSE_KEY}
EOF
done
```

### istio-cni

```bash
for CTX in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}; do
  helm upgrade --install istio-cni oci://${HELM_REPO}/cni \
    --namespace ${ISTIO_NAMESPACE} \
    --kube-context ${CTX} \
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
done
```

### ztunnel

```bash
for CTX in ${REMOTE_CONTEXT1} ${REMOTE_CONTEXT2}; do
  helm upgrade --install ztunnel oci://${HELM_REPO}/ztunnel \
    --namespace ${ISTIO_NAMESPACE} \
    --kube-context ${CTX} \
    --version ${ISTIO_IMAGE} \
    -f - <<EOF
configValidation: true
enabled: true
env:
  L7_ENABLED: "true"
  SKIP_VALIDATE_TRUST_DOMAIN: "true"
hub: ${REPO}
istioNamespace: ${ISTIO_NAMESPACE}
multiCluster:
  clusterName: ${CTX}
namespace: ${ISTIO_NAMESPACE}
profile: ambient
proxy:
  clusterDomain: cluster.local
tag: ${ISTIO_IMAGE}
terminationGracePeriodSeconds: 29
variant: distroless
EOF
done
```

> 注意：多集群时 `SKIP_VALIDATE_TRUST_DOMAIN`、shared root of trust、以及 clusterName 的实际值要和你的 trust domain 设计一致，不能盲目照抄。

---

## 5.6 创建 east-west gateway

### 原则
- 每个 workload cluster 都要有自己的 east-west gateway
- 它是跨集群 ambient 通信的必要基础设施之一

### 建议
- 直接按 Solo multicluster ambient 官方步骤部署
- 不建议在这里自行发明一套 east-west yaml

---

## 5.7 链接多个 ambient mesh

### 目标
- 建立 cluster 间 control-plane / discovery / peering 关系

### 路径
- 使用 Solo 官方 multicluster ambient 流程
- 先完成：
  1. shared root of trust
  2. east-west gateway
  3. cluster link / peering

---

## 5.8 接入业务命名空间与 waypoint

以 `team-a-runtime` 为例，在两个 workload cluster 都做：

```bash
kubectl --context ${REMOTE_CONTEXT1} create namespace team-a-runtime
kubectl --context ${REMOTE_CONTEXT1} label namespace team-a-runtime istio.io/dataplane-mode=ambient --overwrite
istioctl --context ${REMOTE_CONTEXT1} waypoint apply -n team-a-runtime --enroll-namespace

kubectl --context ${REMOTE_CONTEXT2} create namespace team-a-runtime
kubectl --context ${REMOTE_CONTEXT2} label namespace team-a-runtime istio.io/dataplane-mode=ambient --overwrite
istioctl --context ${REMOTE_CONTEXT2} waypoint apply -n team-a-runtime --enroll-namespace
```

---

## 5.9 多集群入口建议

### 推荐做法
- 入口仍放在一个主 ingress 集群
- 通过 Gloo Gateway / kgateway 暴露对外入口
- 外部仍由：
  - GLB
  - Cloud Armor
  - PSC / Nginx
  管理

### 不建议
- 让每个 workload cluster 都独立暴露公网入口，再靠 DNS 乱拼
- 没有统一入口就直接把多集群 ambient 暴露给上游调用方

---

## 6. Validation and Rollback

## 6.1 管理面验证

```bash
kubectl --context ${MGMT_CONTEXT} get pods -n ${MGMT_NAMESPACE}
meshctl check --kubecontext ${MGMT_CONTEXT}
```

## 6.2 workload cluster 验证

```bash
kubectl --context ${REMOTE_CONTEXT1} get pods -n ${ISTIO_NAMESPACE}
kubectl --context ${REMOTE_CONTEXT1} get ds -n ${ISTIO_NAMESPACE} ztunnel
kubectl --context ${REMOTE_CONTEXT1} get ns -L istio.io/dataplane-mode,istio.io/use-waypoint

kubectl --context ${REMOTE_CONTEXT2} get pods -n ${ISTIO_NAMESPACE}
kubectl --context ${REMOTE_CONTEXT2} get ds -n ${ISTIO_NAMESPACE} ztunnel
kubectl --context ${REMOTE_CONTEXT2} get ns -L istio.io/dataplane-mode,istio.io/use-waypoint
```

## 6.3 多集群特有验证

- management plane 能看到所有 agent
- 两个 cluster 的 east-west gateway 已就绪
- cluster 间服务发现正常
- waypoint 只在需要 L7 的 namespace 上启用

## 6.4 回滚顺序

1. 先撤业务 namespace 的 `use-waypoint`
2. 再撤 `dataplane-mode=ambient`
3. 再撤跨集群 peering
4. 再卸载 east-west gateway
5. 最后卸载 ambient 组件

---

## 7. Reliability and Cost Optimizations

### 高可用
- management cluster 独立
- 每个 workload cluster 至少 3 节点
- `istiod`、waypoint、gateway 至少 2 副本

### 成本
- 不要所有 namespace 都启 waypoint
- 只给需要 L7 policy / tracing / metrics 的业务开启

### 安全
- 所有 cluster 共用受控 root of trust
- relay / telemetry 走 BYO TLS
- 东西向链路明确 trust domain 策略

---

## 8. Handoff Checklist

- [ ] management cluster 已独立部署
- [ ] workload clusters 已创建
- [ ] `gloo-platform` 管理面已安装
- [ ] 所有 workload cluster 的 agent 已注册
- [ ] 所有 workload cluster 已安装 `istiod / istio-cni / ztunnel`
- [ ] east-west gateway 已部署
- [ ] shared root of trust 已配置
- [ ] cluster peering / link 已完成
- [ ] 业务 namespace 已 enroll ambient
- [ ] waypoint 已按需启用

