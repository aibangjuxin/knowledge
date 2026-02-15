# OAuth 2.0 Authorization Code Flow for Native Apps (RFC 8252)

本文档详细描述了 Native App（如 Electron 应用）通过 OAuth 2.0 获取 Google 访问令牌的标准流程，以及常见网络问题的排查指南。

## 1. 核心流程分析

你提供的流程图描述了 **Loopback IP Address** 模式，这是 RFC 8252 推荐的 Native App 授权方式。

### 标准流程图 (Mermaid)

```mermaid
sequenceDiagram
    participant User as 用户
    participant Browser as 系统浏览器
    participant LocalServer as 本地服务 (Electron)
    participant GoogleAuth as Google 授权服务器
    participant GoogleToken as Google 令牌端点

    Note over LocalServer: 1. 生成 PKCE Code Verifier & Challenge
    Note over LocalServer: 2. 生成随机 State (防 CSRF)
    
    LocalServer->>Browser: 3. 打开授权 URL (包含 scope, client_id, redirect_uri, code_challenge, state)
    Browser->>GoogleAuth: 4. 请求授权页面
    GoogleAuth->>User: 5. 展示登录/授权页
    User->>GoogleAuth: 6. 用户同意授权
    GoogleAuth->>Browser: 7. 302 重定向到 http://127.0.0.1:{port}/callback?code=xxx&state=xxx
    Browser->>LocalServer: 8. 发送 GET 请求包含 code 和 state
    
    Note over LocalServer: 9. 验证 state 一致性
    
    LocalServer->>GoogleToken: 10. POST /token (code, code_verifier, client_id, client_secret)
    GoogleToken-->>LocalServer: 11. 返回 Access Token / Refresh Token
    
    Note over LocalServer: 12. 登录成功，保存 Token
```

### 关键组件说明

1.  **PKCE (Proof Key for Code Exchange)**:
    *   **作用**: 防止授权码（Authorization Code）被恶意程序拦截。
    *   **机制**: 在第 3 步发送 `code_challenge`，第 10 步发送原始 `code_verifier`，Google 验证两者匹配才颁发 Token。
    *   **建议**: 虽然 Google 目前对部分旧客户端不强制 PKCE，但**强烈建议**在 Electron 应用中实现 PKCE 以提高安全性。

2.  **State 参数**:
    *   **作用**: 防止 CSRF 攻击。
    *   **机制**: 生成随机字符串随请求发送，回调时验证返回的 `state` 是否与发送的一致。

3.  **Loopback Redirect URI**:
    *   通常使用 `http://127.0.0.1:{random_port}/callback`。
    *   **注意**: 避免使用 `localhost`，推荐显式使用 `127.0.0.1` 以避免 DNS 解析问题。

---

## 2. 故障排查指南 (Troubleshooting)

### 🔴 错误 1: `Proxy connection ended before receiving CONNECT response`

**现象**:
```log
[OAuth] Token exchange failed: GaxiosError: request to https://oauth2.googleapis.com/token failed, reason: Proxy connection ended before receiving CONNECT response
```

**原因分析**:
*   **Node.js 网络环境**: Electron 的主进程（Main Process）运行在 Node.js 环境中，它发出的 HTTP 请求（如使用 `axios`, `node-fetch`, or `google-auth-library`）默认**不会自动**完全遵循系统的代理设置，或者遵循了错误的环境变量。
*   **代理中断**: 你的请求尝试通过一个代理服务器（可能是系统默认代理，如 127.0.0.1:7890），但在建立 HTTPS 隧道（CONNECT 方法）时，代理服务器关闭了连接。
*   **常见场景**: 本地开启了 VPN/代理软件，但 Node.js 客户端配置不当，或者代理软件不稳定。

**解决方案**:

1.  **检查环境变量**:
    确保启动 Electron 时，环境变量中包含正确的代理配置。
    ```bash
    export http_proxy=http://127.0.0.1:7890
    export https_proxy=http://127.0.0.1:7890
    # 注意：Node.js 对大写 HTTPS_PROXY 更敏感，建议大小写都设置
    ```

2.  **在代码中显式配置代理 (推荐)**:
    如果使用 `axios` 或 `google-auth-library`，建议显式传入 `httpsAgent`。
    ```javascript
    const { HttpsProxyAgent } = require('https-proxy-agent');
    const axios = require('axios');

    // 自动检测系统代理或硬编码
    const proxyUrl = process.env.HTTPS_PROXY || 'http://127.0.0.1:7890';
    
    const agent = new HttpsProxyAgent(proxyUrl);

    const res = await axios.post('https://oauth2.googleapis.com/token', data, {
      httpsAgent: agent,
      // ...其他配置
    });
    ```

3.  **关闭 SSL 验证 (仅调试用)**:
    如果代理涉及自签名证书（如 Charles/Fiddler），可能需要临时关闭验证（**生产环境禁止**）：
    ```javascript
    process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
    ```

---

### 🔴 错误 2: `net_error -101 (ERR_CONNECTION_RESET)` / SSL Handshake Failed

**现象**:
```log
[76223:0215/181811.501900:ERROR:net/socket/ssl_client_socket_impl.cc:916] handshake failed; returned -1, SSL error code 1, net_error -101
```

**原因分析**:
*   **网络阻断**: `-101` 是 `ERR_CONNECTION_RESET`。在中国大陆地区访问 `googleapis.com` 若不经过代理，TCP 连接会被 GFW 重置（RST 包）。
*   **代理不稳定**: 即使配置了代理，如果代理服务器与 Google 的连接不稳定，或者代理协议握手超时，也会导致 SSL 握手失败。
*   **Electron Chromium 网络栈**: 此错误日志来自 Chromium 网络层（Electron 的底层），说明是渲染进程或使用了 Chromium 网络栈发起的请求失败。

**解决方案**:

1.  **确保全局/规则模式正确**:
    确保你的代理软件（Clash, V2Ray 等）规则中，`googleapis.com` 走的是代理（Proxy/Global），而不是直连（Direct）。

2.  **Electron 应用代理设置**:
    Electron 可能会读取系统代理，但有时需要显式通过 API 设置。
    ```javascript
    // 在 main process 中应用启动时
    app.whenReady().then(() => {
    // 强制走本地代理
        session.defaultSession.setProxy({
            mode: 'fixed_servers',
            proxyRules: 'http=127.0.0.1:7890;https=127.0.0.1:7890'
        });
    });
    ```
    *注意*: 这会影响 `BrowserWindow` 和 `net` 模块的请求。Node.js 原生模块 (`http`/`https`/`axios`) 不受此 API 影响，需按错误 1 的方案处理。

3.  **检查本地防火墙/杀毒软件**:
    有时本地安全软件会拦截并重置加密连接。

## 总结

你的流程设计是正确的。遇到的问题核心在于 **Node.js/Electron 环境下的网络代理配置**。

*   **Token 交换失败** 是因为 Node.js 进程没走通代理 -> **修复代码中的 Agent 配置**。
*   **SSL 错误** 是因为网络层连接被重置 -> **检查代理软件规则和连通性**。