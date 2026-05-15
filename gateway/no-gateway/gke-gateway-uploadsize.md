# GKE Gateway Upload Size Limit — 调研与方案

> 文档版本: v1.0
> 更新日期: 2026-05-15
> 目标读: 基础设施工程师 / Platform Team

---

## 1. 结论先行

**GKE Gateway 原生不支持 request body size limit（上传文件大小限制）。**

Gateway API (HTTPRoute) 标准规范中，HTTPRoute 的 Filter 类型只有以下六种：

| Filter 类型 | 作用 |
|------------|------|
| `RequestHeaderModifier` | 修改请求头 |
| `ResponseHeaderModifier` | 修改响应头 |
| `RequestRedirect` | 请求重定向 |
| `ResponseRedirect` | 响应重定向 |
| `URLRewrite` | URL 重写 |
| `RequestMirror` | 请求镜像 |

**没有** `RequestBodySizeLimit`、`ClientMaxBodySize` 或任何与 body 大小相关的 Filter。

这意味着：**你无法在 GKE Gateway (HTTPRoute/Gateway CR) 层面限制上传大小。**

---

## 2. 你的当前架构中的位置

```
Client → PSC → IIP (nginx .so) → GKE Gateway → Kong/Direct Runtime
              ↑
         client_max_body_size
         (在这里生效)
```

从你的 `gateway-2.0-architecture-mesostate.html` 架构图来看：

```
PSC Attachment → IIP (Internal Ingress Proxy) → GKE Gateway (teamN-gateway)
                                            → HTTPRoute → Kong Gateway 2.0 / Direct Runtime
```

**IIP 位于 GKE Gateway 的上游**，即流量顺序是：

```
Internet → PSC → IIP → GKE Gateway → (Kong Gateway / Direct Runtime)
```

所以 IIP 的 `client_max_body_size` 配置会**先于 GKE Gateway** 生效，这是合理的分层设计。

---

## 3. 限制上传大小的可行方案

### 方案 A：保留 IIP 层（推荐）

**原理：** IIP 是 nginx-based，有成熟的 `client_max_body_size` 指令。

**配置示例：**

```nginx
# IIP nginx.conf 或 location 块中
client_max_body_size 100M;   # 允许最大上传 100MB
client_body_buffer_size 1M; # 内存缓冲区大小

# 超出时的响应
client_max_body_size 100M;
# 默认返回 413 Request Entity Too Large
```

如果用 nginx .so 模块（你当前的实现方式），确保 .so 加载时正确传递了 `client_max_body_size` 参数。

**优点：** nginx 原生支持，稳定可靠，无需改动 Gateway 层
**缺点：** 需要维护 IIP 层

---

### 方案 B：应用层限制（Kong Gateway / Runtime）

如果 GKE Gateway 的上游是 **Kong Gateway 2.0**，Kong 提供了插件来限制请求 body 大小。

**Kong Plugin: `request-size-limiting`**

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: team1-upload-limit
  namespace: kong-team1
plugin: request-size-limiting
config:
  # 字节为单位，104857600 = 100MB
  allowed_payload_size: 104857600
  size_unit: bytes
```

**应用到大陆/路由：**

```yaml
# annotations on KongIngress or via deck sync
metadata:
  annotations:
    konghq.com/plugins: team1-upload-limit
```

**注意：** Kong 的 `request-size-limiting` 插件是针对 **request payload**（包括 JSON body 和文件），不是严格意义上的文件上传大小，但可以覆盖大多数场景。

---

### 方案 C：Application Pod 中限制（Direct Runtime）

如果上游是 **Direct Runtime**（不走 Kong），限制需要在应用层实现：

- **nginx sidecar：** 在 Pod 中注入 nginx sidecar，所有流量先经过 nginx sidecar
- **应用框架：** 大多数语言/框架都有 body size limit 配置
  - Go: `http.MaxBytesReader`
  - Python: Flask's `MAX_CONTENT_LENGTH`
  - Node.js: `body-parser` limit option

**示例 - Go HTTP Server:**

```go
func uploadHandler(w http.ResponseWriter, r *http.Request) {
    // 限制 body 大小为 100MB
    r.Body = http.MaxBytesReader(w, r.Body, 100<<20)
    defer r.Body.Close()
    
    // 正常处理...
}
```

---

### 方案 D：Google Cloud Armor（WAF 层）

Google Cloud Armor 支持配置 WAF 规则，可以限制请求大小。适用于**更上层的防护**（在 GLB/PSC 层）。

**注意：** Cloud Armor 主要用于安全防护（SQLi, XSS 等），不是专门的文件上传控制。精细度有限。

---

## 4. 各层对比

| 层级 | 是否支持 body size limit | 实现方式 | 适用场景 |
|------|-------------------------|---------|---------|
| **PSC / GLB** | ❌ 不支持 | N/A | N/A |
| **IIP (nginx)** | ✅ 支持 | `client_max_body_size` | **推荐在此层统一限制** |
| **GKE Gateway** | ❌ 不支持 | N/A | 纯路由/LB，无 body 处理 |
| **Kong Gateway** | ✅ 支持 | `request-size-limiting` 插件 | Kong 上游时使用 |
| **Direct Runtime** | ✅ 支持 | 应用代码 / nginx sidecar | 直接后端时使用 |
| **Cloud Armor** | ⚠️ 有限支持 | WAF size rule | 顶层安全防护 |

---

## 5. 推荐方案：分层限制

基于你的架构，**推荐的分层策略**：

```
Client
  │
  ▼
IIP (nginx .so)         ← 统一在这里设置 client_max_body_size 100M
  │                      ← 413 响应在这里返回，不透传到下游
  ▼
GKE Gateway             ← 只做路由，不处理 body
  │
  ├──→ Kong Gateway     ← Kong 插件可叠加限制（可选）
  │                       ← 例如 request-size-limiting 插件
  │
  └──→ Direct Runtime    ← 应用层自行限制（如需要）
```

**核心原则：** IIP 是你控制 request body size 的唯一可靠位置，GKE Gateway 层不处理 body 内容。

如果担心 IIP 和 Kong 双重限制导致混乱，建议：
- **IIP 层**：设置一个宽松的上限（如 500M），作为安全防护
- **Kong/Runtime 层**：根据具体业务设置精确限制（如 10M）

这样 IIP 挡掉异常大的恶意请求，G Kong/Runtime 做精确的业务限制。

---

## 6. IIP client_max_body_size 配置检查清单

如果你当前使用 nginx .so 的 IIP，确保：

- [ ] `client_max_body_size` 已设置（不是 `proxy_body_size`，那是转发给后端的）
- [ ] `client_body_buffer_size` 设置合理（减少磁盘 I/O）
- [ ] 413 响应已自定义返回格式（可选）
- [ ] 对应 location/server 块已正确加载
- [ ] 已在测试环境验证 413 行为

```nginx
# IIP location 块示例
location /team1/ {
    client_max_body_size 100M;
    client_body_buffer_size 1M;
    
    # proxy_pass 到 GKE Gateway
    proxy_pass http://team1-gateway-ilb;
}
```

---

## 7. 附录：Gateway API Body Limit 相关讨论

- Gateway API 官方 Discussion: [GitHub #1558](https://github.com/kubernetes-sigs/gateway-api/discussions/1558) — 社区有讨论是否需要 `RequestBodyLimit` filter，但目前（v1.4/v1.5）仍未纳入标准。
- GKE Gateway 是 Gateway API 的实现，遵循上游规范，因此也没有这个功能。

---

## 8. 参考链接

- [Gateway API HTTPRoute Filters](https://gateway-api.sigs.k8s.io/reference/api-types/httproute/#filters)
- [Kong request-size-limiting Plugin](https://docs.konghq.com/hub/kong-inc/request-size-limiting/)
- [NGINX client_max_body_size](https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size)
- [Google Cloud Armor WAF Rules](https://cloud.google.com/armor/docs/waf-rules)
