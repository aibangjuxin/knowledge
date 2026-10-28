# nginx 层 Header 语义详解

> 配套文档：[`../README.md`](../README.md)
>
> 覆盖：L7 (`http` 模块) 的请求头/响应头改写机制、变量命名、L4 (`stream`) 边界、
> 继承陷阱、可直接粘贴的排查配置。

---

## 目录

- [1. L4 (stream) 为什么完全不参与 Header 改动](#1-l4-stream-为什么完全不参与-header-改动)
- [2. L7 请求方向：`proxy_set_header`](#2-l7-请求方向proxy_set_header)
- [3. L7 响应方向：`add_header` / `proxy_hide_header`](#3-l7-响应方向add_header--proxy_hide_header)
- [4. 变量命名规则与三个推论](#4-变量命名规则与三个推论)
- [5. 继承规则：整体替换，不是合并](#5-继承规则整体替换不是合并)
- [6. 观测变量速查](#6-观测变量速查)
- [6.1 补充观测手段：直接看线上真实字节](#61-补充观测手段直接看线上真实字节)
- [6.2 补充：让日志和实际发出的值严格一致](#62-补充让日志和实际发出的值严格一致)
- [6.1.1 补充：临时回显端点（看本跳收到什么）](#611-补充临时回显端点看本跳收到什么)
- [6.1.2 补充：别拿 Runtime 日志反推 L7 发了什么](#612-补充别拿-runtime-日志反推-l7-发了什么)
- [6.3 补充：headers-more 模块](#63-补充headers-more-模块)
- [7. 排查配置模板](#7-排查配置模板)
- [8. 常见误判](#8-常见误判)

---

## 1. L4 (stream) 为什么完全不参与 Header 改动

`stream` 模块工作在 **TCP/UDP 字节流**层面：它把连接的一端字节原样搬到另一端。
它**不解析 HTTP 报文**，因此：

| 能力 | stream | http |
|---|---|---|
| 读/改 HTTP Header | ❌ | ✅ |
| 改 `Host` / `User-Agent` | ❌ | ✅ |
| 按 path 路由 | ❌ | ✅ |
| `ssl_preread` 看 SNI/ALPN | ✅（仅握手前几百字节） | 不适用 |
| PROXY protocol 带真实 IP | ✅ | ✅（`real_ip` 模块） |

**两种例外情况，需要单独确认：**

1. **L4 其实是 `http` 块**。有些团队把"四层"叫作"只做端口转发的那层"，
   但实现上是在 `http {}` 里做 `proxy_pass`。这种 L4 **完全有能力改 Header**。
   确认方法：

   ```bash
   nginx -T 2>/dev/null | grep -nE "^\s*(stream|http)\s*\{" 
   ```

2. **L4 做 TLS 终结**（`listen 443 ssl;` + `proxy_pass`）。
   TLS 终结只影响**传输层加密**，不会改写 HTTP 报文体，
   所以 Header 字节依然原样透传 → 结论不变。

> **排查建议**：在动手查 L4 之前，先花 10 秒执行上面的 `nginx -T | grep`。
> 这一步能直接砍掉或保留一个嫌疑层，是本方法论里性价比最高的一个动作。

---

## 2. L7 请求方向：`proxy_set_header`

### 2.1 基础语义

```nginx
proxy_set_header <field> <value>;
```

- **作用**：设置**转发给上游**的请求头。
- **同名客户端头会被顶掉**：一旦你为 `X` 配了 `proxy_set_header`，
  客户端自己发来的 `X` 就不再透传（源码 `ngx_http_proxy_create_request`
  里通过 `headers->hash` 跳过同名客户端头）。
- **空值 = 删除**：`proxy_set_header X "";` 表示**不向上游发送** `X`。
- **默认值**：只有两个 —— `Host $proxy_host` 和 `Connection close`。
  其余客户端头默认全部透传（`proxy_pass_request_headers` 默认 `on`）。
- **继承**：见第 5 节。

### 2.2 常见写法与含义

```nginx
# 覆盖成固定值
proxy_set_header X-Caep-Src-Useragent "FIXED";

# 覆盖成另一个请求头的值（← 本案例最可能的凶手）
proxy_set_header X-Caep-Src-Useragent $http_user_agent;

# 透传客户端原值（显式写出来，用于"禁止被下层默认覆盖"）
proxy_set_header X-Caep-Src-Useragent $http_x_caep_src_useragent;

# 删除该头
proxy_set_header X-Caep-Src-Useragent "";

# 正确设置 Host（生产必备）
proxy_set_header Host $host;
```

### 2.3 用 `map` 做"有则用之，无则退化为 UA"

这是第 8 节方案 C 的实现，也是"显式优先级"的标准写法：

```nginx
map $http_x_caep_src_useragent $caep_src_useragent_final {
    default  $http_x_caep_src_useragent;   # 客户端声明了就用声明的
    ""       $http_user_agent;             # 没声明才退化为 UA
}
```

> `map` 的匹配规则：
> - `default` 兜底；
> - 字符串精确匹配优先于正则；
> - 正则按配置**书写顺序**第一个命中即止；
> - `hostnames`、`volatile` 等修饰符按需使用。
>
> `map` 定义在 `http {}` 块，变量是**惰性求值**的（第一次用到才计算）。

---

## 3. L7 响应方向：`add_header` / `proxy_hide_header`

### 3.1 `add_header`

```nginx
add_header <field> <value> [always];
```

- 加的是**响应头**，客户端可见。
- **默认只在特定状态码生效**：`200, 201, 204, 206, 301, 302, 303, 304, 307, 308`。
  其他状态码（如 `4xx`/`5xx`）**不会**加。
- 加 `always` 后**所有**状态码都加。
  → 排查时**必须加 `always`**，否则错误响应上看不到探针。
- **继承规则与 `proxy_set_header` 相同**（见第 5 节）——这是最容易误伤的地方。

### 3.2 `proxy_hide_header`

```nginx
proxy_hide_header <field>;
```

- 从上游响应中**移除**指定头，不转发给客户端。
- nginx **默认**不透传上游的 `Date`、`Server`、`X-Pad`、`X-Accel-*`。
- 反向操作用 `proxy_pass_header`。

> 响应方向排查时，"上游返回了什么"用 `$upstream_http_*`，
> "客户端最终收到什么"用 `$sent_http_*"。两者不同 = 中间有改动。

---

## 4. 变量命名规则与三个推论

### 4.1 规则

**转小写 + 短横线换下划线**。

```text
X-Caep-Src-Useragent      →  $http_x_caep_src_useragent
User-Agent                →  $http_user_agent
X-Forwarded-For           →  $http_x_forwarded_for
```

源码依据：`ngx_http_variables.c` 的 `ngx_http_variable_unknown_header()`，
逐字符比较时把 Header 名中的 `A-Z` 转小写、`-` 转 `_`。

### 4.2 推论 1：命名冲突不可区分

`x-caep-src-useragent` 与 `x_caep_src_useragent` 在 nginx 变量空间里**完全等价**。
如果链路中同时出现这两种写法，你**无法**用 `$http_*` 区分它们。

### 4.3 推论 2：下划线形式的请求头默认被丢弃

```nginx
underscores_in_headers off;   # 默认值
```

> 官方原文：*"When the use of underscores is disabled, request header fields whose
> names contain underscores are marked as invalid and become subject to the
> `ignore_invalid_headers` directive."*

`ignore_invalid_headers` 默认 `on`，因此**含下划线的请求头直接被丢弃**。

| 客户端发的是 | nginx 收到吗 |
|---|---|
| `X-Caep-Src-Useragent`（短横线） | ✅ |
| `X_Caep_Src_Useragent`（下划线） | ❌ **被丢弃** |

> 这条独立于"值被覆盖"，是**另一种**故障模式。
> 现象上区分：短横线版本"值被改"，下划线版本"直接消失"。
> 排查时先用 `tcpdump` 或 `curl -v` 确认客户端**实际发出的名字**。

### 4.4 推论 3：同名多值被逗号拼接

同一 Header 出现多次时，`$http_*` 返回的是用 `", "` 拼接的字符串，
**不是数组**。所以：

```text
$http_x_caep_src_useragent == "SRC_B, SRC_C"
```

意味着上游收到了**重复头**，而不是"值被改了"。
这在 nginx 源码里体现为 `ngx_http_variable_unknown_header()` 里的
`p = ngx_pnalloc(...)` + `*p++ = ','` 拼接逻辑。

---

## 5. 继承规则：整体替换，不是合并

> nginx 官方原文（`proxy_set_header` 与 `add_header` 均有此条款）：
> *"These directives are inherited from the previous configuration level
> **if and only if there are no `proxy_set_header` directives defined on the current level**."*

### 5.1 后果

在 `location` 里**新增**第一条 `proxy_set_header` 时，
如果这个 `location` 原本没有，则从 `server`/`http` 继承来的
**全部** `proxy_set_header` 会被**整体丢弃**，只剩模块默认值
（`Host $proxy_host` + `Connection close`）。

源码依据（`ngx_http_proxy_merge_loc_conf`）：

```c
ngx_conf_merge_ptr_value(conf->headers_source, prev->headers_source, NULL);

if (conf->headers_source == prev->headers_source) {
    conf->headers = prev->headers;      /* 只有完全没定义时才继承 */
}
```

`add_header` 在 `ngx_http_headers_module` 中的继承逻辑一致。

### 5.2 排查时的自检清单

在 `location` 里加了探针后，**立刻确认**下面这些是否还在：

- [ ] `Host` 还是 `$host`（不是 `$proxy_host`）
- [ ] `X-Forwarded-For` / `X-Forwarded-Proto` 还在
- [ ] 业务自定义头（如 `X-Caep-Src-Useragent`）还在
- [ ] 响应方向的上层安全头（`Strict-Transport-Security` 等）还在

### 5.3 安全做法

**优先把探针加在已有 `proxy_set_header` 的同一层。**
若必须新建 `location`，则把该层原有的 `proxy_set_header` **完整复制**一遍。

```nginx
# ✅ 好：探针与业务配置同层，继承关系不变
location /v1/ {
    proxy_set_header Host              $host;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Dbg-H1-UserAgent $http_user_agent;   # 探针
    proxy_pass http://upstream;
}

# ❌ 危险：新 location 只有探针，继承的 Host / XFF 全丢
location /debug/ {
    proxy_set_header X-Dbg-H1-UserAgent $http_user_agent;
    proxy_pass http://upstream;
}
```

> nginx 1.29.3+ 提供 `add_header_inherit merge` 可改变 `add_header` 的继承行为；
> `proxy_set_header` 没有对应开关，仍需手工复制。

---

## 6. 观测变量速查

| 变量 | 方向 | 含义 | 备注 |
|---|---|---|---|
| `$http_<name>` | 请求 | **我收到的**客户端请求头 | 唯一可用的请求方向视角 |
| `$sent_http_<name>` | 响应 | **我发出**给客户端的响应头 | 已被 `proxy_hide_header` 处理过 |
| `$upstream_http_<name>` | 响应 | **我从上游收到**的响应头 | 仅最后一个上游 |
| `$upstream_addr` | — | 上游地址 | 排查是否打到了预期 upstream |
| `$proxy_add_x_forwarded_for` | 请求 | 追加 XFF 的值 | |
| `$remote_addr` | — | 客户端 IP（受 `real_ip` 影响） | |
| `$ssl_preread_server_name` | L4 | SNI | 仅 stream 层 |

**注意**：请求方向**没有**"我发出去的头"的变量。
想看发出去的头 → 只能观测**下一跳的入口**，或用第 7 节的探针间接构造。

---

## 6.1 补充观测手段：直接看线上真实字节

前两节都是"通过 nginx 自己的视角观测"。当两者结论不一致时，
可以退回到**原始字节**这一层：

### 方式 A：链路抓包（明文段才有效）

```bash
# 在 L7 与 L4 之间的链路上抓包（该段必须是明文 HTTP）
sudo tcpdump -i any -A -s0 'tcp port <L4_PORT> and host <L4_IP>' \
  | grep -iE 'user-agent|x-caep|x-probe'
```

能看到：头的**真实大小写**、是否**重复**、是否被**截断**，
以及是否有 nginx 视角看不到的中间设备在改写。
这是唯一能区分"重复头"与"值被改"的手段。

### 方式 B：nginx debug 日志（需编译 `--with-debug`）

```nginx
events {
    debug_connection <你的客户端IP>;   # 只对测试连接生效
}
error_log /var/log/nginx/error.log debug;
```

日志里两类行含义不同，**这是 nginx 少有的能直接看到"发出去的头"的地方**：

| 日志行 | 含义 |
|---|---|
| `http header:` | **收到**的请求头 |
| `http proxy header:` | **发给上游**的请求头 |

> 只对测试 IP 开启，debug 级别日志量极大。

### 方式 C：加一个"对照组"探针头

在请求里额外带一个**没人会特意处理**的头：

```bash
curl -s https://your.host/path \
  -H 'User-Agent: UA_DIRECT_A' \
  -H 'X-Caep-Src-Useragent: SRC_B' \
  -H 'X-Probe-1: probe-value-1'
```

- 若 `X-Probe-1` 一路正常，而 `X-Caep-Src-Useragent` 被改
  → 证明是**针对这个头名的显式规则**，不是链路整体丢头。
- 若两者都被改/都丢了
  → 是更上游的通用改写或整链路问题。

---

## 6.1.1 补充：临时回显端点（看本跳收到什么）

在 L7、Kong 每一层挂一个临时回显端点，可以**直接看到该跳收到的完整头列表**，
不用翻日志：

```nginx
location = /__echo {
    default_type text/plain;
    return 200 "ua=$http_user_agent\nsrc=$http_x_caep_src_useragent\nprobe=$http_x_probe_1\n";
}
```

Kong 侧则可以直接路由到 echo 服务（如 `mendhak/http-https-echo` 或 httpbin 的 `/headers`），
看到链路末端实际收到的头。

> ⚠️ 回显端点会把请求头原样吐给调用方，**仅在排查期间开启**，且要限制来源 IP。

## 6.1.2 补充：别拿 Runtime 日志反推 L7 发了什么

**不同层的日志记录的是各自"收到"的值。**

| 日志来源 | 记录的是 |
|---|---|
| L7 nginx access_log | 客户端 → L7 **收到**的请求头 |
| Kong `file-log` / `http-log` 的 `request.headers` | 客户端 → Kong **收到**的原始值（**不是** Kong 发给上游的值） |
| Runtime 应用日志 | Kong → Runtime **收到**的请求头 |

所以：

- Kong 的 `file-log` 能证明"**进 Kong 之前是对的**"；
- 但它**看不到** Kong 发给 Runtime 的值 —— 要看后者，
  只能在 Kong 与 Runtime 之间抓包，或让 Kong 路由到 echo 服务。

这是排查时最容易搞错的一步：**别用 Runtime 的日志去反推 L7 发了什么**，
那是 Kong 发给 Runtime 的，中间还隔着 Kong 这一跳。

## 6.2 补充：让日志和实际发出的值严格一致

一个容易忽略的技巧：**用同一个变量既做 `proxy_set_header` 又做日志字段**。
这样日志里的 `OUT_*` 就是**实际发出去的值**，而不是你的推测。

```nginx
http {
    map $http_x_caep_src_useragent $out_src_ua {
        default $http_x_caep_src_useragent;
        ""      $http_user_agent;      # 为空时才回填 UA，不覆盖客户端发来的值
    }

    log_format hdr_debug '$time_iso8601 rid=$request_id remote=$remote_addr '
                         'IN_ua="$http_user_agent" IN_src="$http_x_caep_src_useragent" '
                         'OUT_src="$out_src_ua" '
                         'up=$upstream_addr st=$status up_st=$upstream_status';

    server {
        access_log /var/log/nginx/hdr_debug.log hdr_debug;

        location / {
            proxy_set_header X-Caep-Src-Useragent $out_src_ua;
            proxy_set_header X-Request-Id         $request_id;   # 跨层关联日志
            proxy_pass http://upstream;
        }
    }
}
```

`$request_id` 用于跨层关联日志行，比时间戳更可靠。

---

## 6.3 补充：headers-more 模块

若 nginx 编译了 `headers-more` 模块，还有两个指令可用：

| 指令 | 方向 | 说明 |
|---|---|---|
| `more_set_input_headers` | 请求 | 改写**发给上游**的请求头 |
| `more_set_headers` | 响应 | 改写**返回给下游**的响应头 |

排查时**不要漏掉这两个指令**：

```bash
nginx -T 2>/dev/null | grep -nE 'more_set_(input_)?headers'
```

---

## 7. 排查配置模板

### 7.1 带开关的探针（推荐）

```nginx
http {
    # 白名单来源才生效；排查完清空白名单即停用
    map "$remote_addr:$http_x_debug_trace" $debug_trace_on {
        default        0;
        "10.20.30.40:1" 1;
    }

    # 掩码后再盖章，避免泄露凭证
    map $http_authorization $masked_auth {
        default  "***";
        "~."     $http_authorization;
    }

    log_format dbg_headers
        '$remote_addr "$request" '
        'ua="$http_user_agent" '
        'caep_src="$http_x_caep_src_useragent" '
        'dbg_h1_ua="$http_x_dbg_h1_useragent" '
        'dbg_h1_caep="$http_x_dbg_h1_caepsrcuseragent" '
        'dbg_h2_caep="$http_x_dbg_h2_caepsrcuseragent"';

    server {
        listen 443 ssl;
        server_name api.example.com;

        location / {
            access_log /var/log/nginx/dbg_headers.log dbg_headers;

            # ---- 探针（与业务配置同层）----
            proxy_set_header X-Dbg-H1-UserAgent       $http_user_agent;
            proxy_set_header X-Dbg-H1-CaepSrcUserAgent $http_x_caep_src_useragent;
            proxy_set_header X-Dbg-H1-Trace            $debug_trace_on;

            # ---- 业务配置保持原样 ----
            proxy_set_header Host              $host;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            proxy_pass http://backend;
        }
    }
}
```

### 7.2 响应方向探针

```nginx
location / {
    # 看上游返回了什么
    add_header X-Dbg-R1-UpstreamUA  $upstream_http_user_agent always;
    # 看客户端最终收到什么
    add_header X-Dbg-R1-SentUA      $sent_http_user_agent always;
    # 上层已有的安全响应头要一起复制，否则会被整体替换
    add_header Strict-Transport-Security "max-age=31536000" always;
}
```

> `always` 不可省：默认状态码白名单不含 `4xx/5xx`。

---

## 8. 常见误判

| 误判 | 实际 | 纠正方法 |
|---|---|---|
| "L4 也可能是凶手" | `stream` 不解析 HTTP | `nginx -T \| grep -A3 stream` 确认模块 |
| "我加了探针但下游没看到" | 探针加在了 `add_header`（响应方向） | 请求方向要用 `proxy_set_header` |
| "探针头名都一样，后面的覆盖前面的" | 是的，只剩最后一跳 | 头名带跳号：`X-Dbg-H1-*` / `X-Dbg-H2-*` |
| "客户端头没传过来" | 可能是下划线形式被 `underscores_in_headers off` 丢弃 | `curl -v` 看实际发出的名字 |
| "值被改成了另一个值" | 可能是同名重复头被 `, ` 拼接 | 看值里有没有 `, ` |
| "加探针后线上出问题了" | `proxy_set_header` 继承被整体替换，`Host`/XFF 丢了 | 回到第 5 节自检清单 |
| "响应头没加上" | `add_header` 默认状态码白名单 | 加 `always` |
| "响应里少了 Server/Date" | nginx 默认不透传上游的 `Date`/`Server`/`X-Pad`/`X-Accel-*` | 需要时用 `proxy_pass_header` |
| "头整个消失且名字含下划线" | `underscores_in_headers off`（默认）丢弃 | 客户端改用连字符 |
| "头整个消失且格式奇怪" | `ignore_invalid_headers on`（默认）丢弃非法头 | 修正客户端 |
| "所有自定义头都没了" | `proxy_pass_request_headers off` | 检查该指令 |
| "用 Runtime 日志反推 L7 发了什么" | 各层日志只记"收到"的值 | 见 6.1.2 |
| "grep 不到 `x_caep_src_useragent`" | 连字符与下划线两种写法都搜 | 两种写法都要搜 |
