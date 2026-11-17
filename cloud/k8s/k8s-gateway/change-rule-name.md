# NetworkPolicy 命名规范对照表

> **命名规范参考** (`name-define.md`)
>
> - **Default 级别**：`default-(deny|allow)-(ingress|egress)-{source or target svc}`
> - **App Specific 级别**：`(deny|allow)-(ingress|egress)-{source or target svc}`
> - 若不显式指定 `ingress` 或 `egress`，默认两者均包含。

---

## 1. Gateway Namespace (`abjx-gw-int`)

| 原名称 | 建议名称 | 是否需要修改 | 说明 |
|--------|----------|:----------:|------|
| `default-deny-all` | `default-deny-all` | ✅ 符合 | 兜底拒绝策略，无方向/来源限定，属特殊基线规则，保持不变 |
| `default-allow-dns` | `default-allow-egress-kube-dns` | ❌ 需修改 | 缺少方向字段 `egress`，且未标明目标服务；原名过于泛化 |
| `default-allow-gcp-hc-ingress` | `default-allow-ingress-gcp-hc` | ❌ 需修改 | 方向字段 `ingress` 应紧跟 `allow`，来源 `gcp-hc` 应在最后 |
| `default-allow-gw-egress-to-kong` | `default-allow-egress-kong` | ❌ 需修改 | 多余前缀 `gw-` 和介词 `to-`；`egress` 方向已隐含"从本 NS 出发" |
| `default-allow-gw-to-no-gw-rt` | `default-allow-egress-no-gw-rt` | ❌ 需修改 | 缺少方向字段，`gw-to-` 前缀冗余，目标应直接描述为 `no-gw-rt` |
| `default-allow-nginx-ingress-to-gw` | `default-allow-ingress-nginx` | ❌ 需修改 | 方向字段 `ingress` 位置错误（应在 allow 后），还含多余 `to-gw` 后缀 |
| `default-allow-istiod` | `default-allow-egress-istiod` | ❌ 需修改 | 缺少方向字段 `egress`，规则仅含 Egress 类型 |

---

## 2. Tenant Namespace (`teamname-int`)

| 原名称 | 建议名称 | 是否需要修改 | 说明 |
|--------|----------|:----------:|------|
| `default-deny-all` | `default-deny-all` | ✅ 符合 | 同上，基线兜底规则保持不变 |
| `default-allow-dns` | `default-allow-egress-kube-dns` | ❌ 需修改 | 同 GW 命名空间，缺少 `egress` 方向和目标服务 |
| `allow-intra-ns-kong-teamname-int` | `allow-kong-teamname-int` | ⚠️ 建议简化 | `intra-ns` 含义可由命名空间本身推断；`ingress+egress` 均含则无需写方向，整体可简化 |
| `allow-intra-ns-ms-teamname-int` | `allow-ms-teamname-int` | ⚠️ 建议简化 | 同上，`intra-ns` 冗余，简化为 App Specific 格式 |
| `allow-intra-ns-nogateway-teamname` | `allow-nogateway-teamname-int` | ❌ 需修改 | `intra-ns` 冗余；后缀缺少 `-int` 环境标识，与其他 App Specific 策略不一致 |
| `default-allow-egress-to-drn` | `default-allow-egress-drn` | ❌ 需修改 | 介词 `to-` 与方向字段 `egress` 语义重复，去除即可 |
| `default-allow-egress-workload-identity` | `default-allow-egress-workload-identity` | ✅ 符合 | 完全符合规范：`default-allow-egress-{target}` |
| `default-allow-gw-ingress-to-no-gw-rt` | `default-allow-ingress-abjx-gw` | ❌ 需修改 | 方向字段位置错误；`to-no-gw-rt` 是本 NS 的目标，不属于名称描述范围；来源应为 `abjx-gw` |
| `default-allow-kdp-ingress-to-kong-rt` | `default-allow-ingress-kdp` | ❌ 需修改 | 方向字段位置错误；`to-kong-rt` 冗余，podSelector 已精确限定落点；来源简化为 `kdp` |
| `default-allow-restricted-api` | `default-allow-egress-restricted-api` | ❌ 需修改 | 缺少方向字段 `egress`，规则仅含 Egress 类型 |

---

## 修改统计

| 状态 | 数量 |
|------|:----:|
| ✅ 完全符合，无需修改 | 3 |
| ⚠️ 建议简化（可选） | 2 |
| ❌ 需要修改 | 12 |

---

*文档版本: 1.0 — 2026-05-26*


这个问题问的是视角问题，很关键。

## 规则视角分析

你说的规则是**打在 Kong DP 命名空间**上的 Egress 规则，允许 Kong DP 的流量出去访问 `teamname-int`。

按命名规范：

```
default-(deny|allow)-(ingress|egress)-{source or target svc}
```

- 方向：**egress**（从 Kong DP 出发）
- target svc：**teamname**（目标是 teamname-int）

所以规则应命名为：

```
default-allow-egress-teamname
```

---

## 与你已有规则的对照

| 规则所在 NS | 规则名称 | 方向 | 说明 |
|------------|---------|:----:|------|
| `kong-apw-kong-int` (Kong DP) | `default-allow-egress-teamname` | → `teamname-int` | Kong DP 的出站规则，**这是你问的这条** |
| `teamname-int` (Tenant) | `default-allow-ingress-kdp` | ← `kdp` | Tenant NS 对应的入站白名单（已有） |

> **这两条是一对**，一条写在 Kong DP 的 namespace 上（egress），一条写在 `teamname-int` 上（ingress）。NetworkPolicy 需要两端都放行流量才能真正通。

如果你想把这条规则加入文档，我可以帮你补充进去。

## 评估：`allow-egress-teamname` vs `default-allow-egress-teamname`

你的判断**完全正确**，理由如下：

| 对比维度 | `default-allow-egress-teamname` | `allow-egress-teamname` |
|--------|--------------------------------|------------------------|
| 适用级别 | Default（平台基线/通用基础设施） | App Specific（应用专属） |
| 典型场景 | DNS、Health Check、Workload Identity | **Kong DP 访问特定租户** ← 这条 |
| 是否能代表"通用"规则 | ✅ 适合放任意命名空间 | ✅ 与 Kong DP 强绑定 |

> `default-*` 应留给"每个命名空间都可能需要的"基础策略；Kong DP egress 到 teamname-int 是一条面向具体应用拓扑的规则，属于 App Specific，`allow-egress-teamname` ✅ 是正确命名。

---

以下是对应的 NetworkPolicy YAML（打在 Kong DP 命名空间）：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress-teamname
  namespace: kong-apw-kong-int      # Kong DP 所在命名空间
spec:
  podSelector: {}                    # 作用于 Kong DP NS 内所有 Pod
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: teamname-int
      ports:
        - port: 8080
          protocol: TCP
        - port: 8443
          protocol: TCP
  policyTypes:
    - Egress
```

**与之配对的 Ingress 规则**（已在 `teamname-int` 中定义）：

```yaml
# 已存在于 k8s-gateway-netpol.md § 2.9
name: default-allow-ingress-kdp
namespace: teamname-int
```

两条规则共同构成完整的流量对：

```
kong-apw-kong-int Pod
   │ allow-egress-teamname (Egress)
   ▼
teamname-int Pod (apigateway: KONG)
   ↑ default-allow-ingress-kdp (Ingress)
```

需要我把这条规则追加到 [k8s-gateway-netpol.md](cci:7://file:///Users/lex/git/knowledge/cloud/k8s/k8s-gateway/k8s-gateway-netpol.md:0:0-0:0) 里单独开一个 Section 3（Kong DP Namespace）吗？