TrustConfig + Nginx 自定义证书信息路由

以下是整理好的 Markdown 文档，用于说明在 Google Load Balancer（GLB）上配置多个 mTLS 认证并通过 Nginx 进行请求路由的可行性与推荐实践：

⸻

多个 mTLS 认证配置在 Google Load Balancer 上的可行性与实践

背景

在多租户或多客户端环境下，存在不同客户端使用不同证书进行 mTLS 验证的场景。目标是在 Google Cloud HTTPS Load Balancer（GLB）上完成 mTLS 客户端认证，并将请求路由至后端 Nginx，根据证书信息转发至对应服务。

⸻

可行性分析

方法一：多个 TrustConfig + ServerTLSPolicy

项目	内容
描述	每个客户端证书使用不同的 CA 信任链（TrustConfig），并为每个服务配置独立的 ServerTLSPolicy 绑定不同的 TrustConfig
优点	安全隔离彻底，可根据证书完全分离后端服务
缺点	配置复杂，每个服务都需要独立的 Backend Service，LB 配置量大

适用场景：
	•	客户端间完全隔离；
	•	每个服务后端资源不同；
	•	管理维护成本可以接受。

⸻

方法二：单个 TrustConfig + Nginx 自定义证书信息路由（推荐）

项目	内容
描述	所有客户端证书由一个共同的 CA 签发，GLB 完成统一 mTLS 验证，并通过 HTTP Header 传递证书信息至后端 Nginx；Nginx 根据 Header 中的证书字段路由到不同服务
依赖 Header	x-goog-authenticated-user-cert-subject、x-goog-authenticated-user-cert-issuer
优点	配置简单、集中维护、便于扩展
缺点	所有客户端必须共享相同 Root/Intermediate CA

Nginx 示例配置：

map $http_x_goog_authenticated_user_cert_subject $client_cert_cn {
    default "unknown";
    ~CN=client-a\.example\.com "client-a";
    ~CN=client-b\.example\.com "client-b";
}

location /api/ {
    if ($client_cert_cn = "client-a") {
        proxy_pass http://backend-service-a;
    }
    if ($client_cert_cn = "client-b") {
        proxy_pass http://backend-service-b;
    }
}

适用场景：
	•	多个客户端共享一个 CA；
	•	后端为同一集群部署；
	•	希望集中管理证书和配置。

⸻

实践建议与总结

方案	可行性	推荐程度	使用建议
多个 TrustConfig + 多个 Backend Service	可行	中	适用于隔离要求高的服务部署
单个 TrustConfig + Header 路由	可行	高	推荐用于大部分统一管理的多租户场景



⸻

附加建议
	•	使用 Cloud Armor：结合 path matcher 与 source IP 白名单 可进一步增强安全性；
	•	在 Nginx 实现 CN 校验（如 $ssl_client_s_dn_cn）时，建议与上层 Header 验证形成冗余验证机制，防止被伪造；
	•	确保证书中包含必要字段（如 CN 或 SAN），便于规则精确匹配；
	•	结合日志记录客户端证书信息，方便追踪问题或审计；

⸻

如你有更复杂的场景（如客户端证书需动态分发、灰度路由等），也可以引入 API Gateway（如 Kong）进行更细粒度的控制。

是否需要我继续输出后续 Cloud Armor + Nginx 白名单控制策略的 Markdown？