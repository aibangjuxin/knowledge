# `certificatemanager.googleapis.com` API 依赖关系

> 一句话:Certificate Manager API(服务名 `certificatemanager.googleapis.com`,REST 根
> `https://certificatemanager.googleapis.com`)是 GCP 集中管理 SSL/TLS 证书的服务
> 的**控制平面**。只有**真正调用过 Certificate Manager 资源**的服务 / 命令才会触发
> 这个 API 的依赖,启用它本身**不会**让任何 LB / GKE / Cloud Run 自动用它。

---

## 1. 这个 API 是什么

| 维度 | 内容 |
|---|---|
| API 服务名 | `certificatemanager.googleapis.com` |
| 启用命令 | `gcloud services enable certificatemanager.googleapis.com` |
| 控制台入口 | **Network Security → Certificate Manager** |
| 主要资源类型 | `Certificate` / `CertificateMap` / `CertificateMapEntry` / `TrustConfig` / `DnsAuthorization` |
| 跟旧 SSL Cert 资源的关系 | **替代**了 `compute.sslCertificates.*` 中"自管理 SSL 证书"的演进路线(2019 GA);旧的 `gcloud compute ssl-certificates create --domains=... --managed` 已不推荐 |
| 跟 Secret Manager 的关系 | **互不替代** — Cert Manager 管 cert 元数据 + 引用; Secret Manager 是通用 K/V,有时被 cert-manager-operator / External Secrets Operator 用来存非 GCP 签发的私钥 |
| 跟 GKE `cert-manager` 的关系 | **完全无关** — GKE cert-manager 是 Kubernetes 生态的 cert-manager.io,跟 GCP Certificate Manager 同名但不是同一个东西 |

**它是控制平面服务** — 启用后**只**意味着你可以用 `gcloud` / Console / Terraform
**管理** Certificate Manager 资源。**不启用它 ≠ 你不能用 HTTPS LB**,因为:

- **自管理 SSL 证书**走的是 `compute.sslCertificates.*`(传统 GLB 用)
- **Google 托管 SSL 证书**(Google-managed SSL certificates)也走 `compute.sslCertificates.*`
- 只有**用 `gcloud certificate-manager certificates create`** 创建的证书 / Map / TrustConfig 才走这个新 API

---

## 2. 依赖关系模型

GCP 服务之间的"依赖某个 API"有 3 层,容易混淆:

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: 启用 API (services.enable)                          │
│   决定 "我能不能创建这个服务的资源"                            │
│   例: 启用 certificatemanager.googleapis.com 才能用          │
│        `gcloud certificate-manager certificates create`     │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: 调用服务 (gcloud / Console / API)                   │
│   决定 "我创建的 GLB 资源引用哪个证书源"                      │
│   例: Target HTTPS Proxy 用旧 sslCertificates vs             │
│        用新 Certificate Manager (targetHttpsProxies 中       │
│        `certificateManagerCertificates` 字段)                │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: 资源引用 (Resource link)                            │
│   决定 "创建的证书 + 谁去消费它"                             │
│   例: target-https-proxy → certificate → certificateMap →   │
│       (backends)                                            │
└─────────────────────────────────────────────────────────────┘
```

**回答这个问题的关键:用户问的是 Layer 1 → Layer 3 之间的链路** —
"启用了 cert-manager API,哪些 GCP 服务会被影响?"

答案分两类:

- **直接消费者 (direct consumer)**:创建 / 引用 Certificate Manager 资源的服务
- **传递消费者 (transitive consumer)**:通过 IaC / 自动化 / Cloud Build / Terraform 间接用到

---

## 3. 直接消费者 [kb]

> **⚠️ 本节是 [kb] 级别的知识(2026-06 之前我对 GCP 公开文档的理解),未实时验证**。
> 实时答案请跑 §8 的 `gcloud services list` 命令获取。

下面这些 GCP 资源 / 服务在创建或操作时**会触发对 `certificatemanager.googleapis.com` 的调用**:

### 3.1 显式 / 强依赖(不启用 API 直接报权限错)

| 资源 / 命令 | 调用场景 | 备注 |
|---|---|---|
| `gcloud certificate-manager *` | 任何 cert-manager CLI | CLI 自身就调这个 API |
| **Target HTTPS Proxy** (External Application Load Balancer) | 当 `certificateManagerCertificates` 字段被设置时 | 新 GLB 链路的推荐做法 |
| **Target SSL Proxy** (External Network Load Balancer) | 当引用 cert-manager cert 时 | SSL 代理 LB |
| **URL Map** | 当 `--certificate-map` 被指定时 | 多域名 + cert map 路由 |
| **GKE Gateway API** (GKE 1.24+ GatewayClass `gke-l7-global-external-managed`) | 当 `tls.certificateRefs` 指向 cert-manager Secret 时 | Gateway 自动同步 cert 状态 |
| **Certificate Manager TrustConfig** | 任何 trust-configs CLI 操作 | mTLS 链路必需 |
| **Network Security Server TLS Policy** | `--mtls-policy` 引用 TrustConfig 时 | 间接通过 TrustConfig,启用 cert-manager 即可 |
| **Cloud Build / Terraform / Config Connector** | 当 IaC 模板里 `gcp_certificate_manager_*` 资源出现 | IaC apply 时调 |
| **Anthos Service Mesh (ASM) / Cloud Service Mesh** | mTLS 链路的 cert provisioning | 通过 cert-manager 子服务集成 |

### 3.2 弱依赖(常见交互,但老路径不强制)

| 资源 | 交互方式 |
|---|---|
| **Cloud Load Balancing 控制台** | 创建新 LB 时,Certificate 选项卡会显示 cert-manager 资源(可选用) |
| **Certificate Manager → Load Balancer 自动化**(2024+) | 创建 cert 时可一键 attach 到现有 LB |
| **Cloud Armor** | 跟 cert-manager 无直接 API 调用,但在 mTLS 链路上常组合 |

### 3.3 **不依赖**的服务(常见误判)

| 服务 | 为什么**不**依赖 |
|---|---|
| **Cloud Run** | 自己的 domain mapping + Serverless NEG,不走 cert-manager |
| **App Engine Standard** | 自己的 cert provisioning(基于 Google Trust Services) |
| **Firebase Hosting** | 自动 cert,Firebase 控制台管理 |
| **Google-managed SSL certificates**(旧 GLB) | 走 `compute.googleapis.com`,**不**走 cert-manager API |
| **Self-managed SSL certificates**(传统 GLB) | 同样走 `compute.googleapis.com` |
| **GCE VM 自身的 HTTPS** | 跟 GCP cert-manager 完全无关,VM 上跑 nginx 自己签 cert 即可 |

---

## 4. 传递消费者(IaC / 自动化路径)[kb]

如果你的环境用了**任意一种** IaC / 自动化,这个 API 可能被**间接**调用:

| 路径 | 何时调用 | 触发点 |
|---|---|---|
| **Terraform `google_certificate_manager_*` 资源** | `terraform apply` | 来自 `terraform-google` provider |
| **Config Connector** (`certificate-manager.*` CRD) | K8s apply | GKE 上的 GKE Config Connector |
| **Pulumi** | `pulumi up` | 来自 `gcp` provider,跟 Terraform 同底 |
| **Cloud Build** | build step 里 `gcloud certificate-manager ...` | CI/CD 流水线 |
| **Cloud Deploy** | 同上 | SDP pipeline |
| **Workload Identity 联邦的 CI** (GitHub Actions / GitLab / Argo) | 部署脚本里调 | 短时 token + cert-manager 调用 |
| **cert-manager.io Operator for GCP**(2023+ GA) | GKE 上跑 cert-manager,然后通过 ACME DNS-01 签 + 推到 Certificate Manager | 跟 GCP 原生 API 双向调用 |
| **Anthos Config Management** | 推送 CertManager manifests | 跨集群同步 |

**关键判断:如果你的环境根本没装这些 IaC / 自动化 / cert-manager-operator,enable
cert-manager API 几乎没有任何"副作用"。** 它只影响显式调用它的代码。

---

## 5. 什么时候**必须** enable

按从常见到罕见的顺序:

1. **你用了 `gcloud certificate-manager *` 创建 / 查询证书** — 100% 必须
2. **你的 Target HTTPS Proxy / Target SSL Proxy 引用了 `certificateManagerCertificates`** — 100% 必须
3. **你用 GKE Gateway API + GatewayClass `gke-l7-*` + `tls.certificateRefs` 指向 cert-manager Secret / CertificateMap** — 必须
4. **你在 GKE 上跑 `cert-manager.io` operator + `gcp-cert-manager-issuer`** — 必须
5. **你做 mTLS GLB**(`TrustConfig` + `ServerTLSPolicy` + `--mtls-policy`) — 必须
6. **Terraform / Config Connector / Pulumi 模板里出现 `google_certificate_manager_*`** — 必须
7. **你用 Anthos Service Mesh 的 cert provisioning 通过 cert-manager** — 必须

**简明判断口诀:**
> "代码里出现 `gcloud certificate-manager` / `google_certificate_manager_*` /
> `kubectl apply` cert-manager 资源 → 启用。否则不强制。"

---

## 6. 什么时候**可以 / 应该** 不 enable

- **只用老式 GLB**(`gcloud compute ssl-certificates create --managed` 配 Target HTTPS Proxy)— **不要** enable cert-manager API(浪费 IAM surface)
- **Cloud Run / App Engine / Firebase** — 跟 cert-manager 无关
- **临时调试 / 学习环境** — 避免在生产 project 启用未用到的 API(扩大攻击面,违反 least-privilege)

---

## 7. 启用 / 禁用命令 + 成本 + IAM

### 7.1 启用

```bash
gcloud services enable certificatemanager.googleapis.com \
  --project=YOUR_PROJECT_ID
```

### 7.2 禁用(谨慎,会**软删除**所有 Certificate Manager 资源 — 30 天 hard delete)

```bash
gcloud services disable certificatemanager.googleapis.com \
  --project=YOUR_PROJECT_ID
```

### 7.3 成本

- **API 调用本身免费**(`certificatemanager.googleapis.com` 调任何方法不计费)
- 资源存储免费
- **Google 托管证书($0)** — `gcloud certificate-manager certificates create --managed` 自动续费,无额外费用
- **你自上传的证书**:无存储费,但证书本身(从 CA 买的)要钱
- **真正的隐性成本**:**没有 LB 部署的"野生" cert-manager cert 也会持续 renew**,Google 也会发 HTTP-01 / DNS-01 challenge(注意 DNS 记录更新 / 暴露的 80 端口)

### 7.4 IAM 角色

| 角色 | 用途 |
|---|---|
| `roles/certificatemanager.owner` | 完整读写 + 删除 cert-manager 资源 |
| `roles/certificatemanager.editor` | 读写 |
| `roles/certificatemanager.viewer` | 只读 |
| `roles/certificatemanager.certManagerViewer` (旧) | 兼容老 IAM |
| `roles/certificatemanager.certRequester` | 限创建/请求 cert,**不能**配置 LB 引用(最小权限) |

**推荐:生产用 `certRequester` 角色给 cert 申请者(应用 owner),`owner` 角色只给
platform / SRE 团队。**

---

## 8. 验证 API 是否启用 + 看依赖关系(可执行脚本)

```bash
#!/bin/bash
# verify-cert-manager-api.sh
# 检查 cert-manager API 是否启用 + 列出 project 内所有依赖它的资源引用
set -e
PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"

echo "=== 1. API 启用状态 ==="
gcloud services list --enabled --project="$PROJECT" \
  --format='value(config.name)' 2>/dev/null \
  | grep -E "^certificatemanager\.googleapis\.com$" \
  && echo "✅ ENABLED" || echo "❌ NOT ENABLED"

echo
echo "=== 2. Project 内所有 cert-manager 资源数量 ==="
for r in certificates certificate-maps certificate-map-entries \
         trust-configs dns-authorizations; do
  COUNT=$(gcloud certificate-manager "$r" list --project="$PROJECT" \
    --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')
  printf "  %-30s %s\n" "$r" "$COUNT"
done

echo
echo "=== 3. 哪些 LB 在引用 cert-manager(看 target proxies) ==="
echo "--- Target HTTPS Proxies 引用 cert-manager certificates ---"
gcloud compute target-https-proxies list --project="$PROJECT" \
  --format='table(name,certificateManagerCertificates,sslCertificates)' 2>/dev/null \
  | head -20
echo
echo "--- Target SSL Proxies 引用 cert-manager certificates ---"
gcloud compute target-ssl-proxies list --project="$PROJECT" \
  --format='table(name,certificateManagerCertificates,sslCertificates)' 2>/dev/null \
  | head -20

echo
echo "=== 4. TrustConfig 关联(被 Network Security ServerTLSPolicy 引用) ==="
gcloud network-security server-tls-policies list --project="$PROJECT" \
  --location=global --format='table(name,mtlsPolicy)' 2>/dev/null | head -20

echo
echo "=== 5. GKE / ASM 是否在用 cert-manager ==="
echo "--- GKE Gateway CRD 中引用 cert-manager 的 Gateway ---"
kubectl get gateways -A -o custom-columns=\
'NS:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.gatewayClassName,CERTS:.spec.listeners[*].tls.certificateRefs[*].name' 2>/dev/null \
  | head -20
echo
echo "--- ASM 是否装了 cert-manager operator ---"
kubectl get pods -A -l app=cert-manager --no-headers 2>/dev/null | head -5

echo
echo "=== 6. 总结 ==="
echo "  看到非零行 = 项目内有 cert-manager 资源 / 引用,API 必启用"
echo "  全是 0 / N/A = cert-manager API 实际上没人在用,可考虑 disable(谨慎)"
```

**运行:**
```bash
chmod +x verify-cert-manager-api.sh
./verify-cert-manager-api.sh aibang-12345678-ajbx-dev
```

---

## 9. 跟相邻概念的区别速查

| 概念 | 是 / 不是 | 区别 |
|---|---|---|
| **Cert Manager API**(本文) | GCP 控制平面的 API service name | 启用后才可用 |
| **Certificate Manager**(产品名) | GCP 提供的证书管理服务 | 跟 API 是同一物,产品名 |
| **cert-manager.io**(Kubernetes 生态) | K8s 上的 cert-manager Operator | **不同** — K8s 上的 CRD + controller,跟 GCP 自己的 cert-manager 是两套 |
| **Google-managed SSL certs** (老 GLB) | 旧 `compute.sslCertificates` 资源里的 `--managed` 选项 | 走 `compute.googleapis.com`,**不**走 cert-manager API |
| **SSL Policy** (Network Security) | TLS 协议 / cipher 套件配置 | 跟证书管理**不同维度** — 决定"用什么 TLS 版本",不是"用什么 cert" |
| **Server TLS Policy** (Network Security) | mTLS 链路的 server 端策略 | 引用 TrustConfig,间接需要 cert-manager |
| **Private CA** (`privateca.googleapis.com`) | GCP 私有 CA 服务 | 跟 cert-manager 是**不同 API**,但 mTLS 链路常配对使用 |
| **Secret Manager** (`secretmanager.googleapis.com`) | 通用 K/V 密钥管理 | 偶尔被 cert-manager Operator 用来存私钥,但不是 cert-manager API 本身 |

---

## 10. 参考资料(权威入口)

- Certificate Manager 产品页: https://cloud.google.com/certificate-manager
- Certificate Manager docs hub: https://cloud.google.com/certificate-manager/docs
- REST API reference(v1): https://cloud.google.com/certificate-manager/docs/reference/rest
- gcloud reference: https://cloud.google.com/sdk/gcloud/reference/certificate-manager/
- mTLS 链路设计:https://cloud.google.com/load-balancing/docs/mtls
- gcp cert-manager vs K8s cert-manager 区分:https://cloud.google.com/certificate-manager/docs/overview

---

## 附录:本 doc 的局限声明

> 本 doc 写在 **2026-06-23**。直接消费者 / 传递消费者列表是基于我训练数据 + 之前
> 知识库积累的**静态稳态**理解,GCP 文档会随时间变化,新功能可能加入(比如
> 2024+ 的 `Certificate Issuance Policy`、2025+ 的 `Certificate Authority Service`
> 集成等)。
>
> **所有"哪个 service 依赖此 API"的结论,在你做生产决策前,请用 §8 的脚本在
> 你自己的 project 里实际跑一遍,或跑下面这条命令拿到 GCP 后端实时返回的依赖图:**
>
> ```bash
> # 这条命令直接问 GCP 后端"哪些 service 依赖 cert-manager API"
> # (可能在某些 project 不可用,如果没权限会报 403)
> gcloud services dependencies list \
>   --service=certificatemanager.googleapis.com \
>   --project=YOUR_PROJECT_ID
> ```
>
> 如果该命令在你的 project 里有输出,**那才是实时依赖图**,比本 doc 任何 [kb] 标记的
> 列表都权威。
