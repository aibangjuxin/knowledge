- [CNAME](#cname)
- [**一、CNAME 的基本原理**](#一cname-的基本原理)
- [**二、企业使用 CNAME 的核心原因**](#二企业使用-cname-的核心原因)
  - [**1 解耦服务地址**](#1-解耦服务地址)
    - [**没有 CNAME**](#没有-cname)
    - [**使用 CNAME**](#使用-cname)
  - [**2 平台统一入口（API Gateway / LB）**](#2-平台统一入口api-gateway--lb)
  - [**3 跨系统 / 跨平台集成**](#3-跨系统--跨平台集成)
  - [**4 环境切换（非常常见）**](#4-环境切换非常常见)
  - [**5 多层架构抽象**](#5-多层架构抽象)
- [**五、CNAME 的限制**](#五cname-的限制)
- [**六、GCP 场景（与你的架构相关）**](#六gcp-场景与你的架构相关)
    - [**API 域名统一入口**](#api-域名统一入口)
- [**七、什么时候**](#七什么时候)
- [**不建议使用 CNAME**](#不建议使用-cname)
- [**八、企业 DNS 设计总结**](#八企业-dns-设计总结)
- [**一、典型架构**](#一典型架构)
- [**二、请求过程中的 Host header**](#二请求过程中的-host-header)
- [**三、TLS 证书使用哪个**](#三tls-证书使用哪个)
- [**四、Nginx 应该监听什么 Host**](#四nginx-应该监听什么-host)
- [**五、为什么不能监听 CDN 域名**](#五为什么不能监听-cdn-域名)
- [**六、CDN 可选配置（Origin Host Header）**](#六cdn-可选配置origin-host-header)
- [**七、证书部署的两种常见模式**](#七证书部署的两种常见模式)
  - [**模式1（最常见）**](#模式1最常见)
  - [**模式2（企业安全）**](#模式2企业安全)
- [**八、Google Cloud + CDN 常见配置**](#八google-cloud--cdn-常见配置)
- [**九、企业最佳实践总结**](#九企业最佳实践总结)
- [**十、一个很多人会忽略的坑（非常重要）**](#十一个很多人会忽略的坑非常重要)

# CNAME

企业 DNS 中大量使用 **CNAME（Canonical Name）** 是非常常见的设计，它的核心目的不是增加解析层级，而是 **解耦域名与真实服务地址，提升可维护性和灵活性**。下面从 DNS 工作原理和企业架构实践两个角度解释。

---

# **一、CNAME 的基本原理**

DNS 记录类型中：

| **记录类型** | **作用**          |
| ------------ | ----------------- |
| A            | 域名 → IPv4       |
| AAAA         | 域名 → IPv6       |
| CNAME        | 域名 → 另一个域名 |

例如：

```
api.team1.aibang     CNAME   gateway.platform.aibang
gateway.platform.aibang   A       34.120.10.5
```

解析流程：

```
graph TD
    A["Client DNS Query api.team1.aibang"] --> B["DNS 返回 CNAME gateway.platform.aibang"]
    B --> C["Client 再查询 gateway.platform.aibang"]
    C --> D["DNS 返回 A 记录 34.120.10.5"]
    D --> E["Client 连接目标 IP"]
```

确实会多一次解析，但通常 **DNS Resolver 会缓存**，性能影响非常小。

---

# **二、企业使用 CNAME 的核心原因**

## **1 解耦服务地址**

最重要的原因是 **IP 或后端地址变化时无需修改所有记录**。

例如：

### **没有 CNAME**

```
service1.api.aibang   A  34.120.10.5
service2.api.aibang   A  34.120.10.5
service3.api.aibang   A  34.120.10.5
```

如果负载均衡 IP 改变：

需要修改 **所有记录**。

---

### **使用 CNAME**

```
service1.api.aibang   CNAME   gateway.api.aibang
service2.api.aibang   CNAME   gateway.api.aibang
service3.api.aibang   CNAME   gateway.api.aibang

gateway.api.aibang    A       34.120.10.5
```

如果 IP 变化：

只修改

```
gateway.api.aibang
```

即可。

---

## **2 平台统一入口（API Gateway / LB）**

在 API 平台架构中非常常见。

例如：

```
order.team1.api.aibang    CNAME    api-gateway.company.net
user.team2.api.aibang     CNAME    api-gateway.company.net
```

真实入口：

```
api-gateway.company.net   A    GLB_IP
```

架构：

```
graph TD
    A["order.team1.api.aibang"] --> B["CNAME api-gateway.company.net"]
    B --> C["Google Cloud Load Balancer"]
    C --> D["Kong Gateway"]
    D --> E["Backend Service"]
```

优点：

- 所有 API 都走统一 gateway

- DNS 层保持灵活

---

## **3 跨系统 / 跨平台集成**

很多 SaaS 或 Cloud 服务要求：

**必须使用 CNAME 接入**

例如：

```
api.company.com   CNAME   service.vendor.com
```

原因：

- Vendor 需要控制后端 IP

- Vendor 可以动态扩展

例如：

- CDN

- WAF

- SaaS API Gateway

---

## **4 环境切换（非常常见）**

CNAME 可以用于 **环境切换**。

例如：

```
api.company.com   CNAME   api-prod.company.net
```

测试环境：

```
api.company.com   CNAME   api-stage.company.net
```

切换只需修改一条记录。

---

## **5 多层架构抽象**

大型企业 DNS 通常会分层：

```
service.team.api.company.com
```

DNS：

```
service.team.api.company.com  CNAME   api-gateway.company.com
api-gateway.company.com       CNAME   glb.company.net
glb.company.net               A       34.120.10.5
```

结构：

```
graph TD
    A["service.team.api.company.com"] --> B["api-gateway.company.com"]
    B --> C["glb.company.net"]
    C --> D["Load Balancer IP"]
```

这使得：

- API Gateway 可以迁移

- LB 可以更换

- DNS 结构保持稳定

---

# **五、CNAME 的限制**

使用 CNAME 时需要注意一些 DNS 规则。

| **限制**           | **说明**           |
| ------------------ | ------------------ |
| 不能与 A 记录共存  | 同一 hostname      |
| 不能用于 zone root | 例如 company.com   |
| 会多一次解析       | 但 resolver 会缓存 |
| TTL 影响切换速度   | TTL 设置很关键     |

---

# **六、GCP 场景（与你的架构相关）**

在 **GKE + Kong + GLB** 架构中，CNAME 常用于：

### **API 域名统一入口**

```
order.team1.api.aibang    CNAME   api-gateway.company.com
payment.team1.api.aibang  CNAME   api-gateway.company.com
```

真实入口：

```
api-gateway.company.com   A   GLB_IP
```

好处：

| **优点**       | **说明**         |
| -------------- | ---------------- |
| 域名自治       | 团队自己管理子域 |
| 平台统一入口   | 所有流量进入 GLB |
| 架构可迁移     | gateway 可替换   |
| DNS 修改最小化 | 改一条记录即可   |

---

# **七、什么时候**

# **不建议使用 CNAME**

如果域名就是 **最终入口**：

例如：

```
api.company.com
```

通常直接使用：

```
A
```

或

```
AAAA
```

避免额外解析。

---

# **八、企业 DNS 设计总结**

企业常见模式：

```
service.team.api.company.com
      │
      ▼
CNAME api-gateway.company.com
      │
      ▼
A GLB_IP
```

优势：

| **优点**     | **说明**              |
| ------------ | --------------------- |
| 解耦 IP      | IP 改变不影响业务域名 |
| 平台统一入口 | API Gateway           |
| DNS 可扩展   | 新服务只加 CNAME      |
| 易于迁移     | LB / Gateway 可替换   |

---

💡 **结合你当前 GKE + Kong + GLB 架构**，企业 DNS 通常会这样设计：

```
*.team.api.company.com
        │
        ▼
CNAME api-gateway.company.com
        │
        ▼
Google Cloud Load Balancer
        │
        ▼
Kong Gateway
```

---

如果你愿意，我可以再给你讲一个 **很多公司 DNS 设计的隐藏套路**：

> 为什么有些企业会出现 **三层甚至四层 CNAME 链**（看起来很复杂，但其实是为了支持 **多云 / 灰度发布 / 流量迁移**）。

这个在 **大型 API 平台架构**里其实非常经典，而且你在 GCP + Kong 场景以后很可能会用到。

这是 **CDN + Load Balancer + Nginx 架构**里非常关键的一个问题，本质涉及 **HTTP Host Header 与 TLS SNI 的传递规则**。结论先说：

> **Nginx 应该监听用户访问的原始域名（origin domain），而不是 CDN 域名。**

CDN 在正常配置下 **不会修改 Host header**，而是把用户访问的域名原样传给源站。

下面系统说明。

---

# **一、典型架构**

你的描述结构大致是：

```
Client
   │
   ▼
CDN
   │
   ▼
GLB (Google Cloud Load Balancer)
   │
   ▼
Nginx
   │
   ▼
Backend
```

DNS 可能是：

```
api.company.com   CNAME   cdn.vendor.net
```

---

# **二、请求过程中的 Host header**

用户访问：

```
https://api.company.com/v1/order
```

HTTP 请求：

```
GET /v1/order HTTP/1.1
Host: api.company.com
```

CDN 接收到请求后：

- **默认保留 Host header**

- 向源站发送请求

所以到达源站（GLB/Nginx）时仍然是：

```
GET /v1/order HTTP/1.1
Host: api.company.com
```

流程：

```
graph TD
    A["Client request Host=api.company.com"] --> B["CDN"]
    B --> C["Forward request Host=api.company.com"]
    C --> D["GLB"]
    D --> E["Nginx"]
```

---

# **三、TLS 证书使用哪个**

TLS 握手使用的是 **SNI(Server Name Indication)**。

客户端访问：

```
https://api.company.com
```

TLS SNI：

```
api.company.com
```

CDN 到源站的 TLS：

通常也是：

```
SNI = api.company.com
```

因此：

**源站证书必须匹配**

```
api.company.com
```

或者

```
*.company.com
```

而不是 CDN 的域名。

---



# **四、Nginx 应该监听什么 Host**



Nginx server block 应该配置：

```
server {
    listen 443 ssl;

    server_name api.company.com;

    ssl_certificate cert.pem;
    ssl_certificate_key key.pem;
}
```

如果有多个 API：

```
server {
    listen 443 ssl;
    server_name *.api.company.com;
}
```

---

这个问题涉及 **DNS 解析、HTTP Host Header、TLS SNI、Nginx vhost 匹配** 四个层面。关键结论先说：

  

> **客户端访问的原始域名才是 Host Header 和 TLS SNI，CNAME 目标不会出现在 HTTP 请求中。**

  

所以 **Nginx 应该监听的是用户访问的域名，而不是 CNAME 指向的域名**。

  

下面按请求链路解释。

---

# **一、DNS CNAME 只发生在解析阶段**

  

假设 DNS：

```
api.team1.aibang     CNAME    glb-entry.company.net
glb-entry.company.net    A    34.120.10.5
```

DNS 解析流程：

```
graph TD
    A["Client Query api.team1.aibang"] --> B["DNS 返回 CNAME glb-entry.company.net"]
    B --> C["Client 再查询 glb-entry.company.net"]
    C --> D["DNS 返回 IP 34.120.10.5"]
    D --> E["Client 连接 34.120.10.5"]
```

**注意**

  

此时客户端只是拿到了 IP。

  

客户端仍然认为自己访问的是：

```
api.team1.aibang
```

---

# **二、TLS SNI 使用的是原始域名**

  

客户端建立 TLS 时会发送 **SNI(Server Name Indication)**：

```
SNI: api.team1.aibang
```

Load Balancer / Nginx 根据这个选择证书。

  

因此：

|**项目**|**值**|
|---|---|
|DNS CNAME|glb-entry.company.net|
|TLS SNI|api.team1.aibang|
|证书 CN|api.team1.aibang 或 *.team1.api.aibang|

---

# **三、HTTP Host Header 也是原始域名**

  

HTTP 请求：

```
GET /order HTTP/1.1
Host: api.team1.aibang
```

不会变成：

```
Host: glb-entry.company.net
```

---

# **四、Nginx 实际看到的请求**

  

假设流量：

```
Client → GLB → Nginx
```

Nginx 收到的请求：

```
GET / HTTP/1.1
Host: api.team1.aibang
```

因此 Nginx server block 应该是：

```
server {
    listen 443 ssl;

    server_name api.team1.aibang;

    ssl_certificate /certs/team1.pem;
}
```

---

# **五、什么时候才需要监听 CNAME 目标**

  

只有一种情况：

  

用户 **直接访问 CNAME 目标域名**

  

例如：

```
https://glb-entry.company.net
```

这种情况下：

```
Host: glb-entry.company.net
```

Nginx 才需要监听它。

  

否则不需要。

---

# **六、GLB + Nginx + CNAME 的真实企业架构**

  

典型结构：

```
order.team1.api.aibang
payment.team1.api.aibang
```

DNS：

```
order.team1.api.aibang    CNAME    api-gateway.company.net
payment.team1.api.aibang  CNAME    api-gateway.company.net
```

GLB：

```
certificate:
*.team1.api.aibang
```

流量：

```
graph TD
    A["Client order.team1.api.aibang"] --> B["DNS CNAME api-gateway.company.net"]
    B --> C["Google Cloud Load Balancer"]
    C --> D["Nginx / Kong"]
    D --> E["Backend Service"]
```

Nginx：

```
server {
    server_name *.team1.api.aibang;
}
```

---

# **七、证书应该绑定在哪里（重要）**

  

如果 TLS 在 **GLB terminate**：

  

证书在 GLB：

```
*.team1.api.aibang
```

Nginx：

```
HTTP (内部)
```

如果 TLS **pass-through 到 Nginx**：

  

证书在 Nginx：

```
*.team1.api.aibang
```

---

# **八、很多人会误解的一点**

  

很多人认为：

```
api.team1.aibang CNAME glb-entry.company.net
```

请求会变成：

```
Host: glb-entry.company.net
```

其实 **不会发生**。

  

CNAME **只是 DNS alias，不是 HTTP redirect**。

---

# **九、一个真实生产例子（CDN）**

  

例如：

```
www.example.com CNAME d123.cloudfront.net
```

用户访问：

```
https://www.example.com
```

CloudFront 收到：

```
Host: www.example.com
```

证书：

```
www.example.com
```

而不是：

```
d123.cloudfront.net
```

---

# **十、在你这个 GKE + Kong + GLB 架构里的建议**

  

结合你现在的架构：

```
Client
   ↓
DNS (CNAME)
   ↓
GLB
   ↓
Nginx
   ↓
Kong
   ↓
RT Service
```

建议：

  

证书统一放在 **GLB**

  

例如：

```
*.team1.api.aibang
*.team2.api.aibang
```

Nginx/Kong 只根据：

```
Host Header
```

做路由。

---

如果你愿意，我可以再给你讲一个 **很多大型 API 平台都会踩的坑**：

  

**CNAME + Wildcard 证书 + GLB 多证书选择时的 SNI 匹配问题。**

  

这个问题在 **GCP + Kong API Gateway 架构里非常常见，而且会导致随机证书错误**。

# **五、为什么不能监听 CDN 域名**

假设 CDN 域名是：

```
cdn.vendor.net
```

如果 Nginx 只监听：

```
server_name cdn.vendor.net;
```

会出现：

| **问题**          | **原因**         |
| ----------------- | ---------------- |
| TLS mismatch      | SNI 不匹配       |
| Host routing 错误 | Host header 不同 |
| CDN 回源失败      | 证书验证失败     |

因为客户端访问的始终是：

```
api.company.com
```

---

# **六、CDN 可选配置（Origin Host Header）**

很多 CDN 允许修改回源 Host。

例如：

```
Origin Host Header
```

可以配置：

| **选项**     | **说明**          |
| ------------ | ----------------- |
| Pass through | 使用用户原始 Host |
| Override     | 使用指定 Host     |

如果 override：

```
Host = origin.company.internal
```

那 Nginx 就要监听：

```
server_name origin.company.internal;
```

但企业通常 **不会这么做**。

---

# **七、证书部署的两种常见模式**

## **模式1（最常见）**

TLS 终止在 CDN。

```
Client TLS
   │
   ▼
CDN (TLS termination)
   │
   ▼
HTTP
   │
   ▼
Origin
```

Origin 不需要证书。

---

## **模式2（企业安全）**

TLS 双端。

```
Client TLS
   │
   ▼
CDN
   │
   ▼
TLS
   │
   ▼
Origin
```

这时：

Origin 证书必须匹配：

```
api.company.com
```

---

# **八、Google Cloud + CDN 常见配置**

在 GCP 架构里通常是：

```
Client
   │
   ▼
Cloud CDN
   │
   ▼
GLB
   │
   ▼
Nginx
   │
   ▼
Kong
```

Nginx 配置：

```
server {
    listen 443 ssl;
    server_name api.company.com;
}
```

证书：

```
*.company.com
```

---

# **九、企业最佳实践总结**

| **项目**          | **推荐**         |
| ----------------- | ---------------- |
| Host header       | 原始域名         |
| Nginx server_name | 原始域名         |
| Origin 证书       | 原始域名证书     |
| CDN 域名          | 不需要出现在源站 |

简单记住一句话：

> **源站只需要认识用户访问的域名，不需要认识 CDN 的域名。**

---

# **十、一个很多人会忽略的坑（非常重要）**

如果你使用 **Google Cloud Load Balancer + CDN**，需要注意：

GLB 的证书匹配 **也是基于 SNI**。

所以 GLB 必须配置证书：

```
api.company.com
```

否则会出现：

```
SSL handshake failed
```

即使 CDN 在前面。

---

如果你愿意，我可以帮你画一个 **完整的 CDN → GLB → Nginx → Kong 的 TLS / Host / SNI 传递图**。

这个图能一次性解释清楚 **证书在哪终止、Host 如何传递、SNI 如何匹配**，很多做 API 平台的人第一次看都会突然完全理解整个链路。
