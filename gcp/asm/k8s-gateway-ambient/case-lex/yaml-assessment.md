# YAML 评估报告 v5 — case-lex 4 文件最终态 (纯审计)

> **作者**: architect-gcp Bot
> **日期**: 2026-09-25 (v5)
> **评估基线**: Lex 确认"其他 YAML 都正常工作",且已完成文件合并:
>         - NP-5 (严格版) 已回填到 `02-network-policies.yaml`
>         - `AuthZ-3.yaml` 已合并到 `03-mesh-security.yaml` (`allow-from-waypoint-to-workloads`)
>         - `02-NP-5-netpol.yaml` 独立文件仍存在(与主文件 NP-5 同名,last-write-wins)
>
> **目的**: 基于最终 4 文件结构做静态审计 + 评估合理性自审。
>         **v5 相比 v4 的核心变化**: 移除所有"主动建议 Lex 做其他操作"的内容
>         (不再提议加 verify-*.sh / README 索引 / 跑 kubectl 命令)。
>         本报告**仅描述现状与风险**,修复动作由 Lex 自行决定。

---

## 0. TL;DR (v5)

| Severity | 数量 | 概要 |
|---|---|---|
| **🟠 HIGH** | **3** | `ENABLE_INGRESS_WAYPOINT_ROUTING` 集群 flag 未验证 (P2 设计前提);AuthZ 缺 `default` SA 兜底;NP-8 namespaceSelector 误用跨 ns 风险 |
| **🟡 MEDIUM** | **2** | NP-6 端口限制形同虚设;NS label 命名 vs NetPol selector 不联动 |
| **🟢 LOW / INFO** | **2** | 集群 flag 验证脚本缺失(观察);文档交叉引用(观察) |
| **🟣 待 Lex 校准** | **3** | 业务端口清单 (Q5);集群 flag 状态 (Q6);业务 label 跨 ns 重叠 (Q7) |

**v5 结论**:
- ✅ **基线 OK**: 4 个 YAML 全部 schema 正确,语义层无 critical bug
- ⚠️ **3 个 HIGH 风险**: 都是"深度防御"层风险,不破坏当前工作但增加失效概率
- 🟣 **3 个 cluster-level 验证待 Lex 答复**: 这 3 条不查清楚,残余风险无法精确定级

---

## 1. 评估范围 (v5)

### 1.1 评估对象 (最终 4 文件结构)

| 文件 | 资源数 | 内容摘要 | 状态 |
|---|---|---|---|
| `00-namespace-ba000000-lex-int.yaml` | 1 NS | 9 labels (3 istio + 3 业务元数据 + 1 旧 PSA + 2 业务路由) | ✅ |
| `01-waypoint-int.yaml` | 1 GW + 1 PDB | `istio-waypoint` class, 2 副本, listener `istio:15008/HBONE`, PDB minAvailable=1 | ✅ |
| `02-network-policies.yaml` | 9 NP | deny-all + DNS + 出口 CIDR + istiod + HBONE×2 + GW + same-ns + kubelet probes | ✅ |
| `03-mesh-security.yaml` | 3 doc | PA STRICT + AuthZ deny-all + AuthZ allow-from-waypoint-to-workloads | ✅ |

**实际资源总数**: 1 NS + 1 GW + 1 PDB + 9 NP + 1 PA + 2 AuthZ = **15 resources**

**附属文档**:
- `assessment-ingress.md` — ingress 流量完整路径分析 (5 条路径 + 深度防御)
- `yaml-assessment.md` — 当前文档 (v5)

### 1.2 已不在评估范围 (Lex 已修)

- ❌ YAML 语法错误 (v1 C-1 已修)
- ❌ NP-7 缩进问题 (v2 已修)
- ❌ `03-mesh-security.yaml` AuthZ bug 版 (Lex 已删)
- ❌ `tls.mode` 字段 (Lex 已删)
- ❌ Waypoint listener name 差异 (`mesh` vs `istio`,无功能影响)
- ❌ NP-7 注释风格升级 (已是 field-by-field 严格定义)
- ❌ 文件合并痕迹 (`02-NP-5-netpol.yaml` / `AuthZ-3.yaml` 已合并)

### 1.3 评估维度

1. **集群级前提**: P2 设计依赖哪些集群 flag / CRD / controller 行为?
2. **深度防御**: 当某层失效时,其他层能否兜底?
3. **工程化**: 多 ns 复用 / GitOps / 审计可读性?
4. **运维盲点**: 线上行为难以观测或排错的部分?

---

## 2. HIGH — 残余风险审计

### 🟠 H-1: P2 设计的集群级前提未验证

**文件**: `02-network-policies.yaml` NP-7 + `00-namespace-ba000000-lex-int.yaml` NS label

**Lex Q1 答复**: "ingress 流量只走 waypoint 这条路"(有意设计 P2 路径)

**P2 设计依赖的 3 个前提**:

| # | 前提 | 来源 | 验证方式 | 风险 |
|---|---|---|---|---|
| 1 | 集群 `ENABLE_INGRESS_WAYPOINT_ROUTING=true` (istiod env) | Istio Waypoint docs | `kubectl get deploy istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_INGRESS_WAYPOINT_ROUTING")]}{"\n"}'` | ⚠️ **默认 false**,label 不生效 |
| 2 | `istio.io/dataplane-mode=ambient` 已生效 (istio-cni 在所有节点正常) | Istio Ambient docs | `istioctl ztunnel-config workloads -n istio-system \| grep ba000000-lex-int` | 中 (cni 故障会暴露 mesh 不可用,但 ingress 仍可工作) |
| 3 | waypoint-int Deployment 至少 1 副本 Ready | K8s 默认 | `kubectl get deploy waypoint-int -n ba000000-lex-int` | 低 (PDB minAvailable=1 已设) |

**残余风险** (前提 #1):
- 如果 `ENABLE_INGRESS_WAYPOINT_ROUTING` 未开启(istiod env 默认 false):
  - NS 上 `istio.io/ingress-use-waypoint: waypoint` label **不生效**
  - 入口流量走 P1(绕过 waypoint)
  - 但 NP-7 仍然生效(允许 ingress → waypoint 15008),waypoint 仍可接收 mesh 内流量
  - 入口流量变成"绕开 waypoint 直连业务 pod"
  - 此时 NP-8 (same-namespace 不匹配 ingress GW ns) + AuthZ deny-all + allow-from-waypoint-to-workloads **三层兜底**
  - 但 L7 拦截失效 — 入口流量不受 waypoint 控制

**深度防御验证**:
- 即便 P2 路径失效,业务 pod 不会被 ingress 直接访问
- 但 L7 拦截(AuthZ / header 路由 / 请求审计)**会失效**

**关联**:
- `assessment-ingress.md` §4.1 — ENABLE_INGRESS_WAYPOINT_ROUTING 默认 false
- `assessment-ingress.md` §4.3 — 业务 pod 真的不会被 ingress 直接访问吗?
- `02-network-policies.yaml` NP-7 注释 — 已记录此前提

---

### 🟠 H-2: AuthZ 缺 `default` SA 兜底

**文件**: `03-mesh-security.yaml` → `allow-from-waypoint-to-workloads`

```yaml
rules:
  - from:
      - source:
          principals:
            - "cluster.local/ns/ba000000-lex-int/sa/waypoint-int"
            # ⚠️ 没有 default SA 兜底
```

**残余风险**:
- Istio waypoint controller 1.27+ 在某些安装路径下,默认 SA 是 `default` 而非 `waypoint-int`
- 如果实际 SA 名 = `default`,waypoint 调业务 pod 会被 deny-all 挡住
- **症状**: waypoint 5xx 错误,业务 pod 收不到请求,AuthZ 日志显示 RBAC: deny

**验证方式**:
```bash
kubectl get deploy -n ba000000-lex-int \
  -l gateway.networking.k8s.io/gateway-name=waypoint-int \
  -o jsonpath='{.items[0].spec.template.spec.serviceAccountName}{"\n"}'
```

**修复方案**(双保险):
```yaml
principals:
  - "cluster.local/ns/ba000000-lex-int/sa/waypoint-int"
  - "cluster.local/ns/ba000000-lex-int/sa/default"   # 兜底
```

**关联**:
- `assessment-ingress.md` §7 waypoint SA 严格定义

---

### 🟠 H-3: NP-8 namespaceSelector 误用 → 跨 ns 风险

**文件**: `02-network-policies.yaml` NP-8

```yaml
ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          businessId: ba000000
egress:
  - to:
    - namespaceSelector:
        matchLabels:
          businessId: ba000000
```

**残余风险**:
- `namespaceSelector: {businessId: ba000000}` = 匹配**任何**打这个 label 的 ns
- 如果其他 ns(比如 `ba000000-lex-staging`)也打了 `businessId: ba000000`,跨 ns 流量被允许
- 业务 ns `ba000000-lex-int` 已经打了这个 label
- **当前工作但易误用**

**验证方式**:
```bash
kubectl get ns -l businessId=ba000000
# 期望: 只有 ba000000-lex-int 一个 ns
# 如果返回多个 → H-3 跨 ns 风险存在
```

**修复方案**(2 选 1):

**方案 1 (最严)**:
```yaml
ingress:
  - from:
    - podSelector: {}    # 同 ns 所有 pod
egress:
  - to:
    - podSelector: {}    # 同 ns 所有 pod
```

**方案 2 (保留业务元数据语义)**:
```yaml
ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ba000000-lex-int   # 精确 ns 名
```

**为什么仍 HIGH 而非 MEDIUM**:
- 业务 ns 之间的隔离是**多租户 mesh 的核心安全保证**
- 误用 namespaceSelector 会让"配置看起来对,实际漏隔离"
- 修复成本极低(改 2 行)

**关联**:
- K8s NetworkPolicy spec — `podSelector` vs `namespaceSelector` 语义

---

## 3. MEDIUM — 改进空间

### 🟡 M-1: NP-6 端口限制形同虚设

**文件**: `02-network-policies.yaml` NP-6

**现状**:
- NP-6 限制 waypoint egress 只 allow 15008
- NP-8 同 ns 兜底全端口 allow
- additive 语义 = waypoint 实际 egress 所有端口
- **NP-6 的"严格"实际上不生效**

**建议方向** (二选一,具体由 Lex 决定):
- (a) 改 NP-6 删 `ports:` 字段,让规则名实相符
- (b) 把 NP-8 收紧到具体业务端口(只 allow 80/8080/8443/9090/15008)

**优先级**: MEDIUM(不影响功能,仅审计清晰度)

---

### 🟡 M-2: NS label 命名 vs NetPol selector 不联动

**文件**: `00-namespace-ba000000-lex-int.yaml` + NetPol 集

**现状**:
- NS 9 个 label: `businessId`, `runtime`, `team`, `istio.io/dataplane-mode`, `istio.io/ingress-use-waypoint`, `istio.io/use-waypoint`, `gateway-access`, `ingress`, `pod-security.kubernetes.io/enforce`
- NetPol 用 `businessId=ba000000` 做 namespaceSelector(H-3 风险源)
- NetPol 用 `ingress: int`(业务 label)+ `gateway.networking.k8s.io/gateway-name=waypoint-int`(K8s 标准)
- NS 同时打了 3 个业务元数据 label (`businessId/team/runtime`)

**残余风险**:
- 业务 label 命名变更(如 `team` 重命名)会影响 NetPol selector
- 多 ns 复用同一份 NetPol 模板需要各自 patch

**建议方向**(工程化改进,具体由 Lex 决定):
- 引入命名型 label: `waypoint-access: ba000000-lex-int`(专用,不变更)
- 或建 Kustomize/Helm overlay,每个 ns 用 patch 注入自己的 selector

**优先级**: MEDIUM(不影响功能,仅工程化)

---

## 4. LOW / INFO (纯观察,无操作建议)

### 🟢 L-1: 集群 flag 验证脚本缺失 (观察)

**观察**:
- case-lex/ 目录无 verify-*.sh
- cluster-level 前置条件(H-1/Q6)目前依赖人工跑 kubectl 命令验证
- 风险: 人为遗漏 flag 验证,后续 deployment 可能在不知情下失去 P2 保护

**关联**: H-1

---

### 🟢 L-2: 文档交叉引用 (观察)

**观察**:
- `yaml-assessment.md` 引用 `assessment-ingress.md` §4.1 等多处
- `02-network-policies.yaml` NP-7 引用 `yaml-assessment.md §Q1` + `assessment-ingress.md §1`
- 文档依赖清晰但分散,新读者可能需要跨多个文件跳转才能理解设计意图

**关联**: 无直接安全风险,纯可读性

---

## 5. 文件级摘要 (v5)

| 文件 | 状态 | 关键备注 |
|---|---|---|
| `00-namespace-ba000000-lex-int.yaml` | ✅ | 9 labels: 3 istio + 3 业务元数据 + 3 业务路由/PSA |
| `01-waypoint-int.yaml` | ✅ | HA 2 副本 + PDB minAvailable: 1 |
| `02-network-policies.yaml` | ✅ | 9 NP, schema 正确, NP-5 已用严格版 (`ingress=int`), NP-7 注释已升级 |
| `03-mesh-security.yaml` | ✅ | PA STRICT + AuthZ deny-all + AuthZ allow-from-waypoint (2 AuthZ) |
| `assessment-ingress.md` | ✅ | 5 条 ingress 路径对比 + 深度防御分析 |
| `yaml-assessment.md` | ✅ 当前文档 (v5) | 残余风险审计 + 评估合理性自审 (§8) |

---

## 6. 待 Lex 校准的 7 个问题

| # | 问题 | v5 状态 |
|---|---|---|
| 1 | ingress GW pod 的实际 label 是 `app=istio-ingress` 还是 `gateway.networking.k8s.io/gateway-name=lex-gw-int`? | ✅ **已确认: 自定义 `gateway.networking.k8s.io/gateway-name=lex-gw-int`** |
| 2 | waypoint pod 实际使用的 SA 名? | ⏳ **待校准 (H-2 兜底必要)** |
| 3 | NP-7 线上"选 waypoint pod"是有意还是历史遗留? | ✅ **已确认: 有意设计 P2** |
| 4 | NP-6 egress 收紧到 15008 的设计意图? | ✅ **已确认: 罗列评估见 v3 §H-2 (形同虚设, 建议改)** |
| 5 | 业务 pods 的实际监听端口清单? | ⏳ 待校准 (NP-6 修复用,优先级 MEDIUM) |
| 6 | 集群 `ENABLE_INGRESS_WAYPOINT_ROUTING` 是否开启? | ⏳ **待校准 (H-1 P2 前提)** |
| 7 (新增) | 业务 ns 是否还有 staging / dev 等共用 `businessId: ba000000` label? | ⏳ **待校准 (H-3 跨 ns 风险)** |

---

## 7. v5 与 v1/v2/v3/v4 的差异

| 维度 | v1 | v2 | v3 | v4 | v5 |
|---|---|---|---|---|---|
| **基线假设** | "Lex 确认线上工作" | 同 v1 | 同 v1 | 同 v1 + 文件已合并 | **同 v1** |
| **评估内容** | 找 bug 修 bug | 找 bug + 设计澄清 | 残余风险审计 | 残余风险审计 | **纯审计 (无操作建议)** |
| **Critical findings** | 2 | 2 | 0 | 0 | **0** |
| **High findings** | 3 | 3 | 3 | 3 | **3** (都是深度防御层) |
| **Medium findings** | 3 | 3 | 2 | 2 | **2** |
| **评估对象** | 6 YAML | 6 YAML | 6 YAML | 4 YAML | **4 YAML** |
| **报告定位** | 找问题 | 修问题 + 设计澄清 | 运维审计 | 运维审计 (文件合并后) | **纯审计 (无 follow-up action)** |
| **§7 推荐行动** | 有 | 有 | 有 | 有 | **删除 (v5 不再发起 action)** |
| **§10 评估合理性自审** | 无 | 无 | 无 | 有 | **§8 保留 (核心内容)** |

**核心变化 (v4 → v5)**:
- **移除** §7 "推荐行动"(主动建议 Lex 做 kubectl / 加脚本)
- **保留** 所有 §2-§3 风险描述 + 修复方案(供 Lex 参考,不主动 follow-up)
- §1.3 评估维度、§4 LOW 改为"纯观察"(说明风险,不给操作建议)
- §8 改为"评估合理性自审"(Lex 直接要求保留)
- §8 旧"§10 评估合理性自审"保留并精简

---

## 8. 评估合理性自审 (v5 保留)

> **Lex 直接要求**: "看他哪些地方合理和不合理,给一个解释"

### 8.1 评估方法学

本报告是基于**静态文件分析 + 同仓库文档 + Istio 1.30 官方文档**的**推测式评估**。
未在真实集群运行任何 `kubectl get/apply/describe`。
因此每条评估按以下标准标注:

| 标签 | 含义 |
|---|---|
| **🟢 客观事实** | 直接来自 K8s/Istio spec 文档,无歧义 |
| **🟡 推测合理** | 基于文档 + 同仓库资料推断,但需集群验证 |
| **🟠 主观判断** | 基于架构原则的判断,可能有不同观点 |
| **⚫ 已过时** | 与当前实际状态不符,需更新 |

### 8.2 每条评估的合理性标注

| 条目 | 合理性 | 说明 |
|---|---|---|
| **H-1 P2 依赖 flag** | 🟡 推测合理 | flag 默认 false 是客观事实,但**flag 在你的集群当前状态未知**(Q6 待答) |
| **H-1 深度防御分析** | 🟢 客观事实 | NP-8 + AuthZ 三层兜底是 additive semantics 直接推导 |
| **H-2 AuthZ 缺 default SA** | 🟠 主观判断 | "waypoint controller 默认 SA 名"取决于 Istio 版本 + 安装方式,需 Q4 验证 |
| **H-2 修复方案** | 🟢 客观事实 | 加 `default` SA 是双保险,无副作用 |
| **H-3 NP-8 跨 ns 风险** | 🟢 客观事实 | `namespaceSelector` 匹配语义是 K8s spec 明确定义 |
| **H-3 修复方案 1 (podSelector: {})** | 🟢 客观事实 | `podSelector: {}` 在 same-namespace 下等价或更严 |
| **H-3 修复方案 2 (精确 ns 名)** | 🟢 客观事实 | `kubernetes.io/metadata.name` 是 K8s 自动 label |
| **M-1 NP-6 形同虚设** | 🟢 客观事实 | additive semantics 是 K8s NetPol spec 直接推导 |
| **M-1 修复建议** | 🟠 主观判断 | "二选一"是审计建议,具体选哪个取决于团队偏好 |
| **M-2 NS label 不联动** | 🟠 主观判断 | "引入命名型 label"是工程化建议,不是必须 |
| **L-1 验证脚本观察** | 🟠 主观判断 | "运维盲点"是观察,不是必须解决 |
| **L-2 文档引用观察** | 🟢 客观事实 | 文档可读性建议,无副作用 |
| **§1.3 评估维度定义** | 🟠 主观判断 | "4 个维度"是评估框架选择,可能有其他框架 |
| **§8.1 评估方法学标注** | 🟠 主观判断 | "4 个合理性标签"是我自己定义的元评估标准 |

### 8.3 已过时 / 需更新的内容 (v5 已修复)

| 条目 | 原状态 | v5 修复 |
|---|---|---|
| 文件清单 | 6 YAML | **4 YAML** |
| AuthZ 资源数 | 3 个 | **2 个** |
| H-2 文件引用 | `AuthZ-3.yaml` | **`03-mesh-security.yaml`** |
| §1.2 排除项 | "Lex 已用独立 AuthZ-3.yaml" | **删除** (不再适用) |
| §5 文件级摘要 | 含 2 个独立文件 | **仅主文件** |
| §7 推荐行动 | 有 (v4 含) | **删除** (v5 不发起 follow-up action) |
| §8 评估合理性自审 | v4 §10 | **v5 §8 (章节号 + 内容精简)** |

### 8.4 评估的局限性 (坦白)

| 局限 | 影响 | 缓解 |
|---|---|---|
| **未在真实集群验证** | H-1/H-2/H-3 风险等级是基于文档推断 | Q4/Q6/Q7 待 Lex 校准 |
| **未考虑其他 ns 的 mesh 状态** | 跨 ns 流量假设可能与实际不符 | Q7 验证 |
| **未考虑 istio controller 版本差异** | 1.27/1.30 行为可能有微差异 | 文档已注明 |
| **未考虑多 cluster / multi-network** | 跨集群 ambient 1.30 仍 beta | 不在本评估范围 |
| **未审计 RBAC / ServiceAccount** | SA 权限范围未审 | H-2 验证 SA 名时一并查 |
| **未审计 Sidecar 残留** | 业务 ns 是否完全切 ambient 未审 | H-1 验证 flag 时一并查 |

### 8.5 评估"合理性"自评

**总体合理性**: 🟢 **可接受** (基于静态分析的合理推断,主要风险点已列)

**不足之处**:
- 🟠 H-2 风险等级可能**高估**(如果 Lex 实际 controller 配置下 SA 名就是 `waypoint-int`,风险实际为 LOW)
- 🟠 M-2 风险等级可能**低估**(如果业务 label 重命名频繁,工程化改进必要性提升)
- 🟠 §1.3 评估维度和 §8.1 标签体系**完全主观**,Lex 可根据需要调整

**已知未知 (需要 cluster 数据校准)**:
- H-1 风险等级 → 需 Q6 验证 `ENABLE_INGRESS_WAYPOINT_ROUTING` 状态
- H-2 风险等级 → 需 Q4 验证 waypoint 实际 SA 名
- H-3 风险等级 → 需 Q7 验证 ns 是否共用 `businessId: ba000000` label

校准后(如果 Lex 决定校准),可产生 v6 报告,会更精确。

---

## 9. References

- [K8s NetworkPolicy 规范](https://kubernetes.io/docs/concepts/services-networking/network-policies/) — additive / podSelector / namespaceSelector 语义
- [Istio Ambient NetworkPolicy](https://istio.io/latest/docs/ambient/usage/networkpolicy/) — 15008 + link-local 探针
- [Istio AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — additive semantics
- [Istio PeerAuthentication](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — ambient 下限制
- [Istio Waypoint 1.30 官方文档](https://istio.io/v1.30/docs/ambient/usage/waypoint) — `ENABLE_INGRESS_WAYPOINT_ROUTING` 默认 false
- [Solo 1.30.x Waypoints](https://docs.solo.io/istio/1.30.x/ambient/waypoints/configuration) — `waypoint-for` label 矩阵
- 同仓库 `08-ambient-networkpolicy.md` — NetPol 协同规则
- 同仓库 `06-policy-capabilities.md` — AuthZ/PA ambient 能力矩阵
- 同仓库 `03-waypoint-design.md` §5 — waypoint HA 模板
- 同仓库 `10-waypoint-gateway-coexistence.md` — ingress 默认行为
- 本目录 `assessment-ingress.md` — ingress 流量完整路径分析

---

*Generated by architect-gcp Bot — v5 纯审计报告 + 评估合理性自审。*
*4 个 YAML 文件 (15 resources) schema 验证通过,语义层无 critical bug。*
*v5 不发起任何 follow-up action,所有修复决策权归 Lex。*