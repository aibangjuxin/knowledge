# DestinationRule TLS: `insecureSkipVerify` 与 SIMPLE 模式字段详解

> 适用环境：GKE + Cloud Service Mesh / ASM，Istio DestinationRule 出站 TLS 配置
> 前置知识：已理解 DestinationRule 基本概念（见 `DestinationRule.md`），理解 nginx reverse proxy TLS 配置

---

## 1. 先厘清两个概念：TLS 终止（Termination） vs TLS 发起（Origination）

在讨论 `insecureSkipVerify` 之前，必须先理解 Istio Gateway 数据面上两个方向的 TLS 行为：

```
客户端请求流经 Gateway 时：

  [Ingress/Gateway]  ←  TLS 终止 (Termination)
       ↓
  Envoy 内部路由
       ↓
  [Upstream/后端Pod]  ←  TLS 发起 (Origination)
```

| 方向 | 谁终止/发起 | 配置来源 |
|------|------------|---------|
| **入站 TLS 终止**（Terminate） | Gateway Envoy 接收客户端 HTTPS | `Gateway` CR 的 `servers[].tls` |
| **出站 TLS 发起**（Origination） | 调用方 Envoy 连接后端 | `DestinationRule` CR 的 `trafficPolicy.tls` |

`insecureSkipVerify` 属于 **出站 TLS 发起** 配置——它控制"Gateway Envoy 作为 TLS 客户端，连接后端 Pod 时，是否验证后端的证书"。

---

## 2. SIMPLE 模式完整字段

`DestinationRule.trafficPolicy.tls.mode: SIMPLE` 时，TLS 字段完整列表：

```yaml
trafficPolicy:
  tls:
    mode: SIMPLE                    # 必选：单向 HTTPS，客户端验证服务端
    sni: app.service.namespace.svc  # 可选，推荐填写
    caCertificates: /path/to/ca.pem # 可选，默认使用系统 CA 池
    insecureSkipVerify: false       # 可选，默认为 false（严格校验）
```

### 2.1 `sni` — Server Name Indication

**作用：** TLS 握手中 ClientHello 阶段发送的主机名。

```yaml
tls:
  mode: SIMPLE
  sni: team-a-service.team-a-runtime.svc.cluster.local
```

**为什么需要：**
- Pod 可能托管多个 HTTPS 服务（基于 SNI 区分）
- Pod 证书的 CN/SAN 通常匹配 Service FQDN
- 不填 `sni` 时，Envoy 会自动用 `host` 字段的值作为 SNI（如果 host 是 FQDN）

**注意事项：**
- `sni` 不做证书校验，只在 TLS 握手中发送
- 证书校验由 `caCertificates` 或系统 CA 池完成

### 2.2 `caCertificates` — 服务端 CA 证书

**作用：** 指定一个 CA 证书文件路径，Envoy 用它验证后端服务端的证书链。

```yaml
tls:
  mode: SIMPLE
  sni: team-a-service.team-a-runtime.svc.cluster.local
  caCertificates: /etc/pki/ca-bundle/ca.crt   # Pod 内挂载的内部 CA
```

**行为：**
- `caCertificates` 存在 → Envoy 用这个 CA 验证后端证书
- `caCertificates` 不存在 → Envoy 用容器内置的系统 CA 池验证
- 验证内容：证书链完整性、证书有效期、CN/SAN 匹配 `sni` 值

**何时需要显式指定 `caCertificates`：**
- Pod 证书由私有 CA 签发（不在系统 CA 池中）
- Pod 证书是自签名证书
- 内网使用 `*.uk.aibang.local` 这类私有域名证书

**如何让 Envoy 容器内能访问 CA 文件：** 必须通过 Kubernetes Secret + VolumeMount 把 CA 注入到 ingressgateway Pod 内：

```yaml
# Step 1: 创建包含内部 CA 的 Secret
apiVersion: v1
kind: Secret
metadata:
  name: internal-root-ca
  namespace: istio-ingressgateway-int
type: Opaque
data:
  ca.crt: <base64 encoded internal CA cert>

---
# Step 2: 在 Gateway Deployment 的 sidecar 容器中 volumeMount
# （ASM/ingressgateway 通常由 ASM 自动管理，需要通过 ASM 的办法注入）
# 或者在同 namespace 创建一个 ConfigMap 并挂载到 /etc/pki
```

**平台化成本警告：** ASM/ingressgateway Pod 由 Google/平台托管，直接修改 Pod spec 挂载自定义 CA 比较困难。常见的变通方案：
- 用 ASM 的 `Gateway` 证书管理机制，但 ASM 不支持挂载自定义 CA 给 Envoy 做 upstream 验证
- 在同 namespace 用一个 init-container 或 sidecar 注入 CA 文件
- **临时方案**：使用 `insecureSkipVerify: true`（见下）

### 2.3 `insecureSkipVerify` — 跳过证书校验

**作用：** 完全禁用后端证书校验——不验证证书链、不验证 CN/SAN、不验证有效期。

```yaml
tls:
  mode: SIMPLE
  sni: team-a-service.team-a-runtime.svc.cluster.local
  insecureSkipVerify: true    # 禁用所有服务端证书校验
```

**安全影响：**

```
insecureSkipVerify: false (默认)
  → 加密流量 + 认证服务端身份（信任链验证）
  → 中间人攻击 (MITM) 不可能

insecureSkipVerify: true
  → 加密流量（数据仍然被加密）
  → 但不认证服务端身份
  → 同一网络中的攻击者可以伪造后端证书实施 MITM
```

**什么时候可以用（勉强接受）：**
- 纯内网环境，且网络层有其他强隔离（VPC Firewall、NetworkPolicy）
- 调试时快速验证连通性
- 临时过渡，等待 CA 证书分发方案落地
- **绝对不要**在跨网络/公网场景使用

**你当前文档（`asm-no-mtls-sidecar.md`）中的原话：**
> "如果临时无法分发 CA，只能使用不校验证书的后端 HTTPS，这会降级为'加密但不认证后端身份'，生产上不建议长期使用。"

### 2.4 `subjectAltNames` — 期望的服务端身份

**作用：** 指定后端证书的 SAN（Subject Alternative Name），校验时后端证书必须包含列表中至少一个身份。

```yaml
tls:
  mode: SIMPLE
  sni: team-a-service.team-a-runtime.svc.cluster.local
  caCertificates: /etc/pki/ca-bundle/internal-ca.crt
  subjectAltNames:
    - team-a-service.team-a-runtime.svc.cluster.local
    - team-a-service.team-a-runtime
```

**何时有用：**
- Pod 有多个 DNS 名字（FQDN + 简短名字）
- 泛域名证书（`*.uk.aibang.local`）SAN 中有通配符
- 想限制后端只能使用特定身份集合的证书

---

## 3. 四个 TLS 模式的完整对比

```
Istio DestinationRule TLS 模式：

  ISTIO_MUTUAL  ── mesh mTLS，双方互换证书，Istio 自动签发
  SIMPLE        ── 单向 HTTPS，客户端验证服务端（我们讨论的重点）
  MUTUAL        ── 双向 HTTPS，客户端 + 服务端都需证书
  DISABLE       ── 明文，无任何加密
```

### 3.1 SIMPLE 模式完整示意

```
Gateway Envoy (TLS Client)                          Pod (TLS Server)
       │                                                   │
       │  1. TCP 握手                                       │
       │ ────────────────────────────────────────────────→ │
       │                                                   │
       │  2. ClientHello (SNI: team-a-service...)          │
       │ ────────────────────────────────────────────────→ │
       │                                                   │
       │  3. ServerHello + 证书                            │
       │ ←──────────────────────────────────────────────── │
       │                                                   │
       │  4. 证书链校验（用 caCertificates 或系统 CA）      │
       │    - 证书是否由可信 CA 签发？                      │
       │    - 证书 CN/SAN 是否匹配 sni？                    │
       │    - 证书是否在有效期内？                          │
       │                                                   │
       │  5. (可选) ClientKeyExchange + Finished            │
       │ ────────────────────────────────────────────────→ │
       │                                                   │
       │  6. Application Data (加密)                        │
       │ ════════════════════════════════════════════════ │
```

### 3.2 SIMPLE vs MUTUAL vs ISTIO_MUTUAL 字段差异

| 字段 | SIMPLE | MUTUAL | ISTIO_MUTUAL |
|------|--------|--------|--------------|
| `mode` | `SIMPLE` | `MUTUAL` | `ISTIO_MUTUAL` |
| `sni` | ✅ 可选 | ✅ 必选 | ❌ 不需要 |
| `caCertificates` | ✅ 可选 | ✅ 必选 | ❌ 不需要 |
| `insecureSkipVerify` | ✅ 可选 | ❌ 不适用 | ❌ 不适用 |
| `credentialName` | ❌ 不需要 | ✅ 必选（client cert） | ❌ 不需要 |
| `subjectAltNames` | ✅ 可选 | ✅ 可选 | ❌ 不需要 |
| 客户端证书 | ❌ 不发送 | ✅ 发送 | ✅ 自动 SPIFFE |

---

## 4. vs Nginx `proxy_ssl_verify` 对比

### 4.1 Nginx upstream TLS 配置三件套

```nginx
upstream backend {
    server 10.0.0.50:8443;
}

server {
    location / {
        proxy_pass https://backend;

        # ① 启用/禁用服务端证书校验（默认 on）
        proxy_ssl_verify on;          # on = 验证，off = 不验证

        # ② 指定信任的 CA 证书（验证服务端证书链）
        proxy_ssl_trusted_certificate /etc/nginx/certs/internal-ca.crt;

        # ③ 证书链验证深度（默认 3）
        proxy_ssl_verify_depth 2;

        # ④ SNI 发送什么主机名（默认 $host）
        proxy_ssl_server_name on;     # on = 用 upstream 名字做 SNI
        proxy_ssl_name $host;         # 可自定义 SNI 值

        # ⑤ TLS 版本和加密套件（可选）
        proxy_ssl_protocols TLSv1.2 TLSv1.3;
    }
}
```

### 4.2 字段对应关系

```
Istio DestinationRule (SIMPLE)          Nginx (proxy_pass HTTPS)
────────────────────────────────────    ─────────────────────────────────
mode: SIMPLE                            proxy_ssl_verify on;（隐式）
sni: app.svc.ns.svc.cluster.local       proxy_ssl_server_name on; + proxy_ssl_name
caCertificates: /path/to/ca.crt         proxy_ssl_trusted_certificate
insecureSkipVerify: true                proxy_ssl_verify off;
sni（自动）                              upstream 名或 proxy_ssl_name
-                                        proxy_ssl_verify_depth (无直接对应)
```

### 4.3 关键设计差异

| 维度 | Istio DestinationRule | Nginx proxy_ssl |
|------|----------------------|-----------------|
| **配置位置** | Kubernetes CRD（声明式） | nginx.conf（配置文件） |
| **CA 分发** | 需要 VolumeMount 到 IngressGateway Pod | 直接放在 nginx Pod 内 |
| **SNI 默认值** | 必须显式指定 `sni` | 默认用 `$host` 或 upstream 名 |
| **验证深度** | 不可配置（固定合理值） | `proxy_ssl_verify_depth` 可调 |
| **insecureSkipVerify** | `insecureSkipVerify: true` | `proxy_ssl_verify off` |
| **运行时生效** | CRD apply 后 Pilot 分发 | reload nginx |

**最重要的区别：**
- Nginx 作为反向代理时，CA 证书可以**直接放在 nginx Pod 内**，访问文件系统即可。
- Istio Gateway（ingressgateway）是**平台托管的 Pod**，CA 文件需要通过 Kubernetes Secret + 注入机制注入，有平台化成本。
- 这就是为什么在 Istio 场景下，`insecureSkipVerify: true` 往往是"快速起步"的首选，而长期方案需要解决 CA 注入问题。

---

## 5. 你的完整流量链分析：nginx → k8s Gateway → Pod

```
Client
  │
  │ ① HTTPS (TLS 1.2/1.3)
  │  Client Hello → SNI: api.team1.appdev.aibang
  │
  ▼
nginx (运行在独立机器或 Ingress Node)
  │
  │  ② nginx 终止 TLS
  │  用证书: *.team1.appdev.aibang  （Team 级别证书，nginx 本地持有）
  │
  │  ③ nginx 发起新 HTTPS 到 k8s Gateway
  │  证书: *.team1.appdev.aibang  （同一套证书，或者 nginx 自己的通配符）
  │
  ▼
k8s Gateway (ASM Managed Gateway / ingressgateway)
  │
  │  ④ Gateway 终止 TLS（Terminate）
  │  用证书: *.team1.appdev.aibang  （Gateway TLS Secret，Kubernetes 管理）
  │
  │  ⑤ Gateway Envoy 发起 TLS 到后端 Pod（Origination）
  │  DestinationRule SIMPLE 模式驱动这个行为
  │  后端 Pod 证书: *.uk.aibang.local  （Pod 自有证书，私有 CA 或自签名）
  │
  ▼
k8s Pod (team-a-runtime namespace)
  │
  │  ⑥ Pod 内 app 容器终止 HTTPS 8443
  │  证书: *.uk.aibang.local
  │
  ▼
App Container (localhost:8443)
```

### 5.1 每段的证书校验分析

| 段 | 发起方 | 终止方 | 证书 | 是否校验 | 如何校验 |
|----|--------|--------|------|---------|---------|
| ①  Client → nginx | 客户端 | nginx | `*.team1.appdev.aibang` | ✅ 客户端浏览器校验 | 系统 CA 池或导入的根证书 |
| ③  nginx → Gateway | nginx | Gateway | `*.team1.appdev.aibang` | ⚠️ 取决于 nginx 配置 | nginx 信任的 CA |
| ⑤  Gateway → Pod | Gateway Envoy | Pod app | `*.uk.aibang.local` | **取决于 DR 配置** | DR 的 `caCertificates` 或 `insecureSkipVerify` |

**段 ⑤ 是我们讨论的重点。**

### 5.2 段 ⑤ 的三种配置场景

#### 场景 A（推荐）：使用私有 CA + caCertificates

```
Gateway Envoy 侧有内部 CA (internal-root-ca.crt)
  → caCertificates: /etc/pki/internal-root-ca.crt
  → Envoy 验证 Pod 证书链是否由 internal CA 签发
  → 证书 CN/SAN 匹配 *.uk.aibang.local
  → 完整加密 + 完整身份认证
```

**配置示意：**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team-a-service-tls
  namespace: team-a-runtime
spec:
  host: team-a-service.team-a-runtime.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: team-a-service.team-a-runtime.svc.cluster.local
      caCertificates: /etc/pki/ca-bundle/internal-root-ca.crt   # 私有 CA
      subjectAltNames:
        - team-a-service.team-a-runtime.svc.cluster.local
        - team-a-service
```

#### 场景 B（不推荐）：insecureSkipVerify: true

```
Gateway Envoy 完全不验证 Pod 证书
  → 加密流量（仍然防止网络窃听）
  → 但无法防止同一网络中攻击者伪造 Pod 证书
  → 只能在内网 + 网络层强隔离下临时使用
```

**配置示意：**

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team-a-service-tls
  namespace: team-a-runtime
spec:
  host: team-a-service.team-a-runtime.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: team-a-service.team-a-runtime.svc.cluster.local
      insecureSkipVerify: true    # ⚠️ 禁用证书校验，仅加密
```

#### 场景 C（不推荐）：自签名证书 + 无 CA

```
Gateway Envoy 使用系统 CA 池
  → Pod 证书 *.uk.aibang.local 是自签的或私有 CA
  → 系统 CA 池中没有该 CA
  → 证书校验直接失败（连接报错）
```

**结果：** TLS 握手失败，Gateway 无法连接 Pod。

### 5.3 你的域名层级与 CA 策略

```
aibang 内部域名体系：

  *.uk.aibang.local        → Pod 自有证书（私有 CA 签发）
  *.team1.appdev.aibang    → Gateway TLS 终止证书（平台 CA 或 Let's Encrypt）
  *.team2.appdev.aibang    → 同上，按团队区分
```

**关键问题：Pod 的 `*.uk.aibang.local` 证书由谁签发？**

| Pod 证书签发方 | CA 在系统 CA 池？ | 是否需要 caCertificates |
|---------------|------------------|----------------------|
| 公有 CA（DigiCert/Let's Encrypt） | ✅ 是 | 不需要 |
| 私有 CA（如 internal PKI） | ❌ 否 | **需要** + `caCertificates` |
| 自签名 | ❌ 否 | **需要** `insecureSkipVerify: true` 或注入 CA |

---

## 6. 何时需要往 Gateway 加 CA（核心结论）

### 6.1 判断逻辑

```
你需要 CA 证书吗？

  Pod 证书签发者是谁？
  │
  ├─ 公有 CA（Let's Encrypt、DigiCert 等）
  │   └─ ✅ 不需要加 CA，Gateway Envoy 系统 CA 池已包含
  │       → 只需要 sni，caCertificates 可省略
  │
  ├─ 私有 CA（你们内部 PKI）
  │   └─ ❌ 系统 CA 池没有，需要注入 CA
  │       → 需要：caCertificates + VolumeMount Secret
  │
  └─ 自签名（测试/临时）
      ├─ 快速方案：insecureSkipVerify: true（临时）
      └─ 正确方案：把自签名 CA 注入 Gateway Pod
```

### 6.2 在你们的架构中加 CA 的具体位置

```
nginx → k8s Gateway (段 ③)

  这里：
  - nginx 是 TLS 客户端，Gateway 是 TLS 服务端
  - Gateway 用 *.team1.appdev.aibang 证书终止
  - nginx 需要验证这个证书
  - 如果 nginx 信任 Let's Encrypt → 不需要额外 CA
  - 如果 nginx 配置了公司内部根证书 → 那份 CA 需要在 nginx 侧配置

k8s Gateway → Pod (段 ⑤)  ← 最需要关注

  这里：
  - Gateway Envoy 是 TLS 客户端，Pod 是 TLS 服务端
  - Gateway Envoy 需要验证 Pod 的 *.uk.aibang.local 证书
  - 如果 Pod 用公共信任的 CA → 不需要任何额外 CA
  - 如果 Pod 用私有 CA → 需要把该 CA 注入 ingressgateway Pod
```

### 6.3 给 Gateway 注入私有 CA 的两种方式

#### 方式 1：ASM/ingressgateway Namespace ConfigMap（推荐用于平台化）

```bash
# 在 istio-ingressgateway-int namespace 创建包含 CA 的 ConfigMap
kubectl create configmap internal-root-ca \
  --from-file=ca.crt=./internal-root-ca.crt \
  -n istio-ingressgateway-int

# 然后在 Pod spec 中挂载
# （ASM 托管的 Gateway 需要通过 ASM 的机制注入，或者用 GateayClass 扩展）
```

#### 方式 2：通过 DestinationRule 引用（ASM 官方推荐方式）

ASM 支持通过 `MeshConfig` 注入额外的 CA 证书到 ingressgateway：

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: gateway-ca-bundle
  namespace: istio-ingressgateway-int
data:
  internal-ca.crt: |
    -----BEGIN CERTIFICATE-----
    MIIDpzCCAo+gAwIBAgIUA...
    -----END CERTIFICATE-----
```

然后通过 ASM 的 `meshConfig.caCertificates` 挂载：

```bash
# 查看当前 MeshConfig
kubectl get meshconfig mesh-config -n istio-system -o yaml
```

### 6.4 你当前的配置（来自 `asm-no-mtls-sidecar.md`）

```yaml
# DestinationRule（当前生产配置）
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: team-a-service-tls
  namespace: team-a-runtime
spec:
  host: team-a-service.team-a-runtime.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
      sni: team-a-service.team-a-runtime.svc.cluster.local
      # caCertificates: <目前没有配置>
      # insecureSkipVerify: <目前没有配置，默认 false>
```

**这意味着：**
- 如果 `*.uk.aibang.local` 证书是公共 CA 签发 → 当前配置**完全正确**，无需修改
- 如果 `*.uk.aang.local` 是私有 CA 签发 → **证书校验会失败**，需要注入 CA
- 如果 `*.uk.aibang.local` 是自签名测试证书 → 当前配置**会导致连接失败**

---

## 7. 完整的端到端安全建议

### 7.1 你希望"每一条都需要加密"

```
Client → nginx → Gateway → Pod
   ✅       ✅        ✅
   全程 HTTPS，数据全部加密
```

满足这个要求只需要：`mode: SIMPLE`（加密流量），每个 hop 都是 HTTPS。

### 7.2 你还想要"身份认证"

```
Client → nginx → Gateway → Pod
   ✅       ✅        ✅
   + 双向身份认证
```

满足这个要求需要：
- **段 ①**：客户端浏览器验证 `*.team1.appdev.aibang`（公共 CA，天然可信）
- **段 ③**：nginx 验证 Gateway 证书（如果 nginx 信任 Let's Encrypt 或你的平台 CA，无需额外操作）
- **段 ⑤**：
  - 如果 Pod 证书是公共 CA 签发 → 无需额外配置
  - 如果 Pod 证书是私有 CA 签发 → 需要注入 CA + `caCertificates`
  - 如果 Pod 证书是自签名 → `insecureSkipVerify: true`（临时）或注入 CA（永久）

### 7.3 推荐行动项

```
① 确认 Pod 的 *.uk.aibang.local 证书由谁签发

   ├─ 公有 CA（如 Let's Encrypt）→ 什么都不用改，当前配置够用
   │
   ├─ 私有 CA
   │   → 需要把该 CA 证书注入 ingressgateway Pod
   │   → DestinationRule 加 caCertificates 字段
   │
   └─ 自签名测试证书
       → 临时：insecureSkipVerify: true（但要设 Alarm 提醒后续修复）
       → 长期：换成私有 CA 或公共 CA

② 如果是私有 CA，确认你们的 ASM 版本是否支持 meshConfig.caCertificates
   → 查文档：https://cloud.google.com/service-mesh/docs/proxy-plus-ca-bundle

③ 如果私有 CA 注入复杂，可以考虑：
   → Pod 改用公共 CA 签发的证书（如 cert-manager + Let's Encrypt）
   → 这样 DestinationRule 就不需要任何 CA 配置了
```

---

## 8. 快速参考表

### DestinationRule SIMPLE TLS 模式

```yaml
# 最小可用配置（公共 CA 证书）
tls:
  mode: SIMPLE
  sni: app.svc.ns.svc.cluster.local

# 完整配置（私有 CA + SAN 校验）
tls:
  mode: SIMPLE
  sni: app.svc.ns.svc.cluster.local
  caCertificates: /etc/pki/ca-bundle/internal-root-ca.crt
  subjectAltNames:
    - app.svc.ns.svc.cluster.local
    - app

# ⚠️ 临时调试配置（跳过证书校验）
tls:
  mode: SIMPLE
  sni: app.svc.ns.svc.cluster.local
  insecureSkipVerify: true
```

### Nginx 对应配置

```nginx
# 公共 CA 验证（默认）
proxy_ssl_verify on;
proxy_ssl_trusted_certificate /etc/ssl/certs/ca-bundle.crt;  # 系统默认
proxy_ssl_server_name on;

# 私有 CA 验证
proxy_ssl_verify on;
proxy_ssl_trusted_certificate /etc/nginx/certs/internal-ca.crt;  # 私有 CA
proxy_ssl_server_name on;

# 不验证（对应 insecureSkipVerify: true）
proxy_ssl_verify off;
```

### 何时需要 CA 注入

| 后端 Pod 证书类型 | Gateway Envoy 行为 | 需要什么 |
|------------------|------------------|---------|
| 公共 CA（Let's Encrypt） | 系统 CA 池验证通过 | 无额外操作 |
| 私有 CA | 系统 CA 池**没有**，校验失败 | 注入 CA + `caCertificates` |
| 自签名 | 系统 CA 池**没有**，校验失败 | `insecureSkipVerify: true` 或注入 CA |

---

## 9. 参考字段速查

| DestinationRule TLS 字段 | 类型 | 默认值 | 说明 |
|-------------------------|------|--------|------|
| `mode` | enum | 必填 | `SIMPLE`/`MUTUAL`/`ISTIO_MUTUAL`/`DISABLE` |
| `sni` | string | 自动用 host | TLS ClientHello 中的主机名 |
| `caCertificates` | string | 系统 CA 池 | 验证服务端证书的 CA 证书文件路径 |
| `insecureSkipVerify` | bool | `false` | `true` = 完全跳过证书校验 |
| `subjectAltNames[]` | string[] | 空 | 期望的后端证书 SAN 列表 |
| `credentialName` | string | — | MUTUAL 模式引用 client cert Secret |

---

*文档版本：v1.0 — 2026-05-21*
*配套文档：`DestinationRule.md`（基础概念）、`asm-no-mtls-sidecar.md`（no-sidecar 方案）*
