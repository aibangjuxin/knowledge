# Solo 分发 vs 上游 Istio — 版本选型评估(社区方案)

> **TL;DR**:
> - **Solo 没有 "社区版 ambient"** — Solo 卖的是 **license**(Basic / Premium / Enterprise),底层永远是 **Istio 上游 + Solo 分发的强化镜像**
> - **"Solo 开源版"** = 实际是 **Solo 分发的 Istio 镜像,无 license** = 功能等同于上游 Istio
> - **核心差异**:**镜像 tag 形式**(`1.30.3` vs `1.30.3-solo`)+ **CVE 修复周期** + **多 9 个月 n-4 支持**
> - **本场景推荐**:**Solo 分发镜像 + 无 license**(纯 ambient 模式 + Helm 拆分)+ 镜像来自 Solo 仓库 = 享受 CVE 修复 + n-4 支持,**不付任何钱**

---

## 0. 文档定位

> 你已锁定最终方案:**Solo 开源版 + ambient 模式**。
> 
> 关键问题是 — **"Solo 开源版" 到底指什么?** 因为 Solo 的产品线有 4 个 product + 3 个 license tier,容易混。

本文档**回答 3 个问题**:
1. **Solo 的版本 / 产品线到底怎么分?**
2. **本场景用什么具体版本号 / 镜像 / 安装工具?**
3. **与上游 Istio 的差异是什么?**

---

## 1. Solo 产品线速查(避免混淆)

### 1.1 4 个 Solo 产品(2019 价位与免费榜对应)

| Solo 产品 | 基础 OSS 项目 | 免费? | 收费? | 核心价值 |
|---|---|---|---|---|
| **Solo Enterprise for Istio**(formerly Gloo Mesh OSS APIs)| Istio | ✅ 无 license 可跑(基础功能)| 💰 3 个 license tier 解锁企业功能 | Solo 分发的 Istio + CVE backport + n-4 支持 |
| **Gloo Mesh Core** | Istio + Solo platform CRDs | ✅ 部分免费 | 💰 | **管理平面**(多集群发现 / 部署 / lifecycle) |
| **Gloo Mesh Enterprise** | Istio + 多集群联邦 + Gloo CRD | ❌ 付费 | 💰💰 | **多集群 mesh 联邦 + 简化多租户 + service isolation** |
| **Gloo Mesh Gateway** | Envoy + Istio + Gloo CRD | 部分免费 | 💰 | **API 网关层**(VirtualGateway / RouteTable / EnvoyFilter / WAF / rate limit) |

> 来源:[Solo Gloo Platform products](https://docs.solo.io/gloo-mesh-gateway/latest/concepts/platform/overview)

### 1.2 Solo Enterprise for Istio 的 3 个 License Tier

| Tier | 价格 | 包含什么 |
|---|---|---|
| **(无 license)** | 🟢 **免费** | Solo 分发的 Istio 镜像 + CVE backport + n-4 支持 + 长周期维护 |
| **Basic** | 💰 | 免费 + **长期支持** + **FIPS 合规版本** |
| **Premium** | 💰💰 | Basic + **Solo 管理平面** + **Solo UI** + 增强技术支持 |
| **Enterprise** | 💰💰💰 | Premium + **多集群 ambient mesh** + **企业级 feature**(EC2 ambient / agentgateway waypoint / WIMSE token / CEL 授权) |

> 来源:[Solo 1.30 release notes](https://docs.solo.io/istio/1.30.x/reference/changelog/release-notes) + [Solo distribution overview](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/)

### 1.3 关键事实 — "Solo 开源版"在 Solo 生态里的含义

```
❌ 误解 1:"Solo 社区版 ambient" = 单独的产品
✅ 真相:Solo 没有"开源版 ambient"这个独立产品
        "Solo 开源"= Solo Enterprise for Istio **无 license 运行**

❌ 误解 2:用 Solo 一定要买 license
✅ 真相:无 license 可跑,**等同于上游 Istio 1.30**(只是镜像来自 Solo)
        想要多集群 ambient 管理面 / Solo UI / WIMSE 等才需要 license
```

---

## 2. Solo 分发的镜像 vs 上游 Istio 镜像(对比表)

> 这是你最终"setup"时**唯一**需要决定的:用哪个仓库的 image?

| 维度 | 上游 Istio | Solo 分发(Standard)| Solo 分发(Solo)|
|---|---|---|---|
| **镜像仓库** | `gcr.io/istio-release` 或 `docker.io/istio` | `us-docker.pkg.dev/soloio-img/istio` | `us-docker.pkg.dev/soloio-img/istio` |
| **tag 形式**(1.30.3)| `1.30.3-distroless` | `1.30.3-distroless`(相同 tag 名,内容一致) | `1.30.3-solo-distroless`(**带 solo 后缀**) |
| **基础镜像内容** | 等同上游 | 等同上游 + Solo 的 CVE 修复 | 等同上游 + Solo CVE 修复 + 额外 Envoy filters |
| **CVE 修复周期** | 上游 1 个月 minor / patch | **n-4 支持**(多 9 个月)| 同 Solo Standard |
| **FIPS 合规** | ❌ | ✅(`-fips` tag)| ✅(`-fips-solo` tag)|
| **运行时功能** | 与上游完全相同 | 与上游相同 | 多了 **Solo 企业功能**(需 license)|
| **是否免费** | ✅ | ✅ | ✅ |
| **何时用** | 不想绑 Solo 生态 | **想拿 Solo CVE 修复 + n-4 支持** | 想跑企业功能(无 license 跑 = 跟 Solo 一样)|

> 来源:[Solo distributions of Istio overview](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/)

### 2.1 实际 Setup 时,本场景应该选哪个?

```
你的目标:
  - Solo 开源版
  - ambient 模式
  - 社区方案

→ 推荐用 Solo 分发的 Standard 镜像
  - 仓库:us-docker.pkg.dev/soloio-img/istio
  - tag:1.30.3-distroless
  - 不带 -solo 后缀 = 不需要 license
  - 但拿到 Solo 的 n-4 支持 + CVE 修复
```

**为什么不用 `1.30.3-solo-distroless`?**
- `1.30.3-solo-distroless` = Solo 分发 **+ 额外 Envoy filters**(为 Solo 企业功能准备)
- 无 license 跑 = 跟 `1.30.3-distroless` **完全等价**(额外 Envoy filters 不生效)
- 白白承担额外体积 + 无功能收益

### 2.2 镜像差异真相

> 来自 Solo 官方原话:
> "Standard: A copy of the community Istio distribution. This distribution does not contain Solo.io's enterprise features or extended Istio support. Example: `1.30.1`"
>
> "Solo: An enterprise distribution of the community Istio project with additional security patches, as well as certain Envoy filters to enable Solo Enterprise for Istio features. You must use the solo image to use these features. Example: `1.30.1-solo`"
>
> 来源:[Solo distributions of Istio](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/)

---

## 3. Solo 分发版本号与上游 Istio 的对应关系

| Solo 版本 | 对应上游 Istio | 发布日期 | 支持 Kubernetes | K8s Gateway API | 当前状态 |
|---|---|---|---|---|---|
| **Solo 1.30.3** | Istio 1.30.3 | 2026-07-16 | 1.32 - 1.36 | 1.5 - 1.6 | ✅ **Stable** |
| Solo 1.30.0 / 1.30.1 / 1.30.2 | Istio 1.30.0 / .1 / .2 | 2026-05 起 | 1.32 - 1.36 | 1.5 - 1.6 | 早期 patch,已 EOL |
| Solo 1.29.x | Istio 1.29 | 2026-02-24 | 1.30 - 1.35 | 1.4 - 1.5 | ✅ Stable(Gloo Mesh 2.12)|
| Solo 1.28.x | Istio 1.28 | 2025-Q4 | - | - | EOL(超过 n-4 支持窗口)|

> 来源:[Solo 1.30.x supported versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions)

### 3.1 n-4 支持窗口

> "Solo supports n-4 versions for Solo distributions of Istio."
> "The Solo Enterprise for Istio release cycle aligns with the Istio OSS release cadence. After an upstream Istio OSS version is released, a corresponding Solo Enterprise for Istio version is typically released a few days later."

**含义**:
- Istio 上游支持当前 minor + 上一 minor(Istio 只支持 n-1)
- Solo 分发支持 **当前 + 过去 4 个 minor**(n-4)
- → Solo 分发版有 **9 个月额外维护期**

### 3.2 1.30.3 patch 修复了什么

> 来源:[Istio 1.30.3 release notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.3)

| Patch | 修复 | 重要性 |
|---|---|---|
| **1.30.1** | Multi-network ambient 下 ingress 路由到 waypoint 失败的 bug | 🟠 中 |
| 1.30.1 | istio-cni agent 并发 map write panic | 🔴 高 |
| 1.30.1 | consistentHash ring 在 endpoint 更新后不重建 | 🟡 中 |
| 1.30.1 | publishNotReadyAddresses + 流量预设导致流量发给 not-ready 端点 | 🟠 中 |
| 1.30.3 | EXIT_ON_ZERO_ACTIVE_CONNECTIONS 在 ambient ingress gateway 不触发 | 🟡 低 |
| **1.30.3** | **istiod scalability:XDS scoped push**(`AMBIENT_SCOPED_ADDRESS_PUSHES`)| 🟢 正向 |
| 1.30.3 | `PILOT_NODE_UNTAINT_CONTROLLERS_TAINT_NAME` 默认 `cni.istio.io/not-ready` | 🟢 正向 |

**本场景推荐**:**用 1.30.3**(已包含 1.30.1 和 1.30.2 的修复)

---

## 4. 安装工具对比

| 安装方式 | 上游 Istio | Solo 标准版 | Solo Solo 版(企业)|
|---|---|---|---|
| **`istioctl install`** | ✅ | ✅ | ✅ |
| **Helm 拆分 4 chart** | ✅ | ✅ | ✅ |
| **Gloo Operator** | ❌ | ✅ | ✅ |
| **Solo UI** | ❌ | ❌(需 Premium+)| ✅(Enterprise)|

### 4.1 本场景推荐 — Helm 拆分

> **02 文 / 05 文已经用 Helm 拆分方案**,这是 Solo 官方也支持的方式。

```bash
# 关键差异:把 hub 改成 Solo 仓库
export REPO="us-docker.pkg.dev/soloio-img/istio"     # ← Solo 仓库
export HELM_REPO="us-docker.pkg.dev/soloio-img/istio-helm"  # ← Solo Helm 仓库
export ISTIO_VERSION="1.30.3"                            # ← 用 Solo 1.30.3
export ISTIO_IMAGE="${ISTIO_VERSION}-distroless"         # ← 不带 -solo 后缀
```

### 4.2 不要只 4 个 误判 — Solo Helm chart 与上游 chart 区别

```
Solo Helm chart 与上游 Istio chart 的关系:
  - 上游 chart:oci://gcr.io/istio-release/charts/{base,istiod,cni,ztunnel}
  - Solo Helm chart:oci://us-docker.pkg.dev/soloio-img/istio-helm/{base,istiod,cni,ztunnel}

→ 两个仓库的 chart 内容**完全一致**(Solo 不 fork chart,只改镜像)
→ 你可以选任何一个 chart 仓库 + Solo 镜像仓库的组合

本场景推荐:
  - chart:o ci://gcr.io/istio-release/charts/... (上游官方,跟 Istio 升级同步最快)
  - image:us-docker.pkg.dev/soloio-img/istio:1.30.3-distroless (Solo CVE 修复)
```

---

## 5. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **Solo 分发(Standard)** | "Solo 维护的 Istio 镜像" | "A copy of the community Istio distribution. This distribution does not contain Solo.io's enterprise features or extended Istio support." — [Solo docs](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/) |
| **Solo 分发(Solo)** | "Solo 分发 + 企业 filter" | "An enterprise distribution of the community Istio project with additional security patches, as well as certain Envoy filters to enable Solo Enterprise for Istio features, such as support for deploying Istio service meshes in ambient mode. You must use the `solo` image to use these features." — Solo docs |
| **n-4 支持** | "Solo 支持多 4 个 minor" | "Solo supports n-4 versions for Solo distributions of Istio." — Solo docs |
| **Solo Basic license** | "长期支持 + FIPS" | "Basic features are unlocked with a Basic license. These standard features provide you with long-term and FIPS support for Istio on top of the open source offerings of Istio." — [Solo 1.26 overview](https://docs.solo.io/istio/1.26.x/about/overview/) |
| **Solo Premium license** | "Basic + 管理平面 + UI" | "Premium features are unlocked with a Premium license. In addition to all Basic features, a Premium license unlocks better environment visibility and analysis with the Solo Enterprise for Istio management plane and Gloo UI, and increased Solo support." — Solo docs |
| **Solo Enterprise license** | "Premium + 多集群 + 企业 feature" | "Enterprise features are unlocked with an Enterprise license. In addition to all Basic and Premium features, a Premium license unlocks the most comprehensive enterprise-level features." — Solo docs |
| **Gloo Mesh Core** | "管理平面(基础免费)" | "Gloo Mesh Core deploys alongside your Istio environment in single or multicluster environments, and can discover existing Istio installations." — [Solo docs](https://docs.solo.io/gloo-mesh-gateway/latest/concepts/platform/overview) |
| **Gloo Mesh Enterprise** | "多集群 mesh 联邦 + CRD" | "Gloo Mesh Enterprise manages Istio-based service meshes across clusters and infrastructure providers, and secures communication between workloads via mTLS." — Solo docs |
| **Gloo Mesh Gateway** | "API 网关层(基于 Envoy + Istio)" | "Gloo Mesh Gateway is an API gateway based on Envoy and Istio open source technologies." — Solo docs |

---

## 6. 完整 Setup 矩阵 — 本场景用哪个组合

### 6.1 三档对应 — 由低到高

```
档位 A — 完全免费(本场景推荐):
  镜像:Solo 分发 Standard `1.30.3-distroless`
  chart:上游 oci://gcr.io/istio-release/charts/...
  安装工具:Helm 拆分 4 release(02 文方案)
  license:无
  功能:等同上游 Istio 1.30.3 + Solo CVE 修复 + n-4 支持
  适用:dev / 中小生产(本场景)

档位 B — Basic:
  镜像:Solo 分发 `1.30.3-fips-distroless`(FIPS 合规)
  chart:同 A
  license:Basic($/年)
  功能:A + FIPS + 长期支持
  适用:合规场景(政府 / 金融)

档位 C — Premium:
  镜像:同 A 或 B
  chart:同 A
  license:Premium($$/年)
  功能:B + Solo 管理平面 + Solo UI
  适用:多集群管理 + 可观测性平台化

档位 D — Enterprise:
  镜像:`1.30.3-solo-distroless`(企业 filter)
  license:Enterprise($$$/年)
  功能:C + 多集群 ambient mesh 联邦 + 企业 feature
  适用:大型企业 / 跨区域 mesh
```

### 6.2 本场景最终决定

> 已锁定:**Solo 开源版 + ambient**

| 决策项 | 本场景选择 |
|---|---|
| 镜像仓库 | `us-docker.pkg.dev/soloio-img/istio` |
| 镜像 tag 形式 | `1.30.3-distroless`(不带 `-solo` 后缀)|
| chart 仓库 | 上游 `oci://gcr.io/istio-release/charts/` |
| 安装工具 | Helm 拆分 4 release(02 文方案)|
| license | 无 |
| 多集群管理面 | 无(单集群)|
| Solo UI | 无(本场景不需要)|
| FIPS | 合规未强制 → 不需要 |

---

## 7. Setup 命令模板(Solo 1.30.3 + Helm)

> 复用 02 文的安装方案,**只改 hub 与 tag**。

```bash
export REPO="us-docker.pkg.dev/soloio-img/istio"
export HELM_REPO="us-docker.pkg.dev/soloio-img/istio-helm"
export ISTIO_VERSION="1.30.3"
export TAG="${ISTIO_VERSION}-distroless"   # 注意:不带 -solo
export ISTIO_NS="istio-system"

# Step 1:base
helm upgrade --install istio-base \
  oci://${HELM_REPO}/base \
  --namespace ${ISTIO_NS} \
  --create-namespace \
  --version ${ISTIO_VERSION} \
  -f values/base.yaml

# Step 2:istiod
helm upgrade --install istiod \
  oci://${HELM_REPO}/istiod \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f values/istiod.yaml

# Step 3:cni
helm upgrade --install istio-cni \
  oci://${HELM_REPO}/cni \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f values/cni.yaml

# Step 4:ztunnel
helm upgrade --install ztunnel \
  oci://${HELM_REPO}/ztunnel \
  --namespace ${ISTIO_NS} \
  --version ${ISTIO_VERSION} \
  -f values/ztunnel.yaml
```

### 7.1 values 改动

> 与 02 文 `values/` 目录的差异只有 **hub 字段**:

```yaml
# values/istiod.yaml(其他 3 个 chart 类似)
global:
  hub: us-docker.pkg.dev/soloio-img/istio      # ← 从 europe-west2-docker.pkg.dev/.../containers 改为这个
  tag: 1.30.3-distroless
  platform: gke
```

---

## 8. 何时升级 license?何时升级到上游?

### 8.1 升级 license 触发条件

```
现在免费 → 何时付费?
  │
  ├─ 需要多集群 ambient mesh 联邦
  │   └─ 升 Enterprise
  │
  ├─ 需要 Solo UI / 管理平面
  │   └─ 升 Premium
  │
  ├─ 需要 FIPS 合规(政府/金融)
  │   └─ 升 Basic(最低付费 tier)
  │
  └─ 都不要
      └─ 保持免费
```

### 8.2 镜像切换触发条件

| 切换 | 触发 |
|---|---|
| **Solo Standard → Solo Solo** | 需要企业功能 / 多集群 |
| **Solo → 上游 Istio** | 想脱离 Solo 生态 / 不想依赖 Solo CVE backport |
| **Solo 1.30.x → Solo 1.31.x** | patch 累积太多 / 新 feature(1.30 stable,1.31 GA)|

---

## 9. 决策树 — 我该选哪个组合?

```
你的需求?
  │
  ├─ 单集群 + ambient + 不要付费
  │   └─ ✅ 本场景推荐(Solo Standard + Helm + 无 license)
  │
  ├─ 多集群 + ambient
  │   └─ 选 Solo Enterprise(license)
  │
  ├─ FIPS 合规
  │   └─ 选 Solo Basic + FIPS 镜像
  │
  ├─ 想完全脱离 Solo 生态
  │   └─ 选上游 Istio 镜像 + 上游 chart(02 文原始方案)
  │
  └─ 想跑 Gloo 体系的全套(gateway + mesh + UI)
      └─ 选 Gloo Mesh Gateway Enterprise
```

---

## 10. 反向 — Solo 不是万能的场景

| 场景 | 推荐 |
|---|---|
| **跨厂商 mesh 联邦**(Istio + Linkerd 互通)| Solo 不解决(用 Submariner / Skupper)|
| **VM workload 加入 mesh** | Solo 1.30 有 alpha 支持(`istioctl vm add-workload`),生产需谨慎 |
| **AI Gateway**(MCP / agentic workload)| Solo agentgateway 1.30 是 alpha,上游 Istio 也有 |
| **非 K8s 部署** | Solo 不解决(用 Istio 多集群 on VM)|

---

## 11. 与本目录其他文档的关系

| 文档 | 关系 |
|---|---|
| `02-install-ambient-helm.md` | **基础安装方案**,镜像 hub 改为 Solo 后直接复用 |
| `05-upgrade-strategies.md` | 升级机制与 Solo 镜像升级一致(`1.30.3-solo` patch 升)|
| `07-feature-status-1.30.3.md` | Istio 1.30.3 GA 状态矩阵,**Solo 分发版本号 = 上游版本号**,矩阵直接复用 |
| `12-revision-canary-mtls-compat.md` | mTLS / 双 revision 兼容,Solo 镜像无差异 |
| `17-istio-image-tag-automation-sre-workflow.md` | Image Updater 监听 GAR,**改成监听 Solo GAR**(`us-docker.pkg.dev/soloio-img/istio`)|
| `ADR-LOCAL-001-migrate-minimal-to-ambient.md` | 决策记录 — `2_install` 阶段镜像来源改为 Solo |

### 11.1 镜像源变更清单

| 原(02 文)| 新(本篇)|
|---|---|
| `europe-west2-docker.pkg.dev/aibang-12345678-ajbx-dev/containers` | `us-docker.pkg.dev/soloio-img/istio` |
| `proxyv2:1.30.3-distroless` | (Proxy 不再需手动,Helm chart 自带)|
| `pilot:1.30.3-distroless` | `1.30.3-distroless`(Solo Standard)|
| (新增)| `install-cni:1.30.3-distroless`(Solo Standard)|
| (新增)| `ztunnel:1.30.3-distroless`(Solo Standard)|

---

## 12. References

### 12.1 Solo 官方权威

- [Solo Enterprise for Istio 1.30.x overview](https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/) — Solo 分发与 license 总览
- [Solo 1.30.x supported versions](https://docs.solo.io/istio/1.30.x/ambient/about/images/versions) — 版本支持矩阵
- [Solo 1.30.x release notes](https://docs.solo.io/istio/1.30.x/reference/changelog/release-notes) — patch 内容
- [Solo Enterprise for Istio 1.30.x ambient setup (Helm)](https://docs.solo.io/istio/1.30.x/ambient/setup/install/manual) — Helm 安装权威步骤
- [Gloo Platform products overview](https://docs.solo.io/gloo-mesh-gateway/latest/concepts/platform/overview) — 4 个产品总览
- [Solo Enterprise vs Open Source comparison](https://www.solo.io/resources/datasheet/istio-enterprise-feature-comparison) — feature comparison

### 12.2 上游 Istio 对照

- [Istio 1.30 release announcement](https://istio.io/latest/news/releases/1.30.x/announcing-1.30)
- [Istio 1.30.3 patch notes](https://istio.io/latest/news/releases/1.30.x/announcing-1.30.3)
- [Istio 1.30 feature status](https://istio.io/latest/docs/releases/feature-status/)

### 12.3 本目录关联

- `02-install-ambient-helm.md` — Helm 拆分基础
- `05-upgrade-strategies.md` — 升级机制
- `07-feature-status-1.30.3.md` — 1.30.3 feature 矩阵
- `12-revision-canary-mtls-compat.md` — mTLS 兼容
- `17-istio-image-tag-automation-sre-workflow.md` — Image Updater(改监听 Solo GAR)
- `ADR-LOCAL-001-migrate-minimal-to-ambient.md` — 决策记录(需更新 Phase 1 镜像来源)

---

## 13. 关键认知 checklist(自测)

| # | 问题 | 答案要点 |
|---|---|---|
| 1 | **Solo 有"开源版 ambient"产品吗?** | ❌ 无 — Solo 卖 license,底层永远是 Istio 上游 + Solo 镜像 |
| 2 | **"Solo 开源"= 什么?** | Solo 分发的 Standard 镜像 + 无 license = 功能等同上游 Istio |
| 3 | **本场景用哪个 tag?** | `1.30.3-distroless`(不带 `-solo` 后缀)|
| 4 | **为什么不用 `-solo` tag?** | 无 license 时 `-solo` 与不带 `-solo` 功能完全相同,带反而有体积开销 |
| 5 | **本场景需要 license 吗?** | ❌ 不要(单集群 + ambient + 无多集群 / 无 UI / 无 FIPS)|
| 6 | **本场景镜像仓库?** | `us-docker.pkg.dev/soloio-img/istio` |
| 7 | **本场景 chart 仓库?** | 上游 `oci://gcr.io/istio-release/charts/...` |
| 8 | **n-4 支持带来什么?** | Solo 分发版比上游多 9 个月安全补丁窗口(本场景不直接受益,未来升版时受益) |

> 自测 8/8 = 已掌握;6-7 = 大部分懂;≤ 5 = 重读 §1-2

---

## 14. 总结 — 一句话 Setup

**用 Solo 分发的 Standard 镜像 `1.30.3-distroless` + 上游 Istio Helm chart + 无 license + Helm 拆分 4 release 安装,在功能上完全等同于上游 Istio 1.30.3,只是额外获得 Solo 的 CVE backport 与 n-4 支持承诺。**