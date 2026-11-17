TODO:


# version 
- about Version ==> no license => 
    - /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/18-solo-distribution-vs-upstream-istio-comparison.md
    - https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/
    - Solo 分发的 Standard 镜像
      - 仓库:us-docker.pkg.dev/soloio-img/istio
      - tag:1.30.3-distroless
      - 不带 -solo 后缀 = 不需要 license
      - 但拿到 Solo 的 n-4 支持 + CVE 修复
    - no support
      - 1.30.3-solo-distroless = Solo 分发 + 额外 Envoy filters(为 Solo 企业功能准备)
      - 无 license 跑 = 跟 1.30.3-distroless 完全等价(额外 Envoy filters 不生效)
- gatewayClassName ==> using which one ?
        - waypoint support L7 ==> setup ?
        - 

# migration
- /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/11-l7-zero-downtime-constraint.md
- 通过简单的分析来看，要做到平滑迁移看起来不太可能。所以说我们有没有平滑迁移的机会？应该怎么去做？

# solo
- enable ambient
  - will no destination rule for traffic management
  - Ambient 模式让 DestinationRule 彻底消失,集群内加密被 ztunnel 透明接管,业务代码/镜像彻底解耦 TLS。
  - DestinationRule 资源调整（非常关键）
    - 旧模式：必须配置 TLS mode: SIMPLE 或 MUTUAL 来指引 Istio Gateway/Sidecar 向下游 Pod 发起 TLS 请求。
    - Ambient 模式：
        - 删除针对 Runtime 端口的 TLS 设置（或将其设为 DISABLE）。因为底层 ztunnel 会接管 L4 加密，应用层只需发送标准 HTTP。
        - 如果应用了 Ambient，Istio 控制面 (Pilot) 会通过 WDS 自动通知 Gateway 使用 HBONE 协议连接到 Ambient 节点。


- /Users/lex/git/knowledge/gcp/asm/serviceEntry-capabilities-and-use-cases.md
- /Users/lex/git/knowledge/gcp/asm/authorizationPolicy-capabilities-and-use-cases.md  
- /Users/lex/git/knowledge/gcp/asm/peerAuthentication-capabilities-and-use-cases.md



# ingress 
- internal 
- public ingress tls && mTLS 

# Kong 
- /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/20-solo-ambient-kong.md
  - 这里我增加了一个模式定义概念 也就是对我们旧的模式和新的模式做了一个简单的总结:
    - 原来的这套 Istio Gateway + ListenerSet + HTTPRoute 模式，在现代 Cloud Native / Gateway API 的体系下，属于标准的“多租户声明式应用网关”模式（Multi-Tenant Declarative Application Gateway Model），具体可以从以下几个维度来精确定义和总结：
    - 1. 架构与控制面维度：多租户网关与责任分离模式 (Multi-Tenant Gateway with Separation of Concerns)
  这是基于 Kubernetes Gateway API 标准构建的高级多租户架构：
      - 基础设施层 (Infra Team)：负责部署管理 Gateway 资源及底层控制器（Istio Pilot），定义全局的入口基础设施（如 IP、TLS 证书、全局网络等）。
      - 业务团队/租户层 (Tenant Teams)：通过 ListenerSet（或 Gateway API 的跨 Namespace 挂载能力）在各自的逻辑/应用隔离区内声明属于该 Team 的入口规则（域名通配符、端口、TLS 终止点等）。
      - API / 服务开发者 (Service Owners)：在自己的租户 Namespace 中编写 HTTPRoute，通过 parentRefs 将路由精准绑定到团队的 ListenerSet 上。
      - 这种架构打破了传统“单块集中式网关配置”的瓶颈，实现了控制面的声明式自治与多租户隔离。
    - 新的架构模式
      - 在 Ambient 模式下，Pod 间传输已被 ztunnel 自动加密 (HBONE / mTLS)，原本应用层（如应用自建 TLS 或 Envoy TLS Sidecar）的 HTTPS 需求被彻底解耦。
针对您的架构（KongDP 未开启 Ambient / 属于 Mesh 外或未打标 Pod，而 Runtime Pod 位于 Ambient 纳管的 Namespace 下，监听明文端口如 80 或 8443），
      - 下面是推荐的两个方案

        ```text
        2. KongDP 与 Ambient 结合的核心机制
        当 Runtime 卸载了应用层 HTTPS 改用明文端口（例如 80 或 8443）后，Kong 与 Ambient 的对接关键在于将 Kong 视作网关边界提供者（Client-to-Mesh Edge）：

        方案 A：KongDP 位于 Ambient Mesh 外部（推荐，架构最清晰）
        KongDP 的配置：Kong 保持部署在未标记 istio.io/dataplane-mode=ambient 的 Namespace 中。
        Upstream 目标：KongDP 的 upstream 直接填 Runtime 的 Kubernetes Service 域名与明文端口（例如 [http://app-service.110139-int.svc:80](http://app-service.110139-int.svc:80)）。
        流量穿透路径：
        Kong 发出普通的明文 HTTP 请求到 app-service:80。===> 对于这种模式来说，在我们的环境里面，其实就是在明文传输，这个安全风险是需要知晓的。
        流量离开 Kong 节点或进入 Runtime 宿主机时，Runtime 所在节点的 ztunnel 劫持入站流量。
        ztunnel 在入口自动将明文 HTTP 包打上 HBONE (mTLS) 隧道包，解密后投递给 Runtime 的 80 或 8443 端口。
        结果：Kong 自身完全无需关注任何 TLS/mTLS 逻辑，由 ztunnel 在节点侧静默完成加密与身份校验。
        方案 B：KongDP 也加入 Ambient Mesh
        如果将 KongDP 所在 Namespace 也打上 istio.io/dataplane-mode=ambient 标签：
        Kong 节点侧的 ztunnel 会建立 Kong ztunnel ➔ Runtime ztunnel 的直接 L4 HBONE 隧道。
        Kong 内部上游同样只需配置 http://app-service:80，所有节点间的传输将获得全透明的零信任 mTLS 保护。

        方案 B：KongDP 也加入 Ambient Mesh
        如果将 KongDP 所在 Namespace 也打上 istio.io/dataplane-mode=ambient 标签：
        Kong 节点侧的 ztunnel 会建立 Kong ztunnel ➔ Runtime ztunnel 的直接 L4 HBONE 隧道。
        Kong 内部上游同样只需配置 http://app-service:80，所有节点间的传输将获得全透明的零信任 mTLS 保护。
        ```

# egress 
- 我们传统的 egress 流量控制配置/Users/lex/git/gcp/linux/networking/nhf-flow.html
- /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/21-solo-ambient-egress-architecture.html
  - serviceEntry 资源
  - authorizationPolicy 资源


# feature
- file upload ==> dependency Envoy filter configuration?
- custom filter ==> 我们当前的一个解决方案，对于mTLS 的 CN 的校验是在这个里面实现的
- Here, each API is independent. To prevent drift between APIs, we’ve added an additional layer of validation that uses CN-based checks to route different APIs to their respective backends
- timeout
- websockets for internal and public ingress TLS or public ingress mTLS
    


# networkpolicy 
- /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/08-ambient-networkpolicy.md


# secret and configmap ? for migration 
- /Users/lex/git/gcp/gateway-2.0/k8s-gateway-ambient/22-ztunnel-mtls-and-cert-rotation.md