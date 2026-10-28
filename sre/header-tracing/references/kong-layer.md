# Kong DP 层 Header 语义详解

> 配套文档：[`../README.md`](../README.md)
>
> 覆盖：`request-transformer` / `response-transformer` 精确语义、认证类插件的隐藏行为、
> 插件优先级、Admin API 与 KIC 排查命令、模板语法与限制。

---

## 目录

- [1. Kong 在链路中的位置与观测视角](#1-kong-在链路中的位置与观测视角)
- [2. 大小写折叠：OpenResty 的强制行为](#2-大小写折叠openresty-的强制行为)
- [3. request-transformer 的六种操作](#3-request-transformer-的六种操作)
- [3.5 能改 Header 的 Kong 插件清单](#35-能改-header-的-kong-插件清单)
- [4. 认证类插件的隐藏行为](#4-认证类插件的隐藏行为)
- [5. 插件执行顺序](#5-插件执行顺序)
- [6. 模板语法与限制](#6-模板语法与限制)
- [7. 排查命令清单](#7-排查命令清单)
- [8. KIC（Kubernetes Ingress Controller）环境](#8-kickubernetes-ingress-controller环境)
- [9. 常见误判](#9-常见误判)

---

## 1. Kong 在链路中的位置与观测视角

Kong DP 位于 L4 之后、Runtime 之前，是 **L7 之后最后一个能改写请求头的组件**。
本架构中 nginx L4 是字节管道，所以：

```text
nginx L7  →  Kong DP  →  Runtime
   ↑          ↑            ↑
可改头    可改头      只消费
```

### 1.1 Kong 的四个观测视角

| 视角 | API | 含义 |
|---|---|---|
| 入站请求 | `kong.request.get_header("x")` | Kong **收到**的 |
| 出站请求 | `kong.service.request.get_header("x")` | Kong **发出**的（插件改写后） |
| 入站响应 | `kong.service.response.get_header("x")` | 从上游**收到**的 |
| 出站响应 | `kong.response.get_header("x")` | 发给客户端的 |

> **排查价值**：`kong.request` 与 `kong.service.request` 的**差值**，
> 就是 Kong 插件在本层造成的**全部改动**。这是 Kong 侧最精确的取证手段。
> 在 `pre-function` / `post-function` 插件里各打一次，即可拿到"改前 vs 改后"。

```lua
-- post-function 插件示例
local req_in  = kong.request.get_header("x-caep-src-useragent")
local req_out = kong.service.request.get_header("x-caep-src-useragent")
kong.log.warn("[hdr-probe] in=", req_in, " out=", req_out)
```

---

## 2. 大小写折叠：OpenResty 的强制行为

Kong 基于 OpenResty（`ngx_http_lua`），**所有 Header 名在进入 Kong 时统一为小写**。

- HTTP/2 规范（RFC 7540）**强制**要求 Header 名为小写。
- HTTP/1.1 下 OpenResty 内部存储同样小写。

### 2.1 推论

| 场景 | 结论 |
|---|---|
| 客户端发 `X-Caep-Src-Useragent` | Kong 收到的是 `x-caep-src-useragent` |
| 在 Kong 配置里写 `X-Caep-Src-Useragent` | 匹配时**大小写不敏感**，能命中 |
| 用 `kong.request.get_header("X-Caep-Src-Useragent")` | 能取到（大小写不敏感） |
| 下游 Runtime 是 Java `HttpServletRequest` | Servlet 规范要求大小写不敏感，**能**取到 |
| 下游自己把 Header 转成普通 `HashMap` 再精确取值 | **取不到** ← 常见坑，见 `runtime-layer.md` |

> **重要区分**：
> - nginx L7 **透传**客户端原始 Header 时**保留原始大小写**；
> - Kong 会把它转成小写再发给上游。
> 所以"Header 大小写变了"这件事，**Kong 是正常的分界线**，
> 出现"名字大小写不一致"的问题不应往 L7 找。

---

## 3. request-transformer 的六种操作

Kong 官方 `request-transformer` 插件。源码位置：
`kong/plugins/request-transformer/access.lua` → `transform_headers()`。

### 3.1 执行顺序（固定，不可配置）

```text
Remove  →  Rename  →  Replace  →  Add  →  Append
```

**这一点决定了很多"看起来矛盾"的现象**，务必记住。

### 3.2 逐项语义

| 操作 | 配置键 | 何时生效 | 会不会覆盖已有值 |
|---|---|---|---|
| Remove | `remove.headers` | Header **存在**时删除 | — |
| Rename | `rename.headers` | Header **存在**时改名 | — |
| **Replace** | `replace.headers` | **仅当 Header 已存在** | ✅ **覆盖** |
| **Add** | `add.headers` | **仅当 Header 不存在** | ❌ **不覆盖** |
| Append | `append.headers` | 总是追加 | 产生**重复头**（多值） |

> 源码（`transform_headers`）核心逻辑：
> ```lua
> -- Replace header(s)
> for _, name, value in iter(conf.replace.headers, template_env) do
>     name = name:lower()
>     if headers[name] or name == HOST then
>         headers[name] = value          -- 只有已存在才替换
>     end
> end
>
> -- Add header(s)
> for _, name, value in iter(conf.add.headers, template_env) do
>     if not headers[name] and name:lower() ~= HOST then
>         headers[name] = value          -- 只有不存在才添加
>     end
> end
> ```

### 3.3 关键推论：本案例该看哪个操作

客户端**已经发送**了 `x-caep-src-useragent`，所以：

- ✅ `replace.headers` **能**改到它 → **这是要重点排查的配置**。
- ❌ `add.headers` **改不动**它 → 如果你在 Kong 里只看到 `add` 配置，**它不是凶手**。
- ⚠️ `append.headers` 会让下游看到**逗号拼接**的多值 → 现象是"值后面多了一段"，不是"值被换掉"。

> 顺带：`Remove` 在 `Add` 之前执行。所以
> `remove: [x]` + `add: [x: value]` 的组合 = 最终**仍然存在**且值为 `value`。
> 这一点常被误解为"remove 会把 add 也吃掉"，实际不会。

### 3.4 配置示例

```yaml
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: caep-header-transform
  annotations:
    konghq.com/plugin: request-transformer
plugin: request-transformer
config:
  replace:
    headers:
      # 用另一个 Header 的值覆盖（← 本案例最可能的形态）
      - "x-caep-src-useragent:$(headers['user-agent'])"
  remove:
    headers:
      - "x-internal-only"
  add:
    headers:
      - "x-dbg-h2-caepsrcuseragent:$(headers['x-caep-src-useragent'])"
```

> **格式注意**：Header 配置项支持两种写法——
> - 冒号式 `"name:value"`（**值里不能再含冒号**，如 URL、时间戳）
> - 数组式 `["name", "value"]`（值含冒号时用这个）
>
> 官方提示：*"If a value contains a `,` (comma), you can't use the comma-separated
> format for lists. You must use the array notation instead."*

---

## 3.5 能改 Header 的 Kong 插件清单

排查时先确认插件范围，再逐个排除：

| 插件 | 能改请求头 | 能改响应头 | 备注 |
|---|---|---|---|
| `request-transformer` | ✅ | — | 本案主要嫌疑 |
| `request-transformer-advanced` | ✅ | — | 支持正则替换 |
| `pre-function` / `post-function` | ✅ | ✅ | 任意 Lua，可读可写 |
| `serverless-functions` | ✅ | ✅ | 同上 |
| `response-transformer` | — | ✅ | 响应方向 |
| `key-auth` / `jwt` / `oauth2` | ✅（消费凭证） | — | 见第 4 节 |
| `rate-limiting` / `acl` | ✅（注入） | ✅（注入） | 注入 `X-RateLimit-*` 等 |
| `correlation-id` / `request-id` | ✅（注入） | — | 优先级极高 |

> `pre-function` / `post-function` 能做的事没有上限，
> 如果 `request-transformer` 查不出结果，**必须**检查这两个插件。

---

## 4. 认证类插件的隐藏行为

认证类插件在验证成功后可能**主动删除**凭证 Header，不转发给上游。

### 4.1 key-auth

```yaml
plugin: key-auth
config:
  key_names: ["x-caep-src-useragent"]   # ← 如果这里配了这个头名
  hide_credentials: false               # 关键开关
```

| `hide_credentials` | 行为 | 默认值 |
|---|---|---|
| `false` | 凭证头**继续透传**给上游 | ✅ **默认 `false`** |
| `true` | 认证成功后**删除**该头，不发给上游 | |

> schema 原文：*"An optional boolean value telling the plugin to show or hide the
> credential from the upstream service. If `true`, the plugin strips the credential
> from the request."* — `default = false`
>
> ⚠️ **版本差异提示**：不同 Kong 版本该项默认值曾有变化。
> **不要依赖默认值，永远显式写 `hide_credentials: false`**。

> ⚠️ **本案例的隐蔽风险**：如果 `key-auth` 的 `key_names` 里
> 恰好包含 `x-caep-src-useragent`，而 `hide_credentials: true`，
> 那么该头会被**删除**（现象 B：头消失），而不是"被 UA 覆盖"。
> 现象不同 → 排查方向不同 → **先确认现象是"值变了"还是"头没了"**。

### 4.2 其他可能删除/改写 Header 的插件

| 插件 | 行为 |
|---|---|
| `oauth2` / `openid-connect` | 可能消费并清理 `Authorization` |
| `jwt` | 校验失败时直接拒绝；成功时按配置注入 claims |
| `acl` / `rate-limiting` | 注入 `X-Consumer-*`、`X-RateLimit-*` 等 |
| `correlation-id` | 注入 `X-Correlation-Id`（优先级 100001，最高） |
| `request-id` | 注入 `X-Request-Id` |
| `ip-restriction` / `bot-detection` | 注入 `X-Real-Ip` 等 |

> 若你的现象是"**多了**一个头"而不是"头被改了"，优先怀疑上表中的**注入型**插件。

---

## 5. 插件执行顺序

Kong 按插件的 `PRIORITY` 数值**从高到低**执行（access 阶段）。
已核实的常见优先级：

| 插件 | PRIORITY |
|---|---|
| `correlation-id` | 100001 |
| `jwt` | 1450 |
| `key-auth` | 1250 |
| `rate-limiting` | 910 |
| **`request-transformer`** | **801** |

> 数值**越大越先执行**。
> `request-transformer`（801）比 `key-auth`（1250）**后执行**。
>
> 推论：如果 `key-auth` 删掉了某个头，`request-transformer` 就再也看不到它了
> （`replace` 因"头不存在"而什么也不做，`add` 则会**重新添加**它）。
> 这就是"认证插件 + 转换插件组合出诡异结果"的根源。

**排查方法**：`kong.log` 的 debug 级别会打印 request-transformer 渲染的模板值：

```text
[request-transformer] template `$(headers['user-agent'])` rendered to `UA_DIRECT_A`
```

这一行日志**直接告诉你**是哪个插件、哪个模板、渲染出了什么值。

```bash
# 临时打开 debug 日志
curl -s -X PATCH http://127.0.0.1:8001/logging \
  --data "config.log_level=debug"
# 观察后记得改回
curl -s -X PATCH http://127.0.0.1:8001/logging \
  --data "config.log_level=info"
```

---

## 6. 模板语法与限制

### 6.1 支持的模板类型（官方）

| 类型 | 语法 |
|---|---|
| Header | `$(headers.{HEADER-NAME})` 或 `$(headers["{HEADER-NAME}"])` |
| Query 参数 | `$(query_params.{NAME})` 或 `$(query_params["{NAME}"])` |
| URI 捕获组 | `$(uri_captures.{GROUP})` 或 `$(uri_captures["{GROUP}"])` |
| 共享变量 | `$(shared.{VAR})` 或 `$(shared["{VAR}"])` |

> Header 名在模板中**大小写不敏感**。

### 6.2 限制

| 限制 | 说明 |
|---|---|
| **不能改 `X-Forwarded-*`** | 官方明确说明 request-transformer 无法覆盖 `X-Forwarded-*`，需用 `post-function` |
| 值中不能有多余空白/换行 | 模板外的空白会被当作字面量附加 |
| Lua 未启用时不支持表达式 | `untrusted_lua` 关闭时，`$(...)` 内的表达式不会被渲染 |

---

## 7. 排查命令清单

```bash
# ---- 1. 列出所有插件及配置 ----
curl -s http://127.0.0.1:8001/plugins \
  | jq '.data[] | {name, config} | select(.name|test("transformer|auth|jwt|oidc|oauth2"))'

# ---- 2. 只看 request-transformer 的关键字段 ----
curl -s http://127.0.0.1:8001/plugins \
  | jq '.data[] | select(.name=="request-transformer")
        | {replace: .config.replace.headers,
           add: .config.add.headers,
           append: .config.append.headers,
           remove: .config.remove.headers,
           rename: .config.rename.headers}'

# ---- 3. 精确搜本案关键词（caep / useragent）----
curl -s http://127.0.0.1:8001/plugins \
  | jq -r '.data[] | select((.config|tostring)|test("caep|useragent|user-agent";"i"))
        | "\(.name): \(.config|tostring)"'

# ---- 4. 逐个 route / service 查关联插件（插件可能挂在不同层级）----
curl -s http://127.0.0.1:8001/routes | jq '.data[] | {id, name, plugins}'
curl -s http://127.0.0.1:8001/services | jq '.data[] | {id, name, plugins}'

# ---- 5. 全局插件（最容易漏掉的一层）----
curl -s http://127.0.0.1:8001/plugins/global | jq '.[].name'

# ---- 6. 临时挂 http-log / file-log 抓真实请求头 ----
curl -X POST http://127.0.0.1:8001/plugins \
  --data "name=file-log" --data "config.path=/tmp/kong-request.log"
tail -f /tmp/kong-request.log | jq '.request.headers'
```

> ⚠️ **排查纪律**：`file-log` / `http-log` 会把**完整请求头**（含可能的凭证）落盘。
> 排查完成后**立即删除插件并清理日志文件**。

---

## 8. KIC（Kubernetes Ingress Controller）环境

在 GKE + KIC 部署里，配置来自 CRD 而非 Admin API，**直接查 Admin API 可能看不到最终生效值**
（取决于 DB-less / DB-backed 模式）。要同时看两处：

```bash
# 1) KIC CRD（GitOps 的真实来源）
kubectl get kongplugin -A -o yaml | grep -B8 -A12 -i "caep\|useragent"
kubectl get kongroute -A -o yaml | grep -i "pluginRefs"
kubectl get kongingress -A -o yaml

# 2) Ingress 注解形式
kubectl get ingress -A -o yaml | grep -i "konghq.com/headers\|konghq.com/overrides\|konghq.com/plugins"

# 3) 集群内实际生效的 Admin API（端口转发）
kubectl -n <ns> port-forward svc/<kong-svc> 8001:8001 &
curl -s http://127.0.0.1:8001/plugins | jq '.data[].name'

# 4) Kong Pod 里的声明式配置文件
kubectl -n <ns> exec deploy/<kong-deploy> -- cat /kong/declarative/kong.yaml | grep -i -A5 "caep"
```

> **GitOps 特别提醒**：直接用 Admin API 改插件属于**临时改动**，
> 下一次 Argo CD / Flux 同步会被**覆盖回 Git 中的值**。
> 排查用的临时插件请用独立命名并记录，排查完在 Git 里正式修配置。

---

## 9. 常见误判

| 误判 | 实际 | 纠正 |
|---|---|---|
| "Kong 里配了 `add`，所以头被覆盖了" | `add` 只在头**不存在**时生效 | 找 `replace` |
| "Header 名大小写变了是 L7 的问题" | Kong/OpenResty 统一转小写，是**正常行为** | 从 Kong 开始就是小写 |
| "插件里明明配了 `hide_credentials: false`" | 可能被 GitOps 覆盖回旧值 | 查 CRD + 集群内 Admin API |
| "`X-Forwarded-*` 改不动" | request-transformer 确实不支持 | 用 `post-function` |
| "Kong 日志里没有渲染记录" | 日志级别不是 debug | 临时开 debug |
| "只有部分路由有问题" | 插件挂在 route/service 层，不是全局 | 查 route/service 关联插件 |
| "Kong 日志显示的头发对了，应用却没收到" | `file-log`/`http-log` 记的是**进 Kong 的原始值**，不是发给上游的值 | 在 Kong 与 Runtime 之间抓包，或让 Kong 路由到 echo 服务 |
| "`request-transformer` 里没找到，但它还是被改了" | `pre-function`/`post-function` 可改任意头 | 检查 Lua 插件 |
| "grep 不到 `x_caep_src_useragent`" | 连字符与下划线两种写法都搜 | `curl -s http://<admin>:8001/plugins | jq` 全量导出再搜 |
