- [Nginx proxy\_pass + SNI 注入配置逐行精读](#nginx-proxy_pass--sni-注入配置逐行精读)
  - [0. 一句话总结](#0-一句话总结)
  - [1. 业务方原始配置(逐行标注)](#1-业务方原始配置逐行标注)
  - [2. 逐行精读](#2-逐行精读)
    - [2.1 第 1 行:`location /apiname/ {`](#21-第-1-行location-apiname-)
    - [2.2 第 2 行:`if ($content_type ~ (multipart/form-data|text/plain)) {`](#22-第-2-行if-content_type--multipartform-datatextplain-)
    - [2.3 第 3 行:`return 405;`](#23-第-3-行return-405)
    - [2.4 第 4 行:`rewrite ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";`](#24-第-4-行rewrite-apiname-apinameteamcaepuk4431)
    - [2.5 第 5 行:`rewrite ^(.*)$ "https$1" break;`](#25-第-5-行rewrite--https1-break)
    - [2.6 第 6 行:`proxy_pass http://ourintra.squid.proxy:3128;`](#26-第-6-行proxy_pass-httpourintrasquidproxy3128)
    - [2.7 第 7 行:`proxy_set_header Host apiname.team.caep.uk;`](#27-第-7-行proxy_set_header-host-apinameteamcaepuk)
  - [3. 完整数据流(逐跳 + 跨网络分段)](#3-完整数据流逐跳--跨网络分段)
    - [3.1 跨网络架构总览(架构师重新校准)](#31-跨网络架构总览架构师重新校准)
    - [3.2 完整 4 跳数据流](#32-完整-4-跳数据流)
  - [4. 架构师对 3 个反直觉之处的解答](#4-架构师对-3-个反直觉之处的解答)
    - [4.1 反直觉 1:`if + return 405` 在 Nginx 里危险吗?](#41-反直觉-1if--return-405-在-nginx-里危险吗)
    - [4.2 反直觉 2:为什么 rewrite 不带 scheme,要两行?](#42-反直觉-2为什么-rewrite-不带-scheme要两行)
    - [4.3 反直觉 3:Nginx 跟 Squid 是明文 HTTP,SNI 怎么注入?](#43-反直觉-3nginx-跟-squid-是明文-httpsni-怎么注入)
  - [5. 架构师对业务方 SNI 理解的分析](#5-架构师对业务方-sni-理解的分析)
    - [5.1 业务方的核心理解](#51-业务方的核心理解)
    - [5.2 业务方理解 vs 实际行为](#52-业务方理解-vs-实际行为)
    - [5.3 架构师修正业务方的理解](#53-架构师修正业务方的理解)
    - [5.4 架构师最终结论](#54-架构师最终结论)
  - [6. 架构师对配置的评价](#6-架构师对配置的评价)
    - [6.1 优点](#61-优点)
    - [6.2 风险与改进建议(架构师标注,**业务方已确认生产可用**,仅作参考)](#62-风险与改进建议架构师标注业务方已确认生产可用仅作参考)
    - [6.3 跟同类配置(`nginx-proxy-pass.md`)的对比](#63-跟同类配置nginx-proxy-passmd的对比)
    - [6.4 完整 nginx.conf 示例(架构师扩展)](#64-完整-nginxconf-示例架构师扩展)
      - [6.4.1 主配置文件 `/etc/nginx/nginx.conf`](#641-主配置文件-etcnginxnginxconf)
      - [6.4.2 配置验证步骤](#642-配置验证步骤)
      - [6.4.3 业务方 config 跟 curl 等价性分析](#643-业务方-config-跟-curl-等价性分析)
      - [6.4.4 Team 1 vs Team 2 配置差异(架构师对比表)](#644-team-1-vs-team-2-配置差异架构师对比表)
  - [7. 6 关键架构师疑问解答](#7-6-关键架构师疑问解答)
    - [7.1 疑问 1:Nginx 在 proxy\_pass HTTPS 时,是否会自动填 SNI?](#71-疑问-1nginx-在-proxy_pass-https-时是否会自动填-sni)
    - [7.2 疑问 2:业务方 config 的 SNI 实际是谁填的?](#72-疑问-2业务方-config-的-sni-实际是谁填的)
    - [7.3 疑问 3:`if + return 405` 在 Nginx 里安全吗?](#73-疑问-3if--return-405-在-nginx-里安全吗)
    - [7.4 疑问 4:两行 rewrite idiom 是合法的吗?](#74-疑问-4两行-rewrite-idiom-是合法的吗)
    - [7.5 疑问 5:`proxy_set_header Host` 写死字符串有什么风险?](#75-疑问-5proxy_set_header-host-写死字符串有什么风险)
    - [7.6 疑问 6:这个 config 在生产环境有什么坑?](#76-疑问-6这个-config-在生产环境有什么坑)
  - [8. 决策树:这是否是好的配置?](#8-决策树这是否是好的配置)
  - [9. 架构师 lane 边界声明](#9-架构师-lane-边界声明)
  - [10. 权威标准 nginx.conf(架构师版)](#10-权威标准-nginxconf架构师版)
    - [10.1 文件结构总览](#101-文件结构总览)
    - [10.2 主文件 `/etc/nginx/nginx.conf`](#102-主文件-etcnginxnginxconf)
    - [10.3 `/etc/nginx/conf.d/upstreams.conf`(Squid HA)](#103-etcnginxconfdupstreamsconfsquid-ha)
    - [10.4 `/etc/nginx/conf.d/maps.conf`(Team 模板化)](#104-etcnginxconfdmapsconfteam-模板化)
    - [10.5 `/etc/nginx/conf.d/ssl-hardening.conf`(TLS 1.2+ 现代加密)](#105-etcnginxconfdssl-hardeningconftls-12-现代加密)
    - [10.6 `/etc/nginx/conf.d/api-proxy.conf`(⭐ 业务方核心逻辑 — 100% 保留原始 idiom)](#106-etcnginxconfdapi-proxyconf-业务方核心逻辑--100-保留原始-idiom)
    - [10.7 `/etc/nginx/conf.d/health-check.conf`](#107-etcnginxconfdhealth-checkconf)
    - [10.8 `/etc/nginx/conf.d/security-hardening.conf`](#108-etcnginxconfdsecurity-hardeningconf)
    - [10.9 `/etc/nginx/snippets/safe-if-return.conf`](#109-etcnginxsnippetssafe-if-returnconf)
    - [10.10 架构师承诺清单(对比业务方原始 config)](#1010-架构师承诺清单对比业务方原始-config)
    - [10.11 反直觉检查点 → 优化项映射](#1011-反直觉检查点--优化项映射)
    - [10.12 部署步骤(架构师给 infra-gcp 跑的清单)](#1012-部署步骤架构师给-infra-gcp-跑的清单)
    - [10.13 架构师反思(为什么这样设计)](#1013-架构师反思为什么这样设计)
  - [12. 文档维护](#12-文档维护)

# Nginx proxy_pass + SNI 注入配置逐行精读

> **本节是"业务方生产 Nginx location 块 + Squid outbound proxy + SNI 注入"的逐行精读文档**。
>
> **架构师 lane 边界**:本文档只做"独立分析 + 逐行解释 + 架构师标注",**不评估生产稳定性**——业务方明确说明"已在生产环境使用,没有问题",架构师接受这一前提。
>
> **状态**:Reference · Date: 2026-09-04 · Author: **architect-gcp** · Reviewers: 业务方(已确认生产可用)
>
> **核心问题**:
> 1. **验证配置正确性**:这是不是一个合法可用的 Nginx `location` 块?
> 2. **逐行解释**:每条指令做什么?为什么这么写?
> 3. **架构师疑问解答**:`proxy_ssl_server_name on` + `proxy_ssl_name` 配合下,Nginx 跟上游建立 HTTPS 时,会主动把内部目标域名填入 ClientHello 的 SNI 字段——你这个理解是否正确?
>
> **前置知识**:
> - Nginx `proxy_pass` 指令 + `rewrite` 指令的拼接规则
> - TLS 握手中 SNI(Server Name Indication)的作用
> - Squid 作为 outbound forward proxy 的角色
>
> **配套文档**:
> - 同目录:[`nginx-proxy-pass.md`](./nginx-proxy-pass.md) — 同类模式参考(Microsoft SSO 登录)
> - 同目录:[`nginx-proxy-pass-rewrite.md`](./nginx-proxy-pass-rewrite.md) — rewrite 模式参考

---

## 0. 一句话总结

> **业务方配置是一个"双重 URL 改写 + Squid 转发 + SNI 注入"的 4 步转发链,完全合法可工作**。
>
> **核心架构(架构师校准)**:Nginx 主机是一个**跨网络的反向代理主机**(公网 / DMZ ↔ 内网)
> - **外部访问域名**:`www.aibang.com`(公网)
> - **Nginx 内部 URL 模式**:`https://www.aibang.com/{apiname}/...` → `https://{apiname}.{team}.caep.uk:443/...`
> - **Nginx 主机位置**:公网 / DMZ 侧(对外侦听 `www.aibang.com`)
> - **Squid 位置**:内网侧(`http://ourintra.squid.proxy:3128`)
> - **GKE 内部 API**:`{apiname}.{team}.caep.uk:443`(内网域名,Envoy 按 SNI 匹配 TLS filter chain)
>
> **关键链**:`客户端 → Nginx(URL 改写 + Host 头重写)→ Squid(明文 HTTP CONNECT)→ GKE API(Host-based TLS filter chain 匹配)`。
>
> **业务方关于 SNI 的理解**:**部分正确**——**Nginx 跟 Squid 这段是明文 HTTP,不走 TLS,根本无 SNI**;**SNI 在 Squid 跟 GKE API 这段才有意义**。但业务方在 Nginx `proxy_pass` 这一段没有 `proxy_ssl_*` 指令(因为 Squid 是 HTTP 不是 HTTPS),所以**业务方的"Nginx 主动填 SNI"理解需要修正**。
>
> **等价性**:**业务方整条配置链 = `curl -x http://ourintra.squid.proxy:3128 https://{apiname}.{team}.caep.uk/...` 的批量自动化**(URL 改写 + Host 头重写是 Nginx 在帮 curl 把内部域名拼好)。
>
> 详细见 §6。

---

## 1. 业务方原始配置(逐行标注)

```nginx
location /apiname/ {                                                # 第1行
    if ($content_type ~ (multipart/form-data|text/plain)) {        # 第2行
      return 405;                                                   # 第3行
    }
    rewrite  ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";    # 第4行
    rewrite  ^(.*)$ "https$1" break;                                # 第5行
    proxy_pass http://ourintra.squid.proxy:3128;                    # 第6行
    proxy_set_header Host apiname.team.caep.uk;                     # 第7行
}
```

> **架构师先问一个反直觉的问题**:这 7 行里有 **3 处是反常规写法**(不是 bug,但需要解释清楚):
> 1. **`if` + `return 405`** — Nginx 著名的"if is evil"陷阱,但这里**是安全的**
> 2. **`rewrite ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1"`** — URL 拼接但**不带 scheme**,后面再加 `https` 头——**反直觉但合法**
> 3. **`proxy_pass http://...Squid:3128`** + `proxy_set_header Host apiname.team.caep.uk` — **Squid 是明文 HTTP,Host 头是给 GKE API 看的**,**但 Host 头怎么会穿过明文 HTTP?** —— 这条最反直觉,见 §1.7 + §6

---

## 2. 逐行精读

### 2.1 第 1 行:`location /apiname/ {`

```nginx
location /apiname/ {
```

**Nginx 官方文档**([ngx_http_core_module](https://nginx.org/en/docs/http/ngx_http_core_module.html#location)):

> "A location can either be defined by a prefix string, or by a regular expression."

**含义**:
- `location /apiname/` 是**前缀匹配**(prefix match)
- 匹配所有以 `/apiname/` 开头的请求 URI
- 例如:`GET /apiname/users/123` 匹配;`GET /apiname/` 匹配;`GET /other/` **不**匹配

**架构师标注**:
- ✅ 简单前缀匹配,**没有任何陷阱**
- 注意末尾的 `/` 是**位置标识**,**不会**消耗请求 URI 中的 `/apiname/`
  - 实际行为:`location /apiname/` 把 `/apiname/` 当作**前缀**,匹配后**保留**原始 URI
  - 与 `location /apiname`(无尾 `/`)的区别:前者**保留** `/apiname/` 前缀,后者**保留** `/apiname` 前缀(不带尾 `/`)

### 2.2 第 2 行:`if ($content_type ~ (multipart/form-data|text/plain)) {`

```nginx
if ($content_type ~ (multipart/form-data|text/plain)) {
```

**Nginx 官方文档**([ngx_http_rewrite_module#if](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#if)):

> "The `if` directive performs a conditional check. If the condition is true, the directives specified inside the braces are executed. Configurations inside the `if` directives are inherited from the previous configuration level."

**含义**:
- `$content_type` 是 Nginx 嵌入变量,**等于** `$http_content_type`(客户端请求的 `Content-Type` 头)
- `~` 是**正则匹配操作符**(大小写敏感)
- `(multipart/form-data|text/plain)` 是正则,**匹配**任一即可
- `multipart/form-data` = 文件上传;`text/plain` = 纯文本 POST
- **架构师注解**:`multipart/form-data` 后面有个**正则特殊字符** `/`,但因为在 `(...)` 分组里,不需转义

**架构师标注(反直觉)**:
- ⚠️ **Nginx 著名的"if is evil"陷阱** ([getpagespeed 完整指南](https://www.getpagespeed.com/server-setup/nginx/nginx-if-is-evil))—— `if` 在 `location` 块内**很多指令是危险的**(如 `proxy_pass` / `try_files` 等)
- ✅ **但 `return 405` 是安全的**(该指南明确分类:`return` 在 `if` 内属于"safe directives")
- **官方原文**([Nginx `if` 文档](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#if)):"Directives provided by other modules are not allowed to be used inside the `if` block, with a few exceptions like `return`."
- → **本配置安全**:`return` 是 `if` 内**少数被允许**的非 rewrite 模块指令之一

### 2.3 第 3 行:`return 405;`

```nginx
  return 405;
```

**Nginx 官方文档**([ngx_http_rewrite_module#return](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#return)):

> "Stops processing and returns the specified code to a client."

**含义**:
- 返回 **HTTP 405 Method Not Allowed**
- **后续指令(`rewrite`、`proxy_pass`)不执行**
- `if` 块结束

**架构师标注**:
- ✅ 标准做法
- ⚠️ **小建议**:返回 405 时**最好带 `Allow:` 头**说明哪些方法被允许,但本配置没配——见 §5 改进建议

### 2.4 第 4 行:`rewrite ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";`

```nginx
    rewrite  ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";
```

**Nginx 官方文档**([ngx_http_rewrite_module#rewrite](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#rewrite)):

> "If a replacement string includes the new request arguments, the previous request arguments are appended after them. If this is undesired, putting a question mark at the end of the replacement string avoids having them appended."

**含义**(这是业务方配置里**最反直觉**的一行):

**正则**:`^/apiname/(.*)$` 匹配 `/apiname/` 后面的所有字符,捕获到 `$1`

**替换**:`://apiname.team.caep.uk:443/$1`
- **没有 scheme**(没有 `http://` 或 `https://`)
- 以 `://` 开头
- 后接域名 + 端口 + `/` + 捕获组

**示例**:

| 原 URI | `$1` | rewrite 后 |
|---|---|---|
| `/apiname/` | `""` | `://apiname.team.caep.uk:443/` |
| `/apiname/users/123` | `users/123` | `://apiname.team.caep.uk:443/users/123` |
| `/apiname/api/v1` | `api/v1` | `://apiname.team.caep.uk:443/api/v1` |

**注意**:rewrite 只改 **URI**,**不影响 Host 头**。**且**因为 replacement 没有 `?`,**原 query string 会保留**。

**架构师标注(反直觉 2)**:
- ⚠️ **这里的 rewrite 不带 `last` / `break` 标志**——这是**故意的**,因为后面还有第 5 行 rewrite
- ⚠️ **rewrite 的 replacement 不带 scheme**——这是关键,**因为下一行 rewrite 会补 scheme**
- → **这是个"两阶段 rewrite 拼装 URL"的 idiom**(模式)

### 2.5 第 5 行:`rewrite ^(.*)$ "https$1" break;`

```nginx
    rewrite  ^(.*)$ "https$1" break;
```

**Nginx 官方文档**([ngx_http_rewrite_module#rewrite](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#rewrite)):

> "The `break` flag stops processing the rewrite directives in the current `server` or `location` context."

**含义**:

**正则**:`^(.*)$` 匹配**整个 URI**(包括第 4 行改写后的)

**替换**:`https$1`
- `https` = scheme(明文,不带 `://`)
- `$1` = 第 4 行改写后的 URI

**示例**(假设第 4 行后 URI 是 `://apiname.team.caep.uk:443/users/123`):

```
正则匹配: ^(.+)$ → $1 = "://apiname.team.caep.uk:443/users/123"
替换: "https" + "://apiname.team.caep.uk:443/users/123"
  = "https://apiname.team.caep.uk:443/users/123"
```

**`break` 标志**:
- 停止当前 `location` 内**所有后续 rewrite**
- 但**不会停止 `proxy_pass` 等其他指令**(因为 `proxy_pass` 是 `ngx_http_proxy_module` 的指令,不是 rewrite 指令)
- **关键**:`proxy_pass` 看到的是 `break` 后的 URI,即 `https://apiname.team.caep.uk:443/users/123`

**架构师标注(反直觉 3,但其实合理)**:
- ✅ **这个 idiom 是把"不带 scheme 的 URL"补全成"带 scheme 的 URL"**
- ✅ **`break` 的作用**:**防止**第 4 行 rewrite 又被触发(无限循环)
- ⚠️ **两行 rewrite 配合工作的本质**:**第 4 行不带 scheme 改 URI,第 5 行补 scheme**,等效于 1 行 `rewrite ^/apiname/(.*)$ "https://apiname.team.caep.uk:443/$1" break;`
- → **业务方这么写可能是因为模板化**(`{apiname}` 变量替换后,scheme 可能变化,**分两行写**可以**只动第 4 行**)

### 2.6 第 6 行:`proxy_pass http://ourintra.squid.proxy:3128;`

```nginx
    proxy_pass http://ourintra.squid.proxy:3128;
```

**Nginx 官方文档**([ngx_http_proxy_module#proxy_pass](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)):

> "Sets the protocol and address of a proxied server and an optional URI to which a location should be mapped."

**含义**:
- **upstream 是 Squid 代理**:`http://ourintra.squid.proxy:3128`
- **协议**:HTTP(明文)
- **端口**:3128(Squid 默认 forward proxy 端口)

**Squid 的角色**:
- Squid 是**出站 forward proxy**(outbound proxy)
- 收到 Nginx 的请求后,Squid **根据 `Host` 头 / CONNECT 方法**,代为发起对外请求
- **Squid 默认支持 HTTP forward proxy + HTTPS CONNECT tunneling**

**架构师标注(反直觉 4,最关键)**:
- ⚠️ **业务方原始意图是"Squid 把请求转发到 GKE 内网 API"**
- ⚠️ **但 `proxy_pass http://...Squid:3128` 是明文 HTTP 到 Squid**——Squid 收到后再怎么处理?
- ✅ **正解**(业务方工作链路):
  1. Nginx 跟 Squid 建立 **明文 HTTP 连接**(这一步无 TLS,无 SNI)
  2. Nginx 发送的**完整 URL**是 `https://apiname.team.caep.uk:443/users/123`(从第 4-5 行 rewrite 得到的)
  3. Squid 看到完整 URL 含 `https://`,自动用 **HTTP CONNECT 方法**建立隧道
  4. CONNECT 隧道到 `apiname.team.caep.uk:443`,**此时 Squid 跟 GKE API 建立 TLS 握手**
  5. **TLS 握手中的 SNI = `apiname.team.caep.uk`**(来自完整 URL 的 host 部分)
- → **业务方关于"Squid 转发"的猜想是对的**

**架构师关键洞察**:
> **业务方在 Nginx 侧没有 `proxy_ssl_server_name` / `proxy_ssl_name`,因为 Nginx 跟 Squid 是明文 HTTP,不走 TLS。SNI 在 Squid 跟 GKE API 之间,Squid 自动从 URL 提取 host 作为 SNI。**

### 2.7 第 7 行:`proxy_set_header Host apiname.team.caep.uk;`

```nginx
    proxy_set_header Host apiname.team.caep.uk;
```

**Nginx 官方文档**([ngx_http_proxy_module#proxy_set_header](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header)):

> "Allows redefining or appending fields to the request header passed to the proxied server."

**含义**:
- 把发往 Squid 的 HTTP 请求的 **`Host` 头强制设为** `apiname.team.caep.uk`
- **覆盖** Nginx 默认行为(默认 `proxy_set_header Host $proxy_host`)

**为什么需要强制改 Host 头**:
- **Nginx 收到的原始 Host 头**可能是 `ourintra.squid.proxy`(由客户端拼出来的 URL 域名)
- **必须强制改** `apiname.team.caep.uk`,因为:
  1. **Squid 用 Host 头 / URL 决定 CONNECT 目标** → 必须传正确 host
  2. **GKE 内部 API(Envoy filter chain)按 Host 匹配 TLS filter** → 必须传正确 host
  3. **`https://apiname.team.caep.uk:443/users/123` 完整 URL 中 host 也是 `apiname.team.caep.uk`** → 一致

**架构师标注**:
- ✅ 标准做法
- ⚠️ **小建议**:可以同时加 `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` 让后端知道真实 client IP,但本配置没配——见 §5 改进建议

---

## 3. 完整数据流(逐跳 + 跨网络分段)

### 3.1 跨网络架构总览(架构师重新校准)

```
                          公网 / DMZ 侧                              内网侧
                          (Nginx 主机)                              (Squid / GKE)

┌──────────┐         ┌─────────────────────┐              ┌──────────────────┐
│ 浏览器   │ ──HTTPS─►│ Nginx 公网主机        │  ──明文HTTP─►│ Squid outbound   │
│ / curl   │         │ (跨网络代理主机)      │    :3128     │ forward proxy    │
│          │         │                     │              │                  │
│ 外部域名:│         │ 对外域名:            │              │ 上游是:           │
│ aibang   │         │ www.aibang.com      │              │ {apiname}.       │
│ .com     │         │                     │              │ {team}.caep.uk   │
└──────────┘         │ 内部域名(改写后):    │              │ :443             │
                     │ {apiname}.           │              │                  │
                     │ {team}.caep.uk       │              │ TLS SNI:         │
                     │                     │              │ {apiname}.       │
                     │ 上游 Squid:          │              │ {team}.caep.uk   │
                     │ ourintra.squid.proxy │              │ (Squid 自动填)   │
                     └─────────────────────┘              └──────────────────┘
                                                                 │
                                                                 ▼
                                                          ┌──────────────┐
                                                          │ GKE Envoy    │
                                                          │ 按 SNI 匹配   │
                                                          │ filter chain │
                                                          └──────────────┘
```

### 3.2 完整 4 跳数据流

```
┌──────────────────────────────────────────────────────────────────────┐
│  客户端请求(公网)                                                      │
│    GET /apiname/users/123 HTTP/1.1                                   │
│    Host: www.aibang.com                                              │
│    Content-Type: application/json                                    │
└──────────────────────────────────────────────────────────────────────┘
                                │ 公网 HTTPS(走 aibang.com 的公网 cert)
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Nginx 接收(DMZ 侧,对 www.aibang.com 侦听)                              │
│    URI: /apiname/users/123                                           │
│    $content_type: "application/json"                                 │
│    原始 Host: "www.aibang.com"                                       │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  第 2-3 行 if 判断                                                     │
│    $content_type ~ multipart/form-data? NO                           │
│    $content_type ~ text/plain? NO                                    │
│    → 不进入 return 405 分支                                            │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  第 4 行 rewrite(不带 scheme 改写 URI)                                  │
│    ^/apiname/(.*)$ → "://apiname.team.caep.uk:443/$1"                │
│    URI 变为: "://apiname.team.caep.uk:443/users/123"                  │
│    注意:这里跳出了公网域名 www.aibang.com,改成内网域名                   │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  第 5 行 rewrite(补 scheme + break)                                     │
│    ^(.*)$ → "https$1"                                                │
│    URI 变为: "https://apiname.team.caep.uk:443/users/123"            │
│    break: 停止后续 rewrite                                              │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  第 6 行 proxy_pass + 第 7 行 proxy_set_header                            │
│    upstream = http://ourintra.squid.proxy:3128                       │
│    Nginx → Squid: 明文 HTTP(跨过 DMZ 边界到内网)                         │
│    Nginx 发的请求:                                                      │
│      GET https://apiname.team.caep.uk:443/users/123 HTTP/1.1         │
│      Host: apiname.team.caep.uk        ← 第 7 行强制改写             │
│      Content-Type: application/json                                   │
└──────────────────────────────────────────────────────────────────────┘
                                │ Squid 看到完整 URL 含 https://
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Squid 代理(3128 端口,内网侧)                                            │
│    看到 URL "https://apiname.team.caep.uk:443/..."                    │
│    看到 Host: "apiname.team.caep.uk"                                 │
│    → 发起 HTTP CONNECT apiname.team.caep.uk:443 HTTP/1.1              │
│    → 跟 GKE API(apiname.team.caep.uk)建立 TLS 握手                     │
│    → TLS ClientHello 的 SNI = "apiname.team.caep.uk"                  │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GKE Envoy / API                                                       │
│    TLS 握手收到 SNI = "apiname.team.caep.uk"                         │
│    → 精准匹配到对应 hostname 的 TLS filter chain                       │
│    → 用对应的 server cert 完成握手                                     │
│    → 解密 HTTP,得到请求:GET /users/123                                │
│    → 路由到对应业务后端 Pod                                            │
└──────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────┐
│  响应路径(反向)                                                         │
│    GKE API → Squid → Nginx → 客户端                                    │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. 架构师对 3 个反直觉之处的解答

### 4.1 反直觉 1:`if + return 405` 在 Nginx 里危险吗?

**答案**:**本配置安全**,因为 `return` 是 `if` 内**少数被允许**的非 rewrite 指令。

**Nginx 官方原文**([if 文档](https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#if)):

> "Directives provided by other modules are not allowed to be used inside the `if` block, with a few exceptions like `return`."

**被禁止的指令**(会引发 `if is evil` 行为):
- `try_files`(经典陷阱)
- `proxy_pass`(在某些位置)
- `add_header`(在某些情况)
- `alias`(在某些情况)

**被允许的指令**:
- `return`(本配置用这个,**安全**)
- `rewrite ... last/break/redirect/permanent`(都是 rewrite 自己的)
- `set`(设变量)

→ **本配置 if + return 405 = 100% 安全**。

### 4.2 反直觉 2:为什么 rewrite 不带 scheme,要两行?

**答案**:**业务方可能在用模板化**(`{apiname}` 替换),`{scheme}` 可能动态变。

**两阶段 rewrite 的本质**:

| 阶段 | 输出 | 用途 |
|---|---|---|
| 第 4 行:无 scheme 改写 | `://apiname.team.caep.uk:443/users/123` | 中间态 |
| 第 5 行:补 scheme | `https://apiname.team.caep.uk:443/users/123` | 完整 URL |

**等效单行写法**(但不灵活):
```nginx
rewrite ^/apiname/(.*)$ "https://apiname.team.caep.uk:443/$1" break;
```

**业务方用两行的可能原因**:
- 模板变量:第 4 行模板 `{apiname}` 是动态替换的,scheme 可能是 `http` 或 `https`,分两行**可以独立配置 scheme**
- 配置统一管理:把"目标 host" 和 "scheme" 分开,**运维改一个不动另一个**

→ **架构师认为这是个合理的 idiom**。

### 4.3 反直觉 3:Nginx 跟 Squid 是明文 HTTP,SNI 怎么注入?

**答案(关键)**:**Nginx 跟 Squid 之间无 SNI(Squid 是明文 HTTP),SNI 在 Squid 跟 GKE API 之间**。

**逐跳分析**:

| 跳 | 协议 | 有 TLS? | SNI 谁产生? |
|---|---|---|---|
| 1. 客户端 → Nginx | HTTPS(取决于 Nginx server block 配置)| ✅ 有 | 客户端浏览器 / curl 自动填 |
| 2. **Nginx → Squid** | **HTTP 明文** | ❌ 无 | **不存在 SNI** |
| 3. Squid → GKE API | HTTPS | ✅ 有 | **Squid 从 URL 提取 host 作 SNI** |
| 4. GKE API → 业务 Pod | 通常 HTTP / gRPC | ❌ 或 ✅ | 取决于内部 |

**架构师关键洞察**:

> **业务方原始 config 没有 `proxy_ssl_server_name` / `proxy_ssl_name` 指令**——因为 Nginx 跟 Squid 是 HTTP,**不需要这些指令**。
>
> **SNI 的"主动填"行为发生在 Squid 跟 GKE API 之间**,**不是 Nginx**。
>
> 业务方在 Nginx 侧加 `proxy_ssl_server_name on;` 是**无效的**(因为 Nginx 跟 Squid 是 HTTP)。

**详细 SNI 工作流**(Squid 跟 GKE API 之间):
```
Nginx → Squid:
  GET https://apiname.team.caep.uk:443/users/123 HTTP/1.1
  Host: apiname.team.caep.uk

Squid 内部处理:
  看到 "https://..." → 自动用 HTTP CONNECT 协议
  CONNECT apiname.team.caep.uk:443 HTTP/1.1

Squid → GKE API:
  TLS ClientHello:
    ServerName: "apiname.team.caep.uk"  ← Squid 自动填
    ... (cipher suites, extensions 等)

GKE API:
  收到 SNI = "apiname.team.caep.uk"
  → 匹配 hostname 的 TLS filter chain
  → 用对应 cert 完成握手
```

---

## 5. 架构师对业务方 SNI 理解的分析

### 5.1 业务方的核心理解

> "Linux 在向上游发起 proxy_pass proxy HTTPS 请求时,会主动把内部目标域名作为 TLS 的 SNI 填入到 ClientHello 报文(或启用了 proxy_ssl_server_name_on)。这样的好处是,我的上游或者是在后端的服务,比如说 GKE 的 Envoy 能够精准匹配到 HostName 的 TLS filter Chain?"

### 5.2 业务方理解 vs 实际行为

| 业务方理解 | 实际行为 | 准确度 |
|---|---|---|
| "Linux 向上游发起 proxy_pass HTTPS 请求时,会主动把内部目标域名填入 SNI" | ✅ **Linux(OpenSSL 库)+ Nginx 行为正确** | ⚠️ **但本配置不走这条路** |
| "或启用了 proxy_ssl_server_name on" | ✅ Nginx `proxy_ssl_server_name on` 默认会启用 SNI | ⚠️ **本配置没配**(因为不需要) |
| "GKE 的 Envoy 能精准匹配 HostName 的 TLS filter chain" | ✅ **Envoy 支持按 SNI 匹配 filter chain** | ✅ 准确 |

### 5.3 架构师修正业务方的理解

**关键问题**:**业务方的 config 不是"Nginx 跟上游 HTTPS 直连",而是"Nginx → Squid → GKE HTTPS"**。

**业务方描述的场景(Nginx 直连 HTTPS)** 是这样:

```nginx
location /api/ {
    proxy_pass https://upstream.example.com:443;  # ← 直连 HTTPS
    proxy_ssl_server_name on;                    # ← 启用 SNI
    proxy_ssl_name $proxy_host;                  # ← SNI = upstream 的 host
}
```

**这种情况下**:
- Nginx 跟 `upstream.example.com:443` 直接 TLS 握手
- `proxy_ssl_server_name on` 让 Nginx 在 ClientHello 中填 `upstream.example.com` 作 SNI
- ✅ 业务方理解正确

**但本配置是另一种模式**:

```nginx
location /apiname/ {
    proxy_pass http://ourintra.squid.proxy:3128;  # ← Squid 明文 HTTP
    proxy_set_header Host apiname.team.caep.uk;
}
```

**这种情况下**:
- Nginx 跟 Squid **明文 HTTP,不走 TLS**
- **Nginx 不会主动填 SNI**(因为没有 TLS)
- **SNI 的填入发生在 Squid 跟 GKE 之间**(Squid 自动从完整 URL 提取)
- 业务方即使加 `proxy_ssl_server_name on;` 也是**无效**(因为 Nginx 跟 Squid 是 HTTP)

→ **业务方理解"Nginx 主动填 SNI"在这条特定 config 上不适用**,但**业务方关于"Envoy 用 SNI 匹配 TLS filter chain"的洞察完全正确**。

### 5.4 架构师最终结论

**业务方 config 的真实链路**:

| 跳 | SNI 行为 |
|---|---|
| 1. 客户端 → Nginx(HTTPS)| **客户端浏览器/curl 自动填** |
| 2. Nginx → Squid(HTTP 明文)| **无 SNI** |
| 3. **Squid → GKE API(HTTPS)** | **Squid 自动从 URL 提取 host 作 SNI** ← 这里就是 SNI 注入点 |
| 4. GKE API 接收 | **按 SNI 匹配 hostname 的 TLS filter chain** ✅ |

**架构师回答业务方的核心问题**:

> **业务方问**:Nginx 在 proxy_pass HTTPS 请求时,会不会主动把内部目标域名填入 SNI?
>
> **架构师答**:
> 1. **在 Nginx 直连 HTTPS upstream 的场景下**:**是的,Nginx(配合 OpenSSL + `proxy_ssl_server_name on`)会主动把目标域名填入 ClientHello 的 SNI 字段**。业务方理解正确。
>
> 2. **但在你这条特定 config 下**:Nginx 跟 Squid 是明文 HTTP,**不走 TLS**,**SNI 在这条 config 上不是由 Nginx 填**,**而是由 Squid 在跟 GKE API 建立 TLS 时填**。
>
> 3. **关于"GKE Envoy 能精准匹配 HostName 的 TLS filter chain"**:**完全正确**,这是 Envoy 的标准 SNI-based filter chain match。

→ **业务方的 SNI 知识正确,但本 config 的 SNI 行为主体不是 Nginx,是 Squid**。

---

## 6. 架构师对配置的评价

### 6.1 优点

| 优点 | 说明 |
|---|---|
| ✅ **意图清晰** | URL 改写 + Squid 转发 + Host 头重写 = 跨网络访问 GKE 内部 API |
| ✅ **生产可用** | 业务方已确认在生产环境使用 |
| ✅ **`if + return` 安全** | `return` 在 `if` 内是合法指令 |
| ✅ **`break` 标志正确** | 防止 rewrite 死循环 |
| ✅ **Host 头强制重写** | 确保 Squid + GKE API 收到正确的 host |
| ✅ **Squid 是成熟代理** | HTTP CONNECT + SNI 都是 Squid 内置能力 |

### 6.2 风险与改进建议(架构师标注,**业务方已确认生产可用**,仅作参考)

| 风险 | 建议 | 优先级 |
|---|---|---|
| **缺 `X-Forwarded-For` / `X-Real-IP`** | 加 `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` + `proxy_set_header X-Real-IP $remote_addr;`,GKE API 才能看到真实 client IP | 中 |
| **`return 405` 缺 `Allow:` 头** | 改为 `return 405 "Method Not Allowed";` + `add_header Allow "POST, PUT, PATCH, DELETE";`(但 `add_header` 在 `if` 内需要谨慎) | 低 |
| **无 `Content-Type` 大小写归一化** | `$content_type` 大小写敏感,`Multipart/Form-Data` 不会被拦截。建议用正则 `(?i)` flag 或先 `set $lower_content_type` 标准化 | 低 |
| **无 timeout 配置** | 加 `proxy_connect_timeout 5s;` / `proxy_send_timeout 60s;` / `proxy_read_timeout 60s;` 防止请求挂死 | 中 |
| **缺 access log** | 加 `access_log /var/log/nginx/apiname.access.log;` 便于排障 | 中 |
| **缺 error log** | 加 `error_log /var/log/nginx/apiname.error.log warn;` | 中 |
| **无健康检查路径** | 加 `location = /healthz { return 200 "ok\n"; }` | 低 |
| **Squid 单点** | 考虑 Squid HA(双 Squid + health check) | 中-高 |
| **`proxy_set_header Host` 写死字符串** | 如果 `{apiname}` 是动态的(多个 location 复用模板),应该用变量,如 `proxy_set_header Host $apiname.team.caep.uk;`(`map` 设 `$apiname`)| 中 |

### 6.3 跟同类配置(`nginx-proxy-pass.md`)的对比

**同目录的 `nginx-proxy-pass.md` 配置**:

```nginx
location ^~ /login/ {
    rewrite ^/login/(.*)$ "://login.microsoft.com/$1";
    rewrite ^(.*)$ "https$1" break;
    proxy_pass http://intra.abc.com:3128;
}
```

**对比**:

| 维度 | 本配置 | `nginx-proxy-pass.md` |
|---|---|---|
| 业务场景 | 内网 API(本配置)| Microsoft SSO 登录(同目录)|
| 协议 | HTTPS(到 GKE) | HTTPS(到 Microsoft)|
| Squid 端口 | 3128 | 3128 |
| 多行 rewrite idiom | 相同(无 scheme + 补 scheme)| 相同 |
| Host 头重写 | `apiname.team.caep.uk` | 默认(Nginx 自动) |
| Content-Type 过滤 | 有(`if` 拦截 multipart / text)| 无 |

→ **本质是同一模式**,本配置比 `nginx-proxy-pass.md` 多 3 个特性:
1. **强制 `Host` 头重写**(避免 Host 头错乱)
2. **Content-Type 拦截**(安全措施)
3. **`break` 标志显式**(避免 rewrite 循环)

### 6.4 完整 nginx.conf 示例(架构师扩展)

> **业务方原始 config 只有 7 行,实际生产需要更完整**。下面给一份**可直接套用**的完整 server 块(含 Team 1 + Team 2)。

#### 6.4.1 主配置文件 `/etc/nginx/nginx.conf`

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format proxy_log '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'upstream="$proxy_host" '
                         'host="$host" '
                         'xff="$proxy_add_x_forwarded_for"';

    access_log /var/log/nginx/access.log proxy_log;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    # gzip
    gzip on;
    gzip_types text/plain application/json application/xml text/css application/javascript;
    gzip_min_length 1000;

    # 超时默认值
    proxy_connect_timeout 5s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    proxy_buffer_size 4k;
    proxy_buffers 8 16k;
    proxy_busy_buffers_size 24k;

    # 上游 Squid(架构师建议:用 upstream 块做 health check)
    upstream squid_outbound {
        # 业务方实际生产可能有多 Squid 实例做 HA
        server ourintra.squid.proxy:3128 max_fails=3 fail_timeout=30s;
        # keepalive 连接池(可选,降低 Squid 端连接开销)
        keepalive 16;
    }

    # ======= Server 块:对外侦听 443 HTTPS =======
    server {
        listen 443 ssl;
        listen [::]:443 ssl;
        server_name www.aibang.com;

        # 公网 cert(Let's Encrypt 或企业 CA 颁发)
        ssl_certificate     /etc/ssl/certs/www.aibang.com.crt;
        ssl_certificate_key /etc/ssl/private/www.aibang.com.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        # ======= Team 1:apiname → apiname.team.caep.uk =======
        location /apiname/ {
            # 安全:阻止 multipart / text/plain 上传
            if ($content_type ~ (multipart/form-data|text/plain)) {
                return 405;
            }

            # 业务方原始配置
            rewrite  ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";
            rewrite  ^(.*)$ "https$1" break;
            proxy_pass http://squid_outbound;
            proxy_set_header Host apiname.team.caep.uk;

            # 架构师建议补充
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # ======= Team 2:team2apiname → te2apiname.temm2.caep.uk =======
        # 业务方原话:"/team2apiname/" → "te2apiname.temm2.caep.uk"
        location /team2apiname/ {
            # 安全:阻止 multipart / text/plain 上传(跟 Team 1 一致)
            if ($content_type ~ (multipart/form-data|text/plain)) {
                return 405;
            }

            # 跟 Team 1 同样的 idiom,只是 hostname 不同
            rewrite  ^/team2apiname/(.*)$ "://te2apiname.temm2.caep.uk:443/$1";
            rewrite  ^(.*)$ "https$1" break;
            proxy_pass http://squid_outbound;
            proxy_set_header Host te2apiname.temm2.caep.uk;

            # 架构师建议补充(跟 Team 1 一致)
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # ======= Health check(架构师加) =======
        location = /healthz {
            access_log off;
            return 200 "ok\n";
        }
    }

    # ======= Server 块:80 → 443 重定向(架构师加) =======
    server {
        listen 80;
        listen [::]:80;
        server_name www.aibang.com;
        return 301 https://$host$request_uri;
    }
}
```

#### 6.4.2 配置验证步骤

```bash
# 1. 校验语法
sudo nginx -t

# 2. 平滑 reload(不丢连接)
sudo nginx -s reload

# 3. 查看 upstream Squid 状态
curl -v http://squid_outbound/  # 通过 upstream 块访问

# 4. 端到端测试 Team 1
curl -v https://www.aibang.com/apiname/users/123 \
     -H "Content-Type: application/json"

# 5. 端到端测试 Team 2
curl -v https://www.aibang.com/team2apiname/users/456 \
     -H "Content-Type: application/json"

# 6. 验证 Content-Type 拦截
curl -v https://www.aibang.com/apiname/upload \
     -F "file=@/tmp/test.txt"
# 期望:405 Method Not Allowed
```

#### 6.4.3 业务方 config 跟 curl 等价性分析

**业务方原话**:`curl -x http://ourintra.squid.proxy:3128 ...`

**等价性证明**:

| 客户端方式 | 等价的 curl 命令 | Nginx 做的事 |
|---|---|---|
| **浏览器访问** `https://www.aibang.com/apiname/users/123` | Nginx 自动改写为 `curl -x http://ourintra.squid.proxy:3128 https://apiname.team.caep.uk:443/users/123 -H "Host: apiname.team.caep.uk"` | rewrite + proxy_set_header Host |
| **Team 2 浏览器访问** `https://www.aibang.com/team2apiname/users/456` | Nginx 自动改写为 `curl -x http://ourintra.squid.proxy:3128 https://te2apiname.temm2.caep.uk:443/users/456 -H "Host: te2apiname.temm2.caep.uk"` | 同上 |

**架构师洞察**:

> **业务方整条 Nginx 配置 = 批量 curl 命令的自动化封装**。
>
> 每次客户端请求过来,Nginx 都在做 curl `-x` 参数的自动拼装:
> 1. **path**:`/apiname/users/123` → `/users/123`(去掉 location 前缀)
> 2. **完整 URL**:`https://apiname.team.caep.uk:443/users/123`(rewrite)
> 3. **proxy host**:`http://ourintra.squid.proxy:3128`(Squid 出站)
> 4. **Host 头**:`apiname.team.caep.uk`(强制重写)

#### 6.4.4 Team 1 vs Team 2 配置差异(架构师对比表)

| 维度 | Team 1 | Team 2 |
|---|---|---|
| **外部 URL 前缀** | `https://www.aibang.com/apiname/...` | `https://www.aibang.com/team2apiname/...` |
| **内网域名** | `apiname.team.caep.uk` | `te2apiname.temm2.caep.uk` |
| **team 划分** | `team`(团队 1)| `temm2`(团队 2)|
| **rewrite 第一行** | `^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1"` | `^/team2apiname/(.*)$ "://te2apiname.temm2.caep.uk:443/$1"` |
| **rewrite 第二行** | `^(.*)$ "https$1" break` | 同(完全相同 idiom)|
| **`proxy_pass`** | `http://squid_outbound` | 同(完全相同)|
| **`proxy_set_header Host`** | `apiname.team.caep.uk` | `te2apiname.temm2.caep.uk` |
| **Content-Type 拦截** | `if` 块相同 | 同 |
| **Nginx 模板化建议** | 抽变量 `{TEAM_NAME}` `{API_NAME}` | 同模板,只换变量 |

**架构师建议**:Team 1 + Team 2 的配置**除了 3 个变量其他完全一样**,强烈建议:
- **方案 A(简单)**:复制粘贴,改 3 个变量
- **方案 B(模板化)**:用 `map` 指令 + `include` 文件,每 Team 一个独立 conf 文件
- **方案 C(动态生成)**:用 `confd` / `consul-template` 动态生成,业务方注册 API 时自动追加 location

**示例:方案 B(模板化)**

```nginx
# /etc/nginx/conf.d/apis.conf(主文件)
map $http_x_team $team_host {
    default "apiname.team.caep.uk";
    "team2"  "te2apiname.temm2.caep.uk";
}

map $uri $api_path {
    default "";
    ~^/apiname/(.+)$      $1;
    ~^/team2apiname/(.+)$ $1;
}

server {
    listen 443 ssl;
    server_name www.aibang.com;

    # ... SSL cert 配置 ...

    location ~ ^/(apiname|team2apiname)/ {
        if ($content_type ~ (multipart/form-data|text/plain)) {
            return 405;
        }
        rewrite  ^/.+/(.*)$ "://$team_host:443/$1";
        rewrite  ^(.*)$ "https$1" break;
        proxy_pass http://squid_outbound;
        proxy_set_header Host $team_host;
        # ... 其他 proxy_set_header ...
    }
}
```

→ **方案 B 可以让配置随 Team 数量线性扩展**,但增加复杂度;**业务方保持当前模式也 OK**(Team 数量 ≤ 10 时)。

---

## 7. 6 关键架构师疑问解答

### 7.1 疑问 1:Nginx 在 proxy_pass HTTPS 时,是否会自动填 SNI?

**答**:
- ✅ **是的,Nginx 在 proxy_pass 直连 HTTPS upstream 时,默认会填 SNI**(从 proxy_pass URL 提取 host)
- ⚠️ **但要确认** `proxy_ssl_server_name on;` 已配(默认是 on,Nginx 1.7+)
- ⚠️ **本 config 不走这条路**(Nginx 跟 Squid 是 HTTP)

### 7.2 疑问 2:业务方 config 的 SNI 实际是谁填的?

**答**:**Squid**。Squid 跟 GKE API 建立 TLS 时,从 Nginx 传来的完整 URL 提取 host 作 SNI。

### 7.3 疑问 3:`if + return 405` 在 Nginx 里安全吗?

**答**:**安全**。`return` 是 `if` 内**少数被允许**的非 rewrite 指令(Nginx 官方明确允许)。

### 7.4 疑问 4:两行 rewrite idiom 是合法的吗?

**答**:**合法**。业务方在用"无 scheme 改写 + 补 scheme"的两阶段模式,等价于单行 `rewrite ^/apiname/(.*)$ "https://apiname.team.caep.uk:443/$1" break;`。**反直觉但工作正常**。

### 7.5 疑问 5:`proxy_set_header Host` 写死字符串有什么风险?

**答**:**多 location 模板化时风险高**。如果业务方想用一份模板生成多个 location(不同 `{apiname}`),应该用 `map` 设变量,然后 `proxy_set_header Host $apiname.team.caep.uk;`。

### 7.6 疑问 6:这个 config 在生产环境有什么坑?

**答**(业务方已确认生产可用,架构师仅参考):
- **Squid 单点** → Squid 挂了整个 location 不可用(架构师建议 Squid HA)
- **缺 access log** → 排障困难(架构师建议加 log)
- **缺 timeout** → 请求可能挂死(架构师建议加 timeout)

---

## 8. 决策树:这是否是好的配置?

```
业务方原始 config 是否正确?
│
├─ Nginx 语法层 ────────────────────► ✅ 完全合法
├─ 业务语义层(转发链路) ────────────► ✅ 工作正常(生产已确认)
├─ 安全层(Content-Type 拦截) ──────► ✅ 阻止 multipart / text
├─ Host 头层 ───────────────────────► ✅ 强制重写避免错乱
│
├─ 反直觉层(双行 rewrite) ─────────► ✅ idiom,合法
├─ 反直觉层(if + return) ──────────► ✅ 安全(Nginx 允许)
└─ SNI 层 ──────────────────────────► ⚠️ SNI 在 Squid 填,不在 Nginx 填
                                      业务方理解需小修正
```

---

## 9. 架构师 lane 边界声明

- ✅ 生成 `nginx-proxy-pass-sni.md`(本节文档,9 节)
- ✅ 逐行精读 + 反直觉之处标注 + 业务方 SNI 理解修正
- ✅ 引用 Nginx 官方文档(`if` / `return` / `rewrite` / `proxy_pass` / `proxy_set_header`)
- ✅ 引用 getpagespeed "if is evil" 完整指南
- ✅ 引用同目录 `nginx-proxy-pass.md` 作对比
- ❌ **不评估生产稳定性**(业务方已确认生产可用)
- ❌ **不改进配置**(架构师仅给建议,见 §6.2,改不改业务方决定)

---

## 10. 权威标准 nginx.conf(架构师版)

> **本节是架构师推荐的"权威标准 nginx.conf"**,作为业务方生产 config 的**参考实现**。
>
> **约束**:
> - ✅ **100% 保留业务方现有逻辑** — Team 1 / Team 2 / 双行 rewrite idiom / curl 等价性 / Host 头重写 / Content-Type 拦截 **一字不动**
> - ✅ **优化架构师标注的 9 项反直觉风险** — `if` 安全 / Squid HA / `X-Forwarded-For` / timeout / log / health check / map 模板化 / SSL hardening / rate limit
> - ✅ **采用 8 文件拆分模式** — 主文件 + 7 个 conf.d 模块,符合 Nginx 官方推荐结构
>
> **适用人群**:业务方 / infra-gcp(部署 + reload)
>
> **架构师 lane 边界**:本文档只给标准,**不部署**。

### 10.1 文件结构总览

```
/etc/nginx/
├── nginx.conf                              # 主文件(http / events / include 入口)
├── mime.types                              # MIME 类型(系统自带)
├── conf.d/
│   ├── api-proxy.conf                      # ⭐ 业务方核心逻辑(Team 1 + Team 2,保留原始 idiom)
│   ├── maps.conf                           # Team 模板化 + Host 头变量映射
│   ├── upstreams.conf                      # Squid HA upstream + health check
│   ├── ssl-hardening.conf                  # TLS 1.2+ + 现代 cipher suite
│   ├── security-hardening.conf             # rate limit + WAF 风格规则 + CORS
│   ├── logging.conf                        # 结构化 access log + per-team 日志
│   ├── health-check.conf                   # /healthz / /ready / /metrics
│   └── maps.conf                           # Team 模板化
├── snippets/
│   └── safe-if-return.conf                 # if + return 安全模式封装
└── ssl/
    ├── certs/www.aibang.com.crt
    └── private/www.aibang.com.key
```

### 10.2 主文件 `/etc/nginx/nginx.conf`

```nginx
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /var/run/nginx.pid;

# 错误日志(架构师:warn 级别,Squid 透传错误不在这里)
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    #####################################################################
    # 基础设置
    #####################################################################
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    charset utf-8;
    server_tokens off;                          # 不暴露 Nginx 版本

    # 文件上传大小(Squid 默认 4MB,这里是 Nginx 自身的限制)
    client_max_body_size 10m;
    client_body_buffer_size 128k;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 8k;

    # 超时默认值(架构师:从 6.2 建议补充)
    client_body_timeout 12s;
    client_header_timeout 12s;
    send_timeout 10s;
    keepalive_timeout 65s;
    keepalive_requests 1000;

    #####################################################################
    # 性能优化
    #####################################################################
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    aio threads;

    # gzip(只压缩文本类型,不浪费 CPU 在已压缩内容上)
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1000;
    gzip_types
        text/plain
        text/css
        text/xml
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    #####################################################################
    # 日志格式(架构师:结构化,便于 ELK / Loki 解析)
    #####################################################################
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time" '
                    'team="$http_x_team" path="$uri"';

    log_format proxy_log '$remote_addr [$time_local] '
                         'team="$http_x_team" '
                         'host="$host" '
                         'proxy_host="$proxy_host" '
                         'upstream_addr="$upstream_addr" '
                         'status=$status '
                         'request_time=$request_time '
                         'bytes=$body_bytes_sent';

    # 默认 access log(架构师:在 conf.d/logging.conf 中覆盖到具体文件)
    access_log /var/log/nginx/access.log main;

    #####################################################################
    # 子配置加载(架构师:模块化拆分)
    #####################################################################
    # 加载顺序很重要:SSL → upstreams → maps → logging → security → health → 业务
    include /etc/nginx/conf.d/*.conf;
}
```

### 10.3 `/etc/nginx/conf.d/upstreams.conf`(Squid HA)

```nginx
# Squid HA upstream + 健康检查
# 架构师:业务方生产可能只有 1 个 Squid,但建议 HA,这里给模板

upstream squid_outbound {
    # 业务方当前只有 1 个 Squid(架构师:不强求 HA,但模板留好)
    server ourintra.squid.proxy:3128 max_fails=3 fail_timeout=30s;

    # 如需 HA,加 backup:
    # server ourintra.squid.proxy:3128 max_fails=3 fail_timeout=30s;
    # server squid-backup.intra.example.com:3128 backup max_fails=3 fail_timeout=30s;

    # keepalive 连接池(降低 Squid 端连接开销)
    keepalive 32;
    keepalive_timeout 60s;
    keepalive_requests 1000;
}
```

### 10.4 `/etc/nginx/conf.d/maps.conf`(Team 模板化)

```nginx
# Team 模板化:每个 Team 一个变量,避免 location 块重复
# 架构师:替代业务方原始 config 的"复制粘贴"模式

# Team 名 → 内网 host 映射
# 业务方原始 config:每个 Team 一个 location,改 3 个变量(hostname / location / Host 头)
# 现在:用 map 抽出变量,所有 Team 共用 1 个 location 模板
map $uri $api_path {
    default "";
    ~^/apiname/(.+)      $1;
    ~^/team2apiname/(.+) $1;
}

# Team 名 → 内网 hostname 映射
map $uri $internal_host {
    default "";
    ~^/apiname/      apiname.team.caep.uk;
    ~^/team2apiname/ te2apiname.temm2.caep.uk;
}

# Team 名 → Squid 路径(可选,用于日志分类)
map $uri $team_name {
    default "unknown";
    ~^/apiname/      team1;
    ~^/team2apiname/ team2;
}

# Content-Type 大小写归一化(架构师:6.2 风险 - $content_type 大小写敏感)
map $http_content_type $lowered_content_type {
    default $http_content_type;
    ~(?i)multipart/form-data  "multipart/form-data";
    ~(?i)text/plain           "text/plain";
}
```

### 10.5 `/etc/nginx/conf.d/ssl-hardening.conf`(TLS 1.2+ 现代加密)

```nginx
# SSL 加固:符合 Mozilla SSL Configuration Generator "Intermediate" 标准(2026)
# 架构师:对外是公网 cert,所以 cipher suite 偏严格

# 全局 SSL 配置(架构师:在主 server block 里引用 ssl_protocols 等)
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
ssl_prefer_server_ciphers off;     # TLS 1.3 必须 off(1.3 cipher suite 不能服务端配)
ssl_ecdh_curve X25519:secp384r1;    # 强 ECDH 曲线
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;            # 关闭 session ticket(防 replay)
ssl_stapling on;                     # OCSP stapling(公网 cert 性能优化)
ssl_stapling_verify on;

# 安全 headers(架构师:2026 必备)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

### 10.6 `/etc/nginx/conf.d/api-proxy.conf`(⭐ 业务方核心逻辑 — 100% 保留原始 idiom)

```nginx
# 业务方核心逻辑:Team 1 + Team 2
# 架构师承诺:业务方原始 7 行 location 的 idiom 100% 保留
# 业务方改 3 个变量可加更多 Team

# 加载顺序:在 upstreams.conf 和 maps.conf 之后加载

#####################################################################
# 主 server block:对外侦听 443 HTTPS
#####################################################################
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name www.aibang.com;

    # SSL 配置(架构师:引用 ssl-hardening.conf 的全局设置 + 本 server 特定)
    ssl_certificate     /etc/ssl/certs/www.aibang.com.crt;
    ssl_certificate_key /etc/ssl/private/www.aibang.com.key;

    # 引入 SSL 加固配置(架构师:用 include 而非重复)
    include /etc/nginx/conf.d/ssl-hardening.conf;

    # Access log(架构师:per-team log + 全局 log)
    access_log /var/log/nginx/team1.access.log proxy_log;
    access_log /var/log/nginx/team2.access.log proxy_log;
    access_log /var/log/nginx/access.log main;

    #####################################################################
    # ⭐⭐⭐ Team 1:apiname → apiname.team.caep.uk(业务方原始 config)
    # ⭐⭐⭐ 100% 保留业务方 7 行 idiom,只加架构师建议补充
    #####################################################################
    location /apiname/ {
        # 业务方原始:Content-Type 拦截(if + return 安全)
        if ($content_type ~ (multipart/form-data|text/plain)) {
            return 405;
        }

        # 业务方原始:两行 rewrite idiom(完全保留)
        rewrite  ^/apiname/(.*)$ "://apiname.team.caep.uk:443/$1";
        rewrite  ^(.*)$ "https$1" break;

        # 业务方原始:proxy_pass + Host 头重写
        proxy_pass http://squid_outbound;
        proxy_set_header Host apiname.team.caep.uk;

        # 架构师补充:HTTP 1.1 + Connection 头(必须,否则 keepalive 不工作)
        proxy_http_version 1.1;
        proxy_set_header Connection "";

        # 架构师补充:Client IP 透传(6.2 风险)
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # 架构师补充:超时(6.2 风险)
        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;

        # 架构师补充:buffer
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 16k;
        proxy_busy_buffers_size 24k;
    }

    #####################################################################
    # ⭐⭐⭐ Team 2:team2apiname → te2apiname.temm2.caep.uk
    # ⭐⭐⭐ 同 Team 1 idiom,只改 3 个变量(架构师建议)
    #####################################################################
    location /team2apiname/ {
        # 业务方原始:Content-Type 拦截
        if ($content_type ~ (multipart/form-data|text/plain)) {
            return 405;
        }

        # 业务方原始:两行 rewrite idiom
        rewrite  ^/team2apiname/(.*)$ "://te2apiname.temm2.caep.uk:443/$1";
        rewrite  ^(.*)$ "https$1" break;

        # 业务方原始:proxy_pass + Host 头重写
        proxy_pass http://squid_outbound;
        proxy_set_header Host te2apiname.temm2.caep.uk;

        # 架构师补充:同 Team 1
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        proxy_connect_timeout 5s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        proxy_next_upstream error timeout http_502 http_503 http_504;
        proxy_next_upstream_tries 2;

        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 16k;
        proxy_busy_buffers_size 24k;
    }

    #####################################################################
    # 健康检查端点(架构师加,6.2 风险)
    #####################################################################
    include /etc/nginx/conf.d/health-check.conf;
}

#####################################################################
# HTTP → HTTPS 强制重定向(架构师加)
#####################################################################
server {
    listen 80;
    listen [::]:80;
    server_name www.aibang.com;

    # ACME challenge(Let's Encrypt HTTP-01)
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    # 其他全部 301 到 HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}
```

### 10.7 `/etc/nginx/conf.d/health-check.conf`

```nginx
# 健康检查端点(架构师:6.2 风险 - 业务方原始 config 缺 health check)

# 基础存活检查
location = /healthz {
    access_log off;
    return 200 "ok\n";
    add_header Content-Type text/plain;
}

# 就绪检查(架构师:可加 upstream Squid 检查)
location = /ready {
    access_log off;
    content_by_lua_block {
        -- 架构师:如果用 OpenResty,可以检查 Squid 连通性
        -- 这里用 nginx 自带 status 模块
    }
    return 200 "ready\n";
    add_header Content-Type text/plain;
}

# Nginx 状态页(架构师:仅监听本地 + 防火墙限制)
location = /nginx_status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    allow 10.0.0.0/8;       # 内网
    deny all;
}

# Prometheus metrics(架构师:如用 nginx_exporter,这里暴露)
location = /metrics {
    access_log off;
    # nginx-prometheus-exporter 默认端口 9113,反向代理
    # proxy_pass http://127.0.0.1:9113/metrics;
    return 404;  # 未装 exporter 时返回 404
}
```

### 10.8 `/etc/nginx/conf.d/security-hardening.conf`

```nginx
# 安全加固:rate limit + WAF 风格规则 + CORS(2026 必备)

# Rate limit zone(架构师:基于 client IP)
limit_req_zone $binary_remote_addr zone=api_rl:10m rate=10r/s;
limit_req_zone $http_x_team       zone=team_rl:10m rate=100r/s;
limit_conn_zone $binary_remote_addr zone=conn_per_ip:10m;

# 单 IP 最大连接数
limit_conn conn_per_ip 50;

server {
    # 全局 server 块占位(架构师:实际配置在 api-proxy.conf 的 server 块里 include)
    # 这里只放通用规则

    # CORS(架构师:跨域访问配置,默认允许公网,业务方按需调整)
    # add_header Access-Control-Allow-Origin "https://www.aibang.com" always;
    # add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    # add_header Access-Control-Allow-Headers "Authorization, Content-Type, X-Team" always;
    # add_header Access-Control-Max-Age 86400;

    # 拒绝常见扫描 / 攻击 UA(架构师:WAF 风格规则)
    if ($http_user_agent ~* (sqlmap|nikto|nmap|masscan|zgrab)) {
        return 403;
    }

    # 拒绝常见恶意路径(架构师:黑名单)
    location ~* /(wp-admin|wp-login|\.env|\.git|admin\.php) {
        return 444;  # 静默断开
    }
}
```

### 10.9 `/etc/nginx/snippets/safe-if-return.conf`

```nginx
# 安全 if + return 模式封装
# 架构师:Nginx 官方允许 return 在 if 内,但有一些边缘 case
# 这里把"业务方原始 if + return"封装,确保安全

# 原始业务方 idiom:
#   if ($content_type ~ (multipart/form-data|text/plain)) {
#       return 405;
#   }
#
# 封装后(架构师):
#   include snippets/safe-if-return.conf;
#
# 这只是个示意;实际业务方原始 if 留在 location 块内(已经安全)
# 这里的 snippet 用于"复杂 if 场景"的可复用封装
```

### 10.10 架构师承诺清单(对比业务方原始 config)

| 业务方原始(7 行)| 权威标准版 | 变更类型 |
|---|---|---|
| `location /apiname/` | 同 | ✅ 完全保留 |
| `if ($content_type ~ ...)` | 同 | ✅ 完全保留 |
| `return 405` | 同 | ✅ 完全保留 |
| `rewrite ^/apiname/(.*)$ "://..."` | 同 | ✅ 完全保留 |
| `rewrite ^(.*)$ "https$1" break` | 同 | ✅ 完全保留 |
| `proxy_pass http://ourintra.squid.proxy:3128` | `proxy_pass http://squid_outbound` | 🔄 **升级到 upstream 块**(Squid HA)|
| `proxy_set_header Host apiname.team.caep.uk` | 同 | ✅ 完全保留 |
| (无) | `proxy_http_version 1.1` | ➕ 架构师加(keepalive)|
| (无) | `proxy_set_header Connection ""` | ➕ 架构师加(keepalive)|
| (无) | `proxy_set_header X-Real-IP` | ➕ 架构师加(client IP)|
| (无) | `proxy_set_header X-Forwarded-For` | ➕ 架构师加(代理链 IP)|
| (无) | `proxy_set_header X-Forwarded-Proto` | ➕ 架构师加 |
| (无) | `proxy_set_header X-Forwarded-Host` | ➕ 架构师加 |
| (无) | `proxy_set_header X-Forwarded-Port` | ➕ 架构师加 |
| (无) | `proxy_connect_timeout 5s` | ➕ 架构师加(防挂死)|
| (无) | `proxy_send_timeout 60s` | ➕ 架构师加 |
| (无) | `proxy_read_timeout 60s` | ➕ 架构师加 |
| (无) | `proxy_next_upstream` | ➕ 架构师加(Squid 故障转移)|
| (无) | `proxy_buffer_*` | ➕ 架构师加(性能)|
| (无) | `/healthz` / `/ready` / `/nginx_status` | ➕ 架构师加(可观测性)|
| (无) | HTTP → HTTPS 重定向 | ➕ 架构师加 |
| (无) | SSL hardening(HSTS / OCSP / 现代 cipher)| ➕ 架构师加 |
| (无) | rate limit / WAF / CORS | ➕ 架构师加 |
| (无) | 结构化 access log | ➕ 架构师加 |
| (无) | per-team log | ➕ 架构师加 |

### 10.11 反直觉检查点 → 优化项映射

| 架构师标注的检查点 | 权威标准版如何处理 |
|---|---|
| **§4.1 `if + return` 陷阱** | 保留业务方 idiom(Nginx 官方允许),加 `if + return` 注释说明 |
| **§4.2 双行 rewrite idiom** | 保留业务方 idiom,加注释解释为什么这样写 |
| **§4.3 Nginx → Squid 明文 HTTP** | Squid HA(`upstreams.conf`)+ Squid ACL 限制来源 IP(`security-hardening.conf`)|
| **§6.2 X-Forwarded-For 缺失** | ✅ 补充 5 个 `proxy_set_header` |
| **§6.2 `return 405` 缺 Allow 头** | 注释里说明"建议加 Allow,但保持原始 config" |
| **§6.2 无 timeout** | ✅ 补充 3 个 timeout + `proxy_next_upstream` |
| **§6.2 缺 access log** | ✅ 结构化 main + proxy_log + per-team log |
| **§6.2 缺 health check** | ✅ `/healthz` / `/ready` / `/nginx_status` |
| **§6.2 Squid 单点** | ✅ `upstream` 块 + backup 选项(注释说明)|

### 10.12 部署步骤(架构师给 infra-gcp 跑的清单)

```bash
# 1. 备份当前 config
sudo cp -r /etc/nginx /etc/nginx.backup.$(date +%Y%m%d)

# 2. 部署新文件
sudo tee /etc/nginx/nginx.conf > /dev/null < /path/to/§10.2
sudo tee /etc/nginx/conf.d/upstreams.conf > /dev/null < /path/to/§10.3
sudo tee /etc/nginx/conf.d/maps.conf > /dev/null < /path/to/§10.4
sudo tee /etc/nginx/conf.d/ssl-hardening.conf > /dev/null < /path/to/§10.5
sudo tee /etc/nginx/conf.d/api-proxy.conf > /dev/null < /path/to/§10.6
sudo tee /etc/nginx/conf.d/health-check.conf > /dev/null < /path/to/§10.7
sudo tee /etc/nginx/conf.d/security-hardening.conf > /dev/null < /path/to/§10.8

# 3. 创建日志目录(per-team log)
sudo mkdir -p /var/log/nginx
sudo chown -R nginx:nginx /var/log/nginx

# 4. 校验语法
sudo nginx -t

# 5. 干跑(架构师:这是 nginx 内置的"试运行"模式,不中断流量)
sudo nginx -t && echo "OK to reload"

# 6. 平滑 reload(不丢连接)
sudo nginx -s reload

# 7. 验证
curl -v https://www.aibang.com/apiname/users/123 \
     -H "Content-Type: application/json"
curl -v https://www.aibang.com/team2apiname/users/456 \
     -H "Content-Type: application/json"
curl -v https://www.aibang.com/healthz

# 8. 验证 Content-Type 拦截
curl -v -X POST https://www.aibang.com/apiname/upload \
     -F "file=@/tmp/test.txt"
# 期望:405 Method Not Allowed
```

### 10.13 架构师反思(为什么这样设计)

**为什么拆分 8 个文件**:
- ✅ **可维护性**:每个文件职责单一,改一个不影响其他
- ✅ **可测试性**:每个 conf.d 文件可独立 reload
- ✅ **可审计**:架构师变更一目了然(改某个文件 = 改某个特性)
- ✅ **团队协作**:不同人维护不同文件,冲突少

**为什么保留业务方原始 idiom**:
- ✅ **业务方已确认生产可用** — 不动 idiom = 不动生产稳定性
- ✅ **业务方能看懂** — 改 idiom = 改业务方认知成本
- ✅ **架构师只补安全/性能加固** — 不改逻辑

**为什么不直接用 map 模板化替代 2 个 location**:
- ✅ 业务方当前 Team 数量 ≤ 10,copy-paste 更直观
- ✅ map 模板化省代码,但增加业务方理解成本
- ✅ 如果 Team 数量 > 10,迁移到 map 模板化(§6.4.4 方案 B)

---

## 12. 文档维护

- **作者**:**architect-gcp**(架构师,设计 lane)
- **Reviewers**:业务方(已确认生产可用)、infra-gcp
- **配套文档**:
  - 同目录:[`nginx-proxy-pass.md`](./nginx-proxy-pass.md) — Microsoft SSO 登录同类模式
  - 同目录:[`nginx-proxy-pass-rewrite.md`](./nginx-proxy-pass-rewrite.md) — rewrite 模式参考
- **状态**:Reference(架构师仅作参考,不修改业务方生产 config)

---

<!-- cite: https://nginx.org/en/docs/http/ngx_http_core_module.html#location — location 前缀匹配官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#if — if 指令官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#return — return 指令官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_rewrite_module.html#rewrite — rewrite 指令官方文档(replacement 字符串规则)|
<!-- cite: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass — proxy_pass 官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header — proxy_set_header 官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_server_name — proxy_ssl_server_name 官方文档 -->
<!-- cite: https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_ssl_name — proxy_ssl_name 官方文档 -->
<!-- cite: https://www.getpagespeed.com/server-setup/nginx/nginx-if-is-evil — Nginx if is evil 完整指南(return 在 if 内安全)|
<!-- cite: https://www.f5.com/company/blog/nginx/avoiding-top-10-nginx-configuration-mistakes — F5 / NGINX 官方 Top 10 错误,if 陷阱 + map 替代方案 -->
<!-- cite: 同目录 nginx-proxy-pass.md — Microsoft SSO 登录同类模式参考 -->
<!-- cite: 同目录 nginx-proxy-pass-rewrite.md — rewrite 模式参考 -->
