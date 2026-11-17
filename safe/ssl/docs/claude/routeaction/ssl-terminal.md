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

我现在调整了我的策略，我的核心需求是这样的 
长域名进来 → 透明代理 → 客户端地址栏不变 → 后端走短域名 path 逻辑 基于这个原则帮我探索，写一份新的、面向生产实施的透明代理版手册 命名为explorer-routeaction.md，你可以当前参考文档目录所有其他文档。 帮我完成我最原始的需求 类似这些步骤 1. 如何将 GLB 上面的域名进行 update 并绑定多个证书？  2. 我想创建一个新的 backend server 绑定到我的 Nginx 上面。这个新的 backend server 我想要参考原来运行的那个（也就是原来 Nginx 指定的那个）来创建。  3. 如果我以前没有通过 URL map 来管理对应的规则或配置，那么我现在如何创建对应的 URL map 规则？ 举例子的时候你可以考虑一下，比如说我以前的短域名下面有多个 API。你可以给我举两个 API 的例子，我都是“短域名 + API 名字”的形式，比如 API01 和 API02。  但在长域名情况下，因为是一个泛解析，可能有不同的域名进入到我的这个 GLB。所以： 1. 你的 URL map 可以按照这种格式帮我去生成或者写入。  3. 对于后端的 Nginx 配置，我需要做什么对应的调整？关于这一部分，你也可以给我一个或者比较多的例子，比如说两个。  你需要给出我具体的配置例子。因为我们不想在 Nginx 里面去做长域名的管理，目前我可以只考虑长域名进来之后做对应的mapping 让它访问到短域名上面对应的Path去 .把全部的控制放在 URL Map 里面。我想把所有的东西都在边缘节点 GLB 来实现。 因为我的目的（也就是核心目的）是要保持我原来的 Nginx 配置，即支持短域名和 proxy_pass 的这部分逻辑不改变，但同时又想支持长域名的用户进来之后 实现在不改变 URL 地址的情况下 同时支持长短域名访问到最终的API Nginx里面还不做调整.


# GLB URL Map RouteAction 实施方案：长域名透明代理，地址栏不变，后端复用短域名 Path 逻辑

> 核心原则：
>
> - 长域名进来
> - GLB URL Map 在边缘节点做 `routeAction.urlRewrite`
> - 客户端地址栏保持长域名不变
> - Nginx 继续复用原来的短域名 path 逻辑
> - 不在 Nginx 中管理长域名

---

## 1. Goal and Constraints

### 你的原始目标，收敛成一句话

把长域名入口统一放到 GLB 上处理，但不做 301/302 跳转，而是做透明代理。

### 目标拆解

1. 保持现有短域名链路继续可用：
   - `https://www.aibang.com/API01`
   - `https://www.aibang.com/API02`
2. 新增长域名入口，例如：
   - `https://api01-team01.googleprojectid.aibang.com`
   - `https://api02-team02.googleprojectid.aibang.com`
3. 长域名请求进入 GLB 后，不改变浏览器地址栏。
4. GLB 将长域名请求内部改写成短域名语义，再转发给原 Nginx。
5. Nginx 不负责长域名管理，不增加长域名 `server_name`。

### 本文适用前提

这个方案能做到“Nginx 不改长域名配置”，但要满足下面条件：

1. Nginx 现有短域名 `location` 已经存在。
2. 长域名最终要映射到的短域名 path 已经存在，或者可以直接复用已有 path。
3. GLB 转发给 Nginx 时，Nginx 允许接收 `Host: www.aibang.com` 这类短域名语义。

复杂度：`Moderate`



