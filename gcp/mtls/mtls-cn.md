在 Nginx 中进行的 CN 校验，指的是对客户端证书中的 Subject（主题）字段中的 Common Name（CN）字段 进行检查，用于确认客户端身份。

⸻

🔍 什么是 CN（Common Name）？

在 X.509 客户端证书中，CN 是 Subject 字段的一部分，代表该证书绑定的客户端身份。

示例客户端证书的 Subject：

Subject: C=US, ST=California, L=San Francisco, O=ExampleCorp, CN=team-a-client

其中：
	•	CN=team-a-client 就是这个客户端证书的 Common Name
	•	它通常代表客户端的逻辑名称、系统身份、用户编号等
	•	在服务端，我们可以用 Nginx + njs 脚本等方式提取该 CN，并据此做访问控制或流量路由

⸻

✅ Nginx 中如何获取客户端证书的 CN？

Nginx 提供了 $ssl_client_s_dn 和 $ssl_client_s_dn_cn 变量：
	•	$ssl_client_s_dn：完整的 Subject DN 字符串
	•	$ssl_client_s_dn_cn：直接提取 CN 字段（若有）

示例配置（基于 map 实现访问控制）：

map $ssl_client_s_dn_cn $allowed {
    default           0;
    team-a-client     1;
    team-b-client     1;
}
server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_client_certificate /etc/nginx/ssl/ca.crt;
    ssl_verify_client on;

    if ($allowed = 0) {
        return 403;
    }

    location / {
        proxy_pass http://internal-service;
    }
}


⸻

🚦 示例场景：你提到的 “基于不同的 location 分配不同的 CN”

你可以这样配置：

server {
    listen 443 ssl;
    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;
    ssl_client_certificate /etc/nginx/ssl/ca.crt;
    ssl_verify_client on;

    location /team-a/ {
        if ($ssl_client_s_dn_cn != "team-a-client") {
            return 403;
        }
        proxy_pass http://squid-team-a;
    }

    location /team-b/ {
        if ($ssl_client_s_dn_cn != "team-b-client") {
            return 403;
        }
        proxy_pass http://squid-team-b;
    }
}


⸻

🔐 总结

名称	说明
CN (Common Name)	客户端证书中的通用名字段，标识客户端身份
提取方式	Nginx 中使用 $ssl_client_s_dn_cn 获取
校验方式	可通过 map、if、njs 等方式做认证路由
场景	实现基于证书身份的 ACL、认证、流量分发等


⸻

如果你希望基于更复杂的条件（比如 CN 前缀/正则匹配）实现 ACL，我可以为你写一个基于 njs 的中间层逻辑模板。是否需要？


你使用的命令输出的是证书的详细信息，其中：

openssl x509 -in isrgrootx1.pem -text -noout -subject -nameopt RFC2253

这个命令中关键信息如下：

Subject: CN=ISRG Root X1,O=Internet Security Research Group,C=US


⸻

🔍 那么这里的 CN 是什么？

在证书中，CN 表示 Common Name（通用名称），是证书主题（Subject）的一部分。它通常用于标识：
	•	对于 服务端证书（如 HTTPS 网站）：CN 通常是主机名或域名（如 www.example.com）。
	•	对于 客户端证书：CN 通常是用户名、设备名或其它身份标识（如 client1.example.com 或 John Doe）。
	•	对于 CA 证书（根证书）：如你例子中的 ISRG Root X1，CN 表示该 CA 的名字，比如 “ISRG Root X1”。

⸻

🔐 那在 Nginx 中做 mTLS 校验时，这个 CN 是校验哪个证书的？

在 Nginx 中开启 ssl_verify_client on; 并结合 ssl_client_certificate 指定受信 CA 后：
	•	Nginx 会校验客户端证书是否由受信任的 CA 签发。
	•	如果你使用如下配置：

ssl_verify_client on;
ssl_client_certificate /etc/nginx/ca.crt;

map $ssl_client_s_dn $authorized {
    default         0;
    ~CN=client-a    1;
    ~CN=client-b    1;
}

if ($authorized = 0) {
    return 403;
}

那么这里校验的 CN 就是客户端证书（Client Cert）的 Subject 字段里的 CN，如：

Subject: CN=client-a,O=example,C=US



⸻

✅ 示例总结

角色	CN 是什么
服务端证书	域名（如 www.example.com）
客户端证书	客户标识（如 client-a 或 device123）
CA 根证书	证书颁发机构名称（如 ISRG Root X1）

而你的示例中 Subject: CN=ISRG Root X1,... 是根证书的 Subject，表示这个证书是一个 CA 证书，名字叫 “ISRG Root X1”。

⸻

如需我帮你生成一段 nginx 配置进行 CN 匹配验证的完整样板，也可以告诉我客户端证书的结构。