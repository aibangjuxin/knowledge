# Ambient 安装方案 — Helm 拆分安装 istio-base / istiod / istio-cni / ztunnel

> **TL;DR**:
> - 你现在的 `istioctl install --set profile=minimal` **装不全 ambient** — ambient 需要额外 3 个 chart:`istio-cni` + `ztunnel`
> - 推荐 **Helm 拆分安装**:base → istiod → istio-cni → ztunnel,每个独立 release,独立升级
> - **不要混合 `istioctl install` 与 Helm install** — 二者底层同一 chart,但渲染路径不同,混用会出 CRD 漂移
> - 镜像沿用 `1.30.3-distroless`,**tag 不变**,只换 profile

---

## 1. 为什么不能继续用 `istioctl install --set profile=ambient`

| 命令 | 装什么 | 缺失什么 |
|---|---|---|
| `istioctl install --set profile=minimal` | 仅 `istiod` | ❌ `istio-cni`、`ztunnel`、`cni-plugin` |
| `istioctl install --set profile=ambient` | `istiod` + `cni` + `ztunnel` | ✅ 但**不能拆开升级**(一个 release 整体) |
| **Helm 拆分安装** | 4 个独立 release | ✅ 可单独升 ztunnel、单独升 istiod |

**推荐 Helm 拆分**:每个组件独立 release,**未来升级只动一个**(本目录 05 文会展开)。

---

## 2. 前置确认

> [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) 的硬性要求:

- [x] Istio ≥ 1.19(你 1.30 ✅)
- [x] K8s ≥ 1.27(GKE 自动接受)
- [x] K8s Gateway API CRD v1.0+(你 v1.5.1 ✅)
- [x] 节点 OS = `cos_containerd`(GKE 默认,无需改)
- [x] Helm ≥ 3.6
- [x] 集群资源余量 ≥ 每节点 100m CPU + 128Mi mem(ztunnel DaemonSet 用)

---

## 3. 镜像策略(沿用 GAR,不动)

```bash
# 你现有的 GAR 镜像(已经验证可用)
export HUB="europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers"
export TAG="1.30.3-distroless"

# 注意:ambient 需要的是 istiod 和 ztunnel 这 2 个 image
# - proxyv2:sidecar 用,ambient 模式下不再注入 → 但保留,留着入口 Gateway 用
# - pilot:istiod 用
# - ztunnel:ambient 专有(原 1.30-distroless 标签已包含)
# - install-cni:istio-cni DaemonSet 用

# 验证镜像都在
gcloud artifacts docker images list ${HUB} \
  --project=aibang-12345678-ajbx-dev \
  --include-tags 2>/dev/null | grep -E "proxyv2|pilot|ztunnel|install-cni"
```

**你需要补推的镜像**(如果你之前没推过):
```bash
# 在 bastion 主机上,从官方 docker.io 拉 → skopeo copy 到 GAR
# 镜像源: gcr.io/istio-release (Istio 官方分发)
skopeo copy --src-creds "${USER}:${PASS}" \
  docker://gcr.io/istio-release/ztunnel:1.30.3 \
  docker://${HUB}/ztunnel:${TAG}

skopeo copy --src-creds "${USER}:${PASS}" \
  docker://gcr.io/istio-release/install-cni:1.30.3 \
  docker://${HUB}/install-cni:${TAG}
```

---

## 4. Helm 拆分安装:4 步走

> 来源:`~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` §4.5,改用 **官方 Istio chart**(无需 Solo 仓库),
> 适配你的 GAR 镜像 + minimal 资源约束。

### 4.1 准备 values 文件(推荐持久化,不要每次 inline)

```bash
mkdir -p ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values
cd ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values
```

#### `values/base.yaml` — 公共基础

```yaml
# base.yaml — 控制 revision 命名 + 默认 profile
defaultRevision: ""     # 默认 revision = ""(兼容现有 minimal 安装)
# 不要设 profile,profile 字段是 istioctl 的语法,Helm 不识别
```

#### `values/istiod.yaml` — 控制面

```yaml
# istiod.yaml — 沿用 minimal 资源约束(e2-medium 节点余量有限)
global:
  hub: europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers
  tag: 1.30.3-distroless
  platform: gke

# ambient 必须:istiod 给 ztunnel 也分发配置
pilot:
  cni:
    enabled: true
    namespace: istio-system
  resources:
    requests:
      cpu: 100m       # 与原 minimal 脚本一致
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
  autoscaleMin: 2
  autoscaleMax: 3
  replicaCount: 2

meshConfig:
  accessLogFile: /dev/stdout
  defaultConfig:
    proxyMetadata:
      ISTIO_META_DNS_AUTO_ALLOCATE: "true"
```

#### `values/cni.yaml` — CNI 插件

```yaml
# cni.yaml — 节点级网络拦截,ambient 必备
global:
  hub: europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers
  tag: 1.30.3-distroless

ambient:
  dnsCapture: true          # ambient 关键:抓 DNS 解析
excludeNamespaces:
  - istio-system
  - kube-system
  - gke-managed-system      # GKE 系统组件

cni:
  cniConfDir: /etc/cni/net.d
  cniBinDir: /opt/cni/bin
  resource:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi
```

#### `values/ztunnel.yaml` — 节点级 mTLS 代理

```yaml
# ztunnel.yaml — DaemonSet,每节点 1 pod
configValidation: true
enabled: true

hub: europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers
tag: 1.30.3-distroless

istioNamespace: istio-system
namespace: istio-system

env:
  L7_ENABLED: "true"        # 启用 L7 处理能力(为未来 waypoint 准备)

proxy:
  clusterDomain: cluster.local

terminationGracePeriodSeconds: 29

variant: distroless          # 与现有镜像一致

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi
```

---

### 4.2 执行安装(按顺序)

```bash
export ISTIO_VERSION="1.30.3"
export ISTIO_NS="istio-system"

# Step 1:base — CRD + ClusterRole 等全局资源
helm upgrade --install istio-base \
  oci://gcr.io/istio-release/charts/base \
  --namespace ${ISTIO_NS} \
  --create-namespace \
  --version ${ISTIO_VERSION} \
  -f ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values/base.yaml

# Step 2:istiod — 控制面
helm upgrade --install istiod \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values/istiod.yaml

# Step 3:istio-cni — 节点级 CNI 拦截
helm upgrade --install istio-cni \
  oci://gcr.io/istio-release/charts/cni \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values/cni.yaml

# Step 4:ztunnel — 节点级 mTLS 代理
helm upgrade --install ztunnel \
  oci://gcr.io/istio-release/charts/ztunnel \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ~/git/gcp/gateway-2.0/k8s-gateway-ambient/values/ztunnel.yaml
```

---

## 5. 验证清单

```bash
# 1. istiod 跑起来(2 副本)
kubectl get pods -n istio-system -l app=istiod
# 预期:istiod-xxxx   1/1     Running   0   ...
#      istiod-yyyy   1/1     Running   0   ...

# 2. istio-cni DaemonSet(每节点 1 pod)
kubectl get pods -n istio-system -l k8s-app=istio-cni
# 预期:节点数 = DaemonSet 期望 pod 数

# 3. ztunnel DaemonSet(每节点 1 pod)
kubectl get ds -n istio-system ztunnel
kubectl get pods -n istio-system -l app=ztunnel
# 预期:每节点 1 pod,Running

# 4. GatewayClass istio-waypoint 自动注册
kubectl get gatewayclass
# 预期看到:
#   NAME             CONTROLLER                  ACCEPTED   AGE
#   istio            istio.io/gateway-controller   True     ...
#   istio-waypoint   istio.io/waypoint-controller  True    ...  ← ambient 安装后才有

# 5. ambient 关键 CRD 已注册
kubectl get crd | grep -E "waypoint|ztunnel"
# 应包含 ambient 专有 CRD

# 6. 一个 pod 验证 ztunnel 拦截生效
kubectl run nettest --image=alpine --restart=Never -- sleep 3600 \
  -n default
kubectl exec -n default nettest -- wget -qO- http://example.com
# 此时虽未 enable ambient,但 ztunnel 已就绪
```

---

## 6. 与现有 `install-istio.sh` 的并存策略

**不能 2 个工具同时管同一集群**,会出 CRD 漂移。三选一:

| 策略 | 做法 | 推荐度 |
|---|---|---|
| A. **全 Helm,废弃 istioctl 脚本** | 把 `install-istio.sh` 改为 readme 提示,实际用 Helm 装 | ⭐⭐⭐ 推荐(本目录主推) |
| B. 全 istioctl | 用 `istioctl install --set profile=ambient`,**不 Helm** | ⚠️ 失去拆分升级优势 |
| C. 混合(istioctl 装 base/istiod,Helm 装 cni/ztunnel) | 工具混用 | ❌ **不推荐**,CRD 来源不清晰 |

**本目录推荐 A**:把 `k8s-gateway/01-platform/install-istio.sh` 加注释说明:
> "此脚本安装的是 minimal profile,仅含 istiod。
> 如需 ambient(ztunnel + waypoint),请使用 `k8s-gateway-ambient/02-install-ambient-helm.md` 中的 Helm 拆分安装流程。"

---

## 7. 拆分安装带来的好处(为升级铺路)

- 升 ztunnel 时,**不动 istiod** = 不影响配置分发
- 升 istiod 时,**不动 ztunnel** = 节点级代理不重启
- 装新组件(如 `gateway` chart 给 waypoint 用)时,**不动 base** = CRD 不变
- **每步可独立回滚**(`helm uninstall ztunnel` 只卸载 ztunnel)

---

## 8. 严格定义 vs 简化解释(分两栏)

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **defaultRevision: ""** | 默认 revision = 无标签 | "When defaultRevision is empty, istiod is deployed without a revision label and serves as the default control plane." — [Istio Helm Install](https://istio.io/latest/docs/setup/install/helm/) |
| **ambient.dnsCapture** | ambient 抓 DNS 解析 | "When ambient.dnsCapture is enabled, istio-cni redirects DNS lookups from pods to ztunnel for resolution through the mesh." — Istio cni chart values |
| **L7_ENABLED** | 让 ztunnel 参与 L7 | "When L7_ENABLED=true, ztunnel participates in L7 protocol detection to delegate to waypoint proxies." — Istio ztunnel chart values |
| **configValidation** | 启动前校验配置 | "When configValidation is enabled, ztunnel validates its configuration before starting; invalid configuration prevents startup." — Istio ztunnel chart values |

---

## 9. 完整执行脚本(可 copy-paste)

```bash
#!/usr/bin/env bash
# install-ambient-helm.sh — Helm 拆分装 ambient
# 用法: bash install-ambient-helm.sh
set -euo pipefail

export PROJECT_ID="aibang-12345678-ajbx-dev"
export GCP_REGION="europe-west2"
export HUB="${GCP_REGION}-docker.pkg.dev/${PROJECT_ID}/containers"
export TAG="1.30.3-distroless"
export ISTIO_VERSION="1.30.3"
export ISTIO_NS="istio-system"

VALUES_DIR="$HOME/git/gcp/gateway-2.0/k8s-gateway-ambient/values"

echo "=== 0. 创建 namespace ==="
kubectl create namespace ${ISTIO_NS} --dry-run=client -o yaml | kubectl apply -f -

echo "=== 1. helm install istio-base ==="
helm upgrade --install istio-base \
  oci://gcr.io/istio-release/charts/base \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ${VALUES_DIR}/base.yaml

echo "=== 2. helm install istiod ==="
helm upgrade --install istiod \
  oci://gcr.io/istio-release/charts/istiod \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ${VALUES_DIR}/istiod.yaml

echo "=== 3. helm install istio-cni ==="
helm upgrade --install istio-cni \
  oci://gcr.io/istio-release/charts/cni \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ${VALUES_DIR}/cni.yaml

echo "=== 4. helm install ztunnel ==="
helm upgrade --install ztunnel \
  oci://gcr.io/istio-release/charts/ztunnel \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f ${VALUES_DIR}/ztunnel.yaml

echo ""
echo "=== 验证 ==="
kubectl get pods -n ${ISTIO_NS}
echo ""
kubectl get gatewayclass
```

---

## 10. References

- [Istio Ambient Install](https://istio.io/latest/docs/ambient/install/) — 官方安装入口
- [Istio Helm 安装指南](https://istio.io/latest/docs/setup/install/helm/) — Helm chart 拆分权威说明
- [Istio Ambient Architecture](https://istio.io/latest/docs/ambient/architecture/) — 组件关系
- [Istio ztunnel chart values](https://istio.io/latest/docs/reference/config/proxy_extensions/ztunnel/) — ztunnel 配置
- [Istio install-cni chart values](https://github.com/istio/istio/tree/release-1.30/manifests/charts/istio-cni) — CNI 配置
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` §4.5 — Gloo 视角的类似安装流程(用 Solo 镜像,本篇改用官方 Istio 镜像 + GAR 镜像)