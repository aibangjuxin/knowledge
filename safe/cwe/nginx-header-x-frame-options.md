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