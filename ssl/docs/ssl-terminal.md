我现在有这样一个需求：
我有分别两个域名，一个长域名,一个短域名
都是解析到谷歌的internal GLB 上面。GLB是一个Https的LB我GLB GLB 上面会配置短域名的证书，也会配置长域名的泛解析证书。下面仅仅是我测试的例子。 
短域名www.aibang.com 
用户API一般如下 https://www.aibang.com/api_name1 https://www.aibang.com/api_name2 我们是通过nginx的
Nginx HTTPS 反向代理配置 基于location path 来决定分发的也就是每个API有自己的location 且Location名称唯一其实也就是api_name唯一
```nginx.conf
location /api_name1 {
    proxy_pass https://gke-gateway.intra.aibang.com:443; # Nginx 解密完之后，又重新加密，再发给后端
    proxy_set_header Host www.aibang.com;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
 }

 location /api_name2 {
    proxy_pass https://gke-gateway.intra.aibang.com:443;
    proxy_set_header Host www.aibang.com;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
 }
```

长域名
api-name-team-name.googleprojectid.aibang.com
api-name2-team-name2.googleprojectid.aibang.com
api-name3-team-name3.googleprojectid.aibang.com
后面跟着一个Nginx MIG作为一个backend service 

旧的状态是目前配置如下
```nginx
server {
 listen 443 ssl;
 # 这个服务块只匹配这个域名的请求
 server_name api-name-team-name.googleprojectid.aibang.com;
 ssl_certificate /etc/pki/tls/certs/wildcard.cer;
 ssl_certificate_key /etc/pki/tls/private/wildcard.key;

 include /etc/nginx/conf.d/pop/ssl_shared.conf;

 location / {
    # 把请求反向代理转发到内部 GKE 网关地址
    proxy_pass https://gke-gateway-for-long-domain.intra.aibang.com:443;
    # 设置请求头，告诉后端是哪个域名的请求 转发时，把请求头的 Host 改成目标域名
    proxy_set_header Host api-name-team-name.googleprojectid.aibang.com;
    # 设置请求头，告诉后端是哪个 IP 发起的请求
    proxy_set_header X-Real-IP $remote_addr;
    # 设置请求头，告诉后端是哪个 IP 发起的请求
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
 }
}
```
按照我旧的模式来说，我还给我的长域名启用了一个单独的gke gateway ==> gke-gateway-for-long-domain.intra.aibang.com地址来承担其对应的工作。对于这个 HTTP route，也就是 Gateway 来说，我配置的是我的一个泛域名的证书。

对于我原来的短域名模式来说，我是配置了一个域名，使用了一个单独的 GKE Gateway ==> gke-gateway.intra.aibang.com地址来承载其工作。对于这个 HTTP Route（也就是 Gateway）来说，我配置的是我一个短域名的证书。


想要的一个配置 
如果我们替换proxy_set_header Host www.aibang.com作为一个新的状态
```nginx
server {
 listen 443 ssl;
 # 这个服务块只匹配这个域名的请求
 server_name api-name-team-name.googleprojectid.aibang.com;
 ssl_certificate /etc/pki/tls/certs/wildcard.cer;
 ssl_certificate_key /etc/pki/tls/private/wildcard.key;

 include /etc/nginx/conf.d/pop/ssl_shared.conf;

 location / {
    # 把请求反向代理转发到内部 GKE 网关地址
    proxy_pass https://gke-gateway.intra.aibang.com:443/api-name-team-name/;
    # 设置请求头，告诉后端是哪个域名的请求 转发时，把请求头的 Host 改成目标域名
    proxy_set_header Host www.aibang.com;
    # 设置请求头，告诉后端是哪个 IP 发起的请求
    proxy_set_header X-Real-IP $remote_addr;
    # 设置请求头，告诉后端是哪个 IP 发起的请求
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
 }
}
```




