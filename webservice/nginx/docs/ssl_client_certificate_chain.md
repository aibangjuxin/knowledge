ssl_client_certificate_chain 指令是 Nginx 中用来配置客户端证书验证的一个指令。它的作用是指定一个包含可信的 CA 证书链的文件，供 Nginx 在进行客户端证书验证时使用。这在 MTLS（双向 TLS）配置中非常重要，因为 MTLS 不仅要求服务器提供证书以验证身份，同时客户端也需要提供其证书，服务器将通过这个证书来验证客户端的身份。

  

**1. 模块功能：**

• ssl_client_certificate_chain 指令用于指定一个或多个证书文件，通常是一个 CA 证书链文件，Nginx 会使用它来验证客户端证书的有效性。

• 这对于 MTLS 来说是必须的，确保客户端的证书是由受信任的 CA 签发的。

• **典型场景：** 在启用 MTLS 的情况下，服务器会验证客户端的证书链，以确保客户端身份的真实性。

  

**2. 如何使用：**

  

假设你有一个包含多个 CA 证书链的文件 trusted_cas.pem，你可以在 Nginx 配置文件中使用该指令来指定这个证书链。

```
server {
    listen 443 ssl;

    ssl_certificate /path/to/server.crt;
    ssl_certificate_key /path/to/server.key;

    # 指定一个 CA 证书链文件用于验证客户端证书
    ssl_client_certificate_chain /path/to/trusted_cas.pem;

    # 启用客户端证书验证
    ssl_verify_client on;

    # 其他配置...
}
```

**关键点：**

• ssl_client_certificate_chain 指定的文件通常是一个 PEM 格式的证书文件，包含一个或多个受信任的 CA 证书链。

• 配置 ssl_verify_client on; 启用客户端证书验证。

• 当启用 MTLS 时，客户端在连接时会提供证书，Nginx 会使用指定的证书链来验证该客户端证书。

  

**3. 典型 MTLS 配置：**

  

如果你的配置需要启用 MTLS，除了配置 ssl_client_certificate_chain，你还需要设置以下几个指令：

```
server {
    listen 443 ssl;

    ssl_certificate /path/to/server.crt;
    ssl_certificate_key /path/to/server.key;

    # 指定客户端证书验证链
    ssl_client_certificate_chain /path/to/trusted_cas.pem;

    # 启用客户端证书验证
    ssl_verify_client on;

    # 配置证书验证级别，optional 表示客户端可以不提供证书
    ssl_verify_depth 2;

    # 定义客户端证书验证失败时的处理
    ssl_error_page 400 402 403 404 /path/to/error_page.html;

    # 其他配置...
}
```

• ssl_verify_depth 设置验证客户端证书链的深度。

• ssl_verify_client on 启用客户端证书验证，如果未提供有效证书，则会拒绝连接。

  

**4. 引入版本：**

  

ssl_client_certificate_chain 指令是从 **Nginx 1.13.8** 开始引入的。在此版本之前，Nginx 只支持 ssl_client_certificate，但没有直接的证书链验证功能。

  

**5. 工作流程的可视化：**

  

以下是一个简化的工作流程，展示如何通过 Nginx 配置 MTLS，并且如何利用 ssl_client_certificate_chain 来验证客户端证书：

```
+---------------------+        +--------------------+        +------------------------+
|   Client            |        |  Nginx Server      |        |  CA Certificate        |
|   (with Cert)       |  ----> |                    |  ----> |  Chain (trusted_cas.pem)|
|                     |        | - Verify client cert|        |                        |
+---------------------+        |   (ssl_client_certificate_chain) |                        |
                                | - SSL handshake    |        +------------------------+
                                | - MTLS Auth        |
                                +--------------------+
```

**简化流程：**

1. 客户端在建立连接时会提供自己的证书（客户端证书）。

2. Nginx 会验证客户端提供的证书是否由 trusted_cas.pem 中的 CA 签发。

3. 如果证书有效，Nginx 会允许连接；如果无效，则会根据 ssl_verify_client 的设置拒绝连接。

希望这个解释对你有帮助！如果有更多细节或者其他问题，随时告诉我！