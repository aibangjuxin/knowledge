https-glb-pass-client.md

HTTPS GLB (Google Load Balancer) **不会直接传递完整的客户端证书**到后端服务。这是一个重要的技术限制需要注意。

当您使用 Google Cloud 的 HTTPS 负载均衡器时，它会终止 TLS 连接，这意味着：

1. GLB 会验证客户端证书（如果配置了 MTLS）
2. GLB 会建立一个新的 TLS 连接到您的后端服务
3. **原始的客户端证书不会被传递**到后端服务

但是，Google Cloud 提供了两种方式来处理这个限制：

### 方案 1: 使用 HTTP 头部传递证书信息

在 HTTPS 负载均衡器配置了 MTLS 的情况下，GLB 会将部分证书信息以 HTTP 头部的形式传递给后端：

- `X-Client-Serial-Number`: 客户端证书的序列号
- `X-Client-Subject-DN`: 客户端证书的主题 DN (Distinguished Name)
- `X-Client-Issuer-DN`: 签发客户端证书的 CA 的 DN

但**这不是完整的客户端证书**，只是证书的部分信息。

### 方案 2: 使用 TCP 负载均衡器（保持 TLS 透传）

如果您必须在后端服务（如 Nginx）中进行完整的客户端证书验证，您需要使用 TCP 负载均衡器而不是 HTTPS 负载均衡器：

- TCP 负载均衡器不会终止 TLS 连接
- 完整的 TLS 握手（包括客户端证书）会传递到后端服务
- 您的后端服务（Nginx）将负责 TLS 终止和客户端证书验证

### 结论和建议

基于您原来的架构和需求，如果您需要在 Nginx 中进行详细的客户端证书验证（如检查证书主题名称或其他高级验证），您有两个选择：

1. **使用 HTTPS GLB + 头部信息**：如果简单的证书信息（如主题 DN）足够满足您的验证需求，可以使用 HTTPS GLB 并在 Nginx 中检查相应的 HTTP 头部。

2. **保留 TCP GLB**：如果您需要完整的客户端证书以进行复杂验证，建议保留 TCP 负载均衡器，但您仍然可以使用 Cloud Armor 等其他 Google Cloud 安全服务进行额外保护。

如果您具体的验证需求是检查客户端证书的主题名称，方案 1 可能足够，因为 `X-Client-Subject-DN` 头部包含了这些信息。但如果您需要验证证书的其他部分或执行自定义验证逻辑，可能需要考虑方案 2。



# Client Authentication
 Cloud Load Balancing 之后的 Client Authentication（Also known as “Server TLS Policy”） 这个部分。

在 GCP 的 Server TLS Policy（也就是 HTTPS 负载均衡的 TLS 策略）中，可以指定 mTLS 认证，因此我假设你是通过 GLB 实现 mTLS 认证的。

⸻

进一步确认

我需要确认 以下两点 是否正确：
	1.	GLB 是否真的负责 Client 证书的验证？
	•	如果 GLB 负责 mTLS 认证，那么 GLB 必须配置 Server TLS Policy，并且必须在 Trust Store 里存储 CA 证书，以便验证客户端证书。
	•	你的架构中 Trust Store 放在 Client Authentication 之后，这意味着 GLB 可能已完成客户端证书验证，然后才将流量转发到后端。
	2.	如果 GLB 只是做 TLS 终结，而 Nginx 或其他组件负责 mTLS 验证？
	•	如果 GLB 仅做 普通 TLS 终结（不校验客户端证书），那么 Nginx 或 Squid Proxy 可能会执行 mTLS 验证，而不是 GLB。
	•	但在你的图中，Nginx 并没有特别标注 “mTLS Validation”，这让我进一步推测 GLB 可能执行了 mTLS 认证。

⸻

最终确认：你的 GLB 是否支持 mTLS？
	1.	请检查 GLB 的后端服务（Backend Service）配置
	•	如果 serverTlsPolicy 配置了 mtlsPolicy，那么 GLB 负责 mTLS 认证。
	•	你可以通过 GCloud 命令检查：

gcloud compute backend-services describe YOUR_BACKEND_SERVICE --global

其中，serverTlsPolicy 是否包含 mTLS 配置？

	2.	如果 GLB 只是 TLS 终结，Nginx 是否配置了 ssl_verify_client？
	•	在 Nginx 配置中：

ssl_client_certificate /etc/nginx/client-ca.pem;
ssl_verify_client on;


	•	如果 Nginx 负责 mTLS，GLB 只做 TLS 终结。

⸻

结论
	•	如果 GLB 确实配置了 serverTlsPolicy 并启用了 mTLS，那我的推测是正确的。
	•	如果 GLB 只是 TLS 终结，而 Nginx 或 Squid Proxy 执行了 mTLS 认证，那架构需要调整说明部分。

请确认 GLB 的 serverTlsPolicy 配置，然后我可以更新架构图！ 🚀