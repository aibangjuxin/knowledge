# Istio PeerAuthentication 能力矩阵与实战场景

> 适用环境:GKE / Google Cloud Service Mesh(ASM)/ Upstream Istio · sidecar 模式(也覆盖 ambient 模式差异) · `security.istio.io/v1beta1`
>
> 姊妹文档:
> - [`authorizationPolicy-and-Peerauthentication.md`](./authorizationPolicy-and-Peerauthentication.md) — 概念、分工、分层模型
> - [`authorizationPolicy-capabilities-and-use-cases.md`](./authorizationPolicy-capabilities-and-use-cases.md) — AuthorizationPolicy 的能力矩阵
> - [`serviceEntry-capabilities-and-use-cases.md`](./serviceEntry-capabilities-and-use-cases.md) — ServiceEntry 的能力矩阵(出向流量怎么把外部服务接入治理;ambient 模式 DNS auto-allocate / wildcard 限制 / serviceEntryVisibility 都有专门章节)
>
> 本篇专门回答:**PeerAuthentication 到底能管控什么、典型场景、跟 AuthorizationPolicy 的边界。**

---

## 0. 一句话定位

`PeerAuthentication` 解决的是「**这条进来的连接,要不要带 mTLS 身份**」。

它只看 **4 个东西**:

| 维度 | 字段 | 类比 |
|---|---|---|
| **在哪个 workload 上生效** | `selector` | 监听哪个端口 |
| **整体模式** | `spec.mtls.mode` | 总开关:STRICT / PERMISSIVE / DISABLE / UNSET |
| **逐端口覆盖** | `spec.portLevelMtls[<port>].mode` | 端口级例外 |
| **作用域** | `metadata.namespace` | 全 mesh / 单 namespace / 单 workload |

**它**不**做的事**(常见误解):
- ❌ **不管"谁"** —— 不看 caller 是谁 SA、哪个 namespace、哪条路径;那是 `AuthorizationPolicy` 的活。
- ❌ **不做 end-user 认证** —— 不验证 JWT;那是 `RequestAuthentication` 的活。
- ❌ **不加密 HTTP body** —— 它只决定"是否要 TLS 握手",TLS 实际由 sidecar 完成。

**它**只**管一件事:连接建立阶段,是否要求对方出示合法的 SPIFFE X.509 证书。**

---

## 1. 资源结构骨架

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: <name>
  namespace: <ns>          # 同 namespace = namespace-wide;root namespace = mesh-wide
spec:
  selector:                # 可选:限定到具体 workload
    matchLabels:
      app: api-a
  mtls:                    # 整体 mTLS 模式
    mode: STRICT           # STRICT | PERMISSIVE | DISABLE | UNSET
  portLevelMtls:           # 逐端口覆盖(可选)
    8080:
      mode: DISABLE
    9090:
      mode: PERMISSIVE
```

**整个 spec 就 3 个字段**,故意设计得很简单——它只表达"我要不要 mTLS",不要被它的简洁骗到,**`mode` 的继承与覆盖语义是坑的高发区**。

---

## 2. 四种 mode:语义表

```
┌────────────┬─────────────────────────────────────────────────────────────────────┐
│ STRICT     │ 只接受 mTLS(对方必须出示合法 SPIFFE 证书)                           │
│            │ 明文流量直接拒绝,TCP RST                                            │
│            │ ✅ 生产默认值                                                       │
├────────────┼─────────────────────────────────────────────────────────────────────┤
│ PERMISSIVE │ 同时接受 mTLS 和 明文                                              │
│            │ 用法:迁移期兼容老客户端;一旦全量切换完成,必须改 STRICT               │
│            │ ⚠️ PERMISSIVE 下 AuthorizationPolicy 里的 principals/namespaces    │
│            │ 字段都不可信(明文 = 没身份,可绕过)                                │
├────────────┼─────────────────────────────────────────────────────────────────────┤
│ DISABLE    │ 强制只接受明文;sidecar 不会升级到 TLS                               │
│            │ 用法:老 legacy 服务出口(数据库连接、metrics 端口)                  │
│            │ ⚠️ DISABLE 后 AuthorizationPolicy 在该 workload 上完全失效         │
├────────────┼─────────────────────────────────────────────────────────────────────┤
│ UNSET      │ 不在本策略里设值;继承父级(父 workload → 父 namespace → mesh)        │
│            │ 用法:仅想给某个 workload **port-level** 覆盖,但不想改整体模式       │
└────────────┴─────────────────────────────────────────────────────────────────────┘
```

### 2.1 mode 继承链(理解 UNSET 的关键)

生效优先级:**workload-level > namespace-level > mesh-level**;但同层有 `selector` 的优先于无 `selector` 的。

```
Mesh default (root namespace, no selector)            ← 最弱
    ↓
Namespace default (target ns, no selector)            ← namespace baseline
    ↓
Workload-level (target ns, with selector matchLabels) ← 最强(只在 workload-port 维度被 portLevelMtls 覆盖)
    ↓
Port-level override (portLevelMtls[port])             ← 端口维度最末位
```

**反直觉**:在 root namespace 写的 **带 selector** 的 PeerAuthentication 会被静默忽略——
> "PeerAuthentication policies with workload selectors are ignored when deployed in the root namespace." — [Istio 官方 reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/)

→ 想做 mesh-wide 的端口例外,必须放在 workload 所在 namespace。

### 2.2 portLevelMtls 覆盖规则

`portLevelMtls[<port>]` 的 port 是 **workload 实际监听端口**,不是 service port:

```yaml
# workload 容器里 listen :8080,但 service 暴露 80 → 8080
spec:
  selector:
    matchLabels:
      app: api-a
  mtls:
    mode: STRICT
  portLevelMtls:
    8080:
      mode: DISABLE      # 这个 workload 的 8080 端口接受明文
```

**限制**:
- portLevelMtls 必须配合 `selector`(否则 Istio 不知道作用到哪个 workload)
- `portLevelMtls` 里的 mode 不再向上继承——必须显式设一个值(STRICT / PERMISSIVE / DISABLE,UNSET 在这里没意义)

---

## 3. 实战场景

### 3.1 生产环境基线(全 namespace STRICT)

> **能不能"一行命令让整个 namespace 强制 mTLS"?**

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: <NAMESPACE>
spec:
  mtls:
    mode: STRICT
```

**适用**:任何新建 runtime namespace 的"开张即安全"基线。这是 Lex 现有笔记 §8.2 / §13.1 的标准做法。

### 3.2 Mesh-wide 默认 mTLS

> **能不能"全 mesh 默认 mTLS,但允许个别 namespace 例外"?**

```yaml
# 1. 全 mesh 一刀切 STRICT
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system       # root namespace = mesh-wide
spec:
  mtls:
    mode: STRICT
---
# 2. 允许 legacy namespace 接受明文(迁移用)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-legacy
  namespace: legacy
spec:
  mtls:
    mode: PERMISSIVE
```

**注意**:namespace-level `PERMISSIVE` 覆盖 mesh-level `STRICT`,因为 namespace 粒度更细。

### 3.3 灰度迁移:从 PERMISSIVE 切到 STRICT

> **怎么从老集群"全明文"逐步切到"全 mTLS"而不爆炸?**

Istio 官方迁移路径(被广泛验证):

```
Step 1 (观察期):root namespace 部署 PERMISSIVE
                → mesh-wide 既接受 mTLS 也接受明文,但 Istiod 已开始签发证书
Step 2 (摸底):用 Prometheus / Kiali 监控 sidecar 比例
                → 确认 99%+ workload 已注入 sidecar
Step 3 (收紧):root namespace 改 STRICT
                → 明文直接被拒;若个别 workload 没注入 sidecar,会立刻报 connection refused
Step 4 (稳定):保留 STRICT,只在 audit log 里看是否有未签发证书的请求
```

**坑**:
- Step 1 跨度过大(全 mesh 直接 STRICT):老客户端没装 sidecar 会全部失联,**几乎一定爆炸**。
- 想"灰度切单个 namespace":先让该 namespace 上 STRICT,监控失败率,**不要**靠 PERMISSIVE 试探。

### 3.4 端口级例外:同一服务混合 mTLS + 明文

> **能不能 "metrics 端口走明文,业务端口走 mTLS"?** Prometheus 经常 scrape `/metrics`,不希望强制 TLS。

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: api-metrics-plaintext
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  mtls:
    mode: STRICT            # 整体 STRICT
  portLevelMtls:
    9090:                   # metrics 端口
      mode: DISABLE         # 这个端口允许明文
```

**配合 NetworkPolicy 锁死 metrics 端口只允许 Prometheus IP**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-metrics-netpol
  namespace: <NAMESPACE>
spec:
  podSelector:
    matchLabels:
      app: api-a
  policyTypes: [Ingress]
  ingress:
    - from:
        - ipBlock:
            cidr: 10.0.0.0/8    # 只允许 Prometheus 节点段(具体段请按集群)
      ports:
        - protocol: TCP
          port: 9090
```

### 3.5 老数据库连接(TCP 明文 → 保留明文)

> **能不能 "Pod 访问外部 MySQL 不强制 TLS"?**

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: workload-to-mysql-plaintext
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: backend-job     # 这个 workload 要连外部 MySQL
  mtls:
    mode: STRICT          # 整体还是 STRICT
  portLevelMtls:
    3306:
      mode: DISABLE       # 出口到 MySQL 3306 端口允许明文
```

⚠️ 这只控制**作为 server 接收的连接**——`portLevelMtls` 控的是 inbound。**outbound(本 Pod 作为 client 出去)** 的 mTLS 模式由 **DestinationRule 的 `trafficPolicy.tls.mode`** 控制(不是 PeerAuthentication 的职责)。

### 3.6 临时为某个 workload 兼容老客户端(打补丁)

> **能不能 "namespace 已经 STRICT,但某个新上线的服务要快速接老 client"?

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: api-new-permissive
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-new          # 只对这个 workload 例外
  mtls:
    mode: PERMISSIVE
```

**生产风险**:
- 老 client 上线后,容易忘了再切回 STRICT → 留个永久洞。
- **建议**:把这种例外写进 namespace 创建时记录的"security exceptions"清单里,定期 audit。

### 3.7 跟 AuthorizationPolicy 的关系(常见误解)

| 误解 | 真相 |
|---|---|
| "PeerAuthentication STRICT 后 AuthorizationPolicy 才能生效" | **部分对**:`principals` / `namespaces` / `serviceAccounts` 这几个基于 mTLS 身份的字段需要 STRICT 才可信;**ALLOW/DENY 本身不需要** mTLS |
| "PERMISSIVE 等于没设" | **错**:PERMISSIVE 表示"接受两种",但**只要对方带证书,身份就生效**——所以 PERMISSIVE 也能用 `principals` 字段,只要 client 都启用了 mTLS |
| "DISABLE 等于完全裸奔" | **对**:DISABLE 后该 workload 完全不接受 mTLS,AuthorizationPolicy 也无法基于 mTLS 身份做决策(因为根本没身份) |

**安全的最佳实践**:

```yaml
# mesh-wide 强制 STRICT(身份可信)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
---
# AuthorizationPolicy 此时 principals 字段才有意义
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-a-allow-internal
  namespace: <NAMESPACE>
spec:
  selector:
    matchLabels:
      app: api-a
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/<NAMESPACE>/sa/frontend-sa"]
```

**官方安全公告 [istio-security-2021-004](https://istio.io/latest/news/security/istio-security-2021-004/)** 专门讲 PERMISSIVE 下基于身份的字段可被绕过——**生产 namespace 任何用了 AuthorizationPolicy principal 字段的,必须 STRICT**。

### 3.8 Ambient 模式差异(Istio ≥ 1.22)

> **如果用 ambient 模式而非 sidecar,PeerAuthentication 行为一样吗?**

**关键差异**:

| 维度 | sidecar 模式 | ambient 模式 |
|---|---|---|
| PeerAuthentication | ✅ 完全支持 | ✅ 支持,但有差异 |
| `DISABLE` mode | ✅ 支持 | ❌ **不支持**——ambient 默认加密(HBONE 协议),无法"关闭" |
| `STRICT` mode | ✅ 推荐 | ✅ 用来**阻止绕过 mesh 的明文连接**(防止 pod 直连不经 ztunnel) |
| `PERMISSIVE` mode | ✅ 兼容期 | ✅ 同上 |

ambient 模式下,ztunnel(节点级 mTLS 代理)负责所有 pod 间流量,加密默认开。所以 PeerAuthentication 的核心用途变成 **"确保 mesh 覆盖范围内的连接必须走 ztunnel,不允许旁路"**。

```yaml
# ambient 模式下,常用 STRICT + selector 强制特定 namespace 必须走 mesh
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: <NAMESPACE>
spec:
  mtls:
    mode: STRICT    # 含义:连接必须经过 mesh 加密层
```

### 3.9 Waypoint proxy 粒度

ambient 模式下还能配 waypoint proxy(per-namespace L7 代理)。PeerAuthentication 在 waypoint 上的生效范围与 sidecar 模式一致,但作用在 waypoint 进程,不是应用 pod。

---

## 4. 能力矩阵(它能 / 不能管控什么)

| 类别 | 能/不能 | 说明 |
|---|---|---|
| 强制 mTLS 加密 | ✅ | STRICT / PERMISSIVE / DISABLE |
| 决定是否验证对端身份 | ✅ | STRICT = 必须验证;DISABLE = 不验证 |
| 端口级覆盖 | ✅ | portLevelMtls |
| 控制 namespace / workload 范围 | ✅ | metadata.namespace + selector |
| Mesh-wide 一刀切 | ✅ | 放 root namespace(但带 selector 的会被忽略)|
| 决定对方是谁 / 能不能调 | ❌ | AuthorizationPolicy |
| 验证 JWT 主体身份 | ❌ | RequestAuthentication |
| 选择 TLS 版本 / cipher 套件 | ❌ | MeshConfig / DestinationRule |
| 加密特定 HTTP header | ❌ | 控制 TLS 整体开 / 关,不细化 header |
| 客户端 outbound mTLS | ❌ | DestinationRule.trafficPolicy.tls.mode |
| 拒绝特定 IP / SA | ❌ | AuthorizationPolicy |

**一行总结**:`PeerAuthentication` 管 **"通不通 mTLS"**;不管 **"谁在用 mTLS 跟我说话"** 也不管 **"mTLS 之外要不要加 JWT"**。

---

## 5. 跟其他 Istio 资源的协作

### 5.1 PeerAuthentication + AuthorizationPolicy(标准组合)

```
PeerAuthentication STRICT → 保证所有进来的连接都带 mTLS SPIFFE 身份
        ↓
AuthorizationPolicy ALLOW + principals → 基于 SPIFFE 身份决定放行
```

`PeerAuthentication` 是"身份可信层",`AuthorizationPolicy` 是"基于身份做决策层"。**两者必须协同**,任何只有一边的设计都不完整。

### 5.2 PeerAuthentication + DestinationRule(client 侧 mTLS)

```
PeerAuthentication (server 接收侧) → 是否要求对端出示证书
DestinationRule.tls.mode (client 发起侧) → 自己是否出示证书
```

**当 client 端 DestinationRule 没配 tls.mode 时,Istio 默认就尝试 mTLS(因为是 mesh)。但 PERMISSIVE 下 server 接受明文,client 端就会降级**——所以 PERMISSIVE 是双刃剑。

### 5.3 PeerAuthentication + NetworkPolicy

| 层级 | 资源 | 责任 |
|---|---|---|
| L3/L4 | `NetworkPolicy` | 包能不能到 Pod |
| L4 加密 | `PeerAuthentication` | 到了之后要不要 TLS |
| L7 授权 | `AuthorizationPolicy` | TLS 之内还能不能进 |

PeerAuthentication **不替代** NetworkPolicy,NetworkPolicy **也不替代** PeerAuthentication。**三层必须都有**,详见姊妹文档 §16。

---

## 6. 常见坑(实战验证)

### 6.1 root namespace 带 selector = 静默忽略

```yaml
# ❌ 错:放在 istio-system 还想用 selector,会被忽略
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: mesh
  namespace: istio-system
spec:
  selector:
    matchLabels:
      app: api-a       # ← 无效,这个 selector 在 root ns 被忽略
  mtls:
    mode: STRICT
```

→ 想做 workload-level 例外,必须把策略放到 workload 所在 namespace。

### 6.2 portLevelMtls 不控制 outbound

`portLevelMtls[<port>]` 只控制 **inbound**(本 workload 作为 server 接收)。**outbound**(本 workload 作为 client 出去)的 mTLS 模式由 DestinationRule 控制:

```yaml
# PeerAuthentication 控制 server 侧
spec:
  portLevelMtls:
    8080:
      mode: DISABLE     # 我作为 server 接收 8080 时,允许明文

---
# DestinationRule 控制 client 侧
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: external-mysql
spec:
  host: mysql.example.com
  trafficPolicy:
    tls:
      mode: DISABLE     # 我作为 client 出去时,不走 TLS
```

混用两个字段名一样的 mode 是历史坑——记住:PeerAuthentication 是 server 视角,DestinationRule 是 client 视角。

### 6.3 portLevelMtls 看不到上层

```yaml
# namespace 是 STRICT,但你想让某个 workload port 8080 DISABLE
spec:
  selector:
    matchLabels:
      app: api-a
  mtls:
    mode: UNSET         # 必须显式 UNSET,不能省略
  portLevelMtls:
    8080:
      mode: DISABLE
```

如果 `mtls.mode` 字段整段省略(不是 UNSET),Istio 在某些版本会按 "policy 默认" 处理而非继承父级——**显式 UNSET 比省略更安全**。

### 6.4 STRICT 切换后老 client 立刻断连

没有 PERMISSIVE 过渡期,直接上 STRICT 是高风险动作。

**检查清单**:
- [ ] 确认 namespace 内所有 Pod 都已注入 sidecar(`istioctl analyze`)
- [ ] 确认 ingress / egress 网关也已注入 sidecar
- [ ] 确认跨 mesh 调用方也支持 mTLS
- [ ] **先**对单个 namespace 做 STRICT + 监控 24h,**再**全 mesh 推广

### 6.5 PERMISSIVE 下 AuthorizationPolicy 身份字段失效

这是 Istio 安全公告 [2021-004](https://istio.io/latest/news/security/istio-security-2021-004/) 的核心结论。**生产 namespace 不能用 PERMISSIVE + principal-based AuthorizationPolicy 的组合**(等于明文绕过身份检查)。

### 6.6 DISABLE 让 AuthorizationPolicy 形同虚设

DISABLE = 不接受 mTLS = 所有连接都是明文 = 没有 SPIFFE 身份 = `principals` 字段无法匹配。

→ **DISABLE 等于"那个 workload 没接 mesh"**,AuthorizationPolicy 在它身上失去大部分作用。

### 6.7 多个 PeerAuthentication 在同一 workload 上叠加

如果同一 workload 匹配多条 PeerAuthentication,**最具体的优先**(带 selector > 不带 selector),但**mode 不合并**——只取一条。

```yaml
# 同一 workload 上:
# - ns-wide: STRICT
# - workload-level: PERMISSIVE
# 结果:workload = PERMISSIVE(workload 优先)
```

→ 调试"为什么 STRICT 没生效"时,先 `kubectl get peerauthentication -A -o yaml` 看是否有更高优先级的策略覆盖。

### 6.8 meshConfig.defaultMeshPolicy 不要忽略

Istio 安装时可配 `meshConfig.peerAuthentication.mode`(mesh 默认值)。如果设了 `DISABLE`,**即使你写了 STRICT 的 PeerAuthentication,有些场景下仍可能不生效**(取决于版本)。**mesh-wide baseline 推荐用法是显式 PeerAuthentication**,不靠 meshConfig 默认值。

---

## 7. 决策树:新需求来了该怎么用

```
需求 X
  │
  ├─ X 是 "想强制 mTLS 加密"?
  │   ├─ 整个 namespace → namespace-level STRICT(§3.1)
  │   ├─ 全 mesh        → root namespace STRICT(§3.2)
  │   ├─ 单 workload    → workload-level with selector(§3.6)
  │   └─ 单端口例外     → portLevelMtls(§3.4)
  │
  ├─ X 是 "想兼容老客户端"? → PERMISSIVE + 监控 + 切 STRICT(§3.3)
  │
  ├─ X 是 "想关掉 mTLS"?
  │   ├─ metrics/health 端口 → portLevelMtls DISABLE(§3.4)
  │   ├─ legacy 服务        → workload-level DISABLE(⚠️ 慎用)
  │   └─ 出明文到外部 DB    → DestinationRule DISABLE(不是 PA 的活,§6.2)
  │
  └─ X 是 "想决定谁能调"? → 那是 AuthorizationPolicy,不是 PA(§3.7)
```

---

## 8. 一句话总结

**PeerAuthentication 管**:**"mTLS 通不通"** —— 用 4 种 mode + portLevelMtls,在 mesh / namespace / workload / port 四个层级上控制 mTLS 加密和身份验证。

**PeerAuthentication 不管**:**"谁在说话"**("能不能调"**"**"mTLS 之外还要不要 JWT"**)** —— 这些分别归 AuthorizationPolicy、AuthorizationPolicy、RequestAuthentication。

**典型组合**:`PeerAuthentication STRICT` + `AuthorizationPolicy ALLOW/principals` + `RequestAuthentication`(可选 JWT 主体) = 服务间零信任的最小完整三件套。

## References

- [Istio PeerAuthentication reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — 权威字段表 + mode 继承链
- [Istio Mutual TLS Migration task](https://istio.io/latest/docs/tasks/security/authentication/mtls-migration/) — PERMISSIVE → STRICT 迁移路径
- [Istio Authentication Policy task](https://istio.io/latest/docs/tasks/security/authentication/authn-policy/) — PeerAuthentication 完整配置示例
- [Istio Security concepts](https://istio.io/latest/docs/concepts/security/) — AAA / mTLS / secure naming 全景
- [Istio security advisory 2021-004](https://istio.io/latest/news/security/istio-security-2021-004/) — PERMISSIVE mTLS 下身份字段可绕过的硬约束
- [Istio Ambient Security](https://istio.io/latest/docs/ambient/security/) — ambient 模式下 PeerAuthentication 的差异
- [Istio DestinationRule TLS](https://istio.io/latest/docs/reference/config/networking/destination-rule/#TrafficPolicy-TLSettings) — outbound 侧 mTLS 配置
- [Google Cloud Service Mesh: Authentication policy](https://cloud.google.com/service-mesh/docs/security/authentication-policy) — ASM 视角下的 Authentication 策略
- 同目录 `authorizationPolicy-and-Peerauthentication.md` — 与 AuthorizationPolicy 的分工、模板化、三层模型
- 同目录 `authorizationPolicy-capabilities-and-use-cases.md` — AuthorizationPolicy 能力矩阵