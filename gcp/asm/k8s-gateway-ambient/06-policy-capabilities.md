# Ambient 模式下 AuthorizationPolicy / PeerAuthentication 能力矩阵(场景化)

> **TL;DR**:
> - ambient 下两套策略**大部分仍可用**,只有少量限制(DISABLE mode 不支持、`portLevelMtls` 不生效)
> - **推荐写法**:`targetRefs` 绑 Service / Gateway(waypoint),取代 `selector.matchLabels`
> - 用户上传 / 下载 / header 限制 等业务场景,在 ambient 下用 **waypoint + AuthorizationPolicy** 落地
> - 本篇是**知识储备**(不立即动你现有 policy),只把"能做什么"列清楚,等需要时直接翻

---

## 0. 文档定位

> 来源引用:
> - [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/)
> - [Istio PeerAuthentication reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/)
> - [Istio Ambient Security](https://istio.io/latest/docs/ambient/security/)
> - 同仓库 `~/git/knowledge/gcp/asm/authorizationPolicy-capabilities-and-use-cases.md`(sidecar 版能力矩阵)
> - 同仓库 `~/git/knowledge/gcp/asm/peerAuthentication-capabilities-and-use-cases.md`(sidecar 版能力矩阵)

本文**只列 ambient 下的差异与场景化用法**,完整字段表请直接看上面两篇。

---

## 1. Ambient 下两套策略的差异速查表

| 维度 | sidecar(已熟) | ambient(本篇) |
|---|---|---|
| **AuthorizationPolicy ALLOW / DENY / AUDIT / CUSTOM** | ✅ | ✅(执行点 = waypoint 而非 pod 内 envoy) |
| **AuthorizationPolicy `selector`** | ✅ 绑 pod label | ✅ 仍可用(粒度到 pod) |
| **AuthorizationPolicy `targetRefs`**(API ≥ 1.22) | ✅ 绑 Service / Gateway | ⭐⭐⭐ **推荐**(绑 waypoint Gateway) |
| **AuthorizationPolicy `request.headers[X]`** | ✅ | ✅(waypoint 解析) |
| **AuthorizationPolicy `request.auth.claims[X]`** | ✅ | ✅ |
| **AuthorizationPolicy CUSTOM (ext_authz)** | ✅ | ✅(waypoint 调外部) |
| **PeerAuthentication STRICT** | ✅ 推荐 | ✅ **含义变化**:ambient 默认加密,STRICT 表示"必须走 mesh" |
| **PeerAuthentication PERMISSIVE** | ✅ 迁移期 | ✅ 同上,接受明文或 mesh |
| **PeerAuthentication DISABLE** | ✅ 支持 | ❌ **不支持**(ambient 默认 mTLS,无明文模式) |
| **`portLevelMtls`** | ✅ | ❌ **不支持**(不报错但无效,见 §3) |
| **mTLS 依赖的字段**(principals/namespaces/serviceAccounts) | 需 STRICT | 同上,STRICT 表示"必须走 mesh" |
| **Waypoint 级 PeerAuthentication** | N/A | ✅ 可针对 waypoint 单独配 |

---

## 2. 严格定义 vs 简化解释

| 概念 | 简化解释 | 严格定义 |
|---|---|---|
| **targetRefs** | "绑 Service / Gateway,不绑 pod" | "`targetRefs` allows an AuthorizationPolicy to be applied to specific Kubernetes Services, Gateways, or other Istio-targeted resources; it supersedes `selector` for resource-aware policies." — [Istio AuthorizationPolicy](https://istio.io/latest/docs/reference/config/security/authorization-policy/) |
| **selector(在 ambient 下)** | 仍可用但粒度受限 | "When `selector` is used in ambient, the policy applies to pods matching the selector; for namespace-level L7 control, prefer `targetRefs` to attach to waypoints." — Istio Ambient docs |
| **ambient 下 STRICT 的语义** | "必须走 mesh" | "In ambient, `STRICT` means the connection must traverse ztunnel (mesh-encrypted); `PERMISSIVE` allows plain traffic or mesh; `DISABLE` is not supported because mesh encryption is the default." — [Istio Ambient Security](https://istio.io/latest/docs/ambient/security/) |

---

## 3. ambient 下的关键限制(必看)

### 3.1 `PeerAuthentication` `DISABLE` 不支持

```yaml
# ❌ 这条在 ambient 下不生效(且不报错)
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: metrics-plaintext
spec:
  mtls: {mode: DISABLE}    # ← ambient:被忽略,仍走 mTLS
```

**适用场景损失**:
- 老数据库 / legacy 服务出口 = 只能走 DestinationRule 控制(不是 PeerAuthentication)
- metrics 端口走明文 = 不能用 PeerAuthentication DISABLE

### 3.2 `portLevelMtls` 在 ambient 下无效

```yaml
# ❌ ambient 下,这个策略无效(同 §3.1)
spec:
  mtls: {mode: STRICT}
  portLevelMtls:
    9090: {mode: DISABLE}
```

**绕路方案**:
- metrics 走节点端口 + NetworkPolicy 锁源 IP(详细见 04 文 §3.2)

### 3.3 `selector` 粒度问题

sidecar 模式下,`selector` 绑 pod label 是 fine 的;
ambient 下,业务 pod 没有 sidecar,`selector.matchLabels` **必须基于业务 pod 的 label**(不是 envoy 的)。

实务上,**推荐改用 `targetRefs`** —— 绑 Service 或 Gateway(waypoint),语义更清晰。

---

## 4. 用户上传 / 下载控制(场景 1)

> Lex 明确提到的业务需求:**限制用户上传/下载行为**。

### 4.1 限制"谁能调上传接口"

**前置**:
- 业务有上传接口(假设 `/upload/*`)
- 想限制:只有 SA-A 才能调,其他全部 DENY

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-upload-allow-only-A
  namespace: team-a-runtime           # ambient + waypoint 已就绪的 ns
spec:
  targetRefs:                          # ✅ ambient 推荐写法
    - kind: Service
      group: ""
      name: api-upload
  action: ALLOW
  rules:
    - from:
        - source:
            serviceAccounts: ["team-a-runtime/uploader-sa"]
      to:
        - operation:
            methods: ["POST"]
            paths: ["/upload/*"]
```

### 4.2 限制上传文件类型(MIME)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-upload-mime-only
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-upload
  action: ALLOW
  rules:
    - when:
        - key: request.headers[content-type]
          values:
            - "image/png"
            - "image/jpeg"
            - "application/pdf"
```

### 4.3 限制上传大小(注意:**不是** AuthorizationPolicy)

AuthorizationPolicy **不能限制 body size**,因为 waypoint 转发后才看 body。
**正解**:用 EnvoyFilter 配 buffer filter:

```yaml
# api-upload-body-limit.yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: api-upload-body-limit
  namespace: team-a-runtime
spec:
  workloadSelector:
    labels:
      app: api-upload
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: SIDECAR_INBOUND    # ambient 下 waypoint 也认这个 context
        listener:
          filterChain:
            filter:
              name: "envoy.filters.network.http_connection_manager"
              subFilter:
                name: "envoy.filters.http.router"
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.buffer
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.buffer.v3.Buffer
            max_request_bytes: 52428800  # 50 MB
```

### 4.4 限制上传频率(也不是)

AuthorizationPolicy 不管 rate limit。
**正解**:
- EnvoyFilter + `local_ratelimit` filter(per-pod 限制)
- 或外部 rate limit service(RLS)

---

## 5. Header 限制(场景 2)

> Lex 提到的第二个需求:**限制 header**。

### 5.1 强制必须带某个 header

```yaml
# API key 必须在 header 里
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-require-x-api-key
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-protected
  action: ALLOW
  rules:
    - when:
        - key: request.headers[x-api-key]
          values: ["abc123*"]    # 支持前缀匹配
```

### 5.2 多租户 header 路由

```yaml
# 按 X-Tenant-ID 限制只有 t1/t2 能调
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-allow-tenant
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-multi-tenant
  action: ALLOW
  rules:
    - when:
        - key: request.headers[x-tenant-id]
          values: ["t1", "t2"]
```

### 5.3 阻止特定 header(防 header 注入)

```yaml
# 阻止带 X-Forwarded-For 伪造客户端 IP
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-deny-xff-spoof
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-strict
  action: DENY
  rules:
    - when:
        - key: request.headers[x-forwarded-for]
          values: ["*"]    # DENY 全部带 XFF 的(配合 ingress gateway 已加 XFF 头)
```

> ⚠️ 反直觉:`when: key=..., values=["*"]` = "任何值都匹配" ≠ "存在性断言"
> 想表达"必须存在"用空 `rules: [{}]`(匹配任何)+ 默认 deny all 兜底,详见同仓库 `authorizationPolicy-capabilities-and-use-cases.md` §6.1。

### 5.4 SNI 限制(egress 场景)

```yaml
# 防止"假装访问 saas1 实际访问 saas2"
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: egress-allow-saas1-only
  namespace: team-a-edge
spec:
  targetRefs:
    - kind: Gateway           # 绑 egressgateway
      group: gateway.networking.k8s.io
      name: egress
  action: ALLOW
  rules:
    - to:
        - operation:
            hosts: ["api.saas1.com"]
            ports: ["443"]
      when:
        - key: connection.sni
          values: ["api.saas1.com"]
```

---

## 6. 跨 namespace 隔离(场景 3)

> Lex 团队多租户场景:**team-a 内部的服务只允许 team-a 内部调用**。

### 6.1 ns 级 baseline(最简)

```yaml
# team-a 命名空间 baseline
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: team-a-internal-only
  namespace: team-a-runtime
spec:
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a-runtime"]    # team-a 内部可调
    - from:
        - source:
            principals: ["cluster.local/ns/team-shared/sa/api-aggregator"]
            # 显式允许 team-shared 命名空间的特定 SA
```

### 6.2 配合 waypoint 收口(更精细)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: team-a-waypoint-only
  namespace: team-a-runtime
spec:
  targetRefs:                          # 绑 waypoint
    - kind: Gateway
      group: gateway.networking.k8s.io
      name: waypoint
  action: ALLOW
  rules:
    - from:
        - source:
            namespaces: ["team-a-runtime"]
```

---

## 7. JWT / OIDC 强制(场景 4)

> 强制所有外部请求带 JWT,按 claim 路由。

### Step 1:RequestAuthentication 验证真伪

```yaml
apiVersion: security.istio.io/v1
kind: RequestAuthentication
metadata:
  name: api-jwt-verify
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-public
  jwtRules:
    - issuer: "https://auth.example.com"
      jwksUri: "https://auth.example.com/.well-known/jwks.json"
      audiences: ["api-public"]
      forwardOriginalToken: true
```

### Step 2:AuthorizationPolicy 强制有 JWT

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-require-jwt
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-public
  action: ALLOW
  rules:
    - from:
        - source:
            requestPrincipals: ["*"]    # 任意 issuer 都行(只要 RequestAuthentication 验证过)
```

### Step 3:基于 claim 路由(team / role)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: api-only-team-platform
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-public
  action: ALLOW
  rules:
    - from:
        - source:
            requestPrincipals: ["https://auth.example.com/*"]
      when:
        - key: request.auth.claims[team]
          values: ["platform"]
        - key: request.auth.claims[role]
          values: ["admin", "editor"]
```

---

## 8. 健康检查豁免(场景 5)

```yaml
# 让 kubelet 探针绕过 AuthZ
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-node-probes
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-public
  action: ALLOW
  rules:
    - to:
        - operation:
            paths: ["/healthz", "/readyz"]
            ports: ["15020"]    # ambient 下,ztunnel 节点代理健康检查端口
      when:
        - key: source.ip
          values: ["10.0.0.0/8"]   # kubelet CIDR,按集群实际调整
```

> 注意:sidecar 模式下是 `15020`(envoy admin port);ambient 下 `15020` 是 ztunnel 在节点上的 health 端口。

---

## 9. 黑名单 / 临时封禁(场景 6)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: block-bad-ip
  namespace: team-a-runtime
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-public
  action: DENY
  rules:
    - from:
        - source:
            ipBlocks: ["203.0.113.66"]    # 直连 IP
            remoteIpBlocks: ["198.51.100.0/24"]   # 真实客户端 IP(从 XFF 取)
```

DENY 优先于 ALLOW = 加一条 DENY 就能在不动白名单的情况下"打补丁"。

---

## 10. 演练模式 / dry-run(场景 7)

> 上线新策略前,先用 dry-run 看哪些请求会被影响:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: dry-run-check
  namespace: team-a-runtime
  annotations:
    "istio.io/dry-run": "true"     # ← 不真生效
spec:
  targetRefs:
    - kind: Service
      group: ""
      name: api-public
  action: DENY
  rules:
    - to:
        - operation:
            paths: ["/legacy/*"]
```

查看命中:
```bash
istioctl experimental authz check <pod-name> -n team-a-runtime
```

---

## 11. ambient 下 waypoint 的特殊角色

waypoint 是 L7 策略**唯一执行点**,所以:

| 想做的事 | 选哪里 |
|---|---|
| 限制"谁调我" | `targetRefs: [Service <api-x>]` (waypoint 拦截 Service 入口流量) |
| 限制"调我做什么" | 同上 |
| 限制"对 egress 调外部" | `targetRefs: [Gateway egress]` |
| 限制"对 ingress 的入口流量" | `targetRefs: [Gateway ingress]` |

**waypoint 本身的限制**(绑 waypoint Gateway):
- waypoint 与业务 pod 之间的流量**不受**绑 waypoint 的策略影响
- 业务 pod 互调(同 ns 内)由 **ztunnel 处理 L4**,L7 才会经 waypoint

---

## 12. ambient + 现有 sidecar 混用的边界

| 场景 | 行为 |
|---|---|
| team-a ns = ambient,team-b ns = sidecar | team-a → team-b:走 ztunnel → team-b 的 envoy,需 team-b 配 mTLS(可能需 PERMISSIVE) |
| 同 ns 内 mixed(思必选) | ❌ 同 ns 不能既有 ambient 又有 sidecar,label 冲突 |
| 跨集群 ambient | [Istio multicluster ambient](https://istio.io/latest/docs/ambient/multicluster/) 仍 preview,1.30 部分支持 |

---

## 13. 本场景推荐写法速查

| 想做 | 写法 |
|---|---|
| 限制谁能调上传接口 | `targetRefs: [Service]` + `from.source.serviceAccounts` |
| 限制上传 MIME | `when: request.headers[content-type]` |
| 限制上传大小 | **EnvoyFilter**(非 AuthZ) |
| 限制上传速率 | **EnvoyFilter + local_ratelimit**(非 AuthZ) |
| 强制带 X-API-Key header | `when: request.headers[x-api-key]` |
| 多租户 header 路由 | `when: request.headers[x-tenant-id]` |
| 阻止 header 注入 | `action: DENY` + `when: request.headers[X]` |
| 跨 ns 隔离 | namespace-wide AuthorizationPolicy(无 selector,放 namespace 上) |
| 强制 JWT | `RequestAuthentication` + `AuthorizationPolicy` 组合 |
| 健康检查豁免 | `when: source.ip` 限定 kubelet CIDR |
| 临时封禁 | `action: DENY` + `ipBlocks` |

---

## 14. References

- [Istio AuthorizationPolicy reference](https://istio.io/latest/docs/reference/config/security/authorization-policy/) — 字段权威
- [Istio AuthorizationPolicy Conditions](https://istio.io/latest/docs/reference/config/security/conditions/) — `when` 全部 key
- [Istio PeerAuthentication reference](https://istio.io/latest/docs/reference/config/security/peer_authentication/) — ambient 限制
- [Istio Ambient Security](https://istio.io/latest/docs/ambient/security/) — ambient 下 PA 差异
- [Istio Ambient 资源](https://istio.io/latest/docs/ambient/) — 全部 ambient 文档入口
- 同仓库 `~/git/knowledge/gcp/asm/authorizationPolicy-capabilities-and-use-cases.md` — 完整字段表(本篇精简版)
- 同仓库 `~/git/knowledge/gcp/asm/peerAuthentication-capabilities-and-use-cases.md` — PA 完整字段表(本篇精简版)