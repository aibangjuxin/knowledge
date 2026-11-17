- 这篇文章详细阐述了 Squid 和 Nginx 如何做 SNI 的传递
  - [explorer-sni](../../webservice/explorer-sni.md)
- 这篇文章详细阐述了 TLS 的握手过程 explained
  - [tls-handshake-ascii-flow](./docs/tls-handshake-explained.md)
- 这篇文章详细阐述了 TLS 的握手过程
  - [tls-handshake-explained](./docs/tls-handshake-ascii-flow.md)



GLB hostRewrite API levels ==> mapping to httproute ==> need Verify at EIP support different *.team1.intra.domain support 


Reference:
- https://docs.cloud.google.com/load-balancing/docs/backend-authenticated-tls-backend-mtls



**结论**:**技术上完全可行**。Nginx 注入 SNI 是标准能力,配置如下:

```nginx
# /etc/nginx/nginx.conf(最小 demo,仅用于 §5.2 展示可行性)
# ⚠️ 这是早期 demo,完整最终版见 §5.10.2(粒度 A,按 location 分别加载 Team cert)
#
# =============================================================
# Master Nginx MIG — SNI 注入示例
# 关键指令:
#   proxy_ssl_server_name on  → 启用 SNI 注入(默认 off)
#   proxy_ssl_name <hostname> → 强制使用这个 hostname 作为 SNI
#   proxy_pass https://upstream  → 触发 TLS 重建
# =============================================================
server {
    listen 443 ssl;
    # Nginx 自己需要一张服务端 cert(接收 GLB 重建的 TLS)
    ssl_certificate     /etc/nginx/certs/master-nginx.crt;
    ssl_certificate_key /etc/nginx/certs/master-nginx.key;

    # ↓ 业务方原架构里这部分由 GLB 决定;现在 Nginx 接管
    location /team1apiname/ {
        # 强制 SNI = *.team1.intra.domain 的具体某值
        proxy_ssl_server_name on;
        proxy_ssl_name "team1apiname.team1.intra.domain";  # 或 *.team1.intra.domain 通配
        proxy_ssl_verify off;  # ⚠️ 内部网络,关闭 cert 验证;生产应开启
        proxy_pass https://master-k8s-gateway.intra.domain:443;
    }

    location /team2apiname/ {
        proxy_ssl_server_name on;
        proxy_ssl_name "team2apiname.team2.intra.domain";
        proxy_ssl_verify off;
        proxy_pass https://master-k8s-gateway.intra.domain:443;
    }
}
```