在Nginx中配置MTLS（Mutual TLS）时，通常不需要提供 `client.key` 文件。原因如下：

### 1. MTLS 认证所需的文件

在MTLS中，客户端和服务端都会进行身份验证。以下是配置MTLS时在Nginx需要的主要文件：

- **服务端证书和私钥**：
  - `server.crt`：服务端的公钥证书，用于加密客户端发送的数据。
  - `server.key`：服务端的私钥，用于解密客户端的数据。
- **客户端信任的证书**：
  - `ca.crt`：Nginx配置的CA根证书，用于验证客户端的证书是否由可信的CA签发。

### 2. `client.key`的用途

`client.key` 是客户端的私钥，在MTLS的认证过程中，客户端需要用它来解密服务端发送的数据包，并对数据签名以证明其身份。然而，这个文件是存储在客户端，而不是Nginx上。Nginx只需要`ca.crt`去验证客户端的证书是否合法，而不需要访问客户端的私钥文件。

### 3. 配置示例

以下是一个MTLS配置的示例，展示了Nginx中如何使用相关证书文件：

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    # 客户端证书验证配置
    ssl_client_certificate /etc/nginx/ssl/ca.crt;
    ssl_verify_client on;

    location / {
        proxy_pass http://backend;
    }
}
```

### 配置流程说明

- `ssl_certificate` 和 `ssl_certificate_key` 用于Nginx自身的TLS配置，确保服务端有公私钥对。
- `ssl_client_certificate` 用于指定可信的客户端CA证书，用来验证客户端证书的合法性。
- `ssl_verify_client on` 告诉Nginx开启客户端验证。

所以，在Nginx配置MTLS时，不需要提供 `client.key`。
