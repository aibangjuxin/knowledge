你说得对：GLB（经典外部 HTTP(S) LB / External Application Load Balancer）的 URL Map 在 `urlRedirect` / `urlRewrite` 里目前只支持**静态字符串**，没有类似 Nginx 那种 `$host`、正则分组变量可以在目标 path 里动态拼接。shisho+1

## 现状：URL Map 的能力边界

- `urlRedirect` 支持：`hostRedirect`、`pathRedirect`（或 `prefixRedirect`）、`redirectResponseCode`、`stripQuery` 等，字段值都必须是字面量字符串。docs.cloud.google+1
    
- `urlRewrite` 支持：`pathPrefixRewrite` 或 `pathTemplateRewrite`，也只是“把请求路径改成固定前缀/模板”，不能引用 Host 或别的变量做字符串拼接。oneuptime+1
    
- 文档和社区问答里也没有提供“从 Host 动态提取前缀再拼成 redirect path”的语法，Stack Overflow 上类似问题最终都是用后端或 serverless 方案绕过。stackoverflow+1
    

## 常见替代方案思路

1. **交给后端（例如 Cloud Run / GCE / GKE / Nginx）做 30x**
    
    - URL Map 只做路由，把相关 Host 都打到一个后端服务。
        
    - 后端应用根据 `Host` 自己拼接 path 并返回 301/302。
        
    - 适合你已经有一套 Web / API 逻辑，可以顺手在入口层做 redirect。
        
2. **Serverless NEG + 轻量重定向服务**
    
    典型做法：
    
    - 建一个 Cloud Run / Cloud Functions / App Engine 小服务，逻辑类似：
        
        text
        
        `sub = host.split('.') redirect_to = "/"+ sub + request.path 301/302 -> redirect_to`
        
    - 在 GLB 上，把这些域名统一路由到一个 **Serverless NEG**，NEG 指向这个重定向服务。oneuptime+1
        
    - 这样 GLB 仍然是全局入口，动态逻辑完全由 serverless 代码控制。
        
3. **如果只是简单前缀规则，手动枚举**
    
    - 当前 URL Map 允许为每个 host 写一条 hostRule + pathRule，并在其中配置静态 `urlRedirect`，但必须一条一条写，无法“模板化”添加 host 前缀。googlecloudcommunity+1
        
    - 适合 host 种类非常有限（比如就几百个以内），且改动不频繁的场景。
        

## 小结

所以，“从 Host 动态抽前缀 → 拼成 redirect path”这种基于变量的 rewrite，GLB URL Map 本身目前确实做不到，只能通过后端 / serverless NEG 里的应用逻辑来实现动态重定向。stackoverflow+2

如果你能具体描述一下：

- Host 格式（比如 `foo.example.com` → `/foo/...` 还是更复杂？）
    
- 后端是 Cloud Run / GCE / GKE / 还是只想“纯托管、无服务器”
    

我可以给你一份**具体到 gcloud/terraform 配置 + Cloud Run 示例代码结构**的方案。