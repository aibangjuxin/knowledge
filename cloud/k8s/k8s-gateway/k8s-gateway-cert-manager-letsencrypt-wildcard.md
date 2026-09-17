# K8s Gateway + cert-manager + Let's Encrypt Wildcard 跨 NSS HTTPS 落地

> **原始来源**:[Securing Cross-Namespace Routes with NGINX Gateway, cert-manager & Let's Encrypt (Wildcard HTTPS Guide)](https://medium.com/@sanathw/securing-cross-namespace-routes-with-nginx-gateway-cert-manager-lets-encrypt-wildcard-https-7c0c721d0bf1)
> — by Sanath Waghela · 2025-11-23 · 10 min read
>
> **目录位置**:`/Users/lex/git/knowledge/cloud/k8s/k8s-gateway/`
> (与同目录 `public-fqdn-explorer.md` / `tenant-namespace-k8s-gateway.md` /
> `k8s-gateway-timeout.md` / `k8s-gateway-netpol.md` 形成 "k8s-gateway 系列")。
>
> **这篇文章在我们的场景里怎么用**:见 §11 「场景适配 — 这套东西怎么帮到我」。
> 简单预告:**Cross-project 场景下** Tenant 侧的 cert 通常走
> `gcp/cross-project/public-tls-ingress/` + Google Managed Certificates,
> **Master 侧 K8s Gateway 内部**才是 cert-manager + DNS-01 的真正用武之地 —
> 因为 wildcard (`*.caep.uk`) 必须 DNS-01,Google Managed Cert **又不支持
> wildcard**,所以 cert-manager 是 GKE 内部补 wildcard 的唯一路径。

---

## 目录

- [0. 为什么把这篇收藏进来](#0-为什么把这篇收藏进来)
- [1. 总体架构:cert-manager ↔ Gateway API 的耦合点](#1-总体架构cert-manager--gateway-api-的耦合点)
- [2. HTTP-01 vs DNS-01 — 选错直接死](#2-http-01-vs-dns-01--选错直接死)
- [3. 安装 cert-manager — `enableGatewayAPI=true` 是底线](#3-安装-cert-manager--enablegatewayapitrue-是底线)
- [4. DNS Provider Secret + ClusterIssuer](#4-dns-provider-secret--clusterissuer)
- [5. Gateway TLS 配置 — 注解 / listener / certificateRefs](#5-gateway-tls-配置--注解--listener--certificaterefs)
- [6. HTTPRoute 升级到 HTTPS listener + 可选 redirect](#6-httproute-升级到-https-listener--可选-redirect)
- [7. 验证](#7-验证)
- [8. 排错 5 类 — Stuck / DNS Challenge / Gateway 不用 cert / Rate Limit / Expiry](#8-3-类-排错--stuck--dns-challenge--gateway-不用-cert--rate-limit--expiry)
- [9. Let's Encrypt 速率上限(必须背下来)](#9-lets-encrypt-速率上限必须背下来)
- [10. 生产最佳实践 + 常见 Gotcha](#10-生产最佳实践--常见-gotcha)
- [11. 场景适配 — 这套东西怎么帮到我](#11-场景适配--这套东西怎么帮到我)
- [12. 与现有 doc 的对照 + 引用清单](#12-与现有-doc-的对照--引用清单)

---

## 0. 为什么把这篇收藏进来

Sanath Waghela 这篇是 2025-11-23 发的,核心做了一件事:

**把 cert-manager 从一个独立组件,塞回 Gateway API 的 native 流程**:

| 旧做法 | 新做法 (本文) |
|---|---|
| cert-manager 独立 + `ingress-shim` 注解 | cert-manager 直接 watch **Gateway** 的 `cert-manager.io/issuer` 注解,**自动**生成 `Certificate` + `Secret` |
| `Ingress` + `tls.secretName` | `Gateway.spec.listeners[*].tls.certificateRefs[]` 直接引 Secret |
| HTTP-01 only | 默认 DNS-01,因为目标是 wildcard (`*.yourdomain.com`) |
| IngressClass-specific | **Gateway API** — 跨 namespace、跨 Gateway impl 统一 |

**收藏这篇的核心价值**:

1. **DNS-01 + wildcard 的"为什么"**: HTTP-01 在 Let's Encrypt 的 CA/B Forum
   policy 里就被排除在外 — 任意子域名无限集合的 challenge 在 HTTP 层根本没法表达。
   DNS-01 是**唯一**合法路径,这个不是我猜的,policy 里写死。
2. **`enableGatewayAPI=true` 这个 flag 的真实语义**: cert-manager controller
   在启动时**只检查一次**有没有装 Gateway API CRD,如果 helm install 时
   Gateway API 还没就位,后续 `helm upgrade` 必须 `kubectl rollout restart` 才能
   让 controller 重新读 CRD(原文章明文提到,这是大多数踩坑的根因)。
3. **整套排错路径 + rate limit 数字(50/week)**,不需要再读一遍 ACME RFC。

## 2. HTTP-01 vs DNS-01 — 选错直接死

| 维度 | HTTP-01 | DNS-01 |
|---|---|---|
| 原理 | CA 给 token → 服务端在 `http://<domain>/.well-known/acme-challenge/<token>` 暴露 → CA 抓回来验 | CA 给 token → 服务端在 `_acme-challenge.<domain>` 加 TXT → CA 查 DNS 验 |
| **Wildcard** | ❌ **禁止** (CA/B Forum policy) | ✅ **唯一合法路径** |
| 需要公网可达端口 80 | ✅ 必要 | ❌ 不需要 |
| 需要 DNS provider API 凭据 | ❌ | ✅ |
| DNS 传播延迟 | 无 | 1–10 分钟 |
| 防火墙 / 私有网络 | ❌ 公网必须可达 | ✅ 内网也能发 |
| 每子域一个证书 | ✅ 每个 cert 单 hostname | ✅ 一个 wildcard 覆盖无限子域 |

**结论**: 生产里只要目标带 `*`,**只能 DNS-01**。原文也说 "If you want
wildcard TLS (`*.domain.com`), DNS-01 is required — Let's Encrypt does not
allow HTTP-01 wildcard validation."

## 3. 安装 cert-manager — `enableGatewayAPI=true` 是底线

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true \
  --set config.apiVersion="controller.config.cert-manager.io/v1alpha1" \
  --set config.kind="ControllerConfiguration" \
  --set config.enableGatewayAPI=true
```

**为什么 `enableGatewayAPI=true` 不可省**:

> 原文:"This is important because some of the cert-manager components only
> perform the Gateway API check on startup."

→ 如果 cert-manager 先起来、Gateway API CRD 后装,controller **不会**回头去
适配,必须 `kubectl rollout restart deployment cert-manager -n cert-manager`
让 pod 重启重新读 CRD。**所以安装顺序永远是 Gateway API CRD → cert-manager**。

## 4. DNS Provider Secret + ClusterIssuer

### 4.1 Provider secret (DigitalOcean 例子)

```bash
kubectl create secret generic digitalocean-dns \
  -n nginx-gateway \
  --from-literal=access-token='YOUR_Digitalocean_API_TOKEN'
```

> ⚠️ **secret 必须建在 Gateway 所在 namespace**,因为 cert-manager 会 watch
> Gateway 那个 ns 去找 provider credentials。如果建在 `cert-manager` ns
> 而 Gateway 在 `nginx-gateway` ns,**会 silently fail**。

### 4.2 ClusterIssuer (wildcard-enabled)

(原文 §Step 3 的 YAML 在 Medium 上是付费墙 / 图片化的,这里给可复制的精简版)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    email: ops@yourdomain.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production-account-key
    solvers:
      - dns01:
          digitalocean:
            tokenSecretRef:
              name: digitalocean-dns
              key: access-token
        selector:
          dnsZones:
            - "yourdomain.com"
```

> 💡 **Issuer vs ClusterIssuer**:
> - `Issuer`: **namespaced**,只服务本 ns 内的 Gateway
> - `ClusterIssuer`: **cluster-wide**,任意 ns 的 Gateway 都能引用 → 多租户场景**必须** ClusterIssuer

## 5. Gateway TLS 配置 — 注解 / listener / certificateRefs

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: nginx-gateway
  namespace: nginx-gateway
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production   # ⭐ 触发点
spec:
  gatewayClassName: nginx
  listeners:
    - name: http                                          # 端口 80 → 重定向到 https
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
    - name: https                                         # 端口 443 → 真业务
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate                                   # Gateway 终结 TLS
        certificateRefs:
          - kind: Secret
            name: domain-tls                              # cert-manager 自动建
      allowedRoutes:
        namespaces:
          from: All
```

**四个关键点**:

1. **`cert-manager.io/cluster-issuer` 注解**: cert-manager controller **watch 这个**,
   看到 Gateway 上有它 + 注解指向的 ClusterIssuer 存在 + 没有同名 `Certificate`,
   就**自动**创建一个 `Certificate` resource(注解名要和 ClusterIssuer 严格一致)。
2. **`mode: Terminate`**: TLS 在 Gateway 这层终结,backend service 不再见 TLS。
   备选 `Passthrough` 是给 backend 自己处理 TLS 的场景(本文不用)。
3. **`certificateRefs.name = domain-tls`**: cert-manager 自动建的 Secret
   必须和这个名字对得上;Secret 实际内容 `tls.crt` / `tls.key`。
4. **`allowedRoutes.namespaces.from: All`**: 跨 namespace 必备 —
   多租户 Gateway 必须显式允许所有 ns,否则只服务自己 ns。

## 6. HTTPRoute 升级到 HTTPS listener + 可选 redirect

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: application
spec:
  parentRefs:
    - name: nginx-gateway
      namespace: nginx-gateway
      sectionName: https                                  # ⭐ 改指 https listener
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: app-service
          port: 8080
```

**HTTP → HTTPS 强制重定向**(可选,但生产必加):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: redirect-route
  namespace: nginx-gateway
spec:
  parentRefs:
    - name: nginx-gateway
      sectionName: http
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

> 301 vs 302: **301 是永久重定向**,浏览器会缓存;**302 是临时**。SEO
> 友好 + 性能都偏向 301。

## 7. 验证

```bash
# 1. Certificate Ready?
kubectl get certificate -n nginx-gateway
# 期望: codeify-me-tls   True

# 2. 详细看 cert 状态
kubectl describe certificate codeify-me-tls -n nginx-gateway

# 3. 看 ACME order + challenge
kubectl get orders.acme.cert-manager.io -n nginx-gateway
kubectl get challenges.acme.cert-manager.io -n nginx-gateway

# 4. 证书内容
kubectl get secret codeify-me-tls -n nginx-gateway \
  -o jsonpath='{.data.tls.crt}' | base64 -d | openssl x509 -text

# 期望输出里有:
#   Issuer: Let's Encrypt
#   DNS: *.yourdomain.com

# 5. 实际 HTTPS 调用
curl -vI https://app.yourdomain.com
```

## 8. 3 类常见排错 — Stuck / DNS Challenge / Gateway 不用 cert / Rate Limit / Expiry

### 8.1 Certificate 卡在 "False"

```bash
# 1. 看 certificate 事件
kubectl describe certificate yourdomain-tls -n nginx-gateway
# 关键词: "Failed to create Order: ...", "Waiting for DNS record to propagate"

# 2. Order / Challenge 状态
kubectl get orders.acme.cert-manager.io -n nginx-gateway
kubectl get challenges.acme.cert-manager.io -n nginx-gateway
kubectl describe challenge <name> -n nginx-gateway

# 3. controller 日志
kubectl logs -n cert-manager deployment/cert-manager --tail=100 -f
```

### 8.2 DNS Challenge 没创建 TXT 记录

```bash
# 1. 验证 provider secret 存在
kubectl get secret cloudflare-api-token-secret -n cert-manager -o yaml

# 2. 用 secret 手动打 provider API
export CF_API_TOKEN="$(kubectl get secret cloudflare-api-token-secret -n cert-manager -o jsonpath='{.data.api-token}' | base64 -d)"
curl -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CF_API_TOKEN" \
  -H "Content-Type: application/json"

# 3. 看 _acme-challenge TXT 是否落地
dig TXT _acme-challenge.yourdomain.com +short
```

**Provider-specific 报错速查**:

| Provider | 报错 | 含义 | 修法 |
|---|---|---|---|
| Cloudflare | `Zone not found` | `selector.dnsZones` 跟 zone 不匹配 | 对齐 zone 域名 |
| Cloudflare | `Forbidden` | token 权限不够 | 给 `Zone:DNS:Edit` 权限 |
| Cloudflare | `Invalid zone` | token scope 到错误 zone | 重发 token |
| Route53 | `AccessDenied` | IAM policy 缺权限 | 加 `route53:ChangeResourceRecordSets` |
| Route53 | `NoSuchHostedZone` | region / zone ID 错 | 重新查 |

### 8.3 Gateway 不引用 cert

```bash
# 1. secret 在对的 ns?
kubectl get secret yourdomain-tls -n nginx-gateway

# 2. Gateway 引用对不对
kubectl get gateway nginx-gateway -n nginx-gateway -o yaml | grep -A10 certificateRefs
# 期望:
#   certificateRefs:
#   - kind: Secret
#     name: yourdomain-tls

# 3. secret 里真的有 tls.crt / tls.key
kubectl get secret yourdomain-tls -n nginx-gateway \
  -o jsonpath='{.data}' | jq 'keys'
# 期望: ["tls.crt", "tls.key"]

# 4. controller 重启
kubectl rollout restart deployment nginx-gateway -n nginx-gateway

# 5. Gateway 状态
kubectl describe gateway nginx-gateway -n nginx-gateway | grep -A20 "Status:"
# 期望 Listeners Conditions:
#   - Type: Ready, Status: true
#   - Type: ResolvedRefs, Status: true
```

### 8.4 Rate Limit 报错

```
Error: acme: error: 429 :: POST https://acme-v02.api.letsencrypt.org/...
too many certificates already issued for: yourdomain.com
```

**解法**:

1. **永远先 staging**: 见 §9,生产 50/week 极容易撞。
2. **共用 secret**:多个 Gateway 引同一个 Secret 而不是分别申请。
3. **等 7 天重置** 或在 [crt.sh](https://crt.sh/?q=yourdomain.com) 查发证历史。

### 8.5 证书过期

```bash
# 列所有证书 + 过期时间
kubectl get certificates -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
READY:.status.conditions[0].status,\
EXPIRY:.status.notAfter

# 强制续期(删 CertificateRequest 让 controller 重发)
kubectl delete certificaterequest -n nginx-gateway --all

# 或者删整个 Certificate(controller 会重建 + 触发续期流程)
kubectl delete certificate yourdomain-tls -n nginx-gateway
```

> cert-manager 默认 **30 天前**自动续期,所以"突然过期"通常是 controller
> 起不来 / DNS API 凭据过期 / ClusterIssuer 误删 这三种情况。

## 9. Let's Encrypt 速率上限(必须背下来)

| 限制项 | Production | Staging |
|---|---|---|
| Certificates per domain per week | **50** | 30,000 |
| Duplicate certificates per week | **5** | Unlimited |
| Failed validations per hour | **5** | 60 |
| Accounts per IP per 3 hours | 10 | 500 |

**黄金法则**:

- **任何 cert-manager 测试必须先 staging**,直到最后一刻才切 production。
- staging endpoint: `https://acme-staging-v02.api.letsencrypt.org/directory`
- 不要在生产 issuer 上"试一下 challenge 通不通" — **5 次失败 / 小时**就会 block。

## 10. 生产最佳实践 + 常见 Gotcha

### Best practices

| # | 实践 | 为什么 |
|---|---|---|
| 1 | **永远 staging 先跑通** | 避免 §9 的 50/week 撞墙 |
| 2 | **Prometheus 监控证书过期** | `certmanager_certificate_expiration_timestamp_seconds - time()` < 30d 报警 |
| 3 | **dev / staging / prod 三个独立 issuer** | dev 的 wildcard 跟 prod 的 wildcard 不互相撞 rate limit |
| 4 | **备份 ACME account key** (Secret) | 丢了这个 key = 续期全废 |
| 5 | **DNS provider token 最小权限** | token 泄露 = 攻击者能签发你的 wildcard |

### Gotcha 速查

| 错 | 后果 | 修法 |
|---|---|---|
| 装完 cert-manager 不重启 controller | Gateway API 不被识别 | `kubectl rollout restart deploy/cert-manager` |
| 拿 HTTP-01 去拿 wildcard | **永远 fail** | 必须 DNS-01 |
| `selector.dnsZones` 跟实际 zone 域名不一致 | challenge silently fail | `kubectl describe challenge` 看 `Waiting for DNS...` |
| 直接在生产 issuer 上 debug | 5 次 fail/h 触发 rate limit | 切 staging issuer |
| 没监控证书过期 | 突然业务断流 | Prometheus + Alertmanager |
| DNS token 给了 `*` zone 权限 | 安全事件 | 给 `Zone:DNS:Edit` 最小 scope |

## 11. 场景适配 — 这套东西怎么帮到我

> 这是我自己加的章节**超出原文**。原文给的是 generic K8s Gateway + cert-manager
> 模板;我下面写的是:在我已有的 `public-fqdn-explorer.md` 跨项目 + Tenant→Master
> 架构里,这套东西**真正能落到哪里、不能落到哪里**。

### 11.1 我已有的 TLS 路径全景

| 层 | 资源 | 现状 | 文档 |
|---|---|---|---|
| **Tenant Project** (Project A) | GCP GLB + Google Managed Certificate | ✅ 已经用 Google 托管证书终结 TLS,流量进 PSC | `gcp/cross-project/public-tls-ingress/` |
| **PSC 边界** | TLS **不解**,端到端从 Tenant GLB 到 Master ILB | (Google Managed Cert 不会跨越 PSC) | `gcp/cross-project/public-tls-ingress/` |
| **Master Project** (Project B) MIG Nginx | TLS **不解** (proxy_pass 到 K8s Gateway VIP:443) | nginx `proxy_ssl_server_name on` + SNI = `team1.caep.uk` | `cloud/k8s/k8s-gateway/public-fqdn-explorer.md` §3.3 |
| **Master Project** K8s Gateway | **这里就是本文的用武之地** | 现在 `public-fqdn-explorer.md` 是基于自建 wildcard + 自管 secret;**可以升级成 cert-manager + DNS-01** | (本文) |
| **Backend Namespace Deployment** | 纯 HTTP (mTLS 在 Istio/ASM 内部) | 跟本文无关 | `gcp/asm/solo/` |

### 11.2 三个最具体的帮助点

#### ① K8s Gateway 的 wildcard cert 可以不再手工管理

**现状** (`public-fqdn-explorer.md` §3.3 提及):
> 自建 wildcard Secret,kubectl apply 上去,90 天人工续期 — 这是**手工**的。

**本文给的方案**:
- Master Project 的 K8s Gateway 注解 `cert-manager.io/cluster-issuer: letsencrypt-prod`
- cert-manager controller 自动 watch Gateway → 自动建 `Certificate` → 自动续期
- **零人工介入**

#### ② `*.team1.caep.uk` 这类业务 wildcard 的唯一合法路径

**问题**: Google Managed Certificate **不支持 wildcard** (硬限制,GAIL)。

**对 Master 侧 K8s Gateway 的影响**:
- 要给 `team1.caep.uk` + `*.team1.caep.uk` 一次性签证书
- 必须 DNS-01 (CA/B Forum policy)
- cert-manager + DNS provider secret 是**唯一**在 GKE 内部搞 wildcard 的方案

**配 GCP Cloud DNS** 的 `cloud-dns-dns01` solver(原文没给 GCP 版,这里补):

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-gcp
spec:
  acme:
    email: ops@aibang.cn
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudDNS:
            project: <B_PROJECT_ID>             # GCP project hosting Cloud DNS zone
            serviceAccountSecretRef:
              name: cloud-dns-sa
              key: service-account.json         # GSA KSA 化的 service account key
        selector:
          dnsZones:
            - "caep.uk"                         # 你的 zone
```

GCP Cloud DNS service account 需要 `roles/dns.admin` 在 hosting zone 的 project 上。
key 文件落到 K8s Secret,然后 `serviceAccountSecretRef` 引用。

#### ③ `enableGatewayAPI=true` + install order 这条铁律

**踩坑预警**: 我现在的 GKE 集群(GKE 1.28+) Gateway API CRD 是
`gke-gateway-api` channel(managed by GKE),cert-manager 是自己 helm 装的。
**Install 顺序必须是 Gateway API CRD 已有 → cert-manager helm install**。

**验证命令**:

```bash
# 1. Gateway API CRD 在?
kubectl get crd gateways.gateway.networking.k8s.io

# 2. cert-manager 起来后,日志里应该看到 "Gateway API enabled"
kubectl logs -n cert-manager deploy/cert-manager | grep -i "gateway"

# 3. 重启 controller 让它重新读 CRD(关键!)
kubectl rollout restart deployment cert-manager -n cert-manager
```

### 11.3 **不能** 用 cert-manager 的两处

| 位置 | 原因 |
|---|---|
| Tenant Project GLB | Tenant GLB 必须终结 TLS 给 Client,但 wildcard 不能用 Google Managed Cert;→ 改用 **Self-managed SSL cert (上传 wildcard 到 GCP)** 或 **第三方 CA + cert-manager 不在 GCP 跑**,然后上传 cert 到 GLB |
| PSC 内部跨项目 | PSC 不会端到端带 TLS 进去;**TLS 在 Tenant GLB 终结,内部 ILB 走明文**;Master 侧 nginx proxy_pass 也无 TLS,直到 K8s Gateway 才再终结一次 |

→ 真正需要 cert-manager 的**只有一环**:**Master Project 的 K8s Gateway**。
这一环覆盖之后,所有 HTTPRoute 后端应用都吃 wildcard 自动续期的红利。

## 12. 与现有 doc 的对照 + 引用清单

| 现有 doc | 与本文的关系 |
|---|---|
| `cloud/k8s/k8s-gateway/public-fqdn-explorer.md` | 上游架构(跨项目 + PSC + MIG nginx),本文是 K8s Gateway 层的 TLS 补完 |
| `cloud/k8s/k8s-gateway/tenant-namespace-k8s-gateway.md` | 多租户 Gateway 基础,本文的 cert-manager 是它的 TLS 一环 |
| `cloud/k8s/k8s-gateway/k8s-gateway-timeout.md` | Gateway timeout / retry,与 TLS 无关但在同一系列 |
| `cloud/k8s/k8s-tls-Opaque.md` | Secret 类型对比(`kubernetes.io/tls` vs `Opaque`),cert-manager 输出的是 `kubernetes.io/tls` |
| `gcp/cross-project/public-tls-ingress/` | Tenant GLB 终结 TLS,本文管不到 |
| `gcp/ingress/ingress-control.md` | 老的 Ingress controller 模式,Gateway API 是替代品 |

**外部引用**:

- cert-manager Gateway API guide: <https://cert-manager.io/docs/usage/gateway/>
- Gateway API security model: <https://gateway-api.sigs.k8s.io/concepts/security-model/>
- Let's Encrypt rate limits: <https://letsencrypt.org/docs/rate-limits/>
- 原文 Medium: <https://medium.com/@sanathw/securing-cross-namespace-routes-with-nginx-gateway-cert-manager-lets-encrypt-wildcard-https-7c0c721d0bf1>
- 作者源码: <https://github.com/sanathwaghela/codeify-hub/tree/main/nginx-fabric/cert-manager-letsencrypt>

---

**权威证据 / 最终定型依据**:

1. **原文(必引)** — Sanath Waghela, 2025-11-23, Medium。
   URL: <https://medium.com/@sanathw/securing-cross-namespace-routes-with-nginx-gateway-cert-manager-lets-encrypt-wildcard-https-7c0c721d0bf1>
2. **Let's Encrypt 官方文档**: <https://letsencrypt.org/docs/rate-limits/>
   → §9 的速率上限数字 (50/week, 5/week duplicate, 5/h fail) **直接来自
   这里**,不是原文二手转述。原文给的数字与官方一致。
3. **cert-manager Gateway API 官方用法**: <https://cert-manager.io/docs/usage/gateway/>
   → §3 的 `--set config.enableGatewayAPI=true` 含义 + 启动时只 check 一次的
   行为,官方文档明文: "the Gateway API is only enabled at start-up time"。
4. **CA/B Forum BR (Baseline Requirements) §3.2.2.4.6**: Wildcard certificate
   必须 DNS-01 (or equivalent DNS-based challenge),HTTP-01 不可用。这是 §2
   "HTTP-01 ❌ / DNS-01 ✅ for wildcard" 的根本依据,不靠原文。