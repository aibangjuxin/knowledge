# experimental-install.yaml 分析 — Session Explorer

**会话时间**: 2026-05-29
**用户**: Lex — GCP Infra Engineer
**主题**: Gateway API experimental-install.yaml 文件分析，同事误 apply 风险评估

---

## 文件元信息

| 项目 | 值 |
|-----|---|
| 来源 | `https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml` |
| 大小 | 1.29 MB（1,285,683 bytes） |
| 文档数 | 14 个 YAML document |
| 内容结构 | 12 个 CRD + 2 个 ValidatingAdmissionPolicy |
| Gateway API 版本 | v1.5.1（bundle 版本标记为 v1.5.0-dev） |

---

## 包含的 CRD 清单

### 标准 channel CRDs（`gateway.networking.k8s.io`）

- `gatewayclasses.gateway.networking.k8s.io`
- `gateways.gateway.networking.k8s.io`
- `httproutes.gateway.networking.k8s.io`
- `grpcroutes.gateway.networking.k8s.io`
- `tcproutes.gateway.networking.k8s.io`
- `tlsroutes.gateway.networking.k8s.io`
- `udproutes.gateway.networking.k8s.io`
- `backendtlspolicies.gateway.networking.k8s.io`
- `referencegrants.gateway.networking.k8s.io`
- `listenersets.gateway.networking.k8s.io`

### 实验性 channel CRDs（`gateway.networking.x-k8s.io`，x=experimental）

- `xbackendtrafficpolicies.gateway.networking.x-k8s.io`
- `xmeshes.gateway.networking.x-k8s.io`

---

## ValidatingAdmissionPolicy 机制

### safe-upgrades Policy

**名称**: `safe-upgrades.gateway.networking.k8s.io`
**类型**: ValidatingAdmissionPolicy + ValidatingAdmissionPolicyBinding

**阻止逻辑表达式**（CEL）：
```
object.spec.group != 'gateway.networking.k8s.io'
|| oldObject == null
|| (has(annotations['gateway.networking.k8s.io/channel']) && annotations['gateway.networking.k8s.io/channel'] == 'standard')
|| (oldObject != null && oldObject.annotations['gateway.networking.k8s.io/channel'] == 'experimental')
```

**作用**：禁止在已有 standard channel CRD 的集群上 apply experimental channel CRD，除非先删除 `safe-upgrades` Policy。

**触发条件**：
- apply 的 CRD 带有 `gateway.networking.k8s.io/channel: experimental` 注解
- 且集群中已有 `gateway.networking.k8s.io`（standard channel）CRD

---

## 同事误 apply 到已有集群的后果

| 集群状态 | apply 结果 |
|---------|----------|
| 已有 standard channel CRD（用户现状） | ❌ 被 Policy 阻止 |
| 干净集群（无 CRD） | ✅ 成功 |

让 apply 成功必须先删除 Policy（生产环境不推荐）。

---

## channel 机制

| Channel | API Group | 稳定性 | 用途 |
|---------|-----------|--------|------|
| standard | `gateway.networking.k8s.io` | GA / Stable | 生产环境 |
| experimental | `gateway.networking.x-k8s.io` | Alpha/Beta | 新功能实验 |

**注意**：`xbackendtrafficpolicies` 和 `xmeshes` 的 API Group 是 `gateway.networking.x-k8s.io`（`x-` 前缀），这是与 standard 完全不同的 API 组，不是同 CRD 的不同版本。

---

## GKE 升级影响判断

| 操作 | 对 GKE 升级的影响 |
|-----|-----------------|
| apply 整个 experimental-install.yaml | ❌ 本身无影响 |
| 引入 experimental channel CRD | ⚠️ 潜在风险（API 不稳定） |
| 删除已有 CRD 再 apply | ⚠️ 会级联删除 CR 实例 |

apply 动作本身不影响 GKE 升级：CRD 和 CR 实例存在 etcd 中，GKE 升级是控制平面原地替换，etcd 数据不丢。

---

## 最佳实践

1. **不要 apply 整个文件**：只取需要的 CRD YAML 片段
2. **使用 standard-install.yaml** 而非 experimental-install.yaml（生产环境）
3. **不要删除 safe-upgrades**：这是保护机制
4. **按需只 apply 需要的 CRD**：12 个中通常只需 3-4 个

---

## 用户的集群现状

用户的集群已有 experimental-install.yaml 中**全部 12 个 CRD**，且已有 `safe-upgrades` Policy。同事直接 apply 对集群无额外效果。

---

## 参考文档

- `gcp/gke/docs/experimental-install.md` — 分析报告完整版
- `gcp/gke/docs/gke-type.md` — CRD 清单原始记录
- `gcp/gke/docs/explorer-gke-type.md` — GKE CRD 升级保留行为探索