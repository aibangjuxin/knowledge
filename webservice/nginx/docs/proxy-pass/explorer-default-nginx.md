# Explorer: Default Nginx Front Door to ASM Load Balancer

## 1. Goal and Constraints

### Your Goal

你要做的是一个 7 层 Nginx 前置入口，职责如下：

1. 默认接收外部 HTTPS 请求。
2. 默认把请求 `proxy_pass` 到同一个 GKE ASM 对外暴露的 Load Balancer 入口。
3. Nginx 需要把外部域名改写为 ASM 统一识别的内部 `Host`，以便后面的 Gateway / VirtualService / Route 统一命中。
4. 大多数租户或 API 走默认限制：
   - 上传大小默认 `30M`
   - 超时默认 `60s`
5. 少数 API 有特例：
   - 例如 `components.team.app.aibang` 需要 `50M`
   - 超时 `300s`
6. 请求全部是 HTTPS。
7. 不同 team 可能使用不同泛证书：
   - `*.team.app.aibang`
   - `*.team2.app.aibang`

### Problem Classification

- 架构: 多租户入口设计
- 网络: L7 反向代理到 ASM LB
- 安全: HTTPS 证书、Host 改写、透传真实来源头
- 运维: 默认配置与少数例外配置共存

### Immediate Fix

先做一个可维护的默认 Nginx 模板，支持：

- 默认所有请求进 ASM LB
- 默认超时/Body 限制
- 少数 host 或 path 做覆盖

### Structural Improvement

不要把所有差异写死在多个 `server/location` 里，建议用：

- 公共 `snippets`
- `map` 做 host/path 维度覆盖
- 每个泛域名单独一个 `server`

### Long-term Redesign

如果未来 team 数量继续增长，建议把“team 到证书、team 到上游 Host、team 到限制参数”的关系外置生成，使用模板渲染配置并 CI 校验后 reload。

Complexity: `Moderate`

---

## 2. Recommended Architecture (V1)

### Traffic Flow

```text
Client
  -> HTTPS request to *.team.app.aibang / *.team2.app.aibang
  -> Nginx L7
     - terminate TLS
     - select wildcard cert by server_name
     - apply default limits
     - apply host/path-based overrides
     - rewrite Host to internal ASM gateway host
     - forward X-Forwarded-* headers
  -> ASM Load Balancer IP
  -> ASM Gateway / Istio ingress
  -> internal routes/services
```

### V1 Design Decision

推荐采用下面的设计：

1. 用多个 `server` 块承接不同 team 的泛证书。
2. 所有 `server` 块复用同一套 `proxy_common.conf`。
3. 用 `map` 根据 `$host` 或 `$host:$uri` 决定：
   - 内部统一 Host
   - `client_max_body_size`
   - `proxy_read_timeout`
   - `proxy_send_timeout`
4. `proxy_pass` 统一打到 ASM LB 的同一个 HTTPS 地址。

### Important Risk

如果你直接 `proxy_pass https://<ASM_LB_IP>`，但 ASM 入口证书不是给这个 IP 签发的，TLS 校验会有问题。

生产建议二选一：

1. 最好给 ASM LB 一个内部 DNS 名称，例如 `asm-gateway.internal.aibang`，然后 `proxy_pass https://asm-gateway.internal.aibang:443;`
2. 如果必须走 IP，至少明确设置：
   - `proxy_ssl_server_name on;`
   - `proxy_ssl_name asm-gateway.internal.aibang;`

否则你只是 TCP 连到了 IP，但 TLS SNI 和证书校验可能不匹配。

---

## 3. Directory Layout

```text
/etc/nginx/
  nginx.conf
  conf.d/
    maps/
      asm-defaults.conf
      asm-overrides.conf
    snippets/
      proxy-common.conf
    servers/
      team-app-aibang.conf
      team2-app-aibang.conf
```

---

## 4. Suggested Nginx Configuration

### 4.1 Global `http {}` Level Maps

文件: `conf.d/maps/asm-defaults.conf`

```nginx
# 默认转发到 ASM 统一入口 Host
map $host $asm_internal_host {
    default                            asm-gateway.internal.aibang;
}

# 默认请求体大小
map $host $tenant_client_max_body_size {
    default                            30m;
}

# 默认超时
map $host $tenant_proxy_read_timeout {
    default                            60s;
}

map $host $tenant_proxy_send_timeout {
    default                            60s;
}

map $host $tenant_proxy_connect_timeout {
    default                            10s;
}
```

文件: `conf.d/maps/asm-overrides.conf`

```nginx
# 针对特定 host 做覆盖
map $host $asm_internal_host_override {
    default                            $asm_internal_host;
    components.team.app.aibang         components-internal.asm.aibang;
}

map $host $tenant_client_max_body_size_override {
    default                            $tenant_client_max_body_size;
    components.team.app.aibang         50m;
}

map $host $tenant_proxy_read_timeout_override {
    default                            $tenant_proxy_read_timeout;
    components.team.app.aibang         300s;
}

map $host $tenant_proxy_send_timeout_override {
    default                            $tenant_proxy_send_timeout;
    components.team.app.aibang         300s;
}

# 如果你未来要细到 path 级别，建议用 host:uri 组合
map $host:$uri $tenant_body_size_by_host_uri {
    default                            $tenant_client_max_body_size_override;
    components.team.app.aibang:/upload 50m;
}

map $host:$uri $tenant_read_timeout_by_host_uri {
    default                            $tenant_proxy_read_timeout_override;
    components.team.app.aibang:/upload 300s;
}

map $host:$uri $tenant_send_timeout_by_host_uri {
    default                            $tenant_proxy_send_timeout_override;
    components.team.app.aibang:/upload 300s;
}
```

说明：

- 如果你的“特例”是整个域名级别，就只用 `$host`。
- 如果你的“特例”只是某个 API 路径，例如 `/upload`，就用 `$host:$uri`。
- 这种方式比到处写 `location` 更容易维护。

---

### 4.2 Common Proxy Snippet

文件: `conf.d/snippets/proxy-common.conf`

```nginx
proxy_http_version 1.1;
proxy_set_header Connection "";

# 发给 ASM 统一入口的 Host
proxy_set_header Host $asm_internal_host_override;

# 保留原始访问上下文，便于 ASM / backend 审计和生成回跳链接
proxy_set_header X-Real-IP         $remote_addr;
proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host  $host;
proxy_set_header X-Forwarded-Port  $server_port;

# 可选：如果后端需要识别原始 Host
proxy_set_header X-Original-Host   $host;
proxy_set_header X-Original-URI    $request_uri;

# 指向 ASM LB 的 TLS 行为
proxy_ssl_server_name on;
proxy_ssl_name $asm_internal_host_override;

proxy_connect_timeout $tenant_proxy_connect_timeout;
proxy_read_timeout    $tenant_read_timeout_by_host_uri;
proxy_send_timeout    $tenant_send_timeout_by_host_uri;

# 上传和大响应常见场景
proxy_request_buffering on;
proxy_buffering on;
```

---

### 4.3 Team 1 Wildcard Server

文件: `conf.d/servers/team-app-aibang.conf`

```nginx
server {
    listen 443 ssl http2;
    server_name *.team.app.aibang;

    ssl_certificate     /etc/nginx/certs/team.app.aibang/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/team.app.aibang/privkey.pem;

    # 如果只允许这个泛域名下的具体 host，可以加白名单 map 或者单独 server_name

    client_max_body_size $tenant_body_size_by_host_uri;

    location / {
        include /etc/nginx/conf.d/snippets/proxy-common.conf;

        # 方式 A: 推荐使用内部 DNS 名称
        proxy_pass https://asm-gateway.internal.aibang:443;

        # 方式 B: 如果必须使用 ASM LB IP，则改成下面这种
        # proxy_pass https://10.10.10.10:443;
    }
}
```

---

### 4.4 Team 2 Wildcard Server

文件: `conf.d/servers/team2-app-aibang.conf`

```nginx
server {
    listen 443 ssl http2;
    server_name *.team2.app.aibang;

    ssl_certificate     /etc/nginx/certs/team2.app.aibang/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/team2.app.aibang/privkey.pem;

    client_max_body_size $tenant_body_size_by_host_uri;

    location / {
        include /etc/nginx/conf.d/snippets/proxy-common.conf;
        proxy_pass https://asm-gateway.internal.aibang:443;
    }
}
```

---

## 5. Example for Your Case

如果你要监听：

- `components.team.app.aibang`

默认行为：

- 上传限制 `30M`
- 超时 `60s`
- 转发到 ASM
- `Host` 改写为统一内部 Host

但这个域名有上传特例，需要：

- 上传限制 `50M`
- 超时 `300s`

那么上面的 `map` 已经能表达这个需求。

对于该请求：

```text
https://components.team.app.aibang/upload?fileId=123
```

Nginx 最终会按类似下面的逻辑发给 ASM：

```text
Upstream target: https://asm-gateway.internal.aibang:443/upload?fileId=123
Host header: components-internal.asm.aibang
X-Forwarded-Host: components.team.app.aibang
client_max_body_size: 50m
proxy_read_timeout: 300s
proxy_send_timeout: 300s
```

---

## 6. Why This Design Is Better

### Good

1. 默认值集中管理，绝大多数租户不用重复写配置。
2. 少数特例通过 `map` 覆盖，不污染主 `server` 块。
3. 支持不同 team 用不同泛证书。
4. 支持把外部域名统一转成 ASM 内部 Host。
5. 后续扩展到更多 team 时，只需要继续加映射和 `server` 文件。

### Not Recommended

不建议一开始就这样做：

1. 每个 API 一个 `server` 块
2. 每个特例一个 `location` 块
3. 把所有 `proxy_set_header` 重复写在几十个文件里

这种方式短期能跑，长期会失控。

---

## 7. Trade-offs and Alternatives

### Option A: Single Nginx with Multiple Wildcard Servers

优点：

- 简单直接
- 容易理解
- 适合当前阶段

缺点：

- team 数量继续增多后，证书和 server 文件会增加

### Option B: One Catch-All Server + Dynamic Certificate Loading

优点：

- 配置看起来更集中

缺点：

- 证书变量化更复杂
- 排障成本更高
- 不适合作为 V1

### Option C: Move More Routing Logic into ASM Gateway

优点：

- Nginx 更薄
- 路由能力更靠近 GKE 平台

缺点：

- 前提是 ASM Gateway 能稳定接收你改写后的 Host 语义
- 租户入口证书仍然要在 Nginx 解决

V1 推荐：

- 外部 TLS 和 team wildcard cert 在 Nginx
- 统一入口收敛到 ASM
- 大部分路由和服务治理留在 ASM

---

## 8. Validation and Rollback

### Validation

部署前检查：

```bash
nginx -t
```

灰度验证：

```bash
curl -vk --resolve components.team.app.aibang:443:NGINX_IP \
  https://components.team.app.aibang/upload
```

建议重点检查：

1. 返回证书是否是对应 team 的 wildcard cert
2. ASM 侧是否收到了改写后的 `Host`
3. 后端是否还能看到原始 `X-Forwarded-Host`
4. `413 Request Entity Too Large` 是否按预期只在默认租户生效
5. 上传接口在 `300s` 内长连接是否稳定

### Rollback

1. 保留上一版 Nginx 配置目录
2. 新配置走 `nginx -t`
3. 使用 `nginx -s reload`
4. 如异常，立即恢复上一版并 reload

---

## 9. Reliability and Security Notes

### Reliability

建议补充：

```nginx
proxy_next_upstream error timeout http_502 http_503 http_504;
proxy_next_upstream_tries 2;
```

前提：

- 你的上游如果只有一个 ASM LB IP，这类重试收益有限
- 如果后面是多 VIP 或 DNS 多 A 记录，价值更高

### Security

建议补充：

1. 只信任 ASM LB 的服务端证书链
2. 打开 `proxy_ssl_verify on;`
3. 配置 `proxy_ssl_trusted_certificate`
4. 如有要求，和 ASM 做双向 TLS

示例：

```nginx
proxy_ssl_verify on;
proxy_ssl_trusted_certificate /etc/nginx/ca/asm-ca.pem;
proxy_ssl_verify_depth 2;
```

如果 ASM 当前只暴露公网 LB IP，没有稳定内部 DNS 名称和可信证书链，这一层会比较脆弱。生产上建议先把这个问题补齐。

---

## 10. Recommended V1 Summary

最推荐的 V1 是：

1. 每个 team wildcard cert 一个 `server`
2. 默认都转发到同一个 ASM 入口
3. 用 `proxy_set_header Host` 改写成 ASM 统一内部 Host
4. 用 `X-Forwarded-*` 保留原始访问信息
5. 用 `map` 管理默认值和少数 API 特例
6. 上游尽量使用内部 DNS 名称，不要长期直接依赖裸 IP

---

## 11. Handoff Checklist

1. 确认 ASM 入口推荐使用的内部域名是什么
2. 确认 ASM 是否按改写后的 `Host` 路由
3. 确认后端是否依赖 `X-Forwarded-Host` 或 `X-Original-Host`
4. 确认哪些 team 需要独立 wildcard cert
5. 确认哪些 API 是 `30M/60s` 以外的例外
6. 确认是否要求 Nginx 到 ASM 开启证书校验或 mTLS
7. 把 host/path 到 limit/timeout/internal-host 的关系表纳入 Git 管理

