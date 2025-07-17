你现在的目标是：

  

> **让 SAASP_Proxy 可以绕过原有的 ifpe（不再依赖它），而是通过新的公共 egress 出口，如一组已知公网代理（例如 intproxy.aibang.com:8080/8081/...）**。

  

下面我帮你详细拆解这个改造方案，以及如何落地。

---

## **✅ 方案目标简述**

|**项目**|**说明**|
|---|---|
|原始逻辑|Nginx 请求统一通过 ifpe 代理出公网|
|改造目标|动态或静态选择新的公共代理如 intproxy.aibang.com:8080|
|使用场景|你控制不了 ifpe，希望灵活接入更高可用的 proxy 路径|
|SAASP 可连接公网？|是（通过 proxy），但不能直接访问目标公网地址|

---

## **🛠️ 改造方式 1：**

## **按代理集群写死多个 proxy_pass 条目（静态方案）**

  

直接在 Nginx 配置中为 /login/ 匹配的请求指定一个备用 proxy 地址：

```
location /login/ {
    rewrite ^/login/(.*) ://login.microsoftonline.com/$1 break;
    rewrite ^://(.*)$ https://$1 break;

    # 使用新公网代理
    proxy_pass http://intproxy.aibang.com:8080;
}
```

> **多个代理地址使用不同 location 或 upstream 均可实现动态轮转：**

---

### **➕ 可选（改成 upstream 方式实现多代理）**

```
upstream proxy_pool {
    server intproxy.aibang.com:8080;
    server intproxy.aibang.com:8081;
    server intproxy.aibang.com:8082;
    # 可设置权重、最大失败次数等
}

location /login/ {
    rewrite ^/login/(.*) ://login.microsoftonline.com/$1 break;
    rewrite ^://(.*)$ https://$1 break;

    proxy_pass http://proxy_pool;
}
```

---

## **🛠️ 改造方式 2：**

## **在 SAASP Proxy 中使用 env 环境变量动态传入代理**

  

如果你要支持 curl、Java App 等走 HTTP_PROXY / HTTPS_PROXY，可以直接：

```
export HTTP_PROXY=http://intproxy.aibang.com:8080
export HTTPS_PROXY=http://intproxy.aibang.com:8080
```

然后运行的服务/应用直接走该代理出公网。

---

## **🔄 如果你还想** 

## **保留 fallback 到 ifpe 的功能**

## **？**

  

可以这样写：

```
map $login_backend $proxy_target {
    default http://intproxy.aibang.com:8080;
    "~^fallback$" http://ifpe.gcp.cloud.hk.aibang:3128;
}

location /login/ {
    rewrite ^/login/(.*) ://login.microsoftonline.com/$1 break;
    rewrite ^://(.*)$ https://$1 break;
    proxy_pass $proxy_target;
}
```

> 此时你只需要在请求头、或通过 query param 加个标识触发 fallback 到旧的 ifpe。

---

## **🔍 检查点清单（部署前确认）**

|**检查项**|**说明**|
|---|---|
|✅ intproxy.aibang.com 是公网代理？|确认这些地址是通公网的且稳定|
|✅ SAASP Proxy 有 outbound 权限？|如果处在 private network，需要通过 Cloud NAT 或 proxy 出口|
|✅ Nginx 支持 upstream 模块？|如果用轮转 proxy，则需要支持 upstream（默认有）|
|✅ 安全性控制？|是否需要在 intproxy 上做 IP 限制或认证（如 Basic Auth）|

---

## **✅ 总结图示（绕过 ifpe）**

```
flowchart TD
    GKE_Pod --> Nginx
    Nginx --> SAASP_Proxy
    SAASP_Proxy -->|proxy_pass| NewProxy[intproxy.aibang.com:8080]
    NewProxy --> CloudNAT
    CloudNAT --> Microsoft

    subgraph 目标
        Microsoft[login.microsoftonline.com]
    end
```

---

## **🧩 如果你还想让** 

## **intproxy.aibang.com**

##  **成为你自己可控的 GCP VM Squid 集群，也可以继续告知我，我可以提供完整 proxy 池的部署与负载均衡方案。**