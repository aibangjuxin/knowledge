什么是 HTTP Strict Transport Security (HSTS)？

HTTP Strict Transport Security (HSTS) 是一个安全功能，用于告知浏览器在特定时间内强制通过 HTTPS 访问站点，而不允许使用 HTTP。它可以有效防止中间人攻击（MITM）和协议降级攻击。

主要功能：
	1.	强制所有通信都使用 HTTPS 加密。
	2.	阻止用户无意中通过 HTTP 连接到服务器。
	3.	防止在首次连接时劫持未加密的 HTTP 请求。

在 Nginx 中启用 HSTS

可以通过在配置文件中添加以下指令启用 HSTS：
```yaml
server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
}
```
参数解释：
	•	max-age=31536000: 定义 HSTS 的有效期（秒），此处设置为一年。
	•	includeSubDomains: 将策略应用到主域名及其所有子域名。
	•	preload: 表示希望站点被加入到浏览器的 HSTS preload 列表（需手动提交到 HSTS preload list）。

Nginx 推荐的其他安全策略配置

1. 禁用不安全的协议和加密算法

通过优化 SSL/TLS 配置提高加密强度：
```yaml
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
```
解释：
	•	ssl_protocols: 禁用过时的 TLS 1.0 和 1.1，强制使用更安全的协议版本。
	•	ssl_ciphers: 使用强加密套件，排除弱加密（如 MD5）。
	•	ssl_prefer_server_ciphers: 优先使用服务器定义的加密套件。

2. 内容安全策略 (Content Security Policy, CSP)

CSP 可用于防止 XSS 攻击，通过限制可执行脚本来源：

`add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; object-src 'none';" always;`

解释：
	•	default-src 'self': 只允许加载本域资源。
	•	script-src 'self' 'unsafe-inline': 限制脚本来源，可根据需求移除 'unsafe-inline'。
	•	object-src 'none': 禁用插件对象（如 Flash）。

3. X-Frame-Options

防止点击劫持：

add_header X-Frame-Options "SAMEORIGIN" always;

解释：
	•	SAMEORIGIN: 仅允许同源站点嵌套。
	•	可用选项包括 DENY（禁止嵌套）和 ALLOW-FROM（指定允许的来源）。

4. X-Content-Type-Options

防止 MIME 类型混淆攻击：

add_header X-Content-Type-Options "nosniff" always;

解释：
	•	浏览器严格遵守内容类型声明，不自动猜测 MIME 类型。

5. Referrer-Policy

控制 HTTP 引荐来源头的行为：

add_header Referrer-Policy "no-referrer-when-downgrade" always;

常见选项：
	•	no-referrer: 不发送引用头。
	•	same-origin: 仅在同源请求时发送引用头。
	•	no-referrer-when-downgrade: 默认值，仅在 HTTPS 请求中发送。

6. 启用 HTTP/2

HTTP/2 提供更快的连接速度和安全特性：

listen 443 ssl http2;

7. 限制请求大小和频率

防止拒绝服务攻击 (DoS)：
```yaml
client_max_body_size 1M;
limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;

server {
    location / {
        limit_req zone=one burst=5 nodelay;
    }
}
```
解释：
	•	client_max_body_size: 限制单个请求的最大大小。
	•	limit_req_zone 和 limit_req: 设置 IP 限制请求速率。

8. 隐藏 Nginx 版本号

减少攻击面：

server_tokens off;

推荐完整配置示例
```yaml
server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # 启用 HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # 安全头配置
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; object-src 'none';" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;

    # 限制请求
    client_max_body_size 1M;

    # 隐藏版本号
    server_tokens off;

    location / {
        root /var/www/html;
        index index.html;
    }
}
```
总结

通过配置 HSTS 和其他安全策略，可以显著提高 Nginx 的安全性。以上配置涵盖了 HTTPS 加密、防御常见攻击以及优化安全头的多个方面，适用于生产环境。
