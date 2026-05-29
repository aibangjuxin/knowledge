- setup https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/
```bash
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml

```

---

# experimental-install.yaml 分析报告

**文件来源**：`https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml`
**文件大小**：1.29 MB（1,285,683 bytes）
**包含内容**：14 个 YAML document（12 个 CRD + 2 个 ValidatingAdmissionPolicy）
**Gateway API 版本**：v1.5.1（bundle 版本标记为 v1.5.0-dev）

---

## 一、文件包含的资源清单

### 1.1 CRD 定义（12 个）

| # | CRD 名称 | API Group | 备注 |
|---|---------|-----------|------|
| 1 | `gatewayclasses.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 2 | `gateways.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 3 | `httproutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 4 | `grpcroutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 5 | `tcproutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 6 | `tlsroutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 7 | `udproutes.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 8 | `backendtlspolicies.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 9 | `referencegrants.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 10 | `listenersets.gateway.networking.k8s.io` | `gateway.networking.k8s.io` | 标准 channel |
| 11 | `xbackendtrafficpolicies.gateway.networking.x-k8s.io` | `gateway.networking.x-k8s.io` | **experimental channel** |
| 12 | `xmeshes.gateway.networking.x-k8s.io` | `gateway.networking.x-k8s.io` | **experimental channel** |

### 1.2 ValidatingAdmissionPolicy（2 个）

| # | 名称 | 类型 | 作用 |
|---|-----|------|------|
| 1 | `safe-upgrades.gateway.networking.k8s.io` | ValidatingAdmissionPolicy | 阻止将 experimental channel CRD 安装在已有 standard channel CRD 的集群上 |
| 2 | `safe-upgrades.gateway.networking.k8s.io` | ValidatingAdmissionPolicyBinding | 将上述 Policy 绑定到所有 CRD CREATE/UPDATE 操作 |

---

## 二、channel 机制解析

**关键发现**：这个 YAML 文件中所有 CRD 的 `annotations` 都标记为 `gateway.networking.k8s.io/channel: experimental`。

### 2.1 什么是 Gateway API channel？

Gateway API CRD 有两个 channel：

| Channel | 稳定性 | 用途 |
|---------|--------|------|
| **standard** | GA / 稳定 | 生产环境使用，与 K8s 版本兼容 |
| **experimental** | Alpha/Beta | 新功能实验，schema 可能变化 |

- API Group `gateway.networking.k8s.io` = **standard channel**
- API Group `gateway.networking.x-k8s.io` = **experimental channel**（x 前缀表示 experimental）

### 2.2 你的集群现状

根据 `gke-type.md` 的记录：

```
gatewayclasses.gateway.networking.k8s.io    2025-10-29T02:11:25Z
gateways.gateway.networking.k8s.io          2025-10-29T02:11:24Z
httproutes.gateway.networking.k8s.io        2025-10-29T02:11:25Z
listenersets.gateway.networking.k8s.io      2026-05-29T02:38:00Z
xbackendtrafficpolicies.gateway.networking.x-k8s.io    2026-05-29T02:38:01Z
xmeshes.gateway.networking.x-k8s.io        2026-05-29T02:38:01Z
```

你的集群中：
- `gateway.networking.k8s.io` 的 CRD 在 **2025-10-29** 就已安装（标准 channel）
- `xbackendtrafficpolicies` 和 `xmeshes` 在 **2026-05-29** 被安装（experimental channel）

**注意**：experimental CRD 的 API Group 是 `gateway.networking.x-k8s.io`（注意 `x-` 前缀），这是与 standard channel 完全不同的 API 组，**不是同 CRD 的不同版本**。

---

## 三、safe-upgrades ValidatingAdmissionPolicy 的作用

### 3.1 阻止逻辑

`safe-upgrades` ValidatingAdmissionPolicy 的验证表达式：

```
object.spec.group != 'gateway.networking.k8s.io' 
|| oldObject == null 
|| (has(annotations) && annotations['gateway.networking.k8s.io/channel'] == 'standard')
|| (oldObject != null && oldObject.metadata.annotations['gateway.networking.k8s.io/channel'] == 'experimental')
```

翻译成人话：**禁止在已有 standard channel CRD 的集群上 apply experimental channel CRD**，除非先删除 `safe-upgrades` ValidatingAdmissionPolicy。

### 3.2 如果同事直接 apply 这个文件到你的集群

**场景 A：你的集群已有 standard channel CRD（你的现状）**

```
结果：apply 会被 ValidatingAdmissionPolicy 阻止，报错：
"Installing experimental CRDs on top of standard channel CRDs is prohibited by default."

同事必须先删除 safe-upgrades Policy，才能 apply 这个文件。
```

**场景 B：在干净集群上 apply**

```
结果：apply 成功，所有 CRD 都会被安装。
```

### 3.3 同事需要做什么才能 apply 成功

```bash
# 方案 1：先删掉 safe-upgrades（不推荐在生产环境）
kubectl delete ValidatingAdmissionPolicy safe-upgrades.gateway.networking.k8s.io
kubectl delete ValidatingAdmissionPolicyBinding safe-upgrades.gateway.networking.k8s.io
kubectl apply --server-side -f experimental-install.yaml

# 方案 2：只 apply 你需要的 individual CRD（推荐）
# 不要 apply 整个 experimental-install.yaml
# 只 apply 你实际需要的 CRD
```

---

## 四、最佳实践：不要 apply 整个文件

### 4.1 为什么不应该 apply 整个文件

| 问题 | 影响 |
|-----|------|
| **包含大量不需要的 CRD** | 12 个 CRD 中你可能只需要其中 3-4 个 |
| **experimental channel CRD** | `xmeshes` 和 `xbackendtrafficpolicies` 是实验性的，API 不稳定 |
| **ValidatingAdmissionPolicy 冲突** | 你集群中已有 standard channel CRD，会被阻止 |
| **版本不匹配风险** | GKE 升级时，不同 channel 的 CRD 行为可能不一致 |
| **增加攻击面** | 不需要的 CRD 也会被 API Server 加载，扩大 attack surface |

### 4.2 推荐做法：只 apply 你实际需要的 CRD

**错误做法**（你同事现在的做法）：
```bash
# 一股脑 apply 整个 1.3MB 文件（含 experimental channel CRD）
kubectl apply --server-side -f experimental-install.yaml
```

**正确做法**：按官方分层选取需要的资源

| 场景 | 你需要的 URL |
|-----|-------------|
| 只做 L7 负载均衡（生产环境推荐） | `standard-install.yaml`（约 200KB，stable CRD） |
| 需要 HTTPS 路由策略 | `standard-install.yaml`（已包含 BackendTLSPolicy） |
| 需要 gRPC 路由 | `standard-install.yaml`（已包含 GRPCRoute） |
| 需要 ListenerSet | `standard-install.yaml`（已包含 ListenerSet） |
| 只做基础 Gateway + HTTPRoute | `core-install.yaml`（最小子集，约 50KB） |

示例命令：
```bash
# 最小化安装（只安装核心 CRD）
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/core-install.yaml

# 标准安装（生产环境推荐，包含所有 stable CRD）
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml

# 明确不需要 experimental channel 的 CRD（xmeshes/xbackendtrafficpolicies）
# → 不要用 experimental-install.yaml
```

**关键文件对比**：

| 文件 | 大小 | 包含 CRD | 是否含 experimental |
|-----|------|---------|-------------------|
| `core-install.yaml` | ~50KB | 最小子集 | ❌ 否 |
| `standard-install.yaml` | ~200KB | 全部 stable CRD | ❌ 否 |
| `experimental-install.yaml` | ~1.3MB | stable + experimental | ✅ 是（生产禁用） |

**结论**：你同事应该用 `standard-install.yaml` 或 `core-install.yaml`，**不要用 `experimental-install.yaml`**。

### 4.3 你集群中实际需要的 CRD 判断

根据 `gke-type.md`，你的集群已经有：

| CRD | 已有？ | 是否需要 experimental-install |
|-----|-------|------------------------------|
| `gatewayclasses.gateway.networking.k8s.io` | ✅ 已有 | ❌ 不需要 |
| `gateways.gateway.networking.k8s.io` | ✅ 已有 | ❌ 不需要 |
| `httproutes.gateway.networking.k8s.io` | ✅ 已有 | ❌ 不需要 |
| `listenersets.gateway.networking.k8s.io` | ✅ 已有 | ❌ 不需要 |
| `xbackendtrafficpolicies` | ✅ 已有 | ❌ 不需要 |
| `xmeshes` | ✅ 已有 | ❌ 不需要 |

**结论**：你的集群已经拥有 experimental-install.yaml 中的**全部 CRD**，同事直接 apply 这个文件对集群没有任何额外效果（除非他想强制用 experimental channel 覆盖现有的 standard channel）。

---

## 五、对 GKE 升级的影响

### 5.1 如果 apply 整个 experimental-install.yaml

| 场景 | GKE 升级是否受影响 | 说明 |
|-----|------------------|------|
| CRD 定义存在 etcd 中 | ❌ 不影响 | GKE 升级不删除 CRD |
| CR 实例存在 etcd 中 | ❌ 不影响 | GKE 升级不删除 CR 实例 |
| ValidatingAdmissionPolicy | ⚠️ 可能影响 | Policy 本身也是 CRD，会随 GKE 升级保留 |

### 5.2 真正会影响 GKE 升级的操作

| 操作 | 是否影响 GKE 升级 | 说明 |
|-----|----------------|------|
| apply 整个 experimental-install.yaml | ❌ 本身不影响 | 但可能引入不稳定的 experimental CRD |
| 删除 standard channel CRD 再 apply experimental | ⚠️ **会影响** | 删除 CRD 会级联删除所有 CR 实例 |
| 修改已有 CRD schema | ⚠️ **会影响** | 可能导致 CR 实例无法通过 validation |
| 修改 ValidatingAdmissionPolicy | ⚠️ **会影响** | 可能导致意外阻止正常的资源创建 |

### 5.3 GKE 升级后 CRD 保留机制（再次确认）

```
┌─────────────────────────────────────┐
│           etcd（持久化层）             │
│  ├─ CRD 定义（CustomResourceDefinition） │
│  ├─ CR 实例（你创建的 Gateway/HTTPRoute 等）│
│  └─ ValidatingAdmissionPolicy         │
└─────────────────────────────────────┘
                    │
           GKE 控制平面升级
                    ▼
┌─────────────────────────────────────┐
│  GKE 升级只替换 API Server 二进制      │
│  etcd 数据不丢失、不重置、不迁移        │
└─────────────────────────────────────┘
                    │
           升级后恢复
                    ▼
┌─────────────────────────────────────┐
│  所有 CRD、CR 实例、Policy 完整保留     │
└─────────────────────────────────────┘
```

**结论**：apply experimental-install.yaml **本身不会影响 GKE 升级**。但如果同事 apply 的是**错误版本**（例如过旧的 CRD 版本）或**冲突的 channel**，GKE 升级时可能触发额外的兼容性问题。

---

## 六、总结

| 问题 | 答案 |
|-----|------|
| experimental-install.yaml 包含什么？ | Gateway API v1.5.1 的 12 个 CRD + 2 个安全 Policy |
| 同事 apply 到你的集群会怎样？ | ValidatingAdmissionPolicy 会**阻止**（因为已有 standard channel CRD） |
| 同事必须先做什么才能 apply？ | 删除 `safe-upgrades` Policy，但这在生产环境**不推荐** |
| 对 GKE 升级有影响吗？ | apply 动作本身**不影响** GKE 升级 |
| 最佳实践是什么？ | **不要 apply 整个文件**，只按需 apply 你实际需要的 CRD |
| 你的集群需要 apply 这个文件吗？ | **不需要**。你的集群已有文件中所有 CRD |

**核心建议**：让你同事只取他需要的 CRD YAML 片段，而不是一股脑 apply 整个 1.3MB 文件。最安全的方式是参考官方 `standard-install.yaml`（生产级 stable CRD），而不是 `experimental-install.yaml`。