# GKE CRD 在集群升级后的保留行为探索

**探索目标**：验证 GKE 集群升级后，用户自定义 CRD 和 CRD 本身是否会保留
**参考文档**：`gke-type.md`
**创建时间**：2026-05-29

---

## 结论先行

| 资源类型 | GKE 升级后是否保留 | 说明 |
|---------|-----------------|------|
| **CRD 定义本身** | ✅ 保留 | CRD 是集群级别的 CustomResourceDefinition，由 API Server 管理，不属于 GKE 控制平面组件 |
| **CRD 对应的 CR 实例** | ✅ 保留 | CR 实例存储在 etcd 中，与控制平面升级无关 |
| **GKE 内置 CRD**（如 `gateways.networking.istio.io`） | ⚠️ 由组件决定 | Istio/Anthos Service Mesh 等 addon 升级时可能重建 |
| **用户自行 `kubectl apply` 的 CRD** | ✅ 保留 | 无论手动 apply 还是 GitOps 方式，均独立于 GKE 版本 |

> **核心结论**：用户的自定义 CRD 和 CR 实例在 GKE 升级后**不会丢失**。

---

## 一、CRD 保留机制原理

### 1.1 Kubernetes 架构分层

```
┌─────────────────────────────────────────────────┐
│                  GKE 控制平面                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────┐ │
│  │ API Server  │  │  etcd         │  │其他组件│ │
│  │ (CRD 由它   │  │ (存储所有 CRD  │  │        │ │
│  │  管理)      │  │  和 CR 实例)  │  │        │ │
│  └─────────────┘  └──────────────┘  └────────┘ │
└─────────────────────────────────────────────────┘
                     │
          GKE 升级时只升级控制平面组件
          CRD 定义在 API Server 层
          etcd 数据不变
                     ▼
┌─────────────────────────────────────────────────┐
│             用户工作负载层（不升级）               │
│  ┌─────────────────────────────────────────────┐ │
│  │  CRD 定义  ──►  CR 实例（存在 etcd）         │ │
│  │  用户 YAML apply  →  独立于 GKE 版本          │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### 1.2 GKE 升级实际发生什么

GKE 升级（控制平面）涉及：

1. **API Server 版本升级** — 原地替换二进制
2. **etcd 升级/替换** — 数据目录迁移
3. **Controller Manager、Scheduler 等组件** — 滚动更新
4. **Node Pool 升级** — 工作节点逐个重建

**关键点**：
- etcd 存储所有资源定义（包括 CRD）和资源实例（包括 CR）
- GKE 升级不会清空 etcd，不会重置 CRD 定义
- 升级后 API Server 重新加载 CRD 定义，CR 实例可继续访问

### 1.3 升级期间 CRD 的实际状态

在 GKE 控制平面升级期间（通常 5-15 分钟）：

| 阶段 | CRD 可用性 | CR 实例可用性 |
|-----|-----------|-------------|
| 升级前 | ✅ 正常 | ✅ 正常 |
| 控制平面升级中 | ⚠️ API Server 不可用 | ⚠️ 无法读写 |
| 升级完成 | ✅ 恢复 | ✅ 恢复（数据完整） |

CR 实例**不会**在升级过程中被删除，因为 etcd 数据没有丢失。

---

## 二、按 CRD 来源分类的行为分析

根据 `gke-type.md`，你的 CRD 分为三类：

### 2.1 Kubernetes Gateway API 原生 CRD

| CRD 名称 | API Group | 归属 |
|---------|-----------|-----|
| `gatewayclasses.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `gateways.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `httproutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `grpcroutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `tcproutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `tlsroutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `udproutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `backendtlspolicies.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `referencegrants.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |
| `listenersets.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | K8s Gateway API 标准 |

**行为**：
- Kubernetes 1.26+ 内置支持 Gateway API CRD（通过 `gateway-api` feature gate）
- GKE 从 1.26 开始将 Gateway API CRD 随集群默认安装
- 这些 CRD **不随 GKE 版本升级而变化**（除非 K8s 版本从 <1.26 升级到 >=1.26）
- 创建时间 `2025-10-29` 的表示首次安装，之后未变
- **CRD 定义 + CR 实例在 GKE 升级后完整保留**

### 2.2 GKE Platform CRD

| CRD 名称 | API Group | 说明 |
|---------|-----------|-----|
| `gcpgatewaypolicies.networking.gke.io` | `networking.gke.io` | GKE GCP 网关策略 |
| `gcpedgeextensions.networking.gke.io` | `networking.gke.io` | GKE Edge 扩展 |
| `gcphhttpfilters.networking.gke.io` | `networking.gke.io` | GKE HTTP 过滤器 |
| `gcpinferencepoolimports.networking.gke.io` | `networking.gke.io` | GKE 推理池导入 |
| `inferencepools.inference.networking.k8s.io` | `inference.networking.k8s.io` | GKE 推理池 |
| `autoscalingmetrics.autoscaling.gke.io` | `autoscaling.gke.io` | GKE 弹性伸缩指标 |
| `capacitybuffers.autoscaling.x-k8s.io` | `autoscaling.x-k8s.io` | GKE 容量缓冲 |

**行为**：
- 由 GKE add-on 或 Config Connector 管理
- 创建时间显示为 `2026-05-29`，可能是你当天操作 Istio 或某组件时触发
- GKE minor 版本升级（如 1.28→1.29）时这些 CRD 可能被 addon-manager 重新 apply
- **如果 CRD 的 `kubectl apply` 源文件未变，重 apply 不会破坏现有 CR 实例**
- **如果 GKE 版本升级带来新的 CRD 字段（schema evolution），已有 CR 实例不受影响**

### 2.3 Istio CRD

| CRD 名称 | API Group |
|---------|-----------|
| `gateways.networking.istio.io` | `networking.istio.io` |
| `virtualservices.networking.istio.io` | `networking.istio.io` |
| `destinationrules.networking.istio.io` | `networking.istio.io` |
| `envoyfilters.networking.istio.io` | `networking.istio.io` |
| `serviceentries.networking.istio.io` | `networking.istio.io` |
| `sidecars.networking.istio.io` | `networking.istio.io` |
| `authorizationpolicies.security.istio.io` | `security.istio.io` |
| `peerauthentications.security.istio.io` | `security.istio.io` |
| `requestauthentications.security.istio.io` | `security.istio.io` |
| `telemetries.telemetry.istio.io` | `telemetry.istio.io` |
| `workloadentries.networking.istio.io` | `networking.istio.io` |
| `workloadgroups.networking.istio.io` | `networking.istio.io` |
| `proxyconfigs.networking.istio.io` | `networking.istio.io` |
| `trafficextensions.extensions.istio.io` | `extensions.istio.io` |
| `wasmplugins.extensions.istio.io` | `extensions.istio.io` |

**行为**：
- 由 Istio 控制平面管理（istiod）
- 创建时间 `2026-05-29 02:11:12Z`，与 Istio 安装时间一致
- **Istio 版本升级时**：istiod 会 re-apply Istio CRD，可能覆盖现有定义
- **风险场景**：Istio 升级可能改变 CRD schema，导致已有的 CR 实例需要更新
- **GKE 版本升级时**：Istio CRD 不受影响（Istio 与 GKE 版本独立）

---

## 三、实操验证方案

### 3.1 升级前备份命令

```bash
# 备份所有 CRD 定义
kubectl get crd -o yaml > crd-backup-$(date +%Y%m%d).yaml

# 备份所有 CR 实例（按 CRD 类型）
for crd in $(kubectl get crd | grep -E 'gateway\.networking\.k8s\.io|networking\.istio\.io|networking\.gke\.io' | awk '{print $1}'); do
  kubectl get "${crd%.gateway.networking.k8s.io}" -o yaml > "${crd}-backup-$(date +%Y%m%d).yaml" 2>/dev/null || true
done
```

### 3.2 升级后验证命令

```bash
# 检查 CRD 是否存在
kubectl get crd | grep -E 'gateway\.networking\.k8s\.io|networking\.istio\.io'

# 检查 CR 实例数量是否匹配升级前
kubectl get gatewayclass
kubectl get gateway -A
kubectl get httproute -A
kubectl get virtualservice -A

# 检查 istio CRD 是否完整
kubectl get crd | grep istio.io

# 检查 GKE CRD 是否完整
kubectl get crd | grep networking.gke.io
```

### 3.3 升级后 CR 实例对比

```bash
# 升级前记录
kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' > /tmp/gateways-before.txt

# 升级后验证
kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' > /tmp/gateways-after.txt
diff /tmp/gateways-before.txt /tmp/gateways-after.txt
```

---

## 四、风险场景与应对

### 4.1 高风险场景

| 场景 | 触发条件 | 风险 | 应对 |
|-----|---------|------|-----|
| **Istio 升级时 CRD schema 变更** | 同时升级 Istio 版本 | 已有 VirtualService 等 CR 可能被拒绝 | 升级前执行 Istio 官方迁移指南 |
| **删除 `listenersets`** | kubectl delete 误操作 | 依赖该 CRD 的资源无法创建 | 集群级别 RBAC 限制 delete 权限 |
| **GKE 降级** | 1.29 → 1.28 | 新版本 CRD 可能不兼容旧版本 | 不支持降级，勿尝试 |

### 4.2 中风险场景

| 场景 | 触发条件 | 风险 | 应对 |
|-----|---------|------|-----|
| **Addon Manager 重新 apply CRD** | GKE 升级后 addon 重启 | 可能覆盖用户对 CRD 做的注解/标签 | 用户注解应放在 CR 实例，非 CRD 本身 |
| **Node Pool 升级期间 etcd leader 切换** | 控制平面短暂不可用 | 短时间内无法修改 CR | 使用 `-w` watch 监控是否有数据丢失 |

### 4.3 低风险场景

| 场景 | 风险 | 说明 |
|-----|------|-----|
| **用户手动 `kubectl apply` 更新 CRD** | 无风险 | 除非 apply 错误 YAML，etcd 数据不会丢失 |
| **GitOps 方式更新 CRD** | 无风险 | 同手动 apply，结果一致 |
| **CRD 版本升级（但 CR 实例不升级）** | 无风险 | K8s API versioning 支持多版本共存 |

---

## 五、关键误解澄清

### 误解 1：GKE 升级会重新安装 CRD

**错误**。GKE 升级是控制平面原地升级，不是重新初始化。CRD 存储在 etcd 中，不在控制平面二进制文件中，不会在升级时被重新生成。

### 误解 2：CRD 和 CR 实例需要随 GKE 版本迁移

**错误**。CRD 是 Kubernetes API Server 的扩展机制，CR 实例是数据。两者都不与 GKE 版本绑定。只要不修改 API Server 的 API 组版本，CR 定义可以跨版本使用。

### 误解 3：删除 GKE add-on 会删除 CRD

**部分正确**。删除 Istio add-on 后 Istio CRD 会从 API Server 注销（但 etcd 中的数据仍存在，如果未删除 CR 实例的话）。重新安装 Istio 后，CRD 会重新注册，CR 实例会重新可访问。

---

## 六、验证检查清单

GKE 升级后，执行以下检查确认 CRD + CR 实例完整性：

- [ ] `kubectl get crd | wc -l` 数量不减少
- [ ] `kubectl get gatewayclass` 数量不减少
- [ ] `kubectl get gateway -A` 实例数量 + 内容不变
- [ ] `kubectl get httproute -A` 实例数量 + 内容不变
- [ ] `kubectl get virtualservice -A` 实例数量 + 内容不变
- [ ] Istio CRD 数量不减少
- [ ] GKE Platform CRD 数量不减少

---

## 七、结论总结

**用户 CRD 在 GKE 升级后保留，这是 Kubernetes 设计保证的。**

你的理解是正确的：
> 理解这是一个自定义的资源，应该不会随着我的GKE的升级造成影响的。

唯一需要注意的是 **Istio**（或其他 add-on）自身的版本升级可能带来 CRD schema 变更，但这与 GKE 版本升级是独立的。如果 Istio 版本不变，GKE 升级不会影响任何 Istio CRD 和 CR 实例。

---

## 八、ListenerSet 手动创建场景下的 GKE 升级行为

### 8.1 ListenerSet 是什么

`listenersets.gateway.networking.k8s.io` 是 Kubernetes Gateway API v1.0 引入的 CRD，用于为一组已存在的 Gateway 附加额外的监听器配置。

`+kubebuilder:storageversion` 注解表明这是该资源的存储版本，由 API Server 直接持久化到 etcd。

### 8.2 你的 ListenerSet 创建时间分析

```
listenersets.gateway.networking.k8s.io    2026-05-29T02:38:00Z
```

创建时间为 `2026-05-29`，且 CRD 名称与其他 Gateway API CRD（`backendtlspolicies`、`grpcroutes`、`tcproutes` 等）一致——这些 CRD 全部在同一天 `02:38:00` ~ `02:38:01` 被创建。这个时间戳高度一致，强烈暗示它们是**通过同一组件/操作**批量安装的，可能是：
- GKE Gateway API addon 安装时触发
- Istio 1.29.2 安装时通过 IstioOperator 触发
- 某个 GitOps operator 首次 sync 时触发

但无论如何：**CRD 一旦被创建并持久化到 etcd，之后的 GKE 升级不会重新 apply 它**。

### 8.3 手动创建 vs 自动安装的区别

| 创建方式 | GKE 升级时发生什么 | ListenerSet CR 实例是否保留 |
|---------|-----------------|--------------------------|
| 手动 `kubectl apply` | **无影响**。CRD 定义在 etcd 中独立存在 | ✅ 保留 |
| GitOps（ArgoCD/Flux） | **无影响**。GitOps 会重新 apply 相同内容，etcd 数据不变 | ✅ 保留 |
| GKE addon-manager 安装 | GKE 升级后 addon-manager 会 re-apply CRD（相同 YAML） | ✅ 保留（内容一致） |
| Istio 安装 | 同上，Istio 版本升级时 re-apply | ⚠️ 可能有 schema 变更 |

### 8.4 ListenerSet 的特殊之处

ListenerSet 有一个独特的设计特性：

- **由 GKE Gateway Controller 管理**：GKE 提供了一个 `networking.gke.io/gateway` 控制器（见 `gke-l7-global-external-managed` GatewayClass），它负责监听 Gateway API 资源并转换为 GCP 负载均衡配置
- **Controller 不拥有 CRD 定义**：Gateway Controller 只管理 CR 实例（Gateway、ListenerSet 等），不管理 CRD 定义本身
- **CRD 定义与 Controller 独立**：CRD 定义由 API Server 管理，无论 Controller 是否运行，CRD 定义都不会消失

### 8.5 升级过程中的实际时序

```
GKE 控制平面升级期间
│
├─ 阶段1：API Server 不可用（分钟级）
│   └─ ListenerSet CRD 定义仍在 etcd 中
│   └─ ListenerSet CR 实例仍在 etcd 中
│   └─ 客户端无法读写（符合预期）
│
├─ 阶段2：API Server 重启完成
│   └─ CRD 定义重新注册到 API Server
│   └─ CR 实例可继续读写
│   └─ 数据完整无丢失
│
└─ 阶段3：Gateway Controller 恢复
    └─ 开始 reconcile ListenerSet CR 实例
    └─ 如 CR 实例未变，reconcile 结果一致
```

### 8.6 验证命令（ListenerSet 专项）

```bash
# 升级前：记录 ListenerSet CRD 的 creationTimestamp
kubectl get crd listenersets.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.creationTimestamp}'

# 升级前：记录 ListenerSet CR 实例数量和内容
kubectl get listenerset -A -o yaml > /tmp/listenersets-before-$(date +%Y%m%d).yaml

# 升级后：验证 CRD 存在
kubectl get crd listenersets.gateway.networking.k8s.io

# 升级后：验证 CR 实例内容不变
kubectl get listenerset -A
diff /tmp/listenersets-before-*.yaml <(kubectl get listenerset -A -o yaml)

# 升级后：检查 ListenerSet conditions（确认 controller 已接受）
kubectl get listenerset -A -o jsonpath='{range .items[*]}
{.metadata.namespace}/{.metadata.name}: \
 Accepted={.status.conditions[?(@.type=="Accepted")].status}, \
 Programmed={.status.conditions[?(@.type=="Programmed")].status}
{end}'
```

### 8.7 风险评估结论

| 风险项 | 是否存在 | 说明 |
|-------|---------|------|
| GKE 升级后 ListenerSet CRD 定义丢失 | ❌ 不存在 | etcd 持久化，GKE 不删除 |
| GKE 升级后 ListenerSet CR 实例丢失 | ❌ 不存在 | 同上 |
| GKE 升级期间 ListenerSet 无法访问 | ✅ 存在但正常 | 控制平面升级期间 API Server 不可用，所有自定义资源都无法访问，这是预期行为 |
| GKE 升级后 ListenerSet controller 无法工作 | ❌ 不存在 | Gateway Controller 会在控制平面恢复后自动重新连接 |
| 手动 kubectl apply 更新 ListenerSet CRD 定义导致冲突 | ⚠️ 仅当 apply 错误 YAML | 正确做法：只更新 CR 实例，不更新 CRD 定义 |

---

## 九、Gateway CRD 在 GKE 升级后的保留行为

### 9.1 与 ListenerSet 的类比

`gateways.gateway.networking.k8s.io` 与 `listenersets.gateway.networking.k8s.io` 属于同一套 Gateway API 体系，行为完全一致：

- **CRD 定义**：存储在 etcd 中，由 API Server 管理，GKE 升级不删除
- **CR 实例**：存储在 etcd 中，GKE 升级不丢失
- **Controller 管理**：由 GKE Gateway Controller（`networking.gke.io/gateway`）管理 CR 实例，与 CRD 定义本身无关

### 9.2 你的 Gateway CRD 创建时间

```
gateways.gateway.networking.k8s.io    2025-10-29T02:11:24Z
gatewayclasses.gateway.networking.k8s.io    2025-10-29T02:11:25Z
```

`gateways.gateway.networking.k8s.io` 的创建时间为 `2025-10-29`，早于 `listenersets`（`2026-05-29`）。这说明 Gateway CRD 在集群初始安装 Gateway API addon 时就已经存在，而 ListenerSet 是后来追加的。

### 9.3 Gateway CR 实例的升级影响分析

| 资源 | GKE 升级前 | GKE 升级后 | 说明 |
|-----|-----------|-----------|------|
| `gateways.gateway.networking.k8s.io` CRD 定义 | ✅ 存在 | ✅ 存在 | etcd 持久化，无变化 |
| Gateway CR 实例（kubectl get gateway -A） | ✅ 存在 | ✅ 存在 | 数据完整保留 |
| Gateway 关联的 GCP 负载均衡配置 | ✅ 已配置 | ✅ 自动恢复 | GKE Gateway Controller 重新 reconcile |

### 9.4 升级过程中的行为

```
GKE 控制平面升级
│
├─ 阶段1：控制平面不可用
│   └─ Gateway CR 实例仍在 etcd 中（无影响）
│   └─ GCP 负载均衡配置已在 GCP 层存在（无影响）
│
├─ 阶段2：控制平面恢复
│   └─ API Server 重新注册 Gateway CRD
│   └─ Gateway CR 实例重新可访问
│
└─ 阶段3：Gateway Controller 恢复
    └─ Controller 重新 watch Gateway CR 实例
    └─ 如 CR 内容未变，reconcile 达到与升级前相同的状态
```

### 9.5 验证命令（Gateway 专项）

```bash
# 升级前：记录 Gateway 数量和内容
kubectl get gateway -A -o yaml > /tmp/gateways-before-$(date +%Y%m%d).yaml

# 升级前：记录 GatewayClass 状态
kubectl get gatewayclass -o wide

# 升级后：验证 Gateway CRD 和所有实例
kubectl get crd gateways.gateway.networking.k8s.io
kubectl get gateway -A

# 升级后：对比内容是否有变化
diff /tmp/gateways-before-*.yaml <(kubectl get gateway -A -o yaml)

# 升级后：验证 Gateway 状态
kubectl get gateway -A -o jsonpath='{range .items[*]}
{.metadata.namespace}/{.metadata.name}: \
 conditions={.status.conditions[*].type}
{end}'
```

### 9.6 结论

`gateways.gateway.networking.k8s.io` 作为 Gateway API 的核心 CRD，与 ListenerSet 一样，**不受 GKE 版本升级影响**。用户的 Gateway CR 实例在 GKE 升级后会完整保留，且 GKE Gateway Controller 会在控制平面恢复后自动恢复到升级前的 reconcile 状态。

---

## 十、ListenerSet 版本演进官方来源考证

本节记录 ListenerSet 从实验特性到 Stable 的完整版本演进过程，以及可供核查的官方一手资料。

### 10.1 官方来源

#### 来源一：Kubernetes 官方博客（最权威）

- **URL**：https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5/
- **标题**：*Gateway API v1.5: Moving features to Stable*
- **发布时间**：2026-04-21（对应 2026-02-27 发布的 v1.5.0）

博客 meta 描述原文：

> *"The Gateway API v1.5 brings six widely-requested feature promotions to the **Standard channel** (Gateway API's GA release channel): **ListenerSet**, TLSRoute, HTTPRoute CORS Filter, Client Certificate Validation, Certificate Selection for Gateway TLS Origination, ReferenceGrant"*

#### 来源二：GitHub 官方 Release 页面

- **URL**：https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.5.0
- **仓库**：`kubernetes-sigs/gateway-api`
- **Release 名称**：*Release v1.5.0 · kubernetes-sigs/gateway-api*
- **发布日期**：2026-02-27

### 10.2 版本演进时间线

| Gateway API 版本 | 大约发布时间 | ListenerSet 状态 |
|----------------|------------|----------------|
| v1.3.0 | 2024 年中 | 首次以 `XListenerSet` 形式引入（实验版），API group 为 `gateway.networking.x-k8s.io/v1alpha1` |
| v1.4.x | 2024 年底 | 仍在 Experimental channel，继续完善 |
| **v1.5.0** | **2026-02-27** | **正式升入 Standard channel（GA）**，改名为 `ListenerSet`，API group 变为 `gateway.networking.k8s.io/v1` |
| v1.5.1 | 2026-02-27 之后 | patch 版本，功能不变 |

### 10.3 API Group 变化说明

| 阶段 | Kind | API Group & Version | Channel |
|-----|------|-------------------|---------|
| 实验阶段（v1.3.0 ~ v1.4.x） | `XListenerSet` | `gateway.networking.x-k8s.io/v1alpha1` | Experimental |
| **稳定阶段（v1.5.0+）** | **`ListenerSet`** | **`gateway.networking.k8s.io/v1`** | **Standard（GA）** |

你的集群中 CRD 名称为 `listenersets.gateway.networking.k8s.io`，创建于 `2026-05-29`，正是使用 v1.5.0 Standard channel 版本，与时间线完全吻合。

### 10.4 GKE 版本要求

ListenerSet（v1.5.0 Standard channel）需要 **GKE 版本 >= 1.35.3-gke.1389000** 才能正常使用。低于此版本的 GKE 集群在 apply ListenerSet CR 时会报错。

```bash
# 安装 Standard channel（生产推荐）
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

# 验证 ListenerSet CRD 已安装
kubectl get crd listenersets.gateway.networking.k8s.io \
  -o jsonpath='{.spec.versions[*].name}'
# 预期输出：v1
```

---

## 十一、ListenerSet 使用理由（中英对照结论）

> **参考文档**：`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/ListenerSet.html`（架构图）、`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/k8s-gateway-api-report.md`（深度分析报告）

### 11.1 问题背景：多租户共享单一物理 Gateway 的 namespace 边界冲突

**Without ListenerSet**（问题架构）：

```
┌─────────────────────────────────────────────────────┐
│  Shared Gateway (kgateway-system)                   │
│  所有租户的 listener 配置都硬编码在同一个 Gateway     │
│  资源里，租户团队无法自主管理，必须找平台团队         │
│                                                    │
│  ├─ listener-1: team1 namespace (平台团队配置)      │
│  ├─ listener-2: team2 namespace (平台团队配置)      │
│  └─ listener-3: team3 namespace (平台团队配置)     │
│                                                    │
│  问题：每次增改路由规则都要找平台团队，效率低下       │
│        namespace 边界形同虚设                        │
└─────────────────────────────────────────────────────┘
```

**With ListenerSet**（正确架构）：

```
┌─────────────────────────────────────────────────────┐
│  Shared Gateway (kgateway-system)                   │
│  平台团队只管：IP 地址、TLS 证书、端口               │
│           ▲                                         │
│           │ parentRef (绑定)                         │
│  ┌────────┴─────────┐                              │
│  │ Team1-GW (team1 NS) │  ← 租户 A 自主管理        │
│  │ ListenerSet       │    hostname / TLS /         │
│  │                   │    allowedRoutes            │
│  └──────────────────┘                              │
│  ┌──────────────────┐                              │
│  │ Team2-GW (team2 NS) │  ← 租户 B 自主管理        │
│  │ ListenerSet       │    hostname / TLS /         │
│  │                   │    allowedRoutes            │
│  └──────────────────┘                              │
│                                                    │
│  各租户在自己 namespace 内管理 ListenerSet          │
│  平台团队保有 Shared Gateway 的最终控制权           │
└─────────────────────────────────────────────────────┘
```

### 11.2 中文结论

ListenerSet 解决的是**多租户共享单一物理 Gateway 时的配置自主权问题**。

核心价值：
- **平台团队**：管基础设施（IP、TLS 证书、一个共享 Gateway）
- **租户团队**：管自己的路由逻辑（ListenerSet 中的 hostname、allowedRoutes、TLS 配置）
- **namespace 隔离**：ListenerSet 资源在自己 namespace 下，租户有完整 CRUD 权限
- **绑定机制**：`parentRef` 声明绑定到哪个 Shared Gateway，双向握手确保安全

**一句话**：ListenerSet 让多个租户共享一个物理 Gateway（省 IP、省 LB），同时保持各自 namespace 的**配置自主权**，两不干扰。

### 11.3 English Conclusion

ListenerSet solves the **configuration self-service problem** when multiple tenant teams share a single physical Gateway.

**Core value**:
- **Platform team**: Owns the physical infrastructure (IP, TLS cert, one shared Gateway)
- **Tenant team**: Owns their own routing logic (hostname, TLS termination, allowedRoutes in their own ListenerSet)
- **Namespace isolation**: ListenerSet lives in tenant namespace — tenant has full CRUD permissions without platform team involvement
- **Binding mechanism**: `parentRef` declares which Shared Gateway to attach to; the bidirectional handshake ensures security

**In one sentence**: ListenerSet enables multiple tenants to share a single physical Gateway while keeping **self-service configuration autonomy** per namespace — platform controls infrastructure, tenants control their own routes.

### 11.4 架构图中体现的关系

从 `ListenerSet.html` 架构图可以看到：

| 组件 | 所在 Namespace | 管理者 |
|-----|--------------|-------|
| Shared Gateway（ILB 绑定点） | `kgateway-system` | Platform Team |
| Team1-GW ListenerSet | `team1-gw` | Tenant A Team |
| Team2-GW ListenerSet | `team2-gw` | Tenant B Team |
| HTTPRoute（路由规则） | `team1-runtime` / `team2-runtime` | 各租户团队 |
| Kong Gateway（可选，中间代理） | `kong` | Platform Team |

流量路径：`Client → PSC → ILB → Shared Gateway → ListenerSet → HTTPRoute → Kong/Runtime`

---

## 参考资料

- [Kubernetes CRD Documentation](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [Gateway API ListenerSet Spec](https://gateway-api.sigs.k8s.io/reference/spec/#gateway.networking.k8s.io/v1.ListenerSet)
- [GKE Release Notes](https://cloud.google.com/kubernetes-engine/docs/release-notes)
- [Istio CRD Management](https://istio.io/latest/docs/setup/upgrade/)
- [Gateway API v1.5 Blog](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5/)
- [Gateway API GitHub Release v1.5.0](https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.5.0)