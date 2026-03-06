


应用兼容风险：
- 固定 Host: www.aibang.com 短域名后，依赖原域名的服务可能出现重定向/CORS/Cookie 异常
- 是否所有 API 都有稳定且唯一的 path 前缀？ 这个决定了我们proxy的path 比如唯一且不能和原来已经存在的短域名path冲突 因为后面是同一个GKE Gateway
  - 新建单一 Gateway（或在现有短域名 Gateway 扩展）并加入全部 path 规则 进行模拟测试语法是否正常?
- 路由冲突：多个 API 前缀是否唯一，是否存在前缀覆盖/误匹配 
- 变更风险面：单 Gateway 发布错误会影响全部租户（blast radius 增大）。这个风险最小
- 
GLB TLS 终止
- 必须透传 X-Forwarded-Proto
- GLB 终止 TLS 后，后端拿到的是 HTTP 请求，需要靠这个头让后端知道原始是 HTTPS
```nginx
proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
```
- 有没有可能模拟头访问别人的API? 从安全角度帮我评估方案

GLB 终止客户端 TLS + 后端仍 HTTPS（合规场景,当然这个证书我们可以使用内部一套https证书）
GKE Gateway 收到的是"看起来像短域名请求的流量"，完全不感知长域名的存在。

3 个最关键的操作点
X-Original-Host 透传 → 解决 CORS/Cookie/审计问题（Host 被改写后后端失去原始域名）
HTTPRoute URLRewrite ReplacePrefixMatch: / → 剥离 Nginx 加的路径前缀，后端收到正确的 /v1/resource
GLB Backend Service protocol=HTTPS + HTTPS HealthCheck → 这是合规要求内部加密真正落地的关键配置

# 可能继续的探索
GLB 可以原生完成映射，可以不依赖 Nginx 做这件事
方式 A：GLB URL Map 处理映射 + 保留 Nginx（职责分离，最稳妥）

