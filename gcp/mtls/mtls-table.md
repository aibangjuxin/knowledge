| 文档内容 | 是否在架构中实现？ | 说明 |
|---------|-----------------|------|
| Convert TCP Passthrough LB to Application HTTPS LB | ✅ 是 | 你的架构图显示 Cloud Load Balancing (GLB) 负责 TLS 终结，说明已从 TCP Passthrough LB 迁移到 HTTPS LB。 |
| Use Certificate Manager to store Root and Intermediate CA certs of client certificate | ✅ 可能是 | 你的架构中 Trust Store 显示 Trust Anchor (Root Cert) + Intermediate CA，这符合 Certificate Manager 的功能，但需要确认 GLB 是否真正调用了 Certificate Manager 来存储 CA 证书。 |
| Enable mutual TLS on HTTPS LB | ✅ 可能是 | 你的架构图标注了 Client Authentication ("Server TLS Policy")，这表明 GLB 可能 负责 mTLS 认证。但需要确认 serverTlsPolicy 是否包含 mtlsPolicy。 |
| Revise the Cloud Armor to implement Layer 7 protection | ✅ 是 | 你的架构图中，Cloud Armor 处于 GLB 之前，表明已用于 Layer 7 保护。 |
| Enable IP whitelist on Cloud Armor per Proxy API | ✅ 是 | Cloud Armor 可用于 IP 白名单管理，假设你的策略中已经实现了对 API 代理（Proxy API）的白名单控制。 |
| Perform client cert common name (FQDN) verification on Nginx per Proxy API | ✅ 可能是 | 你的架构图中 Nginx Reverse Proxy 没有明确标注 FQDN 验证，但如果你在 Nginx 中配置了 ssl_verify_client 并且验证了 FQDN，则这一步已实现。 |