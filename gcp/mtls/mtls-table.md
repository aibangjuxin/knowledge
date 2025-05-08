| 文档内容 | 是否在架构中实现？ | 说明 |
|---------|-----------------|------|
| Convert TCP Passthrough LB to Application HTTPS LB | ✅ 是 | 你的架构图显示 Cloud Load Balancing (GLB) 负责 TLS 终结，说明已从 TCP Passthrough LB 迁移到 HTTPS LB。 |
| Use Certificate Manager to store Root and Intermediate CA certs of client certificate | ✅ 可能是 | 你的架构中 Trust Store 显示 Trust Anchor (Root Cert) + Intermediate CA，这符合 Certificate Manager 的功能，但需要确认 GLB 是否真正调用了 Certificate Manager 来存储 CA 证书。 |
| Enable mutual TLS on HTTPS LB | ✅ 可能是 | 你的架构图标注了 Client Authentication ("Server TLS Policy")，这表明 GLB 可能 负责 mTLS 认证。但需要确认 serverTlsPolicy 是否包含 mtlsPolicy。 |
| Revise the Cloud Armor to implement Layer 7 protection | ✅ 是 | 你的架构图中，Cloud Armor 处于 GLB 之前，表明已用于 Layer 7 保护。 |
| Enable IP whitelist on Cloud Armor per Proxy API | ✅ 是 | Cloud Armor 可用于 IP 白名单管理，假设你的策略中已经实现了对 API 代理（Proxy API）的白名单控制。 |
| Perform client cert common name (FQDN) verification on Nginx per Proxy API | ✅ 可能是 | 你的架构图中 Nginx Reverse Proxy 没有明确标注 FQDN 验证，但如果你在 Nginx 中配置了 ssl_verify_client 并且验证了 FQDN，则这一步已实现。 |

**`networksecurity.googleapis.com` (Network Security API) 是在 Google Cloud 中配置和管理高级网络安全功能的核心 API，其中就包括了 `ServerTlsPolicy`。**

如果你需要在你的 Google Cloud 环境中使用 `ServerTlsPolicy` 来为你的负载均衡器（如外部 HTTPS 负载均衡器、内部 HTTPS 负载均衡器、SSL 代理负载均衡器）定义服务器端的 TLS 策略，那么你**必须启用 `networksecurity.googleapis.com` API**。

**`networksecurity.googleapis.com` API 主要用于以下功能：**

1.  **`ServerTlsPolicy`**:
    *   **定义服务器端 TLS 协商策略**: 允许你精细控制负载均衡器在与客户端建立 TLS 连接时所使用的 TLS 版本、密码套件和客户端证书验证模式。
    *   **增强安全性**: 通过强制使用强加密标准并禁用不安全的协议/密码，提高应用的安全性。
    *   **合规性**: 帮助满足特定的安全合规性要求。
    *   **mTLS (双向 TLS)**: `ServerTlsPolicy` 是配置负载均衡器进行客户端证书验证 (mTLS) 的关键部分。

2.  **`ClientTlsPolicy`**:
    *   **定义客户端 TLS 协商策略**: 当你的应用（例如，运行在 GKE 或 Compute Engine 上的服务）作为客户端去连接其他服务时，`ClientTlsPolicy` 允许你定义它在发起 TLS 连接时使用的 TLS 版本和密码套件。
    *   **Service Directory 集成**: 通常与 Service Directory 结合使用，为服务网格 (Traffic Director) 或其他客户端提供安全的出站连接。
    *   **mTLS**: 也可以用于配置客户端在发起连接时提供客户端证书。

3.  **`AuthorizationPolicy`**:
    *   **基于身份的授权**: 与 Envoy 代理（通常通过 Traffic Director 管理）结合使用，允许你根据 JWT (JSON Web Token) 中声明的身份来授权进入服务的请求。
    *   **精细访问控制**: 为你的微服务提供强大的、基于身份的访问控制。

4.  **Gateway Security Policy (与 Gateway Security Policy Rule)**:
    *   这是与 Cloud NGFW (Next-Generation Firewall) 相关的资源，用于定义更高级的威胁防护策略，例如入侵防御系统 (IPS)。

**如何启用 `networksecurity.googleapis.com` API？**

你有几种方式可以启用它：

*   **通过 Google Cloud Console**:
    1.  导航到 "APIs & Services" > "Library"。
    2.  搜索 "Network Security API"。
    3.  选择它并点击 "Enable"。
*   **通过 `gcloud` 命令行工具**:
    ```bash
    gcloud services enable networksecurity.googleapis.com --project=YOUR_PROJECT_ID
    ```
    将 `YOUR_PROJECT_ID` 替换为你的项目ID。
*   **通过 Terraform 等 IaC 工具**:
    在使用 Terraform 管理 Google Cloud 资源时，通常会在 `google_project_service` 资源中声明需要启用的 API。

**总结**

如果你计划使用 `ServerTlsPolicy`（例如，为你的外部 HTTPS 负载均衡器配置特定的 TLS 版本、密码套件或启用 mTLS），那么**启用 `networksecurity.googleapis.com` API 是一个必要的前提条件**。没有启用这个 API，你就无法创建、管理或将 `ServerTlsPolicy` 资源关联到你的负载均衡器。