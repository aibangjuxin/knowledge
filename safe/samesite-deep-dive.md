# SameSite Cookie 深度解析

**Date:** 2026-05-06
**Status:** Technical Deep-Dive
**Classification:** Internal — Safe to Share

---

## Table of Contents

1. [历史背景：为什么需要 SameSite](#1-历史背景为什么需要-samesite)
2. [核心概念：Origin vs Site vs Domain](#2-核心概念origin-vs-site-vs-domain)
3. [SameSite 的三种值](#3-samesite-的三种值)
4. [SameSite 能解决什么问题](#4-samesite-能解决什么问题)
5. [SameSite 与 Cookie 其他属性的关系](#5-samesite-与-cookie-其他属性的关系)
6. [场景深度分析](#6-场景深度分析)
7. [浏览器兼容性矩阵](#7-浏览器兼容性矩阵)
8. [常见误解与陷阱](#8-常见误解与陷阱)
9. [调试与验证方法](#9-调试与验证方法)
10. [迁移指南](#10-迁移指南)

---

## 1. 历史背景：为什么需要 SameSite

### 1.1 HTTP 的无状态困境

HTTP 协议本身是无状态的——服务器处理每一个请求时，都无法知道这个请求来自哪个用户。**Cookie** 的诞生就是为了解决这个问题：

```
客户端                      服务端
  |                            |
  |-- GET / -----------------> |
  |                            |  (无状态，不知道是谁)
  |<-- Set-Cookie: session=abc |
  |                            |
  |-- GET / (Cookie: session) ->|
  |                            |  (有状态，知道是同一用户)
```

### 1.2 Cookie 的双刃剑

Cookie 带来了状态管理的能力，但也引入了安全问题。**CSRF（跨站请求伪造）** 就是最典型的攻击向量。

#### CSRF 攻击原理

```
用户已登录: https://bank.example.com
Cookie 已设置: Set-Cookie: session=abc123

攻击者构造恶意页面: https://evil.com

用户在 evil.com 页面时，浏览器会自动发送 bank.example.com 的 cookie：
<img src="https://bank.example.com/transfer?to=hacker&amount=10000">

浏览器对于 <img>、<script>、<link> 等标签的请求，会自动携带同站 Cookie
→ CSRF 攻击成功
```

### 1.3 第三方 Cookie 的原罪

当用户访问 `www.aibang.com` 时，页面可能加载来自 `analytics.com`、`ads.com` 等第三方的资源。这些第三方也会设置 Cookie，浏览器会将它们视为 **Third-Party Cookie（第三方 Cookie）**。

```
用户访问 www.aibang.com
页面内嵌: <script src="https://tracker.com/script.js">

tracker.com 可以设置 Cookie:
Set-Cookie: uid=xxx; Domain=tracker.com

用户在访问 shop.aibang.com 时，tracker.com 的 Cookie 也会被发送
→ 跨站追踪成为可能
```

### 1.4 SameSite 的诞生

| 时间 | 事件 |
|------|------|
| 2016 | Chrome 51 首次引入 `SameSite` 属性 |
| 2019 | Chrome 76+ 默认启用 `SameSite=Lax` |
| 2020 | Chrome 80 强制执行 SameSite-by-default（未指定 = Lax） |
| 2021 | Firefox 79+ 默认开启 Total Cookie Protection |
| 2022 | Safari 15+ 增强 ITP（Intelligent Tracking Prevention） |
| 2024 | Chrome 进入 Third-Party Cookie Deprecation 阶段 |

> **关键时间点**：Chrome 80（2020年2月）是转折点——未指定 `SameSite` 的 Cookie 默认变为 `Lax`。这导致大量历史遗留系统出现跨域认证问题。

---

## 2. 核心概念：Origin vs Site vs Domain

理解 SameSite 的前提是理清这三个容易混淆的概念。

### 2.1 Origin（源）

**定义：** `scheme://host:port` 的精确组合

```
https://www.aibang.com:443
  └── scheme:   https
  └── host:     www.aibang.com
  └── port:     443
```

| URL A | URL B | 同 Origin？ |
|-------|-------|:-----------:|
| `https://www.aibang.com` | `https://www.aibang.com:443` | ✅ |
| `https://www.aibang.com` | `https://api.aibang.com` | ❌ |
| `https://www.aibang.com` | `http://www.aibang.com` | ❌ |
| `https://www.aibang.com` | `https://www.aibang.com:8080` | ❌ |

### 2.2 Site（站点）

**定义：** 共享同一个 **eTLD+1**（effective Top-Level Domain + 1）的所有主机名。

**eTLD（有效顶级域）：** 公共后缀列表（Public Suffix List）中注册的后缀。

```
.com          → TLD（顶级域）
aibang.com    → eTLD+1（有效域名，aibang 是注册在 .com 下的二级域名）

所有 *.aibang.com 的子域名都属于同一个 Site
```

| URL A | URL B | 同 Site？ | 说明 |
|-------|-------|:--------:|------|
| `https://www.aibang.com` | `https://api.aibang.com` | ✅ | 同 eTLD+1 |
| `https://www.aibang.com` | `https://shop.aibang.com` | ✅ | 同 eTLD+1 |
| `https://www.aibang.com` | `https://www.aibang.com.cn` | ❌ | eTLD+1 是 `aibang.com.cn`，不同 |
| `https://www.aibang.com` | `https://aibang.com` | ✅ | 精确 host vs subdomain |

### 2.3 Domain（域名）

**定义：** 精确的主机名字符串。

```
www.aibang.com  ≠  api.aibang.com  ≠  shop.aibang.com
```

### 2.4 SameSite vs Same-Origin 对照表

| 维度 | Same-Origin | Same-Site |
|------|:-----------:|:---------:|
| 协议 (scheme) | ✅ 必须相同 | ✅ 必须相同 |
| 主机 (host) | ✅ 必须相同 | ✅ 必须相同（eTLD+1） |
| 端口 (port) | ✅ 必须相同 | ❌ 可不同 |
| 子域名 | ❌ 必须相同 | ✅ 可不同 |

> **SameSite = 同 Site**，要求协议和 eTLD+1 相同。子域名可以不同（这就是关键！）

### 2.5 实战：区分 SameSite 和跨域

```
场景：https://www.aibang.com  调用 https://api.aibang.com

分析：
  - scheme: https = https ✅
  - eTLD+1: aibang.com = aibang.com ✅
  - 结论：同 Site (SameSite)

但：
  - Origin: https://www.aibang.com ≠ https://api.aibang.com ❌
  - CORS: 需要配置（因为跨 Origin）
  - Cookie: SameSite=Lax 可以发送（因为同 Site）
```

> **这正是很多人混淆的地方**：CORS 的跨域和 Cookie 的跨站是两套独立体系！即便 CORS 判定为跨域，SameSite=Lax 的 Cookie 仍然可能被发送。

---

## 3. SameSite 的三种值

### 3.1 值总览

| 值 | 跨站导航 GET | 跨站 POST/ajax | 同站请求 | 典型用途 |
|----|:-----------:|:--------------:|:--------:|---------|
| **Strict** | ❌ 不发送 | ❌ 不发送 | ✅ 发送 | 高安全场景（银行后台） |
| **Lax** | ✅ 发送 | ❌ 不发送 | ✅ 发送 | **默认推荐**，适合大多数 Web 应用 |
| **None** | ✅ 发送 | ✅ 发送 | ✅ 发送 | 跨域 iframe、SSO、第三方 API |

### 3.2 SameSite=Strict

最严格的模式。**完全禁止**跨站 Cookie，无论是 GET 导航还是 POST 请求。

```http
Set-Cookie: session=abc123; SameSite=Strict; Secure; HttpOnly
```

**效果：**

```
用户在 https://www.aibang.com
点击链接 → https://api.aibang.com/dashboard
浏览器：❌ 不发送 session cookie
```

**优点：** 完全免疫 CSRF 攻击
**缺点：** 用户体验差——点击外部链接跳转后会"丢失登录状态"

**适用场景：**
- 银行/金融类高安全应用
- 管理后台（不希望任何跨站交互）
- 内部工具（用户总是直接导航，不会从外部链接跳转进来）

### 3.3 SameSite=Lax

放宽的限制。只允许**安全的跨站 GET 请求**（top-level navigation）携带 Cookie。

```http
Set-Cookie: session=abc123; SameSite=Lax; Secure; HttpOnly
```

**允许携带 Cookie 的跨站场景：**

| 触发方式 | 示例 | Cookie 发送？ |
|---------|------|:------------:|
| `<a href="...">` 点击跳转 | `<a href="https://api.aibang.com">` | ✅ GET 导航 |
| `<link rel="preload">` | 预加载资源 | ✅ GET |
| GET 表单提交 | `<form method="GET" action="...">` | ✅ GET |
| 页面预加载 | `dns-prefetch`, `preconnect` | ✅ GET |
| POST 表单提交 | `<form method="POST" action="...">` | ❌ |
| `fetch()`, `XMLHttpRequest` | AJAX/POST | ❌ |
| `<img>`, `<script>` 加载 | 第三方资源加载 | ❌ |
| `<iframe>` 嵌入 | 第三方 iframe | ❌ |

**重要例外：**
> `Sec-Fetch-Site` 头部为 `cross-site` 且请求是 `no-cors` 模式（如 `<img>`、`<script>`、CSS 等），浏览器**仍然会发送 Lax Cookie**。这是浏览器的实现细节，可能随版本变化。

**适用场景：**
- 大多数 Web 应用（前后端分离的普通业务系统）
- 用户从外部链接跳转进来仍需保持登录

### 3.4 SameSite=None

完全不禁用限制，但要求 **Cookie 必须标记为 `Secure`**（仅 HTTPS）。

```http
Set-Cookie: tracking=xyz789; SameSite=None; Secure
```

**警告：Firefox 的特殊行为**

```
Firefox 默认设置 (Enhanced Tracking Protection):
  - 收到 SameSite=None 但没有 Secure → ❌ Cookie 被拒绝
  - 收到 SameSite=None + Secure      → ✅ Cookie 被接受

Chrome (SameSite by default 启用后):
  - 收到 SameSite=None + Secure      → ✅ Cookie 被接受
  - 收到 SameSite=None 但没有 Secure → ⚠️ 被标记为警告，行为不稳定
```

**适用场景：**
- 跨域 SSO（单点登录）
- 嵌入式 iframe 场景（如支付、第三方登录弹窗）
- 需要被第三方页面 AJAX 调用的 API
- 广告/分析类服务（即将被浏览器彻底禁用）

### 3.5 不指定 SameSite 的默认行为

| 时期 | Chrome | Firefox | Safari |
|------|--------|---------|--------|
| 2020 年之前 | 视为 `None` | 视为 `None` | 视为 `None` |
| Chrome 80+ (2020) | 视为 `Lax` | 视为 `Lax` | 视为 `Lax` |
| 当前 (2024+) | 视为 `Lax` | 视为 `Lax` | 视为 `Lax` |

> **迁移建议**：永远显式指定 `SameSite`，不要依赖默认值。显式声明更安全，也更清晰。

---

## 4. SameSite 能解决什么问题

### 4.1 CSRF（跨站请求伪造）

**SameSite=Lax/Strict** 可以完全阻止传统 CSRF 攻击。

```
攻击向量分析：

传统攻击（无 SameSite）：
  <form action="https://bank.com/transfer" method="POST">
    <input name="to" value="hacker">
    <input name="amount" value="10000">
  </form>
  <script>document.forms[0].submit()</script>

SameSite=Lax：
  ❌ 浏览器拒绝为 POST 发送 Cookie → 攻击失败

SameSite=Strict：
  ❌ 任何跨站请求都不发 Cookie → 攻击失败
```

**但 SameSite 不能防止所有 CSRF**：

| 攻击场景 | SameSite 防御 |
|---------|--------------|
| POST 跨站表单提交 | ✅ 有效（Lax+） |
| GET 链接跳转 | ⚠️ Lax 允许，Strict 才阻止 |
| JSONP 跨站请求 | ❌ 不保护（因为是 GET） |
| WebSocket | ❌ 不保护 |
| CORS 预检请求 | ⚠️ 视情况而定 |

### 4.2 信息泄露（跨站 Cookie 窃取）

防止敏感 Cookie 被第三方页面获取：

```
用户在 https://www.aibang.com
第三方脚本：https://tracker.com/script.js

tracker.com 尝试：
  - document.cookie 读取 aibang.com 的 Cookie
    → ❌ 失败（HttpOnly 保护 JS 无法读取）

  - 自己的服务器接收 aibang.com 的 Cookie
    → ❌ 失败（SameSite=Lax 阻止跨站发送）
```

### 4.3 跨站追踪

| 防护效果 | SameSite=None | SameSite=Lax | SameSite=Strict |
|---------|:-------------:|:------------:|:---------------:|
| 广告追踪像素 | ❌ 不保护 | ❌ 不保护 | ❌ 不保护 |
| 第三方分析脚本 | ❌ 不保护 | ❌ 不保护 | ❌ 不保护 |
| 跨站登录 Session | ✅ 保护（None 时允许） | ✅ 允许同站导航 | ⚠️ 限制较多 |
| 第三方 Widget (iframe) | ✅ 允许嵌入 | ❌ 无法嵌入 | ❌ 无法嵌入 |

> SameSite 主要保护**由服务端设置的 Cookie**，对**页面内嵌的第三方脚本自行写入的 Cookie** 保护有限。

---

## 5. SameSite 与 Cookie 其他属性的关系

### 5.1 属性协同矩阵

| 组合 | 效果 | 典型场景 |
|------|------|---------|
| `SameSite=Strict` | 最安全，但用户体验差 | 银行后台 |
| `SameSite=Lax; Secure` | 推荐组合，同站导航可携带 Cookie | 大多数 Web 应用 |
| `SameSite=None; Secure` | 允许跨站发送，但仅 HTTPS | SSO、第三方 iframe |
| `SameSite=None` (无 Secure) | ⚠️ Chrome 警告，Firefox 拒绝 | **不要使用** |
| 无 SameSite 指定 | Chrome 80+ = Lax | 需显式声明 |

### 5.2 Secure 属性

**要求：** `SameSite=None` 必须配合 `Secure`。

```nginx
# 正确
proxy_cookie_path / "/; SameSite=Lax; Secure; HttpOnly";

# 错误 — SameSite=None 没有 Secure
# Firefox 会直接拒绝该 Cookie
```

**Secure 的约束：**
- Cookie 仅在 HTTPS 连接上传输
- HTTP 连接永远不会收到/发送 Secure Cookie
- 开发环境（HTTP）需要注意这点

### 5.3 HttpOnly 属性

**作用：** 阻止 JavaScript 通过 `document.cookie` 访问 Cookie。

```http
# 无 HttpOnly → JS 可以读取 → XSS 可能窃取
Set-Cookie: session=abc123; SameSite=Lax; Secure

# 有 HttpOnly → JS 无法读取 → 更安全
Set-Cookie: session=abc123; SameSite=Lax; Secure; HttpOnly
```

**注意：** HttpOnly 不影响浏览器正常发送 Cookie——浏览器发送 Cookie 时只看 SameSite 和 Secure，与 HttpOnly 无关。

### 5.4 Domain 属性

**决定 Cookie 属于哪个主机。**

```http
# 精确主机（默认）— 只有 api.aibang.com 能收到
Set-Cookie: session=abc; Domain=api.aibang.com

# 共享给所有子域名 — www.aibang.com 和 api.aibang.com 都能收到
Set-Cookie: session=abc; Domain=aibang.com
```

| Domain 设置 | `www.aibang.com` 请求 `api.aibang.com` | 说明 |
|------------|:----------------------------------------:|------|
| `Domain=api.aibang.com` | ❌ 不能 | 精确匹配，默认值 |
| `Domain=aibang.com` | ✅ 可以 | 共享给 eTLD+1 下所有子域名 |

> **配合 SameSite 使用：** 如果需要跨子域名共享 Cookie，`Domain=aibang.com` + `SameSite=Lax` 是常见且安全的组合。

### 5.5 Path 属性

```http
Set-Cookie: session=abc; Path=/api/
```

**作用：** 只有请求路径以 `/api/` 开头的请求才会携带该 Cookie。

> **注意：** `Path` 不是安全边界！即使 `Path=/admin`，子域名 ` attacker.com` 仍可以通过设置 `Domain=.aibang.com` 来覆盖它。

---

## 6. 场景深度分析

### 场景 1：前后端分离，同 Site 不同子域名

```
Frontend:  https://www.aibang.com        (A 主机)
API:       https://api.aibang.com        (B 主机)
Cookie:    ajbx1_session (由 API 设置)
```

**分析：**
- 同 Site（共享 eTLD+1 = `aibang.com`）
- `SameSite=Lax` ✅ 允许发送（跨站 GET 导航）
- `SameSite=Strict` ❌ 不允许（点击链接跳转也是跨站）

**正确配置：**

```nginx
# API 后端设置
Set-Cookie: ajbx1_session=abc123; SameSite=Lax; Secure; HttpOnly; Domain=aibang.com
```

**常见错误：**

```nginx
# 错误 1：没有 Domain，子域名无法共享
Set-Cookie: ajbx1_session=abc123; SameSite=Lax; Secure
# → Cookie 只属于 api.aibang.com，www.aibang.com 访问不到

# 错误 2：SameSite=None 但没有 Secure（Firefox 拒绝）
Set-Cookie: ajbx1_session=abc123; SameSite=None
# → 在 Firefox 下完全失败

# 错误 3：SameSite=Strict（用户从外部链接跳转进来会丢失登录）
Set-Cookie: ajbx1_session=abc123; SameSite=Strict; Secure; Domain=aibang.com
# → 用户体验差，不推荐
```

---

### 场景 2：跨域 SSO（不同 eTLD+1）

```
IdP (登录页):  https://login.aibang.com
SP (业务站):    https://app.shop.com
```

**分析：**
- 不同 eTLD+1（`aibang.com` vs `shop.com`）
- 一定是跨 Site
- `SameSite=Lax` ❌ 不允许（不同 Site）
- `SameSite=None; Secure` ✅ 允许

**正确配置：**

```http
# IdP 设置跨域 SSO Cookie
Set-Cookie: sso_session=xyz; SameSite=None; Secure; HttpOnly; Path=/
```

**关键点：**
1. 必须 `SameSite=None; Secure`
2. 必须 HTTPS
3. 建议 `Domain=` 不指定（默认精确主机）
4. 登录回调时需要用 `window.postMessage` 或服务端重定向传递 session

---

### 场景 3：第三方 iframe 嵌入

```
主页面:  https://www.aibang.com
支付组件: https://pay.aibang.com（被嵌入 iframe）
```

**分析：**
- 跨 Site（iframe 的 document.domain vs 父页面的 document.domain）
- 父页面和 iframe 之间通信受 `postMessage` 限制
- iframe 内部请求需要 Cookie

**正确配置：**

```http
# 支付组件的 API
Set-Cookie: pay_session=abc; SameSite=None; Secure; HttpOnly; Path=/

# 嵌入页面
<iframe src="https://pay.aibang.com/widget"
        allow="camera; microphone"
        sandbox="allow-scripts allow-same-origin allow-popups">
```

**注意：** `sandbox` 属性会禁用父页面的部分权限，iframe 内部的 Cookie 行为可能受影响。

---

### 场景 4：API 作为第三方被跨域调用

```
网站 A:  https://analytics.com（收集数据）
网站 B:  https://shop.aibang.com（调用 analytics API）
```

**分析：**
- 跨 Site（`analytics.com` vs `aibang.com`）
- `shop.aibang.com` 页面内的 JS 调用 `analytics.com` API

**CORS + Cookie 的矛盾：**

```javascript
// shop.aibang.com 页面内的 JS
fetch('https://analytics.com/api/track', {
  method: 'POST',
  credentials: 'include',  // 发送 Cookie
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ event: 'purchase' })
})
```

```
需要同时满足：
1. analytics.com 后端设置 CORS 头：Access-Control-Allow-Credentials: true
2. Access-Control-Allow-Origin 必须是具体域名（不能是 *）
3. Cookie 设置：SameSite=None; Secure; HttpOnly
4. 请求必须是 HTTPS
```

**常见错误：**

```http
# 错误：CORS Allow-Origin 为 *
Access-Control-Allow-Origin: *
# → 浏览器拒绝 credentials: 'include' 配合通配符

# 正确：具体域名
Access-Control-Allow-Origin: https://shop.aibang.com
Access-Control-Allow-Credentials: true
```

---

## 7. 浏览器兼容性矩阵

### 7.1 SameSite 支持情况

| 浏览器 | 版本 | SameSite 支持 |
|--------|------|:-------------:|
| Chrome | 51+ | ✅ |
| Firefox | 52+ | ✅ |
| Safari | 11.1+ (macOS), 11.1+ (iOS) | ✅ |
| Edge | 79+ | ✅ |
| IE | ❌ 不支持 | ❌ |

### 7.2 SameSite=None + Secure 兼容性

| 浏览器 | 支持？ | 备注 |
|--------|:------:|------|
| Chrome 76+ | ✅ | |
| Firefox 86+ | ✅ | 旧版本需要手动开启 |
| Safari 13.1+ | ✅ | iOS 13+ 支持 |
| Edge 79+ | ✅ | |
| IE | ❌ | 不支持 |

### 7.3 各浏览器第三方 Cookie 限制进度

| 浏览器 | 第三方 Cookie 策略 |
|--------|-------------------|
| Chrome | ✅ SameSite=Lax 默认启用；计划 2025 彻底禁用 3rd party cookie |
| Firefox | ✅ ETP 默认开启；Total Cookie Protection |
| Safari | ✅ ITP 2.1+；已限制大多数第三方 Cookie |
| Edge | ✅ 与 Chrome 同步（Chromium 内核） |

### 7.4 2024+ 环境下的调试注意事项

```
Chrome DevTools → Application → Cookies：
  - 可查看每个 Cookie 的 SameSite 状态
  - Blocked Cookies 会显示具体原因（reason 列）

Firefox → Storage Inspector：
  - SameSite=Lax 的跨站 GET 会显示具体限制

Safari → Web Inspector → Storage：
  - ITP 的限制更严格，部分 Cookie 直接被降级
```

---

## 8. 常见误解与陷阱

### 误解 1：设置了 SameSite 就不需要 CSRF Token

**错误。**

- `SameSite=Lax` **允许跨站 GET 导航**携带 Cookie
- `<form method="GET">` 触发的 GET 请求会被发送
- POST 跨站表单在 Lax 下被阻止，但 `Sec-Fetch-Site` 判定不准确时可能漏过

**建议：** `SameSite=Lax` + CSRF Token 双重防护

### 误解 2：Cookie 的 Domain 属性可以跨 eTLD+1

**错误。**

```
设置 Domain=baidu.com 的 Cookie：
  → 可以被 *.baidu.com 接收
  → 但不能被 *.baidu.com.cn 或 *.baidu.org 接收
  → 更不能被 *.google.com 接收

浏览器会拒绝不安全的 Domain 设置：
  Set-Cookie: session=abc; Domain=com
  → 浏览器直接拒绝（com 是公共后缀）
```

### 误解 3：SameSite 可以完全替代 HttpOnly

**错误。** 两个属性解决不同问题：

| 属性 | 防止什么 | 攻击向量 |
|------|---------|---------|
| `HttpOnly` | JS 无法读取 Cookie | XSS 脚本窃取 Cookie |
| `SameSite` | Cookie 不随跨站请求发送 | CSRF、跨站追踪 |

**两者需要同时设置。**

### 误解 4：localhost 可以绕过 SameSite

**错误（现代浏览器的行为）。**

| 环境 | SameSite 行为 |
|------|:-------------:|
| `localhost` (Chrome 89+) | 被视为有效 eTLD+1，SameSite 正常生效 |
| `127.0.0.1` | 无 eTLD，Cookie 可能被视为第一方，但仍受 SameSite 约束 |
| 带端口的 localhost | 端口不同可能触发 SameSite 限制 |

**实际开发时：** 开发环境使用 `https://localhost` + 有效的 TLS 证书（或自签）来模拟生产环境行为。

### 陷阱 1：Nginx 代理丢失 SameSite 属性

```nginx
# 错误：proxy_pass 会剥离 Set-Cookie 属性
location / {
    proxy_pass http://backend;
}

# 正确：显式传递并补充 SameSite
location / {
    proxy_pass http://backend;
    proxy_cookie_path / "/; SameSite=Lax; Secure; HttpOnly";
    proxy_set_header Host $host;
}
```

### 陷阱 2：Chrome 的 SameSite=Lax-by-default 会影响历史 Cookie

```http
# 旧系统遗留：未设置 SameSite 的 Cookie
Set-Cookie: legacy_session=abc

# Chrome 80+ 将其视为 SameSite=Lax
# → 在第三方 iframe 内请求会被阻止
# → 在 AJAX POST 跨站请求时会被阻止
```

**修复：** 主动为所有 Cookie 设置明确的 SameSite 值。

---

## 9. 调试与验证方法

### 9.1 DevTools 检查 Cookie 状态

```
Chrome DevTools → Application → Cookies → 选择站点

列信息：
  Name        : Cookie 名称
  Value       : Cookie 值
  Domain      : Cookie 所属域
  Path        : Cookie 路径
  Expires     : 过期时间
  Size        : 大小
  HTTPOnly    : 是否 HttpOnly
  Secure      : 是否 Secure
  SameSite    : Lax / Strict / None / (空)
  SameParty   : CHIPS (跨站分区 Cookie)
  Partitioned : 是否分区 Cookie
```

**Blocked Cookies 面板：** Chrome DevTools 会显示哪些 Cookie 被阻止及原因。

### 9.2 命令行验证 Cookie 设置

```bash
# 用 curl 模拟请求，查看 Set-Cookie 头
curl -I https://api.aibang.com/api/user \
  -H "Cookie: existing_session=test" \
  -v 2>&1 | grep -i set-cookie

# 输出示例：
# < Set-Cookie: ajbx1_session=abc123; Path=/; HttpOnly; SameSite=Lax; Secure
```

### 9.3 用 OpenSSL 检查 Cookie（替代 curl）

```bash
# 连接 HTTPS，检查响应头中的 Set-Cookie
echo "GET / HTTP/1.1\r\nHost: api.aibang.com\r\n\r\n" | \
  openssl s_client -connect api.aibang.com:443 -servername api.aibang.com 2>/dev/null | \
  grep -i set-cookie
```

### 9.4 浏览器 Console 脚本验证

```javascript
// 查看所有可访问的 Cookie（非 HttpOnly）
console.log(document.cookie);

// 查看 Cookie 详情（Chrome DevTools Console）
// 可直接在 Application 面板查看

// 测试 fetch 携带 Cookie
fetch('https://api.aibang.com/api/data', {
  credentials: 'include'  // 关键：跨域请求需要这个
}).then(r => r.json()).then(console.log);
```

### 9.5 Nginx 配置验证清单

```nginx
# 1. 检查 proxy_cookie_path 设置
proxy_cookie_path / "/; SameSite=Lax; Secure; HttpOnly";

# 2. 检查 upstream 是否正确传递原始 Cookie
proxy_set_header Cookie $http_cookie;

# 3. 检查 CORS 头是否允许 credentials
# 必须是具体域名，不能是 *
add_header Access-Control-Allow-Credentials "true";
add_header Access-Control-Allow-Origin "https://www.aibang.com";  # 不能是 $http_origin

# 4. 检查 SameSite=None 时是否配合 Secure
# 不带 Secure 的 SameSite=None 在 Firefox 被拒绝
```

---

## 10. 迁移指南

### 10.1 迁移检查清单

```
[ ] 清点所有 Set-Cookie 位置（后端代码、Nginx 配置、反向代理）
[ ] 确认每个 Cookie 的用途（session、token、追踪、CSRF）
[ ] 评估每个 Cookie 是否需要跨站访问
[ ] 制定 SameSite 取值策略
[ ] 在测试环境验证（特别是 Firefox）
[ ] 灰度发布（先对一小部分流量生效）
[ ] 监控 Cookie 相关的错误/失败率
[ ] 生产环境全量
[ ] 清理遗留的无指定 SameSite 的 Cookie
```

### 10.2 Cookie 类型 → SameSite 取值映射

| Cookie 用途 | 跨站需求 | 推荐 SameSite | 其他属性 |
|-----------|---------|:------------:|---------|
| Session (登录态) | 同站导航 | `Lax` | `Secure; HttpOnly; Domain=app.com` |
| CSRF Token | 同站请求 | `Lax` 或 `Strict` | `Secure; HttpOnly` |
| 分析/追踪 | 无 | ❌ 不建议使用第三方 Cookie | 考虑替代方案（UA、server-side） |
| 购物车 | 同站导航 | `Lax` | `Secure; HttpOnly` |
| 多域名 SSO | 跨站 | `None` | `Secure; HttpOnly` |
| 嵌入式 Widget | 跨站 iframe | `None` | `Secure; HttpOnly` |
| 高安全后台 | 内部访问 | `Strict` | `Secure; HttpOnly` |

### 10.3 灰度验证方案

```nginx
# Nginx：A/B 测试 SameSite 配置
map $cookie_experiment_group $samesite_value {
    default "Lax";
    "strict"  "Strict";
    "none"    "None";
}

server {
    location / {
        # 对特定 Cookie 名称应用实验值
        proxy_cookie_path / "/; SameSite=${samesite_value}; Secure; HttpOnly";
    }
}
```

### 10.4 快速修复：Nginx 全局注入 SameSite

如果后端代码难以修改，可以在 Nginx 层面统一处理：

```nginx
# 在反向代理层统一为所有 Set-Cookie 添加 SameSite
proxy_buffering off;
proxy_cookie_path / "/; SameSite=Lax; Secure; HttpOnly";

# 对特定路径使用 None（SSO 等）
location /sso/ {
    proxy_cookie_path / "/; SameSite=None; Secure; HttpOnly";
}
```

> **注意：** `proxy_cookie_path` 会覆盖原有的 SameSite 设置。如果后端已经设置了 SameSite，Nginx 的全局注入会二次设置，可能导致重复或冲突。

---

## Summary

| 要点 | 说明 |
|------|------|
| **SameSite 核心** | 控制 Cookie 是否随跨站请求发送 |
| **SameSite=Lax** | 推荐默认值，允许跨站 GET 导航，不允许 POST/ajax |
| **SameSite=Strict** | 完全禁止跨站，最安全但用户体验差 |
| **SameSite=None** | 允许跨站，但必须配合 `Secure` |
| **Secure 必须** | `SameSite=None` 必须有 `Secure`，否则 Firefox 拒绝 |
| **Domain 属性** | 控制 Cookie 属于哪个子域名，需配合 SameSite |
| **与 CORS 关系** | 两套独立机制——CORS 管 API 访问权限，SameSite 管 Cookie 发送 |
| **不能替代 CSRF Token** | SameSite=Lax 允许 GET 跨站，POST 部分允许，需要双重防护 |

---

## References

- [RFC 6265 - HTTP State Management Mechanism](https://tools.ietf.org/html/rfc6265)
- [MDN - Set-Cookie/SameSite](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite)
- [web.dev - SameSite cookies explained](https://web.dev/samesite-cookies-explained/)
- [Chrome SameSite by default documentation](https://www.chromium.org/updates/same-site)
- [Chromium - SameSite Cookie Recipes](https://github.com/GoogleChromeLabs/samesite-cookie-recipes)
- [OWASP - CSRF](https://owasp.org/www-community/attacks/csrf)
- [Public Suffix List](https://publicsuffix.org/)
