# Cipher Suites 详解 (TLS 1.2 / 1.3, K8s / GKE 实战视角)

## 1. 一句话本质

> TLS 握手时,客户端把**自己支持的算法清单**发给服务端,服务端按自己配置的**优先级排序**选一个;这个被选中的"算法组合"就叫 **cipher suite**(密码套件)。它不是一个算法,而是 **4 个子算法的打包**:
>
> 1. **Key Exchange (Kx)** — 怎么安全地交换出对称密钥
> 2. **Authentication (Au)** — 怎么证明服务端真的是它声称的身份(证书 + 签名)
> 3. **Bulk Cipher (Enc)** — 之后真正加密数据流用的对称算法 (AES / ChaCha20)
> 4. **MAC / AEAD** — 怎么防数据被篡改(GCM 模式自带)

握手之后的"业务流量加密"只跟第 3 项有关;前 3 项都是为了一次性协商出**会话密钥**。

## 2. 命名格式速读

### 2.1 TLS 1.2 命名 (OpenSSL 风格)

```
ECDHE - RSA - AES128 - GCM - SHA256
  │      │      │       │      │
  │      │      │       │      └─ MAC / PRF (SHA-256, 用于 HMAC 或 PRF)
  │      │      │       └─ 工作模式: GCM (AEAD, 自带认证+加密)
  │      │      └─ 对称算法 + 强度: AES 128-bit
  │      └─ 认证算法: RSA (用 RSA 私钥对握手签名)
  └─ 密钥交换: ECDHE (椭圆曲线 Diffie-Hellman Ephemeral, 临时密钥, 支持前向保密)
```

**常见前缀速记**:

| 前缀 | 含义 | 安全等级 |
|---|---|---|
| `ECDHE-*` | 椭圆曲线 DH, 临时密钥, **支持前向保密 (PFS)** | ✅ 首选 |
| `DHE-*` | 经典 DH, 临时密钥, PFS | ✅ 备选(慢) |
| `RSA-` (作为 Kx) | 静态 RSA, 私钥泄露 = 过去流量全解 | ❌ 已淘汰 |
| `*NULL*` | 不加密 | ❌ 调试用 |
| `*EXPORT*` | 弱加密出口限制 | ❌ 已废弃 |
| `*RC4*` / `*3DES*` | 老旧对称算法 | ❌ 已废弃 |
| `*CBC*` (无 GCM) | CBC 模式易遭 BEAST/Lucky 13 攻击 | ❌ 慎用 |

### 2.2 TLS 1.3 命名 — **完全不同**

TLS 1.3 是个大简化,**cipher suite 名字里只剩 AEAD 算法**,因为:

- Kx 协议层固定为 (EC)DHE,无选项
- Au 协议层固定为证书签名,无选项
- 握手期间明文部分就完成了 Kx 和 Au

所以 **TLS 1.3 全世界只有 5 个标准 cipher suite** (IANA 注册表):

| 名称 | 对称算法 | 适用 |
|---|---|---|
| `TLS_AES_128_GCM_SHA256` | AES-128-GCM | 通用首选 (性能/安全平衡) |
| `TLS_AES_256_GCM_SHA384` | AES-256-GCM | 强合规需求 (FIPS / 等保) |
| `TLS_CHACHA20_POLY1305_SHA256` | ChaCha20-Poly1305 | 移动端/无 AES 硬件加速 |
| `TLS_AES_128_CCM_SHA256` | AES-128-CCM | 嵌入式 / IoT |
| `TLS_AES_128_CCM_8_SHA256` | AES-128-CCM-8 | 8 字节 tag, 极窄带宽 |

**注意**: TLS 1.3 cipher suite 名字的"前缀"是 `TLS_`,**不是 `ECDHE-...`** 这种。这是很多人混淆的地方。

### 2.3 TLS 1.2 vs 1.3 一图速览

| 维度 | TLS 1.2 | TLS 1.3 |
|---|---|---|
| 名字前缀 | `ECDHE-RSA-AES128-GCM-SHA256` | `TLS_AES_128_GCM_SHA256` |
| 名字里能否选 Kx? | ✅ (ECDHE / DHE / RSA) | ❌ (协议层固定 ECDHE) |
| 名字里能否选 Au? | ✅ (RSA / ECDSA) | ❌ (协议层固定) |
| 名字里能选什么? | Enc + MAC | Enc + MAC |
| 总数 | 几百个 (IANA 大量标 D=Deprecated) | 5 个 (强制精简) |
| 前向保密 (PFS) | 选了 ECDHE/DHE 才有 | **默认就有** |
| 0-RTT | ❌ | ✅ (可关) |

## 3. Cipher Suites 在 K8s 生态里的 5 个应用场景

### 3.1 ① K8s API Server (控制面 TLS)

`kube-apiserver` 启动参数直接配:

```bash
kube-apiserver \
  --tls-cipher-suites=TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 \
  --tls-min-version=VersionTLS12
```

适用对象: 集群内所有 `kubectl` / 控制器 / scheduler / etcd 客户端到 apiserver 的连接。

### 3.2 ② K8s etcd (peer + client TLS)

`etcd` 自己有 `--cipher-suites` flag, 默认包含 `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256` 等 4 个。

```bash
etcd \
  --cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 \
  --listen-client-urls=https://0.0.0.0:2379
```

适用对象: etcd 集群间复制 + 客户端连接。

### 3.3 ③ ingress-nginx (Ingress 边缘)

通过 ConfigMap 的 `ssl-ciphers` 字段配,这是 K8s 上**最常见的配置点**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256"
  ssl-protocols: "TLSv1.2 TLSv1.3"
  ssl-ecdh-curve: "auto"
  ssl-dh-param: ""  # 只有用 DHE-* 时才需要
```

`ssl-ciphers` 的**顺序就是优先级** — 客户端支持的算法,服务端按这个顺序选第一个匹配的。

### 3.4 ④ Istio / Envoy (service mesh mTLS)

Istio 用 Envoy 代理,cipher suites 通过 `meshConfig` 或 PeerAuthentication 配置:

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
```

Envoy 默认 cipher suites (`envoy.tls.context.CryptoProperties`):

- **TLS 1.3**: `TLS_AES_128_GCM_SHA256`,`TLS_AES_256_GCM_SHA384`,`TLS_CHACHA20_POLY1305_SHA256`
- **TLS 1.2**: `ECDHE-ECDSA-AES128-GCM-SHA256`,`ECDHE-RSA-AES128-GCM-SHA256`,`ECDHE-ECDSA-AES256-GCM-SHA384`,`ECDHE-RSA-AES256-GCM-SHA384`,`ECDHE-ECDSA-CHACHA20-POLY1305`,`ECDHE-RSA-CHACHA20-POLY1305`,`DHE-RSA-AES128-GCM-SHA256`,`DHE-RSA-AES256-GCM-SHA384`

### 3.5 ⑤ cert-manager (管证书,不是直接管 cipher)

cert-manager **不直接配 cipher** — 它只管证书的签发/续期/注入 Secret。**实际握手用的 cipher 取决于消费这个 Secret 的 ingress / gateway**。所以 cert-manager 用户经常混淆"我配了 cipher 怎么没生效" — 答案:它从来不管这一层。

## 4. Cipher Suites 在 GKE 上的 3 个配置点

### 4.1 ① GCP HTTPS Load Balancer (SSL Policy)

GKE Ingress 默认会创建一个 **Target HTTPS Proxy**,这个 Proxy 绑定一个 **SSL Policy**,Policy 决定可用 cipher 集合。

**GCP 预置 3 个 Profile**:

| Profile | 最低 TLS | 包含的算法 | 适用 |
|---|---|---|---|
| `COMPATIBLE` | TLS 1.0 | 包含 RSA, DHE, CBC | 老客户端兼容, **不推荐新业务** |
| `RESTRICTED` | TLS 1.2 | ECDHE + AES-GCM, 不含 DHE | 合规场景 (PCI DSS 3.2) |
| `MODERN` | TLS 1.3 | TLS 1.3 的 3 个主流 cipher | **Google 自家前端在用, 推荐** |

gcloud 创建:

```bash
# 引用 MODERN profile
gcloud compute ssl-policies create my-modern-policy \
  --profile MODERN \
  --min-tls-version 1.2

# 绑定到 Target HTTPS Proxy
gcloud compute target-https-proxies update my-https-proxy \
  --ssl-policy my-modern-policy
```

**Custom profile** — 想自己列 cipher 时:

```bash
gcloud compute ssl-policies create my-custom-policy \
  --profile CUSTOM \
  --min-tls-version 1.2 \
  --custom-features "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,..." \
  --custom-features "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,..."
```

**Custom profile 支持的 cipher** (GCP 白名单, 不能乱填):

| 算法 | TLS 版本 | Profile 默认包含 |
|---|---|---|
| `TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256` | 1.2 | MODERN / RESTRICTED / COMPATIBLE |
| `TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256` | 1.2 | MODERN / RESTRICTED / COMPATIBLE |
| `TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA` | 1.2 | COMPATIBLE |
| `TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA` | 1.2 | COMPATIBLE |
| `TLS_RSA_WITH_AES_128_GCM_SHA256` | 1.2 | RESTRICTED / COMPATIBLE (静态 RSA, 无 PFS) |
| `TLS_RSA_WITH_AES_128_CBC_SHA` | 1.2 | COMPATIBLE (无 PFS) |
| `TLS_AES_128_GCM_SHA256` | 1.3 | MODERN (TLS 1.3 唯一名字格式) |
| `TLS_AES_256_GCM_SHA384` | 1.3 | MODERN |
| `TLS_CHACHA20_POLY1305_SHA256` | 1.3 | MODERN |

### 4.2 ② GKE Gateway API (新代际 Gateway)

GKE Gateway (而非 Ingress) 通过 ** GCPBackendPolicy** 配 SSL:

```yaml
apiVersion: networking.gke.io/v1
kind: GCPBackendPolicy
metadata:
  name: my-ssl-policy
  namespace: default
spec:
  default:
    sslPolicy: my-modern-policy   # 引用上面创建的 SSL Policy
  target:
    service:
      name: my-service
      namespace: default
```

或者直接在 Gateway spec 里引用:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-gateway
spec:
  gatewayClassName: gke-l7-global-external-managed
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      options:
        networking.gke.io/pre-shared-certs: my-cert
        # SSL Policy 实际还是绑在 Backend Service / Target Proxy 上
```

### 4.3 ③ GKE Ingress (老的)

老 Ingress 走 Target HTTPS Proxy → SSL Policy,跟 §4.1 一样。但**默认 GKE 创建的 Proxy 是不带 SSL Policy 的** — 也就是说默认就是 **GCP 的"modern-equivalent default"** (TLS 1.0+, 几乎全部 cipher 都支持, 不安全)。**生产环境必须显式绑一个 MODERN 或 RESTRICTED profile**。

## 5. 推荐配置 (拿来即用)

### 5.1 Mozilla "Modern" 配置 (2026 推荐)

```bash
# TLS 1.3
TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256

# TLS 1.2 (ECDHE + AES-GCM + ChaCha20, 全部 PFS)
ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305
```

**不要包含 DHE** — 慢 + DHEat 攻击 (CVE-2002-20001) 风险 + 实际无优势(ECDHE 更快更安全)。
**不要包含 CBC** — BEAST / Lucky 13 攻击面。
**不要包含 RSA Kx** — 无 PFS。

### 5.2 Mozilla "Intermediate" 配置 (兼容老客户端)

```bash
ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384
```

加了 DHE 兜底**只在你必须支持 IE 11 on Win 7** 时用。

### 5.3 GCP 侧推荐

| 业务场景 | Profile |
|---|---|
| 公网用户(Chrome / Safari / Firefox / Edge) | `MODERN` |
| 公网用户(还有少量 IE 11 / 老 Android) | `RESTRICTED` |
| 内部系统 / 老设备 | `COMPATIBLE` (慎用) |
| 严格合规 (等保三级 / 金融) | `RESTRICTED` + 自定义禁用 CBC |

## 6. 实操命令

### 6.1 验证服务端实际支持的 cipher

```bash
# 用 nmap 看 (推荐, 输出清晰)
nmap --script ssl-enum-ciphers -p 443 example.com

# 用 openssl s_client 单点探测
openssl s_client -connect example.com:443 -tls1_2 \
  -cipher 'ECDHE-RSA-AES128-GCM-SHA256' 2>&1 | grep "Cipher    :"

# 用 testssl.sh (最全面)
testssl.sh example.com
```

### 6.2 强制客户端只发某个 cipher (用来反推服务端是否真支持)

```bash
# 如果服务端只配了 ECDHE-* 却没有 RSA-*, 用 -cipher RSA 试探会失败
openssl s_client -connect example.com:443 \
  -cipher 'AES128-GCM-SHA256'   # 无 ECDHE 前缀, 老 Kx, 应该被拒绝
```

### 6.3 K8s ingress-nginx 验证

```bash
# 1. 看 ConfigMap 当前配置
kubectl -n ingress-nginx get cm ingress-nginx-controller -o jsonpath='{.data.ssl-ciphers}'

# 2. 看 Pod 实际生效 (重启后)
kubectl -n ingress-nginx exec <pod> -- cat /etc/nginx/nginx.conf | grep ssl_ciphers

# 3. 用 curl --tls-max 验证
curl -v --tls-max 1.2 --tls-cipher 'ECDHE-RSA-AES128-GCM-SHA256' https://my-app.example.com
```

### 6.4 GKE / GCP 侧

```bash
# 列出当前 project 所有 SSL Policy
gcloud compute ssl-policies list

# 看某 Policy 详细 cipher 列表
gcloud compute ssl-policies describe my-modern-policy

# 看 Target HTTPS Proxy 当前绑的 Policy
gcloud compute target-https-proxies describe my-proxy --format="yaml" | grep -i ssl
```

## 7. 常见坑

### 7.1 排序决定一切

`ssl-ciphers: "A:B:C"` 意思是: **客户端支持的算法里,按 A → B → C 顺序选第一个匹配**。所以:

- 想要 ECDHE 优先 → 放最前
- 想禁用某个算法 → 直接**从列表里删掉**(不要注释,不要放最后,会被客户端"先到先得"坑)

### 7.2 TLS 1.3 名字不写 Kx

很多 K8s 用户给 ingress-nginx 配 `ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256:..."` 然后 TLS 1.3 客户端连不上 — 因为这些名字在 TLS 1.3 下无效。**必须同时配上 `TLS_AES_128_GCM_SHA256:...` 这种格式**,中间用 `:` 分隔:

```yaml
ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384"
```

### 7.3 DHE 慢 + DH param 必须显式

如果用 DHE-* cipher:

- **必须**配 `ssl-dh-param` (至少 2048 bit) — 没有的话 DHE cipher 直接被跳过
- DHE 比 ECDHE **慢 3-10 倍** — 移动端/高并发慎用

### 7.4 静态 RSA Kx = 无 PFS,千万别用

`TLS_RSA_WITH_AES_128_GCM_SHA256` 这种**没有 ECDHE/DHE 前缀的** cipher: 私钥一旦泄露,过去所有用这个密钥加密的会话都能被解。**这就是 Heartbleed 之后的"为什么我们都要 PFS"** 的根本原因。

### 7.5 API server 默认 cipher 行为

`kube-apiserver` 默认启用了 **很多老的 cipher** (出于兼容)。K8s 1.27+ 加了 `--tls-cipher-suites` flag 让你显式覆盖,但**不写这个 flag = 走默认**。生产 K8s 必须显式配,见 §3.1。

### 7.6 GCP 自定义 SSL Policy 数量限制

每个 GCP SSL Policy **最多 100 个 cipher** (`custom-features` flag 调用次数)。超过会报错。**MODERN profile 只有 ~10 个 cipher**,完全够用,不需要 custom。

### 7.7 GKE Autopilot 锁定配置

**GKE Autopilot 集群不允许你改 node 级别配置**,所以 `--tls-cipher-suites` 这种 apiserver flag 你碰不到 — 只能通过 GCP 控制面 (SSL Policy) 配,见 §4.1。

## 8. 决策树 (怎么选)

```
你要保护什么?
├── 内部微服务 (集群内) 
│   └── K8s 自身 (apiserver / etcd)
│       → 显式配 --tls-cipher-suites (见 §3.1, §3.2)
│   └── Service mesh (Istio / Linkerd)
│       → 用 mesh 默认即可, 单独审计时改 meshConfig.tls
│
├── 边缘入口 (公网用户访问)
│   ├── GKE Ingress (老) 
│   │   → 配 SSL Policy = MODERN (见 §4.1)
│   │   → 同时配 ingress-nginx ConfigMap ssl-ciphers (见 §3.3)
│   └── GKE Gateway (新)
│       → 配 GCPBackendPolicy (见 §4.2)
│
└── 自建 nginx / envoy / haproxy
    → 拿 Mozilla Modern 配置 (见 §5.1)
    → TLS 1.2 + TLS 1.3 同时配 (名字格式不同!)
```

## 9. 参考

- **IANA TLS Cipher Suite Registry** (权威源, 几百条): https://www.iana.org/assignments/tls-parameters/tls-parameters.xhtml
- **Mozilla SSL Config Generator**: https://ssl-config.mozilla.org/
- **Mozilla Server Side TLS Wiki**: https://wiki.mozilla.org/Security/Server_Side_TLS
- **GCP SSL Policies 文档**: https://cloud.google.com/load-balancing/docs/ssl-policies
- **ingress-nginx ssl-ciphers 默认值**: https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/configmap.md
- **TLS 1.3 RFC 8446** (定义): https://datatracker.ietf.org/doc/html/rfc8446
- **OWASP TLS Cheat Sheet**: https://cheatsheetseries.owasp.org/cheatsheets/Transport_Layer_Security_Cheat_Sheet.html
- **testssl.sh** (本地探测工具): https://testssl.sh/
