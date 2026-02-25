# 将 DNS 验证脚本转换为 GitHub Pages 静态页面的探索方案
- summary 
- 综合来看，我应该将这项服务部署成一个 API，或者是一个最简单的静态页面发布出来。通过这种方式来实现就可以了，这样最直接。
## 问题背景

当前有一个功能完善的 Bash 脚本 `verify-pub-priv-ip-glm-ipv6-enhanced.sh`，它使用 `dig` 命令查询多个 DNS 服务器，验证域名解析结果，并判断 IP 类型（公网/私网/本地等）。

**核心挑战：**
- 希望将查询结果展示在 GitHub Pages 静态页面上
- 公司网络环境限制，无法在浏览器中直接调用公共 DNS API
- 必须继续使用 `dig` 命令作为查询工具

## 技术约束分析

### 浏览器环境的限制
1. **无法直接执行系统命令**：浏览器中的 JavaScript 无法调用 `dig` 命令
2. **CORS 限制**：即使有 DNS-over-HTTPS (DoH) API，也可能被 CORS 策略阻止
3. **网络隔离**：公司网络可能阻止访问公共 DNS 服务的 API 端点

### 可行的技术路径
由于浏览器无法直接执行 shell 命令，我们需要采用"预生成 + 静态展示"的架构。

## 解决方案探索

### 方案 1：预生成静态数据 + GitHub Actions 自动更新 ⭐ 推荐

**架构设计：**
```
┌─────────────────┐
│  GitHub Actions │
│   (定时触发)     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ 运行 Bash 脚本              │
│ - 执行 dig 命令             │
│ - 生成 JSON 数据            │
│ - 提交到 gh-pages 分支      │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ GitHub Pages                │
│ - 加载预生成的 JSON         │
│ - 使用 JavaScript 渲染      │
│ - 展示可视化结果            │
└─────────────────────────────┘
```

**实现步骤：**

1. **修改脚本支持 JSON 输出**（已支持 `--output json`）
2. **创建 GitHub Actions 工作流**
3. **创建静态 HTML 页面读取 JSON 数据**
4. **配置定时任务自动更新**

**优点：**
- ✅ 完全使用原有的 `dig` 命令逻辑
- ✅ 数据定期自动更新
- ✅ 无需修改核心查询逻辑
- ✅ 适合公司网络环境

**缺点：**
- ❌ 数据不是实时的（取决于 Actions 触发频率）
- ❌ 需要 GitHub Actions 运行环境支持 `dig` 命令

---

### 方案 2：本地生成 + 手动推送

**架构设计：**
```
┌─────────────────┐
│  本地环境       │
│  (手动执行)     │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ 运行脚本生成数据            │
│ $ ./script.sh --output json │
│ $ git add data.json         │
│ $ git push                  │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ GitHub Pages                │
│ - 读取 data.json            │
│ - 渲染展示                  │
└─────────────────────────────┘
```

**优点：**
- ✅ 实现简单
- ✅ 完全控制数据生成时机
- ✅ 100% 使用原有脚本

**缺点：**
- ❌ 需要手动更新
- ❌ 无法自动化

---

### 方案 3：WebAssembly + DNS 客户端 (理论可行但复杂)

将 DNS 查询工具编译为 WebAssembly，在浏览器中运行。

**技术栈：**
- 使用 C/Rust 编写 DNS 客户端
- 编译为 WASM
- 在浏览器中执行 DNS 查询

**优点：**
- ✅ 真正的客户端实时查询

**缺点：**
- ❌ 开发复杂度极高
- ❌ 仍然受网络限制（公司防火墙可能阻止 DNS 查询）
- ❌ 需要重写所有查询逻辑

---

### 方案 4：混合方案 - 本地服务器 + Web 界面

在本地或内网服务器上运行一个轻量级 Web 服务，提供 API 接口调用 `dig` 命令。

**架构设计：**
```
┌──────────────┐      HTTP      ┌──────────────┐
│  浏览器      │ ◄────────────► │ 本地 Web 服务│
│  (前端页面)  │                │  (Node.js/   │
└──────────────┘                │   Python)    │
                                └──────┬───────┘
                                       │
                                       ▼
                                ┌──────────────┐
                                │  dig 命令    │
                                └──────────────┘
```

**实现技术：**
- 后端：Node.js Express / Python Flask
- 前端：静态 HTML + JavaScript
- 部署：内网服务器或本地运行

**优点：**
- ✅ 实时查询
- ✅ 使用原有 `dig` 命令
- ✅ 可以在内网环境使用

**缺点：**
- ❌ 不是纯静态页面
- ❌ 需要服务器运行环境
- ❌ 不适合 GitHub Pages

---

### 方案 5：PWA (Progressive Web App) 纯本地应用 ⚠️ 有限可行

PWA 提供了离线能力和本地存储，但**仍然无法直接执行系统命令**。

**PWA 的能力边界分析：**

#### ✅ PWA 可以做什么
1. **离线访问**：通过 Service Worker 缓存资源
2. **本地存储**：IndexedDB 存储大量数据
3. **后台同步**：Background Sync API（需要网络）
4. **推送通知**：Push API
5. **安装到桌面**：像原生应用一样运行

#### ❌ PWA 不能做什么
1. **执行系统命令**：无法调用 `dig`、`nslookup` 等
2. **访问文件系统**：无法读写任意文件（除了 File System Access API 的有限访问）
3. **绕过网络限制**：仍受 CORS、CSP 等浏览器安全策略限制
4. **直接 DNS 查询**：无法发送原始 DNS 数据包（UDP/TCP 53 端口）

#### 🔄 PWA 混合方案的可能性

**方案 5A：PWA + 本地 Native Messaging（Chrome/Edge）**

```
┌─────────────────┐
│   PWA 应用      │
│  (浏览器中)     │
└────────┬────────┘
         │ Native Messaging API
         ▼
┌─────────────────┐
│  Native Host    │
│  (本地程序)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  dig 命令       │
└─────────────────┘
```

**实现步骤：**

1. **创建 Native Host 程序**（Python/Node.js）
   ```python
   # native_host.py
   #!/usr/bin/env python3
   import sys
   import json
   import subprocess
   import struct
   
   def send_message(message):
       encoded = json.dumps(message).encode('utf-8')
       sys.stdout.buffer.write(struct.pack('I', len(encoded)))
       sys.stdout.buffer.write(encoded)
       sys.stdout.buffer.flush()
   
   def read_message():
       text_length_bytes = sys.stdin.buffer.read(4)
       if len(text_length_bytes) == 0:
           sys.exit(0)
       text_length = struct.unpack('i', text_length_bytes)[0]
       text = sys.stdin.buffer.read(text_length).decode('utf-8')
       return json.loads(text)
   
   def run_dig(domain, dns_server, record_type):
       try:
           result = subprocess.run(
               ['dig', f'@{dns_server}', domain, record_type, '+short'],
               capture_output=True,
               text=True,
               timeout=5
           )
           return {
               'success': True,
               'output': result.stdout.strip(),
               'error': result.stderr
           }
       except Exception as e:
           return {'success': False, 'error': str(e)}
   
   while True:
       message = read_message()
       if message['command'] == 'dig':
           result = run_dig(
               message['domain'],
               message['dns_server'],
               message['record_type']
           )
           send_message(result)
   ```

2. **注册 Native Messaging Host**（Chrome）
   
   创建 `com.example.dns_checker.json`：
   ```json
   {
     "name": "com.example.dns_checker",
     "description": "DNS Checker Native Host",
     "path": "/path/to/native_host.py",
     "type": "stdio",
     "allowed_origins": [
       "chrome-extension://YOUR_EXTENSION_ID/"
     ]
   }
   ```
   
   放置到：
   - macOS: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
   - Linux: `~/.config/google-chrome/NativeMessagingHosts/`
   - Windows: `HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\`

3. **PWA 中调用 Native Messaging**
   ```javascript
   // 注意：需要作为 Chrome Extension 运行，不是纯 PWA
   const port = chrome.runtime.connectNative('com.example.dns_checker');
   
   port.onMessage.addListener((response) => {
       console.log('DNS Result:', response);
       displayResult(response);
   });
   
   function queryDNS(domain, dnsServer, recordType) {
       port.postMessage({
           command: 'dig',
           domain: domain,
           dns_server: dnsServer,
           record_type: recordType
       });
   }
   ```

**优点：**
- ✅ 真正的本地执行 dig 命令
- ✅ 实时查询
- ✅ 离线可用

**缺点：**
- ❌ 需要安装 Chrome Extension（不是纯 PWA）
- ❌ 需要用户手动安装 Native Host
- ❌ 只支持 Chrome/Edge（Firefox 有类似但不同的机制）
- ❌ 安装配置复杂
- ❌ 无法在 GitHub Pages 上直接使用

---

**方案 5B：PWA + WebSocket 本地服务**

```
┌─────────────────┐
│   PWA 应用      │
│  (浏览器中)     │
└────────┬────────┘
         │ WebSocket (ws://localhost:8080)
         ▼
┌─────────────────┐
│  本地 WS 服务   │
│  (后台运行)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  dig 命令       │
└─────────────────┘
```

**实现示例（Node.js）：**

```javascript
// local-dns-service.js
const WebSocket = require('ws');
const { exec } = require('child_process');
const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', (ws) => {
    console.log('PWA connected');
    
    ws.on('message', (message) => {
        const { domain, dnsServer, recordType } = JSON.parse(message);
        
        exec(`dig @${dnsServer} ${domain} ${recordType} +short`, 
            (error, stdout, stderr) => {
                ws.send(JSON.stringify({
                    success: !error,
                    result: stdout,
                    error: stderr
                }));
            }
        );
    });
});

console.log('DNS WebSocket service running on ws://localhost:8080');
```

**PWA 端代码：**

```javascript
// pwa-app.js
let ws;

function connectToLocalService() {
    ws = new WebSocket('ws://localhost:8080');
    
    ws.onopen = () => {
        console.log('Connected to local DNS service');
        document.getElementById('status').textContent = '✅ 已连接本地服务';
    };
    
    ws.onerror = () => {
        document.getElementById('status').textContent = '❌ 本地服务未运行';
        showInstallInstructions();
    };
    
    ws.onmessage = (event) => {
        const result = JSON.parse(event.data);
        displayDNSResult(result);
    };
}

function queryDNS(domain, dnsServer, recordType) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ domain, dnsServer, recordType }));
    } else {
        alert('请先启动本地 DNS 服务');
    }
}

// 页面加载时连接
window.addEventListener('load', connectToLocalService);
```

**Service Worker（PWA 离线支持）：**

```javascript
// sw.js
const CACHE_NAME = 'dns-checker-v1';
const urlsToCache = [
    '/',
    '/index.html',
    '/css/style.css',
    '/js/app.js',
    '/manifest.json'
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then((cache) => cache.addAll(urlsToCache))
    );
});

self.addEventListener('fetch', (event) => {
    // 对于 WebSocket 连接，不缓存
    if (event.request.url.startsWith('ws://')) {
        return;
    }
    
    event.respondWith(
        caches.match(event.request)
            .then((response) => response || fetch(event.request))
    );
});
```

**PWA Manifest：**

```json
{
    "name": "DNS Checker",
    "short_name": "DNS",
    "description": "本地 DNS 验证工具",
    "start_url": "/",
    "display": "standalone",
    "background_color": "#1f2937",
    "theme_color": "#10.721",
    "icons": [
        {
            "src": "/icon-192.png",
            "sizes": "192x192",
            "type": "image/png"
        },
        {
            "src": "/icon-512.png",
            "sizes": "512x512",
            "type": "image/png"
        }
    ]
}
```

**优点：**
- ✅ 真正的 PWA（可安装、离线访问）
- ✅ 实时查询 dig 命令
- ✅ 跨浏览器支持
- ✅ 用户体验接近原生应用

**缺点：**
- ❌ 需要用户手动启动本地 WebSocket 服务
- ❌ 不是"纯"静态应用（依赖本地服务）
- ❌ 首次使用需要安装配置

---

**方案 5C：PWA + DNS-over-HTTPS (DoH) API**

如果可以接受使用 DoH API 而不是 dig 命令：

```javascript
// 使用 Cloudflare DoH API
async function queryDNS_DoH(domain, recordType = 'A') {
    const url = `https://cloudflare-dns.com/dns-query?name=${domain}&type=${recordType}`;
    
    try {
        const response = await fetch(url, {
            headers: { 'Accept': 'application/dns-json' }
        });
        const data = await response.json();
        return data.Answer || [];
    } catch (error) {
        console.error('DoH query failed:', error);
        return [];
    }
}

// 使用 Google DoH API
async function queryDNS_Google(domain, recordType = 'A') {
    const url = `https://dns.google/resolve?name=${domain}&type=${recordType}`;
    
    const response = await fetch(url);
    const data = await response.json();
    return data.Answer || [];
}
```

**优点：**
- ✅ 纯前端实现，无需本地服务
- ✅ 真正的 PWA
- ✅ 可以部署到 GitHub Pages
- ✅ 跨平台、跨浏览器

**缺点：**
- ❌ 不使用 dig 命令（使用 DoH API）
- ❌ 受公司网络限制（可能无法访问 DoH 服务）
- ❌ 无法查询内部 DNS 服务器

---

## 推荐实现方案

### 最佳方案：GitHub Actions + 静态数据展示

这是最适合你需求的方案，既能使用原有的 `dig` 命令，又能在 GitHub Pages 上展示结果。

#### 实现架构

```
Repository Structure:
├── .github/
│   └── workflows/
│       └── dns-check.yml          # GitHub Actions 工作流
├── scripts/
│   └── verify-pub-priv-ip-glm-ipv6-enhanced.sh
├── docs/                          # GitHub Pages 根目录
│   ├── index.html                 # 主页面
│   ├── data/
│   │   ├── latest.json           # 最新查询结果
│   │   └── history/              # 历史数据（可选）
│   ├── css/
│   │   └── style.css
│   └── js/
│       └── app.js                # 数据加载和渲染逻辑
└── domains.txt                    # 要查询的域名列表
```

#### 核心组件

**1. GitHub Actions 工作流 (`.github/workflows/dns-check.yml`)**

```yaml
name: DNS Verification Check

on:
  schedule:
    - cron: '0 */6 * * *'  # 每6小时运行一次
  workflow_dispatch:        # 支持手动触发
  push:
    paths:
      - 'domains.txt'       # 域名列表变更时触发

jobs:
  dns-check:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout repository
        uses: actions/checkout@v3
        
      - name: Install dig
        run: sudo apt-get update && sudo apt-get install -y dnsutils
        
      - name: Run DNS verification
        run: |
          mkdir -p docs/data
          ./scripts/verify-pub-priv-ip-glm-ipv6-enhanced.sh \
            -f domains.txt \
            --output json > docs/data/latest.json
          
          # 添加时间戳
          echo "{\"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\", \"data\": $(cat docs/data/latest.json)}" \
            > docs/data/latest.json
      
      - name: Archive historical data (optional)
        run: |
          mkdir -p docs/data/history
          cp docs/data/latest.json \
            "docs/data/history/$(date -u +%Y%m%d-%H%M%S).json"
      
      - name: Commit and push results
        run: |
          git config user.name "GitHub Actions Bot"
          git config user.email "actions@github.com"
          git add docs/data/
          git commit -m "Update DNS verification results - $(date -u +%Y-%m-%d\ %H:%M:%S)"
          git push
```

**2. 静态 HTML 页面 (`docs/index.html`)**

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS 验证结果 - 实时监控</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>🌐 DNS 验证监控面板</h1>
            <div class="update-info">
                <span id="last-update">加载中...</span>
                <button id="refresh-btn" onclick="loadData()">🔄 刷新</button>
            </div>
        </header>

        <div class="filters">
            <label>
                <input type="checkbox" id="filter-public" checked> 公网 IP
            </label>
            <label>
                <input type="checkbox" id="filter-private" checked> 私网 IP
            </label>
            <label>
                <input type="checkbox" id="filter-local" checked> 本地 IP
            </label>
        </div>

        <div id="results-container">
            <!-- 动态生成内容 -->
        </div>

        <footer>
            <p>数据来源：GitHub Actions 自动化查询</p>
            <p>查询工具：dig (DNS lookup utility)</p>
        </footer>
    </div>

    <script src="js/app.js"></script>
</body>
</html>
```

**3. JavaScript 数据加载和渲染 (`docs/js/app.js`)**

```javascript
async function loadData() {
    try {
        const response = await fetch('data/latest.json');
        const data = await response.json();
        
        // 更新时间戳
        document.getElementById('last-update').textContent = 
            `最后更新: ${new Date(data.timestamp).toLocaleString('zh-CN')}`;
        
        // 渲染结果
        renderResults(data.data);
    } catch (error) {
        console.error('加载数据失败:', error);
        document.getElementById('results-container').innerHTML = 
            '<div class="error">❌ 数据加载失败，请稍后重试</div>';
    }
}

function renderResults(data) {
    const container = document.getElementById('results-container');
    
    // 根据数据结构渲染
    let html = '';
    
    // 假设数据是域名查询结果数组
    if (Array.isArray(data)) {
        data.forEach(result => {
            html += renderDomainResult(result);
        });
    } else {
        // 单个域名结果
        html = renderDomainResult(data);
    }
    
    container.innerHTML = html;
}

function renderDomainResult(result) {
    const verdictClass = result.verdict.toLowerCase();
    const verdictIcon = {
        'public': '🌍',
        'private': '🏠',
        'local': '💻',
        'unknown': '❓'
    }[verdictClass] || '❓';
    
    let html = `
        <div class="result-card ${verdictClass}">
            <div class="result-header">
                <h2>${verdictIcon} ${result.domain}</h2>
                <span class="verdict-badge ${verdictClass}">${result.verdict}</span>
            </div>
            <div class="result-meta">
                <span>记录类型: ${result.record_type}</span>
                <span>Peering 状态: ${result.peering_status}</span>
            </div>
            <div class="dns-servers">
    `;
    
    result.dns_servers.forEach(server => {
        html += `
            <div class="dns-server">
                <div class="server-info">
                    <strong>${server.address}</strong>
                    <span class="server-desc">${server.description}</span>
                </div>
                <div class="server-status ${server.status.toLowerCase()}">
                    ${server.status}
                </div>
                <div class="server-records">
        `;
        
        if (server.records && server.records.length > 0) {
            server.records.forEach(record => {
                html += `
                    <div class="record ${record.type.toLowerCase()}">
                        <span class="ip">${record.ip}</span>
                        <span class="type-badge">${record.type}</span>
                    </div>
                `;
            });
        } else {
            html += '<div class="no-records">无记录</div>';
        }
        
        html += `
                </div>
            </div>
        `;
    });
    
    html += `
            </div>
        </div>
    `;
    
    return html;
}

// 页面加载时自动获取数据
document.addEventListener('DOMContentLoaded', loadData);

// 每5分钟自动刷新一次
setInterval(loadData, 5 * 60 * 1000);
```

**4. 样式表 (`docs/css/style.css`)**

```css
:root {
    --color-public: #10.721;
    --color-private: #f59e0b;
    --color-local: #3b82f6;
    --color-unknown: #6b7280;
    --bg-dark: #1f2937;
    --bg-card: #374151;
    --text-primary: #f9fafb;
    --text-secondary: #d1d5db;
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: var(--bg-dark);
    color: var(--text-primary);
    line-height: 1.6;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
}

header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 2rem;
    padding-bottom: 1rem;
    border-bottom: 2px solid var(--bg-card);
}

h1 {
    font-size: 2rem;
    font-weight: 700;
}

.update-info {
    display: flex;
    align-items: center;
    gap: 1rem;
}

#refresh-btn {
    padding: 0.5rem 1rem;
    background: var(--color-public);
    color: white;
    border: none;
    border-radius: 0.5rem;
    cursor: pointer;
    font-size: 1rem;
    transition: opacity 0.2s;
}

#refresh-btn:hover {
    opacity: 0.8;
}

.filters {
    display: flex;
    gap: 1.5rem;
    margin-bottom: 2rem;
    padding: 1rem;
    background: var(--bg-card);
    border-radius: 0.5rem;
}

.filters label {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    cursor: pointer;
}

.result-card {
    background: var(--bg-card);
    border-radius: 0.75rem;
    padding: 1.5rem;
    margin-bottom: 1.5rem;
    border-left: 4px solid var(--color-unknown);
}

.result-card.public {
    border-left-color: var(--color-public);
}

.result-card.private {
    border-left-color: var(--color-private);
}

.result-card.local {
    border-left-color: var(--color-local);
}

.result-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
}

.verdict-badge {
    padding: 0.25rem 0.75rem;
    border-radius: 0.25rem;
    font-weight: 600;
    font-size: 0.875rem;
    text-transform: uppercase;
}

.verdict-badge.public {
    background: var(--color-public);
    color: white;
}

.verdict-badge.private {
    background: var(--color-private);
    color: white;
}

.verdict-badge.local {
    background: var(--color-local);
    color: white;
}

.dns-server {
    background: rgba(0, 0, 0, 0.2);
    padding: 1rem;
    border-radius: 0.5rem;
    margin-bottom: 0.75rem;
}

.server-info {
    display: flex;
    justify-content: space-between;
    margin-bottom: 0.5rem;
}

.server-desc {
    color: var(--text-secondary);
    font-size: 0.875rem;
}

.server-records {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-top: 0.75rem;
}

.record {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    background: rgba(255, 255, 255, 0.05);
    border-radius: 0.375rem;
    font-family: 'Courier New', monospace;
}

.type-badge {
    padding: 0.125rem 0.5rem;
    border-radius: 0.25rem;
    font-size: 0.75rem;
    font-weight: 600;
}

.record.public .type-badge {
    background: var(--color-public);
}

.record.private .type-badge {
    background: var(--color-private);
}

.record.local .type-badge {
    background: var(--color-local);
}

footer {
    margin-top: 3rem;
    padding-top: 2rem;
    border-top: 1px solid var(--bg-card);
    text-align: center;
    color: var(--text-secondary);
    font-size: 0.875rem;
}

.error {
    padding: 2rem;
    background: var(--color-unknown);
    border-radius: 0.5rem;
    text-align: center;
}
```

#### 部署步骤

1. **准备仓库结构**
   ```bash
   mkdir -p .github/workflows
   mkdir -p docs/{css,js,data}
   mkdir -p scripts
   ```

2. **配置 GitHub Pages**
   - 进入仓库 Settings → Pages
   - Source 选择 `main` 分支的 `/docs` 目录
   - 保存配置

3. **创建域名列表** (`domains.txt`)
   ```
   baidu.com
   google.com
   cloudflare.com
   ```

4. **修改脚本支持批量查询**
   
   需要修改脚本以支持输出多个域名的 JSON 数组格式：
   
   ```bash
   # 在脚本末尾添加批量处理逻辑
   if [[ ${#domains[@]} -gt 1 && "$OUTPUT_FORMAT" == "json" ]]; then
       echo "["
       for i in "${!domains[@]}"; do
           process_domain "${domains[$i]}"
           [[ $i -lt $((${#domains[@]} - 1)) ]] && echo ","
       done
       echo "]"
   fi
   ```

5. **提交并推送**
   ```bash
   git add .
   git commit -m "Add GitHub Pages DNS monitoring"
   git push
   ```

6. **手动触发首次运行**
   - 进入 Actions 标签页
   - 选择 "DNS Verification Check"
   - 点击 "Run workflow"

#### 高级功能扩展

**1. 历史数据趋势图**

在 `app.js` 中添加：

```javascript
async function loadHistoricalData() {
    const files = await fetch('data/history/index.json').then(r => r.json());
    const data = await Promise.all(
        files.slice(-24).map(f => fetch(`data/history/${f}`).then(r => r.json()))
    );
    
    renderTrendChart(data);
}

function renderTrendChart(data) {
    // 使用 Chart.js 或其他图表库
    // 展示 DNS 解析成功率、响应时间等趋势
}
```

**2. 告警通知**

在 GitHub Actions 中添加：

```yaml
- name: Check for failures
  run: |
    if grep -q '"verdict": "UNKNOWN"' docs/data/latest.json; then
      echo "::warning::DNS verification failed for some domains"
      # 可以集成 Slack/Email 通知
    fi
```

**3. 多环境支持**

```yaml
strategy:
  matrix:
    location: [us-east, eu-west, asia-pacific]
    
steps:
  - name: Run from ${{ matrix.location }}
    run: |
      # 使用不同的 DNS 服务器或代理
      ./scripts/verify-pub-priv-ip-glm-ipv6-enhanced.sh \
        -f domains.txt \
        --dns ${{ secrets[format('DNS_SERVER_{0}', matrix.location)] }} \
        --output json > docs/data/${{ matrix.location }}.json
```

---

## PWA 方案总结

### PWA 能否实现纯本地 dig 查询？

**简短回答：不能。**

PWA 本质上仍然是运行在浏览器沙箱中的 Web 应用，无法突破以下限制：

1. **无法执行系统命令**：浏览器安全模型禁止直接调用 `dig`、`nslookup` 等系统工具
2. **无法发送原始网络包**：无法直接发送 UDP/TCP DNS 查询（53 端口）
3. **受网络策略限制**：CORS、CSP 等安全策略仍然适用

### PWA 的实际可行方案

| 方案 | 使用 dig | 纯静态 | 安装复杂度 | 适用场景 |
|------|----------|--------|------------|----------|
| PWA + Native Messaging | ✅ | ❌ | ⭐⭐⭐⭐ | Chrome Extension |
| PWA + WebSocket 本地服务 | ✅ | ❌ | ⭐⭐⭐ | **推荐** - 本地使用 |
| PWA + DoH API | ❌ | ✅ | ⭐ | 公网环境 |

**结论：** 如果必须使用 dig 命令，PWA 需要配合本地服务（WebSocket 或 Native Messaging），无法做到"纯"静态应用。

---

## 所有方案对比总结

| 方案 | 实时性 | 使用 dig | 纯静态 | 复杂度 | 适用场景 |
|------|--------|----------|--------|--------|----------|
| **GitHub Actions + 静态数据** | ⭐⭐⭐ | ✅ | ✅ | ⭐⭐ | **推荐** - 公开展示 |
| 本地生成 + 手动推送 | ⭐ | ✅ | ✅ | ⭐ | 临时方案 |
| WebAssembly | ⭐⭐⭐⭐⭐ | ❌ | ✅ | ⭐⭐⭐⭐⭐ | 技术探索 |
| 本地 Web 服务 | ⭐⭐⭐⭐⭐ | ✅ | ❌ | ⭐⭐⭐ | 内网环境 |
| **PWA + WebSocket 服务** | ⭐⭐⭐⭐⭐ | ✅ | ❌ | ⭐⭐⭐ | **推荐** - 本地使用 |
| PWA + Native Messaging | ⭐⭐⭐⭐⭐ | ✅ | ❌ | ⭐⭐⭐⭐ | Chrome 专用 |
| PWA + DoH API | ⭐⭐⭐⭐⭐ | ❌ | ✅ | ⭐⭐ | 公网环境 |

---

## 针对你的需求的最终建议

### 场景 1：公开展示（GitHub Pages）
**推荐：GitHub Actions + 静态数据**
- 定期自动更新
- 完全使用 dig 命令
- 无需用户安装任何东西
- 适合对外展示监控结果

### 场景 2：个人本地使用
**推荐：PWA + WebSocket 本地服务**
- 实时查询
- 安装后像原生应用
- 离线可用（UI 部分）
- 一次配置，长期使用

### 场景 3：团队内网使用
**推荐：本地 Web 服务 + PWA 前端**
- 部署在内网服务器
- 团队成员通过浏览器访问
- 集中管理，统一维护

### 实施路线图

**阶段 1（立即可用）：**
```bash
# 使用现有脚本 + 手动生成
./verify-pub-priv-ip-glm-ipv6-enhanced.sh -f domains.txt --output json > result.json
# 创建简单的 HTML 读取 result.json
```

**阶段 2（1-2天）：**
- 实现 GitHub Actions 自动化
- 部署到 GitHub Pages
- 实现基础可视化

**阶段 3（可选，1周）：**
- 开发 PWA + WebSocket 本地服务
- 添加离线支持
- 实现实时查询

---

## 快速启动：PWA + WebSocket 方案

如果你想尝试 PWA 方案，这里是最小化实现：

### 1. 创建本地服务（5分钟）

```bash
# 安装依赖
npm init -y
npm install ws

# 创建服务
cat > dns-service.js << 'EOF'
const WebSocket = require('ws');
const { exec } = require('child_process');
const wss = new WebSocket.Server({ port: 8080 });

wss.on('connection', (ws) => {
    ws.on('message', (msg) => {
        const { domain, dns, type } = JSON.parse(msg);
        exec(`dig @${dns} ${domain} ${type} +short`, (err, stdout) => {
            ws.send(JSON.stringify({ 
                success: !err, 
                result: stdout.trim(),
                error: err?.message 
            }));
        });
    });
});

console.log('🚀 DNS Service running on ws://localhost:8080');
EOF

# 启动服务
node dns-service.js
```

### 2. 创建 PWA 页面（10分钟）

```html
<!DOCTYPE html>
<html>
<head>
    <title>DNS Checker PWA</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="manifest" href="manifest.json">
</head>
<body>
    <h1>🌐 DNS Checker</h1>
    <div id="status">连接中...</div>
    
    <input id="domain" placeholder="域名" value="baidu.com">
    <input id="dns" placeholder="DNS" value="8.8.8.8">
    <select id="type">
        <option>A</option>
        <option>AAAA</option>
        <option>CNAME</option>
    </select>
    <button onclick="query()">查询</button>
    
    <pre id="result"></pre>
    
    <script>
        let ws = new WebSocket('ws://localhost:8080');
        ws.onopen = () => status.textContent = '✅ 已连接';
        ws.onerror = () => status.textContent = '❌ 服务未启动';
        ws.onmessage = (e) => {
            const data = JSON.parse(e.data);
            result.textContent = data.success ? data.result : data.error;
        };
        
        function query() {
            ws.send(JSON.stringify({
                domain: domain.value,
                dns: dns.value,
                type: type.value
            }));
        }
        
        // 注册 Service Worker
        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('sw.js');
        }
    </script>
</body>
</html>
```

### 3. 使用

```bash
# 启动服务
node dns-service.js

# 打开浏览器
open index.html

# 或使用 Python 简单服务器
python3 -m http.server 8000
# 访问 http://localhost:8000
```

---

## 注意事项

### GitHub Actions 限制
- 免费账户每月 2000 分钟运行时间
- 单次运行最长 6 小时
- 建议合理设置 cron 频率（如每 6 小时一次）

### 数据存储
- GitHub 仓库大小限制 1GB
- 建议定期清理历史数据，只保留最近 30 天
- 可以使用 Git LFS 存储大文件

### 安全考虑
- 不要在公开仓库中暴露内部域名
- 使用 GitHub Secrets 存储敏感配置
- 考虑使用私有仓库 + GitHub Pages

---

## 结论

对于你的需求，**GitHub Actions + 静态数据展示**是最佳方案。它完美平衡了以下要求：

✅ 继续使用原有的 `dig` 命令和脚本逻辑  
✅ 可以在 GitHub Pages 上公开展示  
✅ 自动化更新，无需手动干预  
✅ 适应公司网络环境限制  
✅ 实现成本低，维护简单  

这个方案不是"实时"查询，但通过合理的更新频率（如每小时或每 6 小时），可以提供足够新鲜的数据，同时避免了浏览器环境的技术限制。


# gemini

这是一个非常经典的需求，但也涉及到一个核心的技术壁垒：**纯静态网页（运行在浏览器中）出于安全沙盒限制，是绝对无法直接调用本地系统的命令行工具（如 `dig`）的，也无法直接发起底层的 UDP/TCP DNS 请求。**

既然你们公司的网络环境受限，无法使用公共的 DoH (DNS over HTTPS) API，且必须依赖本地机器的网络环境和 `dig` 命令，那么要实现“网页化展示”，我们有以下几种切实可行的方案：

---

### 方案一：生成静态数据驱动的报告页面（最符合“纯静态+GitHub Pages”场景）

**思路**：
既然你的脚本已经支持了 `--output json`，你可以让脚本把结果输出为 `data.json`，然后写一个纯静态的 `index.html` 放在 GitHub Pages 上，这个页面通过 JavaScript 读取并渲染 `data.json`。

**工作流**：
1. 在本地机器执行：`./verify-pub-priv-ip-glm-ipv6-enhanced.sh domains.txt --output json > data.json`
2. 将 `data.json` 提交（Push）到 GitHub。
3. GitHub Pages 上的静态网页自动刷新展示最新结果。

**示例 HTML (保存为 `index.html`)**:
```html
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <title>DNS 查询结果报告</title>
    <style>
        body { font-family: system-ui; margin: 2rem; background: #f4f4f5; }
        .card { background: white; padding: 1rem; margin-bottom: 1rem; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .success { color: green; } .failed { color: red; }
        .badge { background: #e0e7ff; color: #3730a3; padding: 2px 6px; border-radius: 4px; font-size: 0.8em; }
    </style>
</head>
<body>
    <h1>DNS Verification Report</h1>
    <div id="app">加载中...</div>

    <script>
        // 读取同目录下的 JSON 文件
        fetch('data.json')
            .then(res => res.json())
            .then(data => {
                const app = document.getElementById('app');
                app.innerHTML = ''; 
                // data 应当是你脚本输出的 JSON 数组格式
                data.forEach(result => {
                    let html = `<div class="card">
                        <h3>${result.domain} (Verdict: ${result.verdict})</h3>
                        <ul>`;
                    
                    result.dns_servers.forEach(server => {
                        let statusClass = server.status === 'SUCCESS' ? 'success' : 'failed';
                        html += `<li><strong>${server.address}</strong>: <span class="${statusClass}">${server.status}</span>`;
                        if(server.records && server.records.length > 0) {
                            html += `<ul>`;
                            server.records.forEach(r => {
                                html += `<li>${r.ip} <span class="badge">${r.type}</span></li>`;
                            });
                            html += `</ul>`;
                        }
                        html += `</li>`;
                    });
                    html += `</ul></div>`;
                    app.innerHTML += html;
                });
            })
            .catch(err => {
                document.getElementById('app').innerHTML = '<p class="failed">无法加载 data.json，请确保已生成该文件并在本地服务器环境下打开。</p>';
            });
    </script>
</body>
</html>
```
*优点：100% 静态，可托管在 GitHub，无需维护后端。*
*缺点：不是实时的查询框，而是批处理结果的展示。*

---

### 方案二：建立轻量级本地 Web API（实现真正的交互式网页）

如果你希望网页上有一个**输入框**，输入域名点击“查询”就能立刻出结果，那么必须在你的本地机器上运行一个“极简后端”。

由于你本身在写 Bash 脚本，我们可以使用 `shell2http`、`websocketd` 或者简单的 Python 脚本将你的 Bash 暴露为本地 API。

**使用 Python Flask 作为中间件桥梁（推荐）**：
1. 本地写一个 `server.py`，它接收前端请求，并在本地调用你的 `.sh` 脚本。
2. 静态页面通过 Ajax 访问 `http://127.0.0.1:5000/api/query?domain=xxx`。

**后端代码 (`server.py`)**:
```python
from flask import Flask, request, jsonify
from flask_cors import CORS
import subprocess
import json

app = Flask(__name__)
CORS(app) # 允许跨域，这样 GitHub 上的静态页面也能请求本地接口

@app.route('/api/query')
def query_dns():
    domain = request.args.get('domain')
    if not domain:
        return jsonify({"error": "No domain provided"}), 400
    
    try:
        # 调用你的 bash 脚本并要求 json 输出
        result = subprocess.run(
            ['./verify-pub-priv-ip-glm-ipv6-enhanced.sh', domain, '--output', 'json'],
            capture_output=True, text=True, check=True
        )
        # 解析脚本的 JSON 输出并返回给网页
        return jsonify(json.loads(result.stdout))
    except subprocess.CalledProcessError as e:
        return jsonify({"error": "Script execution failed", "details": e.stderr}), 500

if __name__ == '__main__':
    app.run(port=5000)
```

**前端交互逻辑 (放在 GitHub Pages 的静态页面里)**:
```javascript
async function doQuery() {
    const domain = document.getElementById('domainInput').value;
    // 请求运行在本地的 Python 服务器
    const response = await fetch(`http://127.0.0.1:5000/api/query?domain=${domain}`);
    const data = await response.json();
    // 渲染 data 到页面...
    console.log(data);
}
```
*(注意：如果前端托管在 `https://` 的 GitHub Pages 上，请求本地 `http://127.0.0.1` 可能会触发浏览器的“混合内容拦截”。建议将前端 HTML 也直接和 Python 放在一起本地访问。)*

---

### 方案三：使用 OliveTin / Gotty 一键将脚本转化为网页

这也是非常适合企业内网运维场景的方案。不需要自己写前后端代码。

**1. 使用 OliveTin**
[OliveTin](https://github.com/OliveTin/OliveTin) 是一个能直接把 Linux Shell 脚本包装成漂亮 Web 界面的工具。
你只需要配置一个 yaml 文件：
```yaml
actions:
  - title: 验证域名 DNS
    shell: ./verify-pub-priv-ip-glm-ipv6-enhanced.sh "{{ domain }}" --output normal
    arguments:
      - name: domain
        type: ascii
```
启动后，它会在本地起一个网页，你可以直接在网页输入框里打字，网页上的终端框会实时显示带有 ANSI 颜色的 bash 脚本输出。

**2. 使用 Gotty**
[Gotty](https://github.com/yudai/gotty) 可以将命令行程序转换为 Web 应用。
只需运行：
```bash
gotty -w ./verify-pub-priv-ip-glm-ipv6-enhanced.sh --output normal
```
然后在浏览器中打开 `http://localhost:8080`，你就能像在终端里一样与脚本交互。

---

### 总结与建议

*   **如果你的目的是“定期巡检并汇报”：** 用 **方案一**。写个 crontab 定时跑脚本生成 `data.json`，前端写个纯静态页面读 JSON，挂在 GitHub Pages 或内部 Nginx 上。
*   **如果你的目的是“提供一个随时可查的网页小工具”：** 用 **方案三 (OliveTin)**。这是成本最低、效果最好的内网运维工具封装法。
*   **如果非要自己开发前后端分离的网页：** 用 **方案二**。用 Python/Node 写个几十行的本地代理接口去调你的 Bash 脚本。