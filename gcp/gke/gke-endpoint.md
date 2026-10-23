# GKE 连接端点探索：DNS Endpoint 与 Central API Proxy

> 生成日期：2026-10-23 · 适用环境：GCP GKE 1.29+ / HGKE 私有集群 · 前提：通过公司出口代理或私网专用代理访问控制平面

---

## TL;DR

| 你听到的词 | 实际是什么 | 谁在把守入口 | 客户端 TLS 验证 |
| :--- | :--- | :--- | :--- |
| **GKE IP Endpoint（传统）** | 控制平面的 **IP 地址**（公网 IP 或 VPC 私有 IP），kubeconfig `server` 直接指向它 | Master Authorized Networks (MAN IP白名单) + K8s RBAC | 集群私有根 CA（kubeconfig 内置 `certificate-authority-data`） |
| **GKE DNS Endpoint** | GKE 给每个集群分配的**唯一 FQDN**（`*.gke.goog`），解析到 **Google Front End (GFE)** 公网 Anycast IP | **Google IAM**（`container.clusters.connect`）+ 可选 VPC-SC + K8s RBAC（**MAN IP白名单不生效**） | **公共商业 CA**（Google Trust Services，无需内置 CA 数据） |
| **Central API Proxy** | 通常指 **Connect Gateway**（`connectgateway.googleapis.com`）——Google 托管的中央反向代理，基于 Fleet Membership 统一纳管访问 | **Google IAM**（`gkehub.gateway.*`）+ 可选 VPC-SC + K8s RBAC | **公共商业 CA**（无需内置 CA 数据） |
| **公司公共代理 :3128** | **客户端所在网络**的 HTTP CONNECT 出口代理（Forward Proxy），用于打通办公网出外网 | 代理白名单 / ACL 规则 | 仅作为 TCP 盲隧道透传，不解密 TLS |
| **HGKE 专用代理 :3128** | 部署在客户 VPC Ingress MIG 上的 **Squid 反向/网关代理**，专门负责把内网管理请求中转到私有 API Server（`192.168.224.2`） | Squid ACL（来源 IP/目标 IP/端口） | 仅在传统无公网/无 DNS Endpoint 私有集群中使用 |

---

## 1. 为什么“以前没有看到 Endpoint 字段，有的环境突然有了”

在 `gcloud container clusters describe` 或 `get-credentials` 时，Endpoint 字段的表现与**集群配置的控制平面端点类型**及 **GKE 版本特性** 直接相关：

1. **版本与字段架构演进**：
   - **传统集群**：在 `describe` 输出中只有顶层的 `endpoint: <IP>`（公网 IP）或 `privateClusterConfig.privateEndpoint: <私网IP>`。
   - **新版集群（GKE 1.29+ 引入控制平面端点解耦）**：API 中引入了独立的结构体 `controlPlaneEndpointsConfig`，并支持配置基于 DNS 的端点（`dnsEndpointConfig`）。
2. **需要显式启用或特定参数触发**：
   - **基于 DNS 的端点不会无条件自动开启**，需要集群创建时或更新时显式传入 `--enable-dns-access`。未开启的集群在 `describe` 中该字段为 null 或不存在。
3. **`get-credentials` 的写入优先级**：
   - 若未显式加参数，`gcloud` 默认写入规则是：**外部公网 IP（若启用） → VPC 私网内部 IP（若为纯私有集群） → DNS 端点（仅当 IP access 被全部禁用时）**。
   - 只有显式指定了 `--dns-endpoint`，或者执行了 `--no-enable-ip-access` 禁用了 IP 访问，kubeconfig 的 `server` 才会变为 `https://*.gke.goog`。

```bash
# 查看集群控制平面端点完整配置（最推荐）
gcloud container clusters describe CLUSTER --location LOC \
  --format="yaml(controlPlaneEndpointsConfig)"

# 查看传统 IP 端点
gcloud container clusters describe CLUSTER --location LOC \
  --format="value(endpoint)"

# 查看 DNS 端点 FQDN（未开启时为空）
gcloud container clusters describe CLUSTER --location LOC \
  --format="value(controlPlaneEndpointsConfig.dnsEndpointConfig.endpoint)"
```

---

## 2. GKE DNS Endpoint 深度解析

### 2.1 底层工作机制与网络路径

- **唯一不可变的 FQDN**：形如 `gke-<hash>-<hash>.<region>.gke.goog`。
- **解析目标并非集群主机**：通过 `dig` 查询该域名，得到的是 **Google Front End (GFE) 的全球公网 Anycast IP**（如 `216.239.3x.xx`），与 `google.com` 或 `googleapis.com` 的接入网关同级。
- **请求处理流水线**：
  1. 客户端发送 TLS 请求到 `*.gke.goog:443`。
  2. GFE 前端使用标准公共证书（Google Trust Services）完成 TLS 握手。
  3. GFE 拦截并检验 HTTP Authorization 头中的 Google OAuth 2.0 Token，**通过 Google IAM 校验调用者是否具有 `container.clusters.connect` 权限**（同时校验 VPC-SC 服务边界策略）。
  4. 校验通过后，GFE 通过 Google 内部高可靠骨干网络将请求转发至集群控制平面的实际 API Server。
  5. API Server 再根据请求携带的身份执行 Kubernetes RBAC 鉴权。

### 2.2 与传统 IP 端点的全方位对比（含安全模型突变）

| 维度 | IP-based Endpoint（传统） | DNS-based Endpoint（新特性） |
| :--- | :--- | :--- |
| **kubeconfig `server`** | `https://<公网IP>:443` 或 `https://10.x.x.x:443` | `https://gke-xxx.<region>.gke.goog` |
| **TLS 证书链** | 集群自签根 CA，kubeconfig 必须带 `certificate-authority-data` | **公共商业 CA** 签发，kubeconfig **无需** CA 证书数据，任意标准客户端均信任 |
| **第一道鉴权门禁** | **网络层白名单（Master Authorized Networks，MAN ≤ 100条 CIDR）** | **身份层 IAM（`container.clusters.connect`）+ VPC-SC** |
| **⚠️ MAN IP 白名单有效性** | **有效**：不在 CIDR 白名单内的 IP 直接 TCP 拒绝 | **⚠️ 自动绕过 / 无效**：流量由 GFE 转发，MAN 白名单无法对 DNS 流量生效 |
| **私有集群免专线访问** | **不支持**：私网 IP 必须依赖 VPN / 专线 / 堡垒机 / VPC 内代理 | **支持**：只要客户端能连公网或 Google API，私有集群控制平面直接可达 |
| **防探测性** | 暴露在公网的 IP 会被端口扫描、漏洞探测 | **未携带有效 IAM Token 的请求一律被 GFE 403 拦截**，无法接触 API Server |

> [!WARNING]
> **安全模型关键转变**：
> 如果企业的合规规范硬性要求“必须通过 IP 来源白名单（CIDR）限制谁能访问 Kubernetes API”，**开启 DNS Endpoint 会让 MAN 白名单不再起作用**。此时必须用 **Google Cloud IAM 条件策略** 或 **VPC Service Controls (VPC-SC) 访问级别（Access Levels）** 来做来源 IP 范围管控。

### 2.3 启用、切换与配置实操

#### 先决条件
- GKE 版本 ≥ **1.29**。
- 集群网络模式必须为 **VPC-native**（基于别名 IP，老旧的 Routes-based 集群不支持）。

#### 命令操作

```bash
# 1. 存量集群开启 DNS access（不会中断现有 IP 访问）
gcloud container clusters update CLUSTER \
  --location=COMPUTE_LOCATION \
  --enable-dns-access

# 2. 生成指向 DNS 端点的 kubeconfig
gcloud container clusters get-credentials CLUSTER \
  --location=COMPUTE_LOCATION \
  --dns-endpoint

# 3. 授权运维人员/服务账号必需的 IAM 权限
# 预置角色：roles/container.developer 或 roles/container.viewer
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="user:engineer@company.com" \
  --role="roles/container.developer"

# 4.（可选进阶）彻底收敛暴露面：仅保留 DNS 端点，完全关闭传统公网/私网 IP 访问
gcloud container clusters update CLUSTER \
  --location=COMPUTE_LOCATION \
  --enable-dns-access \
  --no-enable-ip-access
```

---

## 3. "GCP Central API Proxy"：实为 Connect Gateway

在 GCP 体系中，被官方称为“中央 API 代理”的是 **Connect Gateway**（隶属 Google Cloud Fleet / GKE Hub 体系）。

```
kubectl
   │ (单一公共端点: connectgateway.googleapis.com)
   ▼
Connect Gateway (统一 IAM 鉴权、审计、配额限流)
   │ 
   ├──> Fleet Cluster A (prod-us)
   ├──> Fleet Cluster B (prod-eu)
   └──> Fleet Cluster C (on-prem / hybrid)
```

### 3.1 核心价值
- **多集群统一反向代理**：统一通过 `https://connectgateway.googleapis.com/v1/projects/<proj>/locations/global/gkeMemberships/<membership>` 进行路由。
- **免除每个集群单独暴露**：所有注册到 Fleet 的集群只需注册 membership，无需逐个配置端点和网络路由。
- **天然免堡垒机**：对私有 GKE 集群，Connect Gateway 会直接通过 Google 控制平面底层连接反向代理到 API Server，GKE 集群内无需安装 Agent。

### 3.2 怎么选：DNS Endpoint vs Connect Gateway

| 对比项 | GKE DNS Endpoint | Connect Gateway |
| :--- | :--- | :--- |
| **接入方式** | 每个集群一个专属域名（`gke-xxx.gke.goog`） | 全局单一接入点（`connectgateway.googleapis.com`） |
| **定位与粒度** | 单集群轻量级直连，平替传统堡垒机与私网代理 | 多集群企业级统一接入网关，平台团队集中审计与治理 |
| **依赖体系** | 单独启用，不需要开启 Fleet | 依赖 GKE Fleet (Hub) 注册 |
| **CI/CD 适用度** | 极佳，流水线只需配集群名称获取凭据 | 适合需要跨多集群统一调度与分发的运维平台 |

---

## 4. 公司内部代理与控制平面端点的拓扑叠加

在企业实际落地中，通常存在**两类不同角色的代理**，千万不要混淆：

```
【客户端视角】办公网开发机 / CI-CD Runner
      │
      │ 环境变量: HTTPS_PROXY=http://company-proxy:3128
      ▼
【公司公共出口代理】company-proxy:3128 (HTTP CONNECT 隧道)
      │
      ├───────────────────────────────┬───────────────────────────────┐
      │ 场景 A：走 GKE DNS Endpoint    │ 场景 B：走 Connect Gateway     │ 场景 C：传统私有 IP (无专线)
      ▼                               ▼                               ▼
Google GFE (gke-xxx.gke.goog:443)  Google Connect Gateway API       无法公网路由！必须转入：
      │ (IAM 鉴权)                     │ (IAM 鉴权)                    【HGKE 专属 Squid 代理:3128】
      ▼                               ▼                               (部署在 Ingress MIG: 10.88.27.179)
GKE 私有 API Server                 GKE 私有 API Server                     │ (Squid ACL 校验)
                                                                      ▼
                                                               GKE 私有 API Server (192.168.224.2)
```

### 客户端代理配置规范（对 kubectl / gcloud 均生效）

```bash
# 临时会话配置
export HTTPS_PROXY=http://company-proxy.corp.internal:3128
export HTTP_PROXY=http://company-proxy.corp.internal:3128
export NO_PROXY=localhost,127.0.0.1,.internal

# 验证通过代理能够建立与 GFE 的 TLS 盲隧道
nc -zv -X connect -x company-proxy.corp.internal:3128 gke-xxxx.region.gke.goog 443
```

---

## 5. 核心问题裁决：加了 DNS Endpoint 才能用“公共代理”吗？

### 结论
**是的，在没有专线打通私网的前提下，这句话在工程实践中完全成立。准确逻辑如下：**

1. **为什么过去必须用“自己的独立代理”（如 HGKE MIG Squid）**：
   - 以前的私有 GKE 控制平面只有一个私有 IP（如 `192.168.224.2` 或 `10.x.x.x`）。
   - 公司的公共代理处于办公网出公网的出口，**没有配置通往客户私有 VPC 的路由**，根本无法访问一个内网 IP。
   - 因此团队必须在客户私有 VPC 的双网卡 Ingress MIG 上单独搭一组代理（`10.88.27.179:3128`），先连入私网，再转发给控制平面。
2. **为什么加了 DNS Endpoint 就能直接用“公司公共代理”**：
   - DNS Endpoint（`gke-xxx.gke.goog`）解析出的是 **Google 公网 GFE IP**。
   - 公司的公共代理天然就是用来访问公网互联网的，只需要在代理白名单中放行 `*.gke.goog:443`。
   - 客户端通过公共代理建立一个简单的 HTTP CONNECT TCP 隧道，直接对接 GFE。所有的身份认证和访问控制由 Google IAM 在云端接管，**彻底干掉了对中间私有跳板机 / MIG 代理的维护依赖**。

---

## 6. 排障与自检清单

| 检查阶段 | 排查命令 / 步骤 | 异常表现与处理 |
| :--- | :--- | :--- |
| **1. 端点状态核实** | `gcloud container clusters describe CLUSTER --location LOC --format="yaml(controlPlaneEndpointsConfig)"` | 若无 `dnsEndpointConfig`，说明集群未升级或未开启 `--enable-dns-access`。 |
| **2. Kubeconfig 目标** | `kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'` | • 若为 `https://IP:443`：当前走 IP 模式。<br/>• 若为 `https://*.gke.goog`：当前走 DNS Endpoint。<br/>• 若为 `connectgateway.googleapis.com`：走 Connect Gateway。 |
| **3. IAM 权限排查** | 执行 `kubectl get ns` 返回 `denied: container.clusters.connect` | 账号缺少 GCP IAM 权限。需要补充 `roles/container.developer` 或单独赋予 `container.clusters.connect`。 |
| **4. 公司公共代理连通性** | `curl -x http://company-proxy:3128 -Iv https://gke-xxx.region.gke.goog/version` | • 若报 `403 Forbidden` 来自代理：说明公司公共代理未放行 `*.gke.goog:443`。<br/>• 若报 `403 Forbidden` 来自 GFE：属于正常现象（未带 Google OAuth Token 时的预设行为）。 |
| **5. MAN 白名单困惑** | 为什么配置了 Master Authorized Networks 依然可以从任意 IP 通过 DNS 连入？ | **这是预期行为**。DNS Endpoint 流量经由 GFE 转发，MAN 白名单天然被绕过。如需限制来源，请在 IAM 绑定加入条件（Condition）或配置 VPC-SC 访问级别。 |
| **6. 无法获取凭据** | `gcloud container clusters get-credentials` 报连接超时 | 客户端本地在取凭据时需要访问 `container.googleapis.com:443`，确保该域名已包含在代理的放行列表中。 |

