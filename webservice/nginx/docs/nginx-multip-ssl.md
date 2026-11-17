

```nginx.conf
user nxadm ngxgrp;
worker_processes 1;
error_log /appvol/nginx/logs/error.log info;
events {
    worker_connections 1024;
}
http {
    include mime.types;
    default_type application/octet-stream;
    server_names_hash_bucket_size 256;
    # increase proxy buffer size
    proxy_buffer_size 32k;
    proxy_buffers 4 128k;
    proxy_busy_buffers_size 256k;
    # increase the header size to 32K
    large_client_header_buffers 4 32k;
    log_format correlation '$remote_addr - $remote_user [$time_local] "$status $bytes_sent" "$http_referer" '
                          '"$http_user_agent" "$http_x_forwarded_for" "$request_id"';
    access_log /appvol/nginx/logs/access.log correlation;
    server_tokens off;
    sendfile on;
    keepalive_timeout 65;
    server {
        listen 443 ssl;
        server_name api.abc.com; # as old api 唯一入口后面根据https://api.abc.com/api_name1_version/v1/
        client_max_body_size 20m;
        underscores_in_headers on;
        # HTTP/2 Support
        http_version 1.1;
        ssl_certificate /etc/ssl/certs/api.abc.com_cert.crt; # update with your cert
        ssl_certificate_key /etc/ssl/private/api.abc.com_key.key; # update with your key
        ssl_dhparam /etc/ssl/certs/your_dhparam.pem; # update with your dh param
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
        ssl_prefer_server_ciphers off;
        # enable HSTS (HTTP Strict Transport Security)
        add_header X-Content-Type-Options nosniff always;
        proxy_hide_header x-content-type-options;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Frame-Options "DENY";
        ssl_session_timeout 5m;
        include /etc/nginx/conf.d/*.conf;
    }
    server {
        listen 443 ssl;
        server_name *.def.com; # as new api 唯一入口后面根据https://*.def.com 每个 API 都有独立的域名
        client_max_body_size 20m;
        underscores_in_headers on;
        # HTTP/2 Support
        http_version 1.1;
        ssl_certificate /etc/ssl/certs/def.com_cert.crt; # this cert is for def.com
        ssl_certificate_key /etc/ssl/private/def.com_key.key; # update with your key
        ssl_dhparam /etc/ssl/certs/your_dhparam.pem; # update with your dh param
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
        ssl_prefer_server_ciphers off;
        # enable HSTS (HTTP Strict Transport Security)
        add_header X-Content-Type-Options nosniff always;
        proxy_hide_header x-content-type-options;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
        add_header X-Frame-Options "DENY";
        ssl_session_timeout 5m;
        include /etc/nginx/vhosts/*.conf; 
    }
}
```

## 探索与实现过程 (Exploration & Implementation Process)

### 1. 核心问题分析
目前你拥有两个独立的入口（`api.abc.com` 和 `*.def.com`），并希望通过 GCP Bucket 同步机制简化 SSL 配置。
**核心挑战**：
- **同步逻辑约束**：Bucket 同步逻辑更倾向于处理单一的一组证书（证书+私钥）。
- **证书独立性**：虽然通过 SNI 可以让 Nginx 支持多域名，但传统做法需要配置多个 `ssl_certificate` 路径。
- **简化目标**：在不修改同步逻辑的前提下，实现两套域名证书的自动化分发与加载。

---

### 2. 解决方案探索

#### 方案 A：使用 SAN (Subject Alternative Name) 证书 [最推荐]
**原理**：
SAN 证书（又称多域名证书或 UCC 证书）允许在同一个证书文件中包含多个不同的域名（例如：`api.abc.com` 和 `*.def.com`）。

**适配理由**：
- **完全兼容 Bucket 逻辑**：你只需要生成一个包含两组域名的 SAN 证书，替换原来的证书文件。Bucket 同步逻辑依然只需同步同一个 `.crt` 和 `.key` 文件到目标路径。
- **Nginx 配置极简**：两个 `server` 块直接指向同一个路径即可，无需复杂的分支逻辑。

**配置示例**：
```nginx
# 两个 server 块使用同一套证书文件（包含两组域名）
server {
    server_name api.abc.com;
    ssl_certificate /etc/ssl/certs/unified_entry.crt;
    ssl_certificate_key /etc/ssl/private/unified_entry.key;
    # ... 其他配置 ...
}

server {
    server_name *.def.com;
    ssl_certificate /etc/ssl/certs/unified_entry.crt;
    ssl_certificate_key /etc/ssl/private/unified_entry.key;
    # ... 其他配置 ...
}
```

#### 方案 B：Nginx Map + 动态变量加载 (Nginx 1.15.9+)
**原理**：
利用 Nginx 的 `map` 指令，根据 SNI 变量 `$ssl_server_name` 动态决定证书加载路径。

**配置示例**：
```nginx
map $ssl_server_name $ssl_cert_file {
    api.abc.com      "api.abc.com_cert.crt";
    ~^.*\.def\.com$  "def.com_cert.crt";
}

server {
    listen 443 ssl;
    server_name api.abc.com *.def.com;
    
    # 动态加载路径
    ssl_certificate     /etc/ssl/certs/$ssl_cert_file;
    ssl_certificate_key /etc/ssl/private/$ssl_cert_file_key;
}
```
**场景限制**：
- 虽然配置简化了，但在 Bucket 同步层面，你依然需要确保证书文件已按命名规则同步到位。如果你更倾向于“一个入口同步一切”，此方案稍显复杂。

---

### 3. 落地建议与结论

针对你的目的——**“在不改变 Bucket 同步逻辑的情况下简化配置”**：

**建议采用 方案 A (SAN 证书)**。

1. **操作流程**：
   - 重新签发一份包含 `api.abc.com` 和 `*.def.com` (Wildcard) 的 SAN 证书。
   - 将新证书内容覆盖至原有 Bucket 同步的证书路径。
   - 修改 Nginx 配置，让两个域名侦听块指向这组唯一的证书。
2. **优势**：
   - **零逻辑变更**：ET / Bucket 同步脚本无需改动。
   - **高稳定性**：避免了 Nginx 变量加载可能带来的运行时解析风险。
   - **易维护**：每次同步更新一个文件即可覆盖所有入口域名。

---

## 多证书 Bucket 同步方案 (Multi-Cert Bucket Sync Solution)

如果你已经拥有两套独立的证书文件，并希望在不合并证书的前提下，通过修改实例（Instances）的同步逻辑来实现自动化管理，可以参考以下进阶方案。

### 1. Bucket 目录结构升级
为了支持多证书，建议在 GCS Bucket 中按域名划分子目录，而不是将所有文件堆放在根目录。

**推荐结构**：
```bash
gs://your-nginx-bucket/certs/
├── api.abc.com/
│   ├── cert.crt
│   └── key.key
└── def.com/
    ├── cert.crt
    └── key.key
```

### 2. 实例同步逻辑调整 (Sync Script)
在你的主机实例上，原本可能只是同步一个文件。现在需要通过 `gsutil rsync` 的递归模式来同步整个目录结构。

**同步命令示例**：
```bash
# 使用 -r 递归同步，-d 删除目标端多余文件
gsutil -m rsync -r -d gs://your-nginx-bucket/certs/ /etc/ssl/nginx-certs/
```

**逻辑优势**：
- **目录隔离**：每个域名的证书都在独立的文件夹内，清晰明了，不会发生命名冲突。
- **原子更新**：`rsync` 会保证本地目录结构与 Bucket 严格一致。

### 3. Nginx 配置适配
同步完成后，Nginx 的 `server` 块需要指向对应的子目录。

```nginx
# Server Block 1: api.abc.com
server {
    listen 443 ssl;
    server_name api.abc.com;
    
    ssl_certificate     /etc/ssl/nginx-certs/api.abc.com/cert.crt;
    ssl_certificate_key /etc/ssl/nginx-certs/api.abc.com/key.key;
    # ...
}

# Server Block 2: *.def.com
server {
    listen 443 ssl;
    server_name *.def.com;
    
    ssl_certificate     /etc/ssl/nginx-certs/def.com/cert.crt;
    ssl_certificate_key /etc/ssl/nginx-certs/def.com/key.key;
    # ...
}
```

### 4. 探索：自动化重命名（快速适配旧逻辑）
如果你由于某些原因无法修改 Nginx 的路径配置，可以在同步脚本中增加一步“软链接”或“重命名”逻辑。

**自动化脚本示例**：
```bash
#!/bin/bash
# 1. 同步全量证书
gsutil -m rsync -r gs://your-nginx-bucket/certs/ /tmp/certs_staging/

# 2. 根据需要重命名或移动到 Nginx 指定路径
cp /tmp/certs_staging/api.abc.com/cert.crt /etc/ssl/certs/api.abc.com_cert.crt
cp /tmp/certs_staging/def.com/cert.crt /etc/ssl/certs/def.com_cert.crt

# 3. 热加载 Nginx
nginx -s reload
```

### 5. 总结建议
- **如果你追求极致简化**：请回到方案 A (SAN 证书)，这不需要改动任何同步逻辑。
- **如果你必须保留独立证书**：请采用上述 **“目录结构化同步”** 的方式，这不仅解决了当前问题，也为未来增加第 3、4 个域名做好了架构铺垫。
```