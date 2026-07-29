https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/


Both Solo’s standard and solo distributions of Istio come in the following optional varieties.

- FIPS: An image that is tagged with fips complies with NIST FIPS, for use cases that require federal information processing capabilities. For more information, see About Solo FIPS distribution of Istio. Examples: 1.30.2-fips, 1.30.2-solo-fips
- Distroless: An image that is tagged with distroless is a slimmed down distribution with the minimum set of binary dependencies to run the image, for enhanced performance and security. Note that if your app relies on package management, shell, or other operating system tools such as pip, apt, ls, grep, or bash, you must find another way to install these dependencies. Examples: 1.30.2-distroless, 1.30.2-solo-distroless
An image might be tagged to meet multiple use cases, such as 1.30.2-solo-fips-distroless.


https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/

maybe todo:
- ns ==> created istio-system
- CNI + ztunnel Ambient 


确保每一条的资源数量都要有高可用 eg:
Deployment number

```
kind: 目的地规则 
DestinationRule仅受支持 gateway类名：istio

因为我们将开始使用环境网格 代理（入口）将被替换为 我们必须开始使用Solo agw

种类：后端TLSPolicy 如果我们想继续，请从Gateway APl使用TLS公开租户工作负载

- 首先，我们不应该永远使用“insecureSkipVerify：true”作为此项 是不安全的

- 第二：我们正在使用一些虚拟用户证书，例如“CN=*.dev-sprintboot-rt.aliyun.cloud.us.local”，这也不是真的很安全그래서这种情况下，这会阻碍我们 从使用网格 开始后端TLSPolicy需要适当的安全的TLS设置才能正常工作。

可能的解决方案：

- 为什么我们甚至需要暴露租户使用TLS的应用程序？这看起来像 old env's some legacy
- 在网格中，mTLS由ztunnel保证（环境模式）或侧车（侧车模式），因此在mTLS中执行TLS是 不必要的，可能已经性能影响，解决方案将是让租户暴露自己 纯HTTP，让mesh来处理工作负载之间的mTLS
- 使用一些证书管理器来创建具有正确FQDN的证书需求，但这似乎是多余的如果加密已经由mesh完成 并且不会提供任何额外的价值
```

kind: DestinationRule → DestinationRule is supported only by
gatewayClassName: istio，

Since we willl start using ambient mesh
and proxy （ingress） will be replaced by
Solo agw we will have to start using

kind: BackendTLSPolicy
from Gateway APl if we want to continue
expose tenants workloads with TLS


- first of all, we shouldn't permanently
use "insecureSkipVerify: true" as this
is insecure
- second：， we are using some dummy
cert for users f.e "CN=*.dev-sprintboot-rt.aliyun.cloud.us.local"， this is also not really secure
So in this situation this will block us
from using mesh since
BackendTLSPolicy requires proper
secure TLS setup in order to function.
Possible solutions：
- why do we even need to expose tenant
applications with TLS? this seems like
some legacy from old environment？
in Mesh mTLS is ensured by ztunnel
（ambient mode） or sidecars （sidecar
mode） so doing TLS inside mTLS is
unnecessary and might have
performance impact, solution would be
let tenants expose themselves with
plain HTTP and let mesh take care of
mTLS between workloads

- use some cert manger to create
certificates with proper FQDN on
demand, but still, this seems redundant
if encryption is already done by mesh
and would not provide any additional
value

---

## 分析结论：切换到 Solo agentgateway + Ambient Mesh 能否解决这个问题

> **结论：可以解决，但有一个关键前提。**
>
> 推荐目标不是“把 `DestinationRule` 一比一翻译成 `BackendTLSPolicy`”，而是：
>
> **让租户应用只提供 HTTP，由 Ambient 的 ztunnel/HBONE 在传输层提供 workload-to-workload mTLS；Solo agentgateway 必须启用 Istio 集成，并以 Istio workload identity 通过 HBONE 访问 Ambient workload。**
>
> 在这个目标模型中，现有的 `insecureSkipVerify: true`、dummy backend certificate、租户证书挂载，以及用于 backend TLS 的 `DestinationRule` 都可以删除。`BackendTLSPolicy` 只保留给那些**确实要求应用层 HTTPS** 的例外后端。

### 1. 先纠正两个关键逻辑

#### 1.1 `DestinationRule` 不是由 `gatewayClassName` 字段直接决定是否支持

严格说法不是“`DestinationRule` 只支持 `gatewayClassName: istio`”。`DestinationRule` 是 Istio API，由 Istio control plane/data plane 解释；`gatewayClassName` 则决定哪个 Gateway controller 实现 `Gateway`。当入口改为 `gatewayClassName: agentgateway` 后，不能再假设 agentgateway 会消费 Istio `DestinationRule` 来配置自己的 backend TLS。因此迁移时应把 agentgateway 的 backend 行为表达为 Gateway API / agentgateway 支持的 Policy，或者直接依赖 Ambient HBONE/mTLS。

#### 1.2 换成 agentgateway 不等于必须使用 BackendTLSPolicy

下面两类加密不是同一层：

| 加密机制 | 保护的链路 | 谁持有证书 | 是否要求 backend 应用监听 HTTPS |
|---|---|---|---|
| `BackendTLSPolicy` | agentgateway → backend 的**应用层 TLS origination** | backend 服务器证书 + CA trust；可选 gateway client cert | **是** |
| Ambient HBONE/mTLS | mesh source identity → destination workload identity 的**网格传输层 mTLS** | Istio CA 自动签发 SPIFFE workload certificate | **否**，应用可以只监听 HTTP |

Solo agentgateway 官方对 `BackendTLSPolicy` 的定义非常明确：

> “Originate a one-way TLS connection from the Gateway to a backend.”
>
> “When you configure a TLS listener on your Gateway, the Gateway typically terminates incoming TLS traffic and forwards the unencrypted traffic to the backend service.”
>
> 来源：[agentgateway — BackendTLS](https://agentgateway.dev/docs/kubernetes/latest/security/backendtls/)

**关键判断**：`BackendTLSPolicy` 是“后端本身要求 HTTPS”时使用的 TLS origination API，不是 Ambient Mesh 加密的必选资源。若 backend 改为 HTTP，HTTPRoute 直接引用 HTTP Service 即可；链路安全由 HBONE/mTLS 负责。

### 2. 为什么这个方案能够解决当前两个安全问题

#### 2.1 删除 `insecureSkipVerify: true`

现状中的 `insecureSkipVerify: true` 表示 gateway 虽然建立了 TLS，但没有正确验证 backend 身份。这只提供加密，不提供可信身份认证，不能作为永久生产配置。

切换后有两条安全路径：

1. **推荐路径：HTTP backend + Ambient mTLS**
   - backend 不再使用应用证书；
   - agentgateway 使用 Istio workload identity；
   - agentgateway 通过 HBONE 与目标 ztunnel 建立 mTLS；
   - ztunnel 根据 SPIFFE identity 执行 `PeerAuthentication` / `AuthorizationPolicy`；
   - 不存在 `skip verify` 这个配置点。

2. **例外路径：HTTPS backend + BackendTLSPolicy**
   - 必须配置可信 CA；
   - 必须校验 DNS SAN 或 URI SAN；
   - `BackendTLSPolicy.status.ancestors[].conditions` 必须为 `Accepted=True`、`ResolvedRefs=True`；
   - 禁止使用 `insecureSkipVerify`。

agentgateway 的当前实现已有真实的 `BackendTLSPolicy` 状态与证书校验测试：无效 CA 会得到 `NoValidCACertificate` / `InvalidCACertificateRef`，并使 Policy 不被接受。源码证据：

- [`backendtlspolicy.yaml`](https://github.com/agentgateway/agentgateway/blob/main/controller/pkg/agentgateway/translator/testdata/backends/backendtlspolicy.yaml)
- [`backendtls_test.go`](https://github.com/agentgateway/agentgateway/blob/main/controller/test/e2e/backendtls_test.go)

#### 2.2 删除 dummy certificate

`CN=*.dev-sprintboot-rt.aliyun.cloud.us.local` 这种 dummy certificate 的问题不只是“证书看起来不正式”，而是：

- CN/SAN 可能不匹配实际 Service identity；
- CA 可能不受信；
- 生命周期和轮换通常没有自动化；
- 多租户共享 wildcard private key 扩大泄漏半径；
- 为了让它工作，最终往往又回到 `insecureSkipVerify`。

采用 Ambient 后，租户 backend 应用不再需要持有这张证书。Istio 为 workload 自动签发 SPIFFE identity，HBONE tunnel 使用 mTLS 加密和认证。Istio 官方说明：

> “Traffic to and from pods in the mesh will be fully encrypted with mTLS by default.”
>
> “Every pod in the mesh has the ability to enforce mesh policy and securely encrypt traffic, even though the user application running in the pod has no awareness of either.”
>
> 来源：[Istio — Ztunnel traffic redirection](https://istio.io/latest/docs/ambient/architecture/traffic-redirection/)

HBONE 本身由 HTTP/2、HTTP CONNECT 和 mTLS 组成，并在同一条加密 tunnel 上复用应用连接：

> “HBONE ... is a mechanism to transparently multiplex TCP streams ... over a single, mTLS encrypted network connection.”
>
> 来源：[Istio — HBONE](https://istio.io/latest/docs/ambient/architecture/hbone/)

**关键判断**：应用收到的仍可以是 HTTP，但在 Pod/节点之间传输时不是裸明文；HTTP payload 被封装在已认证、已加密的 HBONE tunnel 中。dummy backend certificate 因此可以从租户应用的 deployment 和 Secret 管理流程中彻底移除。

### 3. 最重要的前提：agentgateway 必须真正加入 Istio/Ambient 安全链路

不能把下面这条链路想当然：

```text
agentgateway（非 mesh source） → HTTP → Ambient backend + PeerAuthentication STRICT
```

如果 agentgateway 只是普通的非 mesh Pod，目标 namespace 又启用了 `PeerAuthentication STRICT`，目标 ztunnel 会把它视为 mesh 外明文流量并拒绝。Istio 官方明确说明：

> “setting a PeerAuthentication policy with mTLS mode set to STRICT, in a namespace with ambient mode enabled, will cause traffic from outside the mesh to be denied.”
>
> 来源：[Istio — Add workloads to the mesh / Pods outside the mesh](https://istio.io/latest/docs/ambient/usage/add-workloads/)

Solo agentgateway 的代码和部署测试已经提供了所需集成能力，而不是只支持普通 HTTP：

- `AgentgatewayParameters.spec.istio` 支持 `caAddress`、`trustDomain`、`clusterId`、`network`；
- 生成的 agentgateway Deployment 会挂载 Istio CA root 和 `istio-token`，并设置 `CA_ADDRESS`、`TRUST_DOMAIN` 等环境变量；
- agentgateway 源码包含 HBONE client/tunnel 实现；
- Gateway translator 支持 `protocol: HBONE` / port `15008`；
- agentgateway 的 BackendTLSPolicy translator 和 e2e test 已覆盖 CA、hostname/SAN 与 Policy status。

源码依据：

- [`agentgateway-istio.yaml`](https://github.com/agentgateway/agentgateway/blob/main/controller/test/deployer/testdata/agentgateway-istio.yaml)
- [`agentgateway-istio-out.yaml`](https://github.com/agentgateway/agentgateway/blob/main/controller/test/deployer/testdata/agentgateway-istio-out.yaml)
- [`hbone_tunnel.rs`](https://github.com/agentgateway/agentgateway/blob/main/crates/agentgateway/src/client/hbone_tunnel.rs)
- [`hbone-listener.yaml`](https://github.com/agentgateway/agentgateway/blob/main/controller/pkg/agentgateway/translator/testdata/gateways/hbone-listener.yaml)

**因此，POC 的验收条件不能只是“HTTPRoute 返回 200”**，还必须证明 agentgateway 发往 Ambient workload 的连接确实使用 HBONE/mTLS，并且 `PeerAuthentication STRICT` 下仍能成功。

### 4. 推荐目标架构

```text
External client
  │ HTTPS（公网/客户端证书体系）
  ▼
Solo agentgateway
  │ 终结 frontend TLS
  │ Istio workload identity + HBONE/mTLS
  ▼
Destination ztunnel
  │ 解封装后转给本地 workload
  ▼
Tenant Service → Pod : HTTP
```

这个模型保留两条安全边界，但不重复维护两套 backend 证书：

1. **Client → agentgateway**：继续使用正式的 frontend TLS 证书；这是外部客户端信任与域名身份，不能删除。
2. **agentgateway → tenant workload**：使用 Istio SPIFFE + HBONE/mTLS；租户应用只提供 HTTP。

> “应用只监听 HTTP”不等于“网络上明文传输”。严格说法是：**应用协议为 HTTP，跨 workload 的传输由 Ambient mTLS 加密。**

### 5. 两种方案的最终选择

| 方案 | 是否解决当前问题 | 安全性 | 运维成本 | 建议 |
|---|---|---|---|---|
| HTTP backend + agentgateway Istio integration + Ambient HBONE/mTLS | **是** | SPIFFE identity + 自动 mTLS，无 skip-verify | 最低，不管理租户 backend cert | **默认方案** |
| HTTPS backend + `BackendTLSPolicy` + cert-manager/private CA | **是** | 正确 CA + SAN 验证时安全 | 高：签发、轮换、CA 分发、SAN 设计 | 只用于合规或应用硬依赖 TLS |
| HTTPS backend + dummy cert + `insecureSkipVerify` | **否** | 无可靠 backend 身份验证 | 表面简单，长期风险最高 | **禁止继续使用** |
| HTTP backend，但 agentgateway 未加入 mesh/HBONE | **否** | STRICT 下会失败；PERMISSIVE 下可能出现明文 | 容易误判“已经有 mesh” | **禁止作为生产目标** |

### 6. 哪些场景仍然应该保留 BackendTLSPolicy

只有满足以下任一条件时，backend HTTPS 才提供额外价值：

- 应用或第三方产品硬编码只接受 HTTPS；
- 流量会离开 Istio mesh，HBONE 保护范围不能覆盖完整链路；
- 合规要求应用端自己终结 TLS，而不接受仅由 mesh transport 提供加密；
- backend 需要独立的 DNS/SAN 身份，或需要 gateway-to-backend 的专用 PKI；
- 需要与非 Istio、非 Ambient 的外部 TLS backend 通信。

这时应使用 cert-manager + internal CA（或组织 PKI）签发正确 SAN，并用 `BackendTLSPolicy.validation.caCertificateRefs` / `wellKnownCACertificates` 和 `hostname` / `subjectAltNames` 做完整验证。

Gateway API 对 backend mTLS 的标准化方向也允许 SPIFFE URI SAN，但 GEP 明确把“automatic mTLS”排除在该 Policy 的职责之外：

> Goal: “Enable the optional use of SPIFFE for Backend mutual TLS.”
>
> Non-Goal: “Define how automatic mTLS should be implemented with Gateway API.”
>
> 来源：[Gateway API GEP-3155 — Complete Backend mutual TLS Configuration](https://gateway-api.sigs.k8s.io/geps/gep-3155/)

**关键判断**：`BackendTLSPolicy` 可以表达手工管理的 backend TLS/mTLS，但不会代替 Ambient 自动 mTLS。两者是可选的分层机制，不是迁移前后的同义资源。

### 7. 建议迁移顺序与 POC 验收

#### Phase 1：证明 agentgateway 与 Ambient 的安全互操作

1. 安装 Solo agentgateway，启用 `AgentgatewayParameters.spec.istio`。
2. agentgateway 保持平台 gateway workload 形态，不要仅靠给 namespace 打 ambient label 来猜测集成已经生效。
3. 将一个测试 tenant namespace 标记为 `istio.io/dataplane-mode=ambient`。
4. backend 改为 HTTP Service，删除该测试服务的 backend certificate mount。
5. 对 tenant namespace 应用 `PeerAuthentication STRICT`。
6. 不创建 `BackendTLSPolicy`，HTTPRoute 直接引用 HTTP Service。

#### Phase 2：必须通过的验证

```bash
# 1. agentgateway 已带 Istio 集成参数与身份材料
kubectl get agentgatewayparameters -A -o yaml
kubectl get deploy -A -l gateway.networking.k8s.io/gateway-class-name=agentgateway -o yaml \
  | grep -E 'CA_ADDRESS|TRUST_DOMAIN|istio-token|istiod-ca-cert'

# 2. tenant namespace 确实进入 ambient，并强制 STRICT
kubectl get ns <tenant-ns> --show-labels
kubectl get peerauthentication -n <tenant-ns> -o yaml

# 3. 路由和 Policy 状态正确
kubectl get gateway,httproute -A -o yaml

# 4. 在 STRICT 下从 agentgateway 访问 HTTP backend 仍返回 200
curl --fail --resolve '<tenant-fqdn>:443:<gateway-ip>' \
  'https://<tenant-fqdn>/health'

# 5. 负向验证：临时使用一个 mesh 外 Pod 直连 backend，应被 STRICT 拒绝
kubectl run outside-mesh-test --rm -it --restart=Never \
  --image=curlimages/curl -- \
  curl --max-time 5 http://<service>.<tenant-ns>.svc.cluster.local:<port>/health

# 6. 查看 ztunnel 日志/metrics，确认不是 permissive plaintext 路径
kubectl logs -n istio-system -l app=ztunnel --since=5m \
  | grep -E '<tenant-ns>|<service>|HBONE|15008'
```

验收标准：

- [ ] frontend HTTPS 正常，证书由正式 PKI 管理；
- [ ] tenant Pod 只监听 HTTP，不再挂载 dummy cert；
- [ ] 不存在 `insecureSkipVerify`；
- [ ] `PeerAuthentication STRICT` 开启后 e2e 仍为 200；
- [ ] mesh 外明文直连被拒绝；
- [ ] ztunnel/HBONE telemetry 能证明 agentgateway → workload 走 mTLS；
- [ ] agentgateway 多副本运行，并按生产要求配置 requests/limits、PDB、HPA 与 topology spread。

### 8. 最终判断

**你的初步判断“切换到 Solo 后可以解决”是成立的，但准确表述应为：**

> Solo agentgateway 本身提供 Gateway API、BackendTLSPolicy 和 Istio/HBONE 集成能力；真正消除 `insecureSkipVerify` 与 dummy backend certificate 的，是“agentgateway 以 Istio workload identity 进入 Ambient HBONE/mTLS 链路 + tenant backend 回归 HTTP”这个组合，而不是单独把 ingress controller 换成 Solo。

推荐把 **HTTP backend + Ambient mTLS** 定为平台默认，把 **BackendTLSPolicy + 正式 PKI** 定为例外流程。这样既解决当前安全债务，也避免为已经由 mesh 加密的内部链路再维护一套重复的租户证书体系。
