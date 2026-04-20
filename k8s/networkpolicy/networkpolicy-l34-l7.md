# NetworkPolicy L3/L4/L7 In GKE And Managed Service Mesh

## 1. Goal And Constraints

阅读完你提供的文档后，针对你提出的“在 L3/L4 层默认允许内部 Namespace 之间互访”的设计，我的分析如下：

1. 设计是否合理？
结论：这种设计在“平台化”初期是合理的平衡，但从“零信任（Zero Trust）”架构的角度来看，它属于一种“半开放”状态。
文档中明确指出，生产级的最佳实践应该是 “分层拒绝”。你现在的想法是将 L3/L4 层的边界放宽（即 Intra-Namespace 默认互访），而将安全压力全部移交给 L7（Istio 的 AuthorizationPolicy）。

2. 这种设计的优缺点分析

| 维度     | 你的设计（L3/L4 默认放通内部）                                                  | 文档推荐的设计（L3/L4 默认拒绝）                         |
| :------- | :------------------------------------------------------------------------------ | :------------------------------------------------------- |
| 运维成本 | 低。内部团队互访不需要频繁修改 NetworkPolicy，只需关注 Istio 规则。             | 高。每次新服务上线都要配置 L3/L4 路径。                  |
| 安全深度 | 中。如果 Sidecar 被绕过（例如恶意容器不注入 Sidecar），L3/L4 层的拦截就失效了。 | 高。即使 L7 授权失效，底层网络依然是不通的（纵深防御）。 |
| 排障难度 | 简单。减少了网络层丢包导致的 503 或连接超时问题。                               | 复杂。必须先解决 DNS 和基础网络放通，否则业务跑不通。    |

3. 核心风险点：Sidecar 绕过
文档在 6.1 节 明确警告了这种做法的风险：如果只靠 L7 的 AuthorizationPolicy 而不限制 L3/L4：
* 网络路径仍是开放的：如果攻击者在 Namespace 内启动了一个没有注入 Istio Sidecar 的 Pod，他可以直接通过 IP 扫描并访问你的业务端口，从而绕过所有的 L7 授权规则。
* 无法替代 Pod 级隔离：NetworkPolicy 是在内核层（通过 eBPF 或 IPTables）拦截的，是真正的“第一道防线”。

4. 改进建议：折中方案
如果你觉得为每个内部团队手动写 NetworkPolicy 太麻烦，可以采取以下自动化思路：
* **默认允许“带标签”的流量**：不要全开，而是规定所有属于“内部团队”的 Namespace 必须带上特定的 Label（如 env: internal）。NetworkPolicy 只允许来自匹配该 Label 的 Namespace 的流量。
* **利用 PeerAuthentication 强制 mTLS**：如果你决定 L3/L4 比较宽松，那么你必须将 PeerAuthentication 设置为 STRICT。这样可以确保即使网络通了，没有证书的非法调用也会在握手阶段被切断。
* **按敏感级分级**：对于普通业务团队，可以默认放通 L3/L4；但对于涉及金融、用户隐私的 “高敏 Namespace”，文档建议必须在 L3/L4 层也做到默认拒绝。

**总结建议**
你的设计在提升接入效率上是非常合理的，尤其是在管理多租户 API 平台时。但为了安全，建议你至少在平台层面保留一个 “默认关闭的外圈（Egress）”，即限制内部 Pod 只能访问集群内，不能随意访问外部互联网，同时通过 PeerAuthentication 强制 mTLS 来弥补 L3/L4 层松散带来的风险。

---

## 2. Short Answer

先给最短结论：

| 层         | 资源                  | 解决的问题                                             | 推荐职责                                              |
| :--------- | :-------------------- | :----------------------------------------------------- | :---------------------------------------------------- |
| L3/L4      | `NetworkPolicy`       | 这条 Pod 到 Pod 的网络连接能不能建立                   | 做默认拒绝、namespace/workload 边界、DNS/基础依赖放通 |
| 传输安全层 | `PeerAuthentication`  | 这条连接是否必须走 mTLS                                | 做 mesh 内部统一 mTLS 基线                            |
| L7         | `AuthorizationPolicy` | 已经连上之后，这个调用者能不能访问这个 API/path/method | 做身份授权、API 级精细访问控制                        |

**一句话原则：**

`NetworkPolicy` 决定“能不能到”，`PeerAuthentication` 决定“连线是否可信”，`AuthorizationPolicy` 决定“到了以后让不让进”。

---

## 3. Recommended Architecture (V1)

复杂度：`Moderate`

推荐的 V1 分层模型如下：

```text
Caller Pod
  |
  | 1. L3/L4: NetworkPolicy
  |    - 是否允许从 caller namespace / pod 到 callee pod:port
  |
  | 2. mTLS baseline: PeerAuthentication
  |    - callee 是否只接受 mTLS
  |
  | 3. L7 authz: AuthorizationPolicy
  |    - caller identity 是否允许访问 callee
  |    - 是否限制到 method / path / host / port
  |
  v
Callee Pod
```

推荐的职责切分：

### 3.1 L3/L4: `NetworkPolicy`

**放在这一层的能力：**
* namespace 间是否允许通信
* 同 namespace 内不同 workload 是否允许通信
* 目标 Pod 端口是否允许访问
* DNS、mesh 基础组件、metrics 等基础依赖是否允许访问
* egress 是否只能走指定出口

**不要指望它做的事情：**
* 识别 HTTP path、method、host
* 按 service account / principal 做授权
* 区分“这个调用是 `/healthz` 还是 `/api/v1/order`”

### 3.2 mTLS Baseline: `PeerAuthentication`

**放在这一层的能力：**
* 统一要求 mesh 内流量必须使用 mTLS
* 为历史系统或迁移期 workload 做少量例外

**不要把它当成：**
* 访问控制系统
* API 白名单系统

### 3.3 L7: `AuthorizationPolicy`

**放在这一层的能力：**
* 基于调用方 identity 授权
* 基于 namespace、service account、principal 做授权
* 基于 HTTP method/path/host 做 API 级约束
* 为同 namespace、跨 namespace、入口网关、egress gateway 定义细粒度规则

**不要把它当成：**
* Pod 网络隔离的替代品
* 集群级网络默认拒绝机制

---

## 4. Why Deny-All Must Be Layered

你说的“默认必须 deny all，然后逐渐放开”，在 Istio 场景里要拆成三层理解：

### 4.1 第一层：L3/L4 默认拒绝

由 `NetworkPolicy` 实现：
* 默认拒绝 ingress
* 默认拒绝 egress
* 只放通必要的 Pod 到 Pod 路径

这是最底层的“网络面”控制。

### 4.2 第二层：mTLS 默认严格

由 `PeerAuthentication` 实现：
* 默认 `STRICT`
* 明确要求 sidecar 到 sidecar 流量必须是 mTLS

这是“连接可信性”的控制。

### 4.3 第三层：L7 默认不授予业务访问

由 `AuthorizationPolicy` 实现：
* 只为明确允许的调用关系写 allow 规则
* 没有被允许的调用，即使网络通了，也不应被业务接受

所以，真正的生产模型不是单层 `deny all`，而是：

`L3/L4 deny all` + `mTLS strict` + `L7 explicit allow`

---

## 5. Best Practice Decision Table

| 需求                            | 最佳实践                                                     | 为什么                        |
| :------------------------------ | :----------------------------------------------------------- | :---------------------------- |
| namespace 之间默认隔离          | 用 `NetworkPolicy`                                           | 这是网络边界，不应交给 L7     |
| 同 namespace 内默认隔离         | 视安全级别决定，敏感 namespace 建议也用 `NetworkPolicy` 收紧 | 避免“同 namespace 默认全通”   |
| mesh 内要求加密和身份           | 用 `PeerAuthentication: STRICT`                              | 保证身份与传输安全基线        |
| 谁可以访问哪个 API              | 用 `AuthorizationPolicy`                                     | 这是身份授权问题              |
| 限制 `/admin`、`POST /v1/order` | 用 `AuthorizationPolicy`                                     | 只有 L7 看得到                |
| 限制只走 egress gateway 出网    | `NetworkPolicy` + mesh egress routing                        | L3/L4 控出口，L7 控目标与策略 |
| 允许 DNS                        | `NetworkPolicy` 显式放通                                     | 否则 deny-all 下解析会失败    |
| 允许控制面或 sidecar 依赖       | 谨慎放通必要端口/目标                                        | 否则会误伤 mesh 基础能力      |

---

## 6. Trade-Offs And Alternatives

### 6.1 方案 A：只用 `AuthorizationPolicy`

**不推荐作为主方案。**

**问题：**
* 网络路径本身仍然可能是开放的
* 无法替代 Pod 级网络隔离
* 故障域和攻击面更大

**适合：**
* 已经有强网络边界，且暂时只补 L7 授权

### 6.2 方案 B：只用 `NetworkPolicy`

**不推荐作为主方案。**

**问题：**
* 做不到 identity-based authorization
* 做不到 method/path 级授权
* 无法表达 API owner 真正关心的业务访问关系

**适合：**
* 没有 service mesh 的纯 Kubernetes 网络隔离

### 6.3 方案 C：`NetworkPolicy` + `PeerAuthentication` + `AuthorizationPolicy`

**这是推荐方案。**

**优点：**
* 分层清晰
* 可验证
* 符合零信任思路
* 更适合平台化和模板化

**代价：**
* 策略对象会变多
* 需要治理命名、模板、验证流程

---

## 7. Implementation Steps

推荐按下面顺序落地，而不是一次性把所有规则写满。

### Step 1: 建立平台默认 L3/L4 基线

每个业务 namespace 至少有：
1. 默认拒绝 ingress
2. 默认拒绝 egress
3. 显式允许 DNS
4. 显式允许必要的 mesh / observability / platform dependency

示例：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: app-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: app-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: app-a
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

**注意：**
* 在 routes-based / kube-proxy DNAT 模型下，`NetworkPolicy` 匹配的是目标 Pod IP 和目标 Pod 端口，不是 Service IP
* 所以不要把 Service CIDR 当成主要放通对象

### Step 2: 定义 namespace / workload 级放通关系

推荐优先使用：
* `namespaceSelector`
* `podSelector`

避免优先使用：
* 大范围 `ipBlock`
* Service CIDR 规则

示例：允许 `frontend` 调 `backend` 的 8080：

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
      podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### Step 3: 建立 mesh mTLS 基线

推荐 namespace 级默认 `STRICT`：

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: backend
spec:
  mtls:
    mode: STRICT
```

**建议：**
* 除非迁移期必须兼容明文，否则不要长期使用 `PERMISSIVE`
* 如果确实有例外，只对特定 workload 做例外，不要把整个 namespace 放宽

### Step 4: 用 `AuthorizationPolicy` 表达真实授权关系

示例：仅允许 `frontend` namespace 中指定 service account 调用 `backend`

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: backend
spec:
  selector:
    matchLabels:
      app: backend
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/frontend/sa/frontend-sa
```

如果需要进一步收紧到 API：

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-order-api
  namespace: backend
spec:
  selector:
    matchLabels:
      app: backend
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/frontend/sa/frontend-sa
    to:
    - operation:
        methods: ["POST"]
        paths: ["/v1/orders"]
```

---

## 8. Recommended Policy Ownership Model

为了避免规则失控，建议按 ownership 切分：

| 层             | 资源                                                    | 维护者                                 |
| :------------- | :------------------------------------------------------ | :------------------------------------- |
| 平台基线       | `default-deny`, DNS, mesh dependency 的 `NetworkPolicy` | 平台团队                               |
| namespace 边界 | 跨 namespace 的 `NetworkPolicy` 模板                    | 平台团队                               |
| mTLS 基线      | `PeerAuthentication`                                    | 平台团队                               |
| API 访问控制   | `AuthorizationPolicy`                                   | 平台团队提供模板，API owner 填业务关系 |

最稳的方式不是让业务团队手写全部策略，而是：
* 平台统一提供 Helm/Kustomize 模板
* 输入调用矩阵
* 自动生成策略

---

## 9. Practical Best Practices

### 9.1 `NetworkPolicy` 最佳实践
* 默认同时拒绝 ingress 和 egress
* 先放通 DNS，否则大量看似无关的问题都会出现
* 优先使用 label selector，不优先使用 IP
* 规则尽量贴近目标 workload，而不是写巨大共享白名单
* 对敏感 namespace，建议同 namespace 内也不要默认全通
* 对 egress，优先设计“只允许访问已知依赖或统一出口”

### 9.2 `PeerAuthentication` 最佳实践
* namespace 级默认 `STRICT`
* workload 例外要极少且有退场计划
* 不要把它和授权逻辑混用

### 9.3 `AuthorizationPolicy` 最佳实践
* 优先基于 `principal` 或 service account，不建议只靠 namespace
* namespace 级 allow 只适合宽松内部流量，不适合高敏场景
* API 级限制放在真正有业务价值的入口上，不要机械地每个 path 都建一条
* 优先按“消费者 -> 服务 -> API 组”建模，而不是按单条 URL 爆炸式建模

---

## 10. Common Mistakes

### 10.1 用 `AuthorizationPolicy` 替代 `NetworkPolicy`
**风险：**
* 网络路径仍可达
* 隔离边界不清楚
* 调试复杂度更高

### 10.2 只做 `NetworkPolicy`，不做 L7 授权
**风险：**
* 同一个可达服务上的所有 API 默认共享网络信任
* 做不到 caller identity 授权

### 10.3 在 deny-all 下忘记 DNS
这是最常见的误伤之一。

### 10.4 使用 Service IP 或 Service port 设计主要规则
在很多实现里，策略实际检查的是 Pod IP / Pod port。

### 10.5 把 namespace 当成唯一安全边界
namespace 是重要边界，但不是足够边界。

对于高敏业务：
* namespace 之间要隔离
* namespace 内 workload 之间也要按需隔离
* API 层仍要做身份授权

---

## 11. Validation And Rollback

### 11.1 验证清单
每次策略发布后至少验证：
1. DNS 解析正常
2. 健康检查正常
3. 业务调用矩阵中的允许路径正常
4. 非允许路径被正确拒绝
5. sidecar 间连接为 mTLS
6. 关键告警、日志、trace 未被误伤

建议命令：
```bash
kubectl get networkpolicy -A
kubectl get peerauthentication -A
kubectl get authorizationpolicy -A
kubectl describe networkpolicy -n backend
kubectl auth can-i --list
istioctl x describe pod <pod-name> -n <namespace>
istioctl proxy-config cluster <pod-name> -n <namespace>
```

建议验证方法：
* 从 caller Pod 内用 `curl` 或测试客户端发起真实请求
* 同时验证允许和拒绝两类路径
* 结合 access log / audit log / Envoy log 确认命中的是哪一层策略

### 11.2 回滚策略
推荐按层回滚，不要直接全量撤销：
1. 先回滚最新变更的 `AuthorizationPolicy`
2. 如果仍异常，再回滚新增的 `NetworkPolicy`
3. `PeerAuthentication` 一般作为稳定基线，除非迁移故障，不建议轻易回退

**发布建议：**
* 先在非生产 namespace 验证
* 再灰度到单个业务 namespace
* 最后模板化推广

---

## 12. Reliability And Cost Optimizations

### 12.1 可靠性
* 用 `NetworkPolicy` 缩小 blast radius
* 用 `PeerAuthentication STRICT` 保证 mesh identity 可用
* 用 `AuthorizationPolicy` 防止“网络通了就默认可信”
* 对关键服务保留最小可用依赖白名单

### 12.2 成本与运维复杂度
* 不要一开始把所有 path 都精细化建模
* 先按 namespace / service / API group 三层做
* 高频变更放在 `AuthorizationPolicy`
* 低频边界变更放在 `NetworkPolicy`

这样做的原因：
* `NetworkPolicy` 更适合稳定边界
* `AuthorizationPolicy` 更适合业务访问关系的持续演进

---

## 13. Final Recommendation For Your Scenario

基于你当前的思路，我建议直接采用下面这个默认模型：

### 13.1 平台默认基线
- 每个 runtime namespace 自动下发 `default deny ingress`
- 每个 runtime namespace 自动下发 `default deny egress`
- 自动放通 DNS
- 自动放通必要 platform dependency
- 自动下发 namespace 级 `PeerAuthentication: STRICT`

### 13.2 服务接入时的放通流程
新服务接入时按顺序处理：
1. 先定义它需要访问哪些服务
2. 平台生成对应 `NetworkPolicy`
3. API owner 定义允许哪些 caller identity
4. 平台或模板生成 `AuthorizationPolicy`
5. 通过验证脚本检查 allow / deny 是否符合预期

### 13.3 设计原则
- L3/L4 做边界，不做业务语义
- mTLS 做强制身份通道
- L7 做真实授权
- 默认拒绝，但例外必须模板化、可审计、可回滚

---

## 14. Handoff Checklist

- 是否所有业务 namespace 都有默认拒绝 ingress/egress
- 是否显式放通了 DNS
- 是否确认 mesh 基础依赖未被误伤
- 是否 namespace 级 `PeerAuthentication` 默认为 `STRICT`
- 是否关键服务已经有 `AuthorizationPolicy`
- 是否高敏 namespace 内 workload 间也做了 L3/L4 收紧
- 是否有 allow/deny 双向测试
- 是否有灰度发布和回滚策略
- 是否有模板化生成方案，而不是人工散写

---

## 15. One-Line Summary

在 GKE + Managed Service Mesh 里，最佳实践不是“只靠一种策略做 deny all”，而是把默认收紧拆成三层：`NetworkPolicy` 负责 L3/L4 可达性基线，`PeerAuthentication` 负责 mTLS 强制，`AuthorizationPolicy` 负责 L7 身份与 API 授权；这样最稳，也最适合平台化落地。
---
