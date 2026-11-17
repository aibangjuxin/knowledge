# GKE Ambient + Waypoint 单集群生产安装版

> 适用场景：**单个 GKE Standard 集群**，采用 **企业版 License + Gloo 管理面 + Solo Enterprise for Istio Ambient**，目标是形成一个可生产落地、可验证、可回滚的安装基线。

---

## 1. Goal and Constraints

### 目标
- 在单个 GKE 集群中部署 ambient mesh
- 工作负载不注入 sidecar
- 通过 waypoint 为选定命名空间提供 L7 能力
- 为后续接入 Gloo Gateway / kgateway、GLB、Cloud Armor 预留入口能力

### 约束
- 集群模式：`GKE Standard`
- 生产环境默认启用：
  - Workload Identity
  - VPC-native (`--enable-ip-alias`)
  - 节点自动修复 / 自动升级
- 管理面与 ambient 组件都部署在同一集群

### 复杂度
- `Moderate`

---

## 2. Recommended Architecture (V1)

```text
Internet
  |
  v
GLB / Cloud Armor / External Gateway (optional)
  |
  v
Single GKE Cluster
  |- gloo-platform management plane
  |- istiod
  |- istio-cni
  |- ztunnel
  |- waypoint (per namespace / per service)
  |- app pods (no sidecar)
```

### V1 原则
- 单集群先不引入跨集群 east-west gateway
- 入口和 mesh 内部治理分层
- ambient 内部优先用 `Gateway API`

---

## 3. Trade-offs and Alternatives

### 推荐方案
**单集群 Gloo 管理面 + Solo ambient**

优点：
- 安装路径最短
- 便于验证 ambient 行为
- 后续迁移多集群时可复用大部分做法

代价：
- 管理面和数据面共集群，故障域未彻底隔离

### 可选方案
**继续 sidecar**

适合：
- 你已有大量 Sidecar / VirtualService 资产

不适合：
- 想先把资源成本和升级成本降下来

---

## 4. Implementation Steps

## 4.1 环境变量

```bash
export GCP_PROJECT_ID="your-project"
export GCP_REGION="us-central1"
export GKE_CLUSTER_NAME="ambient-single-prod"

export GLOO_VERSION="2.13.0"
export GLOO_MESH_LICENSE_KEY="<your-enterprise-license>"

export CLUSTER_NAME="${GKE_CLUSTER_NAME}"
export CLUSTER_CONTEXT="gke_${GCP_PROJECT_ID}_${GCP_REGION}_${GKE_CLUSTER_NAME}"

export ISTIO_VERSION="1.27.0"
export ISTIO_IMAGE="${ISTIO_VERSION}-solo"
export REPO_KEY="<solo-repo-key>"
export REPO="us-docker.pkg.dev/gloo-mesh/istio-${REPO_KEY}"
export HELM_REPO="us-docker.pkg.dev/gloo-mesh/istio-helm-${REPO_KEY}"

export MGMT_NAMESPACE="gloo-mesh"
export ISTIO_NAMESPACE="istio-system"
export APP_NAMESPACE="team-a-runtime"
```

---

## 4.2 创建 GKE 集群

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

### 生产建议
- 节点池至少 3 个节点
- 节点 OS 保持默认 `cos_containerd`
- 若后续要跑 gateway，可单独加一个 infra node pool

---

## 4.3 安装 Gloo 管理面

```bash
helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
helm repo update

helm upgrade -i gloo-platform-crds gloo-platform/gloo-platform-crds \
  --namespace=${MGMT_NAMESPACE} \
  --create-namespace \
  --version=${GLOO_VERSION}

curl https://storage.googleapis.com/gloo-platform/helm-profiles/${GLOO_VERSION}/mgmt-server.yaml > /tmp/mgmt-plane.yaml

helm upgrade -i gloo-platform gloo-platform/gloo-platform \
  --namespace=${MGMT_NAMESPACE} \
  --version=${GLOO_VERSION} \
  --values /tmp/mgmt-plane.yaml \
  --set common.cluster=${CLUSTER_NAME} \
  --set licensing.glooMeshLicenseKey=${GLOO_MESH_LICENSE_KEY}
```

### 生产要求
- relay 用 BYO mTLS 证书
- UI 开启 OIDC / RBAC
- 不建议生产使用 self-signed relay cert

---

## 4.4 安装 Gateway API CRD

```bash
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

---

## 4.5 安装 Ambient 组件

### base

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

### istiod

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

### istio-cni

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

### ztunnel

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

---

## 4.6 加入业务命名空间

```bash
kubectl create namespace ${APP_NAMESPACE}

kubectl label namespace ${APP_NAMESPACE} \
  istio.io/dataplane-mode=ambient --overwrite
```

---

## 4.7 部署 Waypoint

### 推荐

```bash
istioctl waypoint apply -n ${APP_NAMESPACE} --enroll-namespace
```

### 等价 Gateway API 方式

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

---

## 4.8 部署验证应用

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
        - name: http
          containerPort: 80
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

---

## 5. Validation and Rollback

## 5.1 最小验证

```bash
kubectl get pods -n ${MGMT_NAMESPACE}
kubectl get pods -n ${ISTIO_NAMESPACE}
kubectl get ds -n ${ISTIO_NAMESPACE} ztunnel
kubectl get ns -L istio.io/dataplane-mode,istio.io/use-waypoint
kubectl get gateway -n ${APP_NAMESPACE}
kubectl get pods -n ${APP_NAMESPACE}
meshctl check --kubecontext ${CLUSTER_CONTEXT}
```

### 验证点
- `ztunnel` 为每节点一个 Pod
- app pod 无 `istio-proxy`
- namespace 已 enroll 到 ambient
- waypoint deployment / service 已生成

## 5.2 回滚

### 回滚 waypoint
```bash
kubectl label namespace ${APP_NAMESPACE} istio.io/use-waypoint-
kubectl delete gateway waypoint -n ${APP_NAMESPACE}
```

### 退出 ambient
```bash
kubectl label namespace ${APP_NAMESPACE} istio.io/dataplane-mode-
```

### 卸载 ambient
```bash
helm uninstall ztunnel -n ${ISTIO_NAMESPACE}
helm uninstall istio-cni -n ${ISTIO_NAMESPACE}
helm uninstall istiod -n ${ISTIO_NAMESPACE}
helm uninstall istio-base -n ${ISTIO_NAMESPACE}
```

---

## 6. Reliability and Cost Optimizations

- `istiod` 生产建议升到 2 副本
- waypoint 建议 2 副本
- 对只需要 L4 mTLS 的命名空间，不要强行启用 waypoint
- 升级 `ztunnel` 时要预估长连接抖动
- 管理面 Redis / Prometheus 按生产容量单独规划

---

## 7. Handoff Checklist

- [ ] GKE Standard 集群已创建
- [ ] Workload Identity 已启用
- [ ] `gloo-platform` 已安装
- [ ] Gateway API CRD 已安装
- [ ] `istiod / istio-cni / ztunnel` 正常
- [ ] 业务 namespace 已打 `istio.io/dataplane-mode=ambient`
- [ ] waypoint 已部署
- [ ] 测试 workload 已验证无 sidecar
- [ ] 回滚步骤已演练

