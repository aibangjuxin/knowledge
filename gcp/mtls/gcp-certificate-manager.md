是的，在 Google Cloud HTTPS 负载均衡 (GLB) 的 MTLS 配置下，您需要管理客户端证书，而 Google 提供了一些产品来简化这个过程，包括 Google Cloud Certificate Manager 和 Google Cloud IAM 的 CA (Certificate Authority) 相关功能。

⸻

1. 你需要管理的证书类型

在 MTLS (Mutual TLS) 认证下，涉及两类证书：
	1.	服务器端证书：用于 HTTPS 服务器认证，由 GLB 终止 TLS 连接（Server-Side TLS）。
	2.	客户端证书：用于客户端身份验证（Client Authentication），GLB 需要验证客户端证书是否可信。

⸻

2. 适用的 Google Cloud 产品

| Google Cloud 产品 | 作用 |
| --- | --- |
| Google Cloud Certificate Manager | 用于管理 服务器端 SSL/TLS 证书，GLB 可直接引用此证书进行 HTTPS 终止 |
| Google Cloud Private CA | 创建和管理 客户端证书 (Client Certificates)，用于 MTLS 认证 |
| Cloud IAM Policy (Identity & Access Management) | 可配合 Private CA 实现更细粒度的访问控制，限制哪些客户端可以访问 |



⸻

3. 你的 MTLS 解决方案

(1) 服务器证书 (GLB 终止 HTTPS)：
	•	你可以使用 Google Cloud Certificate Manager 来管理 HTTPS 证书，并将其绑定到 GLB。
	•	GLB 终止 TLS 后，将解密的请求转发给后端。

(2) 客户端证书管理 (MTLS 验证)：
	•	你需要使用 Google Cloud Private CA 颁发客户端证书，并提供给受信任的客户端使用。
	•	在 GLB 的 SSL Policy 里启用 MTLS，并上传受信任的 根 CA 证书 (Root CA Certificate) 以便 GLB 进行客户端证书验证。

(3) 额外的安全策略
	•	Cloud Armor：用于基于客户端 IP、HTTP Header 或其他规则进行白名单管理。
	•	GLB 后端：GLB 可以在 HTTP Header 中传递 X-SSL-Client-Cert，Nginx 可以继续解析并进行额外的验证，例如主题名称检查。

⸻

4. 具体实现步骤

(1) 服务器端 HTTPS 证书
	1.	在 Google Cloud Certificate Manager 创建 HTTPS 证书：

gcloud certificate-manager certificates create my-server-cert \
    --domains=my-api.example.com \
    --managed


	2.	将证书绑定到 HTTPS 负载均衡：

gcloud compute ssl-policies create my-ssl-policy \
    --profile MODERN \
    --min-tls-version 1.2


	3.	配置 HTTPS 负载均衡并关联 SSL 证书。

⸻

(2) 客户端证书管理
	1.	创建 Google Cloud Private CA
```bash
gcloud privateca authorities create my-client-ca \
    --location=us-central1 \
    --tier=dev \
    --pool=my-cert-pool \
    --key-algorithm=rsa-pkcs1-4096-sha256
```

	2.	生成并签发客户端证书
```bash
gcloud privateca certificates create my-client-cert \
    --issuer-pool=my-cert-pool \
    --subject="CN=client.example.com,O=MyCompany" \
    --generate-key \
    --key-output-file=client-key.pem \
    --cert-output-file=client-cert.pem
```

	3.	将根 CA 证书上传到 GLB
```bash
gcloud compute ssl-policies update my-ssl-policy \
    --custom-ca-certs=root-ca.pem
```

	4.	在 GLB 启用 MTLS
```bash

gcloud compute target-https-proxies update my-proxy \
    --ssl-policy=my-ssl-policy
```



⸻

5. 后端 (Nginx) 配置

GLB 解析 HTTPS 后，会通过 X-SSL-Client-Cert 传递客户端证书：
```yaml
server {
    listen 443 ssl;

    ssl_certificate /etc/nginx/ssl/server.pem;
    ssl_certificate_key /etc/nginx/ssl/server-key.pem;

    location / {
        set $client_cert $http_x_ssl_client_cert;

        if ($client_cert ~ "CN=allowed-client") {
            # 允许访问
        }

        proxy_pass http://backend-service;
    }
}
```


⸻

6. 额外的 Cloud Armor 配置

你可以用 Cloud Armor 进行白名单控制：
```bash
gcloud compute security-policies rules create 1000 \
    --security-policy=my-policy \
    --expression="request.headers['X-SSL-Client-Cert'] =~ 'CN=allowed-client'"
```


⸻

7. 方案总结
	•	✅ GLB 负责 HTTPS 终止，并启用 MTLS 进行客户端身份验证。
	•	✅ Google Cloud Certificate Manager 管理 服务器证书。
	•	✅ Google Cloud Private CA 颁发 客户端证书，GLB 进行验证。
	•	✅ Cloud Armor 进行白名单和安全策略控制。
	•	✅ GLB 通过 X-SSL-Client-Cert 传递客户端证书到后端 Nginx，Nginx 进行额外检查。

这样，你的 HTTPS GLB 可以保持 原有的 MTLS 逻辑，并且大大简化了 nginx 的配置，不需要手动管理客户端证书，而是让 Google Cloud Private CA 来管理证书的颁发和验证。🚀