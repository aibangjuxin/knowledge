# Solo Mesh 镜像替换与版本升级手册（Ambient）

> **本文档定位**：回答一个具体问题 —— **「我们这套 Solo Mesh，怎么把一个 old image 换成新的？改一下 istio revision 是不是就可以了？」**
>
> **适用网格**：本仓库 `gcp/asm/solo/` 描述的 Solo Enterprise for Istio **Ambient** 网格
> （当前发行版：`1.30.2-solo-fips`，控制面 `istiod` / `istio-cni` / `ztunnel`，
> 入口用 Gateway API + Solo ListenerSet）。
>
> **配套文档**：
> - [`solo.md`](../solo.md) —— 网格主流程与资源变化
> - [`solo-version.md`](../solo-version.md) —— Solo 发行版 / 镜像 tag 命名规则
> - [`install/install.md`](../install/install.md) —— 安装与验证清单

---

## 0. TL;DR（先看结论）

### 0.1 一句话回答「改 revision 就够了吗」

> **不够。** Revision 解决的是「**用哪个控制面**」的问题，**不是**「**跑哪个镜像**」的问题。
> 在 Ambient 里镜像只随 **Pod 模板**变化而变化，所以**任何方式换镜像，最终都必须让目标 Pod 重建（rollout）**。

| 你想换的镜像 | 改 revision 够吗 | 真正要做的事 |
|---|---|---|
| `istiod`（控制面 pilot） | ⚠️ 半够 | 装新 revision **且**把镜像 tag 指到新版：`helm install istiod-<rev> --set revision=<rev> --set global.tag=<new-tag>` |
| `ztunnel`（Ambient 数据面本体） | ❌ 不够 | revision 只是标签；镜像来自 chart values，必须 `helm upgrade ztunnel --set tag=<new-tag>` 让 DaemonSet 滚动 |
| `istio-cni`（节点代理） | ❌ 不够 | Istio 官方明确：**CNI 不支持 canary / revision 升级**，只能原地 `helm upgrade istio-cni` |
| 已有 Pod（租户应用） | ❌ 无关 | 镜像在应用自己的 Deployment 里，要各自 rollout |
| `agentgateway`（入口） | ❌ 无关 | 独立 chart，独立版本号（`v2026.x`），单独 `helm upgrade` |
| 租户业务镜像 | ❌ 无关 | 与 mesh 无关，`kubectl set image` 即可 |

### 0.2 六种替换方式速查

| # | 方式 | 粒度 | 停机 | 可回滚 | 推荐场景 |
|---|---|---|---|---|---|
| **A** | **Helm 原地升级**（patch 版本） | 全组件 | ztunnel 秒级抖动 | ✅ `helm rollback` | **首选**（Solo 官方推荐） |
| **B** | **istioctl 原地升级** | 全组件 | 同上 | ⚠️ 靠重新 apply 老版本 | 已用 `istioctl install -f` 装的网格 |
| **C** | **Revision / Canary 双控制面 + tag 切换** | 控制面可灰度 | tag flip 有风险 | ✅ 改 tag 指回老 revision | 大版本 / 需要灰度验证 |
| **D** | **只覆盖单个组件的镜像** | 单组件 | 极小 | ✅ 改回旧 tag | 热修某个组件 CVE、混版本试用 |
| **E** | 直接 `kubectl set image` | 单组件 | 极小 | ⚠️ 下次升级被冲掉 | **仅应急** |
| **F** | 自建镜像 / 私仓镜像同步 + 改 `hub` | 全组件 | 取决于来源 | ✅ 改回原 hub | air-gapped、自编译热修 |

### 0.3 三条底线

1. **先查集群里的真实镜像**，别信文档里的假设值：
   ```bash
   kubectl get pods -n istio-system -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[*].image'
   ```
2. **`istio-cni` 没有灰度路径**，必须原地升级；升级期间该节点**不允许新 ambient Pod 启动**（这是保护机制，不是 bug）。
3. **Gateway API + tag flip 有黑洞风险**：我们用 Gateway API + ListenerSet，做 canary 时必须先确认 istiod 版本 ≥ **1.30.2**（我们当前正好是 1.30.2 ✅，详见 [§4.4](#44-网关-api-下的-tag-flip-黑洞风险)）。

---

## 1. 我们的网格里到底有哪些镜像

### 1.1 清单

| 组件 | 形态 | Namespace | 安装方式 | 镜像名 | 当前 tag | 能否 canary |
|---|---|---|---|---|---|---|
| `istiod` | Deployment | `istio-system` | Helm `istiod` / `istioctl` | `pilot` | `1.30.2-solo-fips` | ✅ 可 |
| `istio-cni-node` | DaemonSet | `kube-system` | Helm `cni` / `istioctl` | `install-cni` | `1.30.2-solo-fips` | ❌ **不支持** |
| `ztunnel` | DaemonSet | `istio-system` | Helm `ztunnel` / `istioctl` | `ztunnel` | `1.30.2-solo-fips` | ⚠️ 有 revision 标签，但升级仍会断连 |
| `agentgateway` | Deployment | `clienta-gw-int` | Helm `enterprise-agentgateway` | agentgateway | `v2026.x`（独立版本线） | ❌ 独立 |
| 租户应用 | Deployment | `tenant-runtime` 等 | 业务自己的 Kustomize/Helm | 业务镜像 | 业务自己定 | ❌ 无关 |
| 平台 Gateway（Istio Gateway 形态） | Deployment | `clienta-gw-int` | Helm `gateway` | `proxyv2` | `1.30.2-solo-fips` | ✅ 可（走 tag） |

> ⚠️ **Ambient 下没有 sidecar 注入**：`proxyv2` 镜像在 Ambient 网格里只出现在 **Gateway / waypoint**（我们自己跑 Envoy 的入口），
> 租户 Pod 里**不会**有 `istio-proxy` 容器 —— 所以「换 `proxyv2` 镜像后要不要重新注入」这个问题在 Ambient 下**不存在**，
> 换成「**Gateway Pod 重建**」。

### 1.2 关键差异：Ambient 没有「重新注入」这一步

| | Sidecar 模式 | **Ambient 模式（我们）** |
|---|---|---|
| 数据面载体 | 每个 Pod 注入 `istio-proxy` sidecar | **节点级 `ztunnel` DaemonSet** |
| 换 sidecar 镜像要做什么 | 改注入模板 + **重启 Pod 触发重新注入** | **不适用**（没有 sidecar） |
| 换 ztunnel 镜像要做什么 | — | 改 DaemonSet 镜像 → **滚动重建 ztunnel Pod** |
| `istio.io/rev` 标签作用 | 决定**注入哪个控制面**的 sidecar 模板 | 决定**哪个控制面**接管该 ns 的配置（Gateway/HTTPRoute/策略） |
| 换 `istio.io/rev` 会换镜像吗 | 会（模板变了） | **不会**（ztunnel 镜像是 DaemonSet 自己的事） |

> ⭐ **这就是「改 revision 够不够」的全部答案**：
> 在 Sidecar 模式里，revision ≈ 「换控制面 + 换 sidecar 镜像」二合一；
> 在 **Ambient 里这两件事被拆开了** —— revision 只管控制面，ztunnel 镜像要单独动。

---

## 2. 镜像仓库与 tag 命名（Solo 发行版）

### 2.1 tag 命名规则

Solo 发行版在社区 tag 后追加变体后缀（详见 [`solo-version.md`](../solo-version.md)）：

| 变体 | tag 示例 | 说明 |
|---|---|---|
| Standard | `1.30.8` | 社区 Istio 原版，无 Solo 增强 |
| Solo | `1.30.8-solo` | 企业发行版（**ambient mesh 增强需要它**） |
| Solo + FIPS | `1.30.8-solo-fips` | NIST FIPS 140-3，**需要 Solo License Key** |
| Solo + Distroless | `1.30.8-solo-distroless` | 精简依赖，**Pod 内没有 shell / apt / pip** |
| 组合 | `1.30.8-solo-fips-distroless` | 两者叠加 |

### 2.2 镜像仓库（⚠️ 重要纠正）

Solo 官方文档（1.29 及以后）明确：

```bash
export REPO=us-docker.pkg.dev/soloio-img/istio       # 镜像仓库
export HELM_REPO=us-docker.pkg.dev/soloio-img/istio-helm   # Helm OCI 仓库
```

镜像名固定为四个：`pilot` / `proxyv2` / `install-cni` / `ztunnel`。

> ⚠️ **本仓库现有文档与 Solo 官方不一致**：
> [`install/install.md`](../install/install.md) 与 [`yamls/00-istiooperator.yaml`](../yamls/00-istiooperator.yaml) 里写的是
> `hub: gcr.io/istio-release` + `tag: 1.30.2-solo-fips`。
>
> **实测结果**（匿名拉取 GCR manifest）：
>
> | 镜像 | 结果 |
> |---|---|
> | `gcr.io/istio-release/ztunnel:1.30.2`（社区版） | **200** ✅ |
> | `gcr.io/istio-release/ztunnel:1.30.2-solo-fips` | **404** ❌ |
> | `gcr.io/istio-release/ztunnel:1.30.2-solo` | **404** ❌ |
>
> 也就是说 **`gcr.io/istio-release` 里没有 `*-solo*` 标签**，社区仓库只放社区镜像。
> 因此本仓库文档里的 hub 写法需要按**集群实际镜像**修正（见下方排查命令），否则新版本根本拉不下来。
>
> ```bash
> # 排查本集群真实 hub/tag —— 这是唯一的事实来源
> kubectl get pods -n istio-system -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[*].image'
> kubectl get ds ztunnel -n istio-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
> kubectl get deploy istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
> ```

### 2.3 可用 patch 版本

1.30.x 的 patch 构建在 Artifact Registry `us-docker.pkg.dev/soloio-img/istio` 里（Solo 文档给出的示例目标版本是 `1.30.8`）：

```bash
# 列出可用 tag（需要 Artifact Registry 读权限）
gcloud artifacts docker images list us-docker.pkg.dev/soloio-img/istio/ztunnel \
  --filter="tags:1.30.*" --format="value(tags)"
# 或
crane ls us-docker.pkg.dev/soloio-img/istio/ztunnel | grep '^1\.30\.'
```

> 官方要求：**生产环境必须跑当前 minor 的最新 patch**（n-4 安全补丁策略，只对 `-solo` 发行版生效）。

---

## 3. 六种替换方式详解

### 方式 A：Helm 原地升级（**首选**）

Solo 官方对 ambient 网格的推荐路径。适合 **patch 版本升级**（`1.30.2-solo-fips` → `1.30.8-solo-fips`）。

**核心思想**：镜像 tag 由 Helm values 决定 → `helm upgrade` 换 values → Pod 模板变 → DaemonSet/Deployment 自动滚动。

#### A.0 前置

```bash
export ISTIO_VERSION=1.30.8
export ISTIO_IMAGE=${ISTIO_VERSION}-solo-fips      # 保留 -fips 变体
export REPO=us-docker.pkg.dev/soloio-img/istio
export HELM_REPO=us-docker.pkg.dev/soloio-img/istio-helm

istioctl x precheck   # 兼容性检查
```

#### A.1 导出当前 values（**别跳过**，否则自定义会被冲掉）

```bash
helm get values istio-base -n istio-system -o yaml > values-base.yaml
helm get values istiod      -n istio-system -o yaml > values-istiod.yaml
helm get values istio-cni   -n istio-system -o yaml > values-cni.yaml
helm get values ztunnel     -n istio-system -o yaml > values-ztunnel.yaml
```

#### A.2 升级顺序（**顺序敏感**）

> 控制面 → CNI → ztunnel。反了会出现「数据面比控制面新」，不兼容。

```bash
# ① CRDs（base chart）
helm upgrade istio-base oci://${HELM_REPO}/base \
  -n istio-system --version ${ISTIO_IMAGE} -f values-base.yaml

# ② 控制面 istiod
helm upgrade istiod oci://${HELM_REPO}/istiod \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set global.hub=${REPO} --set global.tag=${ISTIO_IMAGE} \
  -f values-istiod.yaml

# ③ CNI（只能原地，见 §4.3）
helm upgrade istio-cni oci://${HELM_REPO}/cni \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set global.hub=${REPO} --set global.tag=${ISTIO_IMAGE} \
  -f values-cni.yaml

# ④ 数据面 ztunnel（最后）
helm upgrade ztunnel oci://${HELM_REPO}/ztunnel \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set hub=${REPO} --set tag=${ISTIO_IMAGE} \
  -f values-ztunnel.yaml
```

#### A.3 各组件的镜像取值键（**别搞混**）

| Chart | 镜像键 | 完整镜像 |
|---|---|---|
| `istiod` | `global.hub` + `global.tag` | `${REPO}/pilot:${ISTIO_IMAGE}` |
| `istio-cni` | `global.hub` + `global.tag` | `${REPO}/install-cni:${ISTIO_IMAGE}` |
| `ztunnel` | `hub` + `tag`（**顶层，不在 global 下**） | `${REPO}/ztunnel:${ISTIO_IMAGE}` |
| `base` | 无镜像 | — |

> ztunnel chart 还支持 `variant`（`distroless` / `debug`）与 `image`（可直接写 `hub/image:tag` 全量）。

#### A.4 CNI 配置生效问题（Solo 文档特别强调）

`istio-cni` **只在启动时读 `istio-cni-config` ConfigMap**。若改了 ConfigMap 却没重启 DaemonSet，设置不生效：

```bash
# 检查 DaemonSet 是否带 checksum 注解
kubectl get ds istio-cni-node -n istio-system -o jsonpath='{.spec.template.metadata.annotations}'
# 没有 checksum/cni-config 注解时，改完必须手动重启
kubectl rollout restart ds/istio-cni-node -n istio-system
```

#### A.5 优缺点

| ✅ 优点 | ⚠️ 代价 |
|---|---|
| 官方推荐；一条命令一个组件；`helm history` / `helm rollback` 天然可回滚 | ztunnel 滚动期间**节点上所有长连接会被断开**（HBONE tunnel 重建） |
| values 留档 → 升级后配置不丢 | CNI 没有灰度，必须一次升完 |
| 适合 patch 版本 | 大版本升级仍建议走 canary |

---

### 方式 B：istioctl 原地升级

适合**用 `istioctl install -f 00-istiooperator.yaml` 装出来的网格**（本仓库的 Lab 路径就是这条）。

```bash
# 关键：必须带与安装时完全一致的 -f 文件和 --set，否则自定义会被重置
istioctl upgrade -f yamls/00-istiooperator.yaml \
  --set hub=${REPO} \
  --set tag=${ISTIO_IMAGE} \
  -y
```

要点：

- `istioctl upgrade` **不支持 `--revision` 安装的网格**（会直接报错）；
- 官方明确警告：**in-place 升级每次只能跨 1 个 minor**（canary 方式才能跨两个 minor）；
- 升级完**必须手动重启数据面**（Sidecar 模式）；Ambient 下 ztunnel 由 installer 一起滚动，但要确认：
  ```bash
  kubectl get pods -n istio-system -o wide | grep -E 'ztunnel|istiod'
  ```

> 💡 **实践建议**：istioctl 路径与 Helm 路径**不要混搭**。若一开始用 `istioctl install`，后续也用 `istioctl upgrade`；
> 想换成 Helm 管理，需要先 `istioctl uninstall` 再用 Helm 重装（或者反过来），否则 Helm 与 istioctl 会互相覆盖。

---

### 方式 C：Revision / Canary 双控制面 + tag 切换

适合**跨大版本**、或需要「先小流量验证再全量」的场景。

#### C.1 基本模型

```
istiod (default rev)  ←── 旧控制面
istiod-<rev>          ←── 新控制面（新镜像）
        ↓ 通过 istio.io/rev 标签 / tag 决定谁接管哪个 namespace
   namespace A → old    namespace B → new
```

- **revision 是不可变的**：装了就别改，名字建议用版本号（`1-30-8`，`.` 不是合法字符）；
- **tag 是可变指针**：`istio.io/rev=<tag>` 的 namespace 跟随 tag 移动，无需逐个改标签。

#### C.2 命令（istioctl 路径）

```bash
# ① 并列装一个新 revision 的控制面
istioctl install --revision=1-30-8 \
  --set profile=ambient \
  --set hub=${REPO} --set tag=${ISTIO_IMAGE} -y

# ② 建 tag 指针（default 指向老版本）
istioctl tag set default --revision 1-30-2
istioctl tag set prod-canary --revision 1-30-8

# ③ 逐个 ns 灰度（先低风险业务）
kubectl label ns <tenant-ns> istio.io/rev=prod-canary --overwrite

# ④ 验证该 ns 的 Gateway / HTTPRoute 状态已被新控制面接管
kubectl get httproutes -n <tenant-ns> -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.parents[*].conditions[*].type}{"\n"}{end}'

# ⑤ 全量：把 default tag 指到新 revision
istioctl tag set default --revision 1-30-8 --overwrite

# ⑥ 清理老控制面
istioctl uninstall --revision 1-30-2 -y
```

#### C.3 命令（Helm 路径，**revisioned ztunnel 的官方写法**）

```bash
# 新 revision 的控制面（与老控制面并存）
helm install istiod-1-30-8 oci://${HELM_REPO}/istiod \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set revision=1-30-8 \
  --set global.hub=${REPO} --set global.tag=${ISTIO_IMAGE}

# revision 化的 ztunnel（官方 ambient 升级文档给出的写法）
helm upgrade ztunnel oci://${HELM_REPO}/ztunnel \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set revision=1-30-8 \
  --set hub=${REPO} --set tag=${ISTIO_IMAGE}

# 把 tag 从老 revision 移到新 revision（一次动一批）
helm template istiod oci://${HELM_REPO}/istiod \
  -s templates/revision-tags-mwc.yaml \
  --set revisionTags="{prod}" --set revision=1-30-8 \
  -n istio-system | kubectl apply -f -

# 回滚：把 tag 指回老 revision
helm template istiod oci://${HELM_REPO}/istiod \
  -s templates/revision-tags-mwc.yaml \
  --set revisionTags="{prod}" --set revision=1-30-2 \
  -n istio-system | kubectl apply -f -
```

#### C.4 优缺点

| ✅ 优点 | ⚠️ 代价 |
|---|---|
| 控制面可灰度，回滚 = 改 tag，秒级 | **CNI 仍要原地升**（见 §4.3） |
| 新老控制面并存，便于对比 | **ztunnel 升级仍会断连**（官方原文：*"even with the use of revisions"*） |
| 可以跨 2 个 minor（canary 方式） | Gateway API 场景有 **tag flip 黑洞风险**（见 §4.4） |
| | istioctl 路径下 ztunnel 的 revision 行为需实测，**官方明确文档的是 Helm 写法** |

---

### 方式 D：只覆盖单个组件的镜像

**不升版本，只换某一个组件的镜像**（例如：只把 ztunnel 换成打过补丁的自建镜像，其它组件不动）。

#### D.1 Helm 路径（最直接）

```bash
# 只换 ztunnel 镜像，其它组件不动
helm upgrade ztunnel oci://${HELM_REPO}/ztunnel \
  -n istio-system \
  --set hub=us-docker.pkg.dev/my-registry/istio \
  --set tag=1.30.2-solo-fips-ztunnel-hotfix \
  -f values-ztunnel.yaml

# 只换 istiod 镜像
helm upgrade istiod oci://${HELM_REPO}/istiod \
  -n istio-system \
  --set global.hub=us-docker.pkg.dev/my-registry/istio \
  --set global.tag=1.30.2-solo-fips-pilot-hotfix \
  -f values-istiod.yaml
```

也可以直接写全量镜像（chart 的 `image` 支持 `hub/image:tag` 形式）：

```bash
helm upgrade ztunnel oci://${HELM_REPO}/ztunnel -n istio-system \
  --set image=us-docker.pkg.dev/my-registry/istio/ztunnel:my-hotfix
```

#### D.2 IstioOperator 路径（本仓库 `00-istiooperator.yaml` 那条）

`IstioOperator` 的 `ComponentSpec` 明确支持 **`hub` / `tag` 组件级覆盖**（顶层 `hub`/`tag` 之外的局部覆盖）：

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  hub: us-docker.pkg.dev/soloio-img/istio
  tag: 1.30.2-solo-fips
  components:
    ztunnel:
      enabled: true
      hub: us-docker.pkg.dev/my-registry/istio     # 只覆盖 ztunnel
      tag: 1.30.2-solo-fips-ztunnel-hotfix
    pilot:
      enabled: true
      # hub / tag 留空 → 继承顶层
    cni:
      enabled: true
```

也可以走 `values` 直通（chart values 原样透传）：

```yaml
spec:
  values:
    ztunnel:
      hub: us-docker.pkg.dev/my-registry/istio
      tag: 1.30.2-solo-fips-ztunnel-hotfix
```

> 💡 如果 `spec.values.ztunnel.*` 在你们的 IstioOperator 版本里不生效，
> **改用上面的 `spec.components.ztunnel.hub/tag`** —— 这是 IstioOperator API 参考里
> 明确列出的字段（`ComponentSpec.hub` / `ComponentSpec.tag`），跨版本更稳。
> 验证方式：`istioctl manifest generate -f 00-istiooperator.yaml | grep -A3 'name: ztunnel'`。

#### D.3 优缺点

| ✅ 优点 | ⚠️ 代价 |
|---|---|
| blast radius 最小，只动一个组件 | **版本矩阵要自己负责**（新 ztunnel + 旧 istiod 的兼容性） |
| 不影响其它组件的 rollout | 破坏「全网格同版本」的一致性，后续升级容易被覆盖 |
| 适合应急热修 | 官方没有为这种混版本组合背书 |

> 🔒 **版本兼容矩阵**（官方约束）：
> - `istio-cni` at 1.x 兼容控制面 1.x+1 与 1.x → **控制面必须先升**；
> - `ztunnel` at 1.x 兼容控制面 1.x+1 与 1.x → 同上，**控制面先于 ztunnel**；
> - 跨版本不要自己脑补矩阵，查 release notes。

---

### 方式 E：直接 `kubectl set image`（**仅应急**）

```bash
# 应急换 ztunnel 镜像（不等 Helm）
kubectl set image ds/ztunnel -n istio-system ztunnel=us-docker.pkg.dev/my-registry/istio/ztunnel:hotfix

# 应急换租户应用镜像
kubectl set image deploy/tenant-app -n tenant-runtime app=my-app:v2
```

| ✅ | ⚠️ |
|---|---|
| 30 秒生效 | **会被下一次 `helm upgrade` / `istioctl upgrade` 无声冲掉**（回到声明值） |
| 不需要 chart 权限 | 集群状态与声明状态漂移，GitOps / CI 检测不出来 |
| | 记录到变更单里必须写清楚 |

> 📌 **只在「CVE 应急窗口内、还没来得及走正式流程」时用**，事后必须回到 A / D 路径做一次正规升级。

---

### 方式 F：自建镜像 / 私仓镜像同步（air-gapped、自编译热修）

#### F.1 镜像同步到自己的 Artifact Registry（最常见）

```bash
export REPO=us-docker.pkg.dev/soloio-img/istio
export ISTIO_IMAGE=1.30.2-solo-fips
export REGISTRY=us-docker.pkg.dev/<your-project>/istio-mirror

for img in pilot proxyv2 install-cni ztunnel; do
  docker pull  ${REPO}/${img}:${ISTIO_IMAGE}
  docker tag   ${REPO}/${img}:${ISTIO_IMAGE} ${REGISTRY}/${img}:${ISTIO_IMAGE}
  docker push  ${REGISTRY}/${img}:${ISTIO_IMAGE}
done
```

之后所有升级命令把 `hub` 指向 `${REGISTRY}` 即可（方式 A / D 里的 `--set hub=` 就是这个作用）。

#### F.2 自编译镜像（改 Envoy 过滤器 / 加 Solo 定制）

```bash
# 以 Solo distro 为基底打自己的镜像
docker build -t ${REGISTRY}/ztunnel:1.30.2-solo-fips-custom -f Dockerfile.ztunnel .
docker push ${REGISTRY}/ztunnel:1.30.2-solo-fips-custom

# 指过去（方式 D）
helm upgrade ztunnel oci://${HELM_REPO}/ztunnel -n istio-system \
  --set image=${REGISTRY}/ztunnel:1.30.2-solo-fips-custom
```

> ⚠️ **FIPS 与 License**：自编译镜像会**破坏 FIPS 认证链**，也不能再声称是 `-solo-fips`；
> 若 mesh 依赖 Solo 企业特性（agentgateway 集成、Enterprise ListenerSet 等），**必须保留 `-solo` 变体**，
> 自编译镜像仅在 Hotfix 且经合规确认后使用。

---

## 4. 专题：「只改 istio revision 就可以了吗」

### 4.1 三层拆解

| 层 | 对象 | revision 能不能控制 | 换镜像的动作 |
|---|---|---|---|
| **控制面** | `istiod` | ✅ 能（装新 revision + 打标签） | 装 revision 时指定新 tag |
| **数据面** | `ztunnel` DaemonSet | ⚠️ 只有标签，**镜像不跟着走** | `helm upgrade ztunnel --set tag=<new>` → DS 滚动 |
| **节点代理** | `istio-cni` DaemonSet | ❌ **官方明确不支持 canary** | 只能原地 `helm upgrade istio-cni` |
| **已有 Pod** | 租户应用 | ❌ 无关 | 镜像在应用自己的 Deployment 里 |

### 4.2 为什么 revision 不会带 ztunnel 一起换

- Ambient 的**数据面是 ztunnel**，它是一个**独立的 DaemonSet**，其镜像由 **chart values** 决定；
- `istio.io/rev` 标签的作用是「**哪个控制面负责这个 namespace 的配置**」，
  它不改变节点上 ztunnel Pod 模板里的 `image` 字段；
- K8s 的 DaemonSet 只在**Pod 模板变化**时才滚动 —— 改标签不会触发滚动。

### 4.3 `istio-cni` 为什么不能 canary

官方原文（Istio ambient 升级文档）：

> *"Istio does not currently support canary upgrades of `istio-cni`, even with the use of revisions."*
> 若确实担心影响面，建议**等节点排空（drain）后再升级 CNI**，或用节点 taint 手工编排。

Solo 补充说明 CNI 的**安全原地升级**机制：`istio-cni` 关闭时会检查 DaemonSet 是否仍存在且仍覆盖本节点；
若是（视为升级），它会**把 CNI 插件留在节点上**，新调度的 ambient Pod 会被**卡住**直到新 CNI 起来——
**这是防止未加密流量泄漏的保护机制**，不是故障。

### 4.4 Gateway API 下的 tag-flip 黑洞风险

我们的入口用 Gateway API + ListenerSet，**canary 的 tag flip 有坑**（Solo 文档专门开了一页）：

- 机制：tag flip 后，老 istiod 发现自己不再拥有那些 Gateway → 会向**仍连着自己的 Gateway Pod 推送一份空 xDS**；
  新 istiod 还没连上 → Gateway **约 15–30 秒没有任何路由配置** → **流量黑洞**；
- 修复：upstream issue [#59959](https://github.com/istio/istio/issues/59959)，
  修复存在于 **Istio 1.29.5+ / 1.30.2+ / 1.31.x**；
  **且必须当前正在运行的 istiod 就已带修复**；
- 我们的现状：`1.30.2-solo-fips` ✅ **正好在修复版本之上**，canary 可以做；
- 若将来回退到 1.30.0 / 1.30.1，**先原地升到 1.30.2+ 再做 canary**；
- 该问题**不影响 in-place 升级**（in-place 是替换，不存在「老控制面失去所有权」这一步）。

> 💡 另一个易踩的坑：迁移期间**不要**给老 istiod 设 `PILOT_ENABLE_GATEWAY_API=false` ——
> 会导致尚未迁移 ns 的 HTTPRoute 状态丢失（两个控制面都不 reconcile）。

### 4.5 结论

> **「改 revision 就够了」只在一种情况下成立：你要换的是 `istiod` 镜像，并且接受「控制面先切、数据面后切」的节奏。**
> 其余情况（ztunnel / CNI / 应用 / agentgateway）都必须各自显式换。
>
> 换句话说，**revision 是「谁来管」的开关，不是「跑什么」的开关。**

---

## 5. 推荐执行流程：我们这套网格的实操剧本

**场景**：`1.30.2-solo-fips` → `1.30.8-solo-fips`（patch 升级，走方式 A）。

### Phase 0 — 盘点与备份

```bash
# 1) 现状快照
kubectl get pods -n istio-system -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[*].image'
kubectl get ds,deploy -n istio-system -o yaml > backup-istio-system.yaml
helm get values istiod    -n istio-system -o yaml > values-istiod.yaml
helm get values istio-cni -n istio-system -o yaml > values-cni.yaml
helm get values ztunnel   -n istio-system -o yaml > values-ztunnel.yaml
helm list -n istio-system

# 2) 兼容性检查
istioctl x precheck

# 3) 记录关键状态（用于升级后比对）
istioctl proxy-status > proxy-status-before.txt
kubectl get gateway,httproute -A -o yaml > gw-before.yaml
```

### Phase 1 — CRDs

```bash
helm upgrade istio-base oci://${HELM_REPO}/base \
  -n istio-system --version ${ISTIO_IMAGE} -f values-base.yaml
```

> Gateway API CRD 也按 Solo 支持矩阵同步（1.30.x 支持 Gateway API **1.5 – 1.6**，
> Solo 建议用 **1.5.0** standard channel）。

### Phase 2 — 控制面 istiod

```bash
helm upgrade istiod oci://${HELM_REPO}/istiod \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set global.hub=${REPO} --set global.tag=${ISTIO_IMAGE} \
  -f values-istiod.yaml
kubectl rollout status deploy/istiod -n istio-system --timeout=5m
```

### Phase 3 — CNI（原地）

```bash
helm upgrade istio-cni oci://${HELM_REPO}/cni \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set global.hub=${REPO} --set global.tag=${ISTIO_IMAGE} \
  -f values-cni.yaml
kubectl rollout status ds/istio-cni-node -n kube-system --timeout=5m
```

### Phase 4 — 数据面 ztunnel（最后，**建议分批**）

> ztunnel 滚动会断掉节点上的长连接（HBONE tunnel 重建）。生产上建议：
> **先 cordon 一个节点 → 升级 → 观察 → 再放量**。

```bash
# 分批 cordon + 滚动（示例）
kubectl cordon node-1
helm upgrade ztunnel oci://${HELM_REPO}/ztunnel \
  -n istio-system --version ${ISTIO_IMAGE} \
  --set hub=${REPO} --set tag=${ISTIO_IMAGE} \
  -f values-ztunnel.yaml
kubectl rollout status ds/ztunnel -n istio-system --timeout=5m
kubectl uncordon node-1
```

### Phase 5 — 验证

见 [§6](#6-验证清单)。

### 回滚

```bash
# 方式 A 回滚：Helm 历史
helm history ztunnel -n istio-system
helm rollback ztunnel -n istio-system <REVISION>

helm history istiod -n istio-system
helm rollback istiod -n istio-system <REVISION>

# 方式 C 回滚：把 tag 指回老 revision
istioctl tag set default --revision 1-30-2 --overwrite
```

---

## 6. 验证清单

```bash
# ① 镜像确实换了
kubectl get pods -n istio-system -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[*].image'
# 期望：全部为 .../pilot:1.30.8-solo-fips、.../ztunnel:1.30.8-solo-fips、.../install-cni:1.30.8-solo-fips

# ② 每个组件都 Ready 且没有 CrashLoop
kubectl get pods -n istio-system -o wide
kubectl get pods -n kube-system -l k8s-app=istio-cni-node -o wide

# ③ 控制面与数据面版本一致（重点：别一半新一半旧）
istioctl version
istioctl proxy-status | head -20

# ④ Gateway / HTTPRoute 状态没丢
kubectl get gateway -A
kubectl get listenerset -A
kubectl get httproute -A
kubectl get gateway -n clienta-gw-int -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
kubectl get listenerset -n clienta-listenerset-int -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'

# ⑤ mTLS 仍然生效（ztunnel 换了最容易出问题的地方）
kubectl exec -n tenant-runtime deploy/tenant-app -c tenant-app -- \
  curl -sv http://tenant-app-svc.tenant-runtime.svc.cluster.local:80 -o /dev/null
# 期望：200，且连接走 127.0.0.1:15008（HBONE）

# ⑥ e2e 真实域名
curl -k --resolve "$HOST:8443:127.0.0.1" "https://$HOST:8443/" -I   # 期望 HTTP/2 200

# ⑦ CNI 配置是否真的生效（若改过 ConfigMap）
kubectl get ds istio-cni-node -n istio-system -o jsonpath='{.spec.template.metadata.annotations}'
```

**验收标准**：

- [ ] 三个组件镜像 tag 一致（无混版本）
- [ ] Gateway / ListenerSet `Programmed=True`，HTTPRoute `Accepted=True`
- [ ] mesh 内 mTLS 正常，无明文旁路
- [ ] 无 CrashLoopBackOff / 无 ztunnel 重启风暴
- [ ] e2e 域名访问 200

---

## 7. 坑位清单

| # | 坑 | 处置 |
|---|---|---|
| 1 | `gcr.io/istio-release` 里**没有** `*-solo*` 镜像（实测 404） | 用 `us-docker.pkg.dev/soloio-img/istio`，或以集群实际镜像为准 |
| 2 | `helm upgrade` **不带原 values** → 自定义全丢 | 每次先 `helm get values ... -o yaml > x.yaml`，再 `-f x.yaml` |
| 3 | `istio-cni` 改了 ConfigMap **不重启不生效** | `kubectl rollout restart ds/istio-cni-node -n istio-system` |
| 4 | ztunnel 滚动**断长连接** | cordon + 分批 + 观察；长连接业务先评估 |
| 5 | Gateway API tag flip **黑洞 15–30s** | 确认 istiod ≥ 1.30.2；优先 in-place；不在老 istiod 关 Gateway API |
| 6 | 控制面与数据面版本**不一致** | 严格顺序：base → istiod → cni → ztunnel |
| 7 | `-fips` 镜像**需要 Solo License Key** | 升级时保留 `license.value` / `license.secretRef` 配置 |
| 8 | `distroless` 变体**没有 shell**，排障命令全废 | 保留一个非 distroless 的旁路 Pod 排障用；或用 `kubectl exec` 换成 debug 容器 |
| 9 | Gateway API CRD / GEP ListenerSet CRD **版本没同步** | Solo 1.30 建议 Gateway API **1.5.0**；GEP CRD 与 Istio 版本号绑定，一并升 |
| 10 | Solo 1.30 起 **不再 watch `XListenerSet`**（experimental 旧版） | Gateway API < 1.5 的平台改用 `EnterpriseListenerSet`（需 ≥ 1.30.3-patch0 + `SOLO_ENABLE_ENTERPRISE_LISTENER_SET=true`） |
| 11 | Solo 1.30/1.31 的 `WorkloadEntry` autoregistration **可能缺 `networking.istio.io/tunnel: http`** | 缺标签时 VM 流量退化为明文，`source.principals` 授权恒 403；手工补标签或改用 `source.ipBlocks` |
| 12 | 私仓拉取需要凭据 | GKE 上给节点 Service Account 加 `roles/artifactregistry.reader`（或用 imagePullSecret） |
| 13 | `kubectl set image` 的改动**会被下次升级冲掉** | 只用于应急，事后走方式 A / D 正规化 |

---

## 8. 参考

| 断言 | 来源 |
|---|---|
| Ambient 升级 = 控制面 / 数据面 / CRD 分别升级；ztunnel 是 DaemonSet，升级会断连 | [Istio — Upgrade with Helm (Ambient)](https://istio.io/v1.30/docs/ambient/upgrade/helm/) |
| `istio-cni` **不支持 canary / revision 升级** | 同上 |
| revision 不可变、tag 是可变指针；`helm template ... revision-tags-mwc.yaml` 移动 tag | 同上 |
| Canary 升级方法；`istioctl install --revision`、ns 打 `istio.io/rev`、重启 Pod 才换数据面 | [Istio — Canary Upgrades](https://istio.io/v1.30/docs/setup/upgrade/canary/) |
| In-place 升级必须带同样的 `-f` / `--set`，否则自定义被重置；in-place 每次只能跨 1 个 minor | [Istio — In-place Upgrades](https://istio.io/v1.30/docs/setup/upgrade/in-place/) |
| IstioOperator `ComponentSpec` 支持组件级 `hub` / `tag` 覆盖 | [IstioOperator API 参考](https://istio.io/v1.30/docs/reference/config/istio.operator.v1alpha1/) |
| chart 的镜像键：`istiod`/`cni` 用 `global.hub`+`global.tag`；`ztunnel` 用顶层 `hub`+`tag`；`image` 支持全量 `hub/image:tag` | Istio chart values（`release-1.30`：`istio-discovery` / `istio-cni` / `ztunnel`） |
| Solo 1.29+ 镜像仓库 `us-docker.pkg.dev/soloio-img/istio`，Helm OCI `.../istio-helm`；镜像名 pilot/proxyv2/install-cni/ztunnel | [Solo — In-place upgrades with Helm](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/manual/) |
| CNI 安全原地升级机制；ConfigMap 只在启动时读取 | 同上 |
| Gateway API tag-flip 黑洞；修复版本 1.29.5+/1.30.2+/1.31.x；不可在老 istiod 关 Gateway API | [Solo — Canary upgrades with the Gateway API](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/gwapi-canary/) |
| Solo tag 变体（`-solo` / `-fips` / `-distroless`）；FIPS 需 License Key | [Solo — About Solo distributions of Istio](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/) |
| 1.30.x 支持矩阵（K8s 1.32–1.36、Gateway API 1.5–1.6）；必须用最新 patch | [Solo — Supported versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions/) |
| air-gapped 镜像同步流程（枚举 → 拉取 → 推私仓 → 改 `global.hub`） | [Solo — Air-gapped environments](https://docs.solo.io/istio/1.30.x/ambient/setup/install/airgap/) |
| `XListenerSet` 不再被 watch；`EnterpriseListenerSet` 替代方案 | [Solo — EnterpriseListenerSet](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/ingress/enterprise-listener-set/) |
| `WorkloadEntry` autoregistration 缺 `tunnel: http` 标签的已知问题 | [Solo — In-place upgrades with Helm → Known version restrictions](https://docs.solo.io/istio/1.30.x/ambient/operations/upgrade/manual/) |
| Ambient 数据面为节点级 ztunnel；`istio.io/dataplane-mode=ambient` 为开启粒度 | [Istio — Add workloads to the mesh](https://istio.io/v1.30/docs/ambient/usage/add-workloads/) |
| agentgateway 独立 chart 与版本线 | [Solo — Agentgateway as an ingress gateway](https://docs.solo.io/istio/1.30.x/ambient/traffic-management/ingress/agentgateway/) |
