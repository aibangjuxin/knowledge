# Nginx 动态证书更新方案：多租户 SSL 证书热更新架构

## 背景与问题

### 场景描述

```
                    ┌─────────────────────────────────────────┐
                    │           GCP Compute Engine             │
                    │                                         │
Tenant A ──HTTPS──▶│  ┌─────────┐     ┌─────────────────┐   │
tenant-a.example.com│  │  Nginx  │────▶│  App Backend    │   │
                    │  └────┬────┘     └─────────────────┘   │
                    │       │                                  │
                    │       │ ssl_certificate                   │
                    │       │ /etc/nginx/certs/tenant-a/       │
                    │       │   ├── cert.pem                    │
                    │       │   └── key.pem                     │
                    │                                          │
Tenant B ──HTTPS──▶│  ┌────┴────┐                            │
tenant-b.example.com│  │  Nginx  │                            │
                    │  └─────────┘                            │
                    │       │                                  │
                    │       │ ssl_certificate                   │
                    │       │ /etc/nginx/certs/tenant-b/       │
                    │       │   ├── cert.pem                    │
                    │       │   └── key.pem                     │
                    └───────┼───────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              │                             │
         ┌────▼────┐                  ┌─────▼─────┐
         │   GCS   │   ◀──KMS─────── │   KMS      │
         │ (Bucket)│     encrypted   │   Key      │
         └─────────┘                  └───────────┘
         存储加密后的证书               用于解密
```

### 当前痛点

| 问题 | 说明 |
|------|------|
| **Rolling Update 成本高** | 每新增一个租户都需要重启实例，VM 启动慢 |
| **生效时间长** | 实例启动 + 证书下载 + KMS 解密 + Nginx 启动 |
| **中断风险** | Rolling Update 期间服务可能短暂不可用 |
| **扩缩容延迟** | 无法快速响应突发的新租户接入 |

### 期望行为

```
现状（Rolling Update）：
  新租户证书上传 GCS → 触发 Rolling Update → 实例重启 → Nginx 重启 → 生效
  耗时：3-5 分钟 + 服务中断风险

期望（热更新）：
  新租户证书上传 GCS → 证书同步 → nginx -s reload → 生效
  耗时：10-30 秒，无服务中断
```

---

## 核心原理：Nginx SSL 证书Reload 机制

### Nginx 如何加载 SSL 证书

Nginx 的 `ssl_certificate` 和 `ssl_certificate_key` 指令在以下时机加载：

```
nginx -s reload 时：
  1. Nginx master 进程读取新的 nginx.conf
  2. 重新解析 ssl_certificate / ssl_certificate_key 指定的文件路径
  3. 将证书和私钥加载到内存（SSL_CTX）
  4. 新请求使用新的证书

关键洞察：
  - nginx -s reload 不中断现有连接（旧 worker 处理完）
  - 新连接使用新证书
  - 证书文件可以在 reload 前更新
```

### SSL 证书热更新可行性

```
┌──────────────────────────────────────────────────────────────┐
│  Nginx reload 时重新读取证书文件                              │
│                                                              │
│  原证书文件 ──▶ 被修改 ──▶ nginx -s reload ──▶ 新证书生效    │
│                                                              │
│  ✓ 文件级别操作                                              │
│  ✓ 无需进程重启                                              │
│  ✓ 连接不中断（优雅重启）                                     │
└──────────────────────────────────────────────────────────────┘

前提条件：
  1. 证书文件路径不变（或软链接不变）
  2. 证书格式正确（PEM）
  3. 私钥权限正确（600）
  4. nginx.conf 配置正确
```

---

## 方案一：证书同步 Daemon（推荐）

### 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                 GCP Compute Engine (Nginx Host)              │
│  ┌──────────────┐     ┌──────────────┐     ┌────────────┐ │
│  │  Nginx       │     │ Cert-Sync    │     │  GCS        │ │
│  │  Master      │◀────│ Daemon       │────▶│  FUSE      │ │
│  │  Process     │     │ (watch +     │     │  Mount     │ │
│  │              │     │  reload)     │     │  /gcs/certs│ │
│  └──────────────┘     └──────┬───────┘     └────────────┘ │
│                              │                              │
│                     ┌────────▼────────┐                    │
│                     │   KMS Decrypt    │                    │
│                     │   (on-demand)    │                    │
│                     └──────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS + Service Account
                              ▼
                    ┌─────────────────┐
                    │   GCS Bucket    │
                    │   (KMS 加密)     │
                    └─────────────────┘
```

### 工作流程

```
1. 证书上传
   └─▶ 租户运营系统上传证书到 GCS: gs://bucket/tenants/tenant-a/cert.pem

2. GCS FUSE 挂载（Daemon 启动时）
   └─▶ gcsfuse --implicit-dirs bucket /gcs/certs
   └─▶ 注意：GCS FUSE 直接访问对象，需要_bucket-level KMS权限

3. Daemon 检测变化
   └─▶ Python/Go 进程 inotify/FSEvents 监控 /gcs/certs 目录
   └─▶ 或定时轮询（每 30s）检查文件变化

4. KMS 解密（如果 GCS 未使用 CMEK 自动解密）
   └─▶ 使用 Service Account + KMS API 解密
   └─▶ 写入 /etc/nginx/certs/tenant-a/cert.pem

5. Nginx Reload
   └─▶ nginx -s reload
   └─▶ Nginx master 进程重新加载证书
   └─▶ 新连接使用新证书
```

### 实现代码：Cert-Sync Daemon (Python)

```python
#!/usr/bin/env python3
"""
Nginx Certificate Sync Daemon
- Watches GCS bucket for new/updated certificates
- Decrypts KMS-encrypted certificates
- Reloads Nginx when certificates change
"""

import os
import time
import json
import logging
import subprocess
import hashlib
from pathlib import Path
from google.cloud import storage
from google.cloud import kms
from google.api_core.exceptions import NotFound

# Configuration
GCS_BUCKET = "your-certificates-bucket"
KMS_KEY = "projects/your-project/locations/global/keyRings/your-ring/cryptoKeys/your-key"
NGINX_CERT_DIR = Path("/etc/nginx/certs")
NGINX_RELOAD_CMD = ["nginx", "-s", "reload"]
POLL_INTERVAL = 30  # seconds
GCS_MOUNT_POINT = Path("/gcs/certs")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class CertSyncDaemon:
    def __init__(self):
        self.storage_client = storage.Client()
        self.kms_client = kms.KeyManagementServiceClient()
        self.bucket = self.storage_client.bucket(GCS_BUCKET)
        self.cert_hashes = {}  # tenant -> file_hash

    def ensure_directories(self):
        """Ensure certificate directories exist"""
        NGINX_CERT_DIR.mkdir(parents=True, exist_ok=True)
        for tenant in self.list_tenants():
            (NGINX_CERT_DIR / tenant).mkdir(exist_ok=True)

    def list_tenants(self):
        """List all tenants from GCS bucket"""
        try:
            blobs = list(self.bucket.list_blobs(prefix="tenants/"))
            tenants = set()
            for blob in blobs:
                parts = blob.name.split("/")
                if len(parts) >= 2:
                    tenants.add(parts[1])
            return tenants
        except Exception as e:
            logger.error(f"Failed to list tenants: {e}")
            return set()

    def download_and_decrypt(self, tenant: str, cert_name: str):
        """Download certificate from GCS and decrypt if needed"""
        remote_path = f"tenants/{tenant}/{cert_name}"
        blob = self.bucket.blob(remote_path)

        # Download encrypted content
        encrypted_content = blob.download_as_bytes()

        # Decrypt using KMS
        try:
            decrypt_response = self.kms_client.decrypt(
                name=KMS_KEY,
                ciphertext=encrypted_content
            )
            decrypted_content = decrypt_response.plaintext
            logger.info(f"Decrypted certificate for {tenant}/{cert_name}")
            return decrypted_content
        except Exception as e:
            logger.error(f"KMS decryption failed for {tenant}/{cert_name}: {e}")
            raise

    def write_certificate(self, tenant: str, cert_name: str, content: bytes):
        """Write certificate to disk and handle permissions"""
        tenant_dir = NGINX_CERT_DIR / tenant
        tenant_dir.mkdir(exist_ok=True)

        file_path = tenant_dir / cert_name
        temp_path = tenant_dir / f".{cert_name}.tmp"

        # Write to temp file first (atomic)
        with open(temp_path, "wb") as f:
            f.write(content)
            os.fsync(f)  # Ensure write is flushed to disk

        # Set permissions: cert=644, key=600
        if cert_name.endswith(".key"):
            os.chmod(temp_path, 0o600)
        else:
            os.chmod(temp_path, 0o644)

        # Atomic rename
        temp_path.rename(file_path)
        logger.info(f"Written certificate to {file_path}")

    def compute_hash(self, content: bytes) -> str:
        """Compute SHA256 hash of content"""
        return hashlib.sha256(content).hexdigest()

    def sync_certificates(self):
        """Sync all certificates from GCS"""
        tenants = self.list_tenants()
        logger.info(f"Found tenants: {tenants}")

        for tenant in tenants:
            for cert_name in ["cert.pem", "key.pem"]:
                try:
                    remote_path = f"tenants/{tenant}/{cert_name}"
                    blob = self.bucket.blob(remote_path)

                    # Get remote content and hash
                    content = blob.download_as_bytes()
                    content_hash = self.compute_hash(content)

                    # Check if changed
                    key = f"{tenant}/{cert_name}"
                    if self.cert_hashes.get(key) == content_hash:
                        continue  # No change

                    logger.info(f"Certificate changed: {key}")

                    # Download and decrypt
                    decrypted = self.download_and_decrypt(tenant, cert_name)
                    self.write_certificate(tenant, cert_name, decrypted)
                    self.cert_hashes[key] = content_hash

                except NotFound:
                    logger.debug(f"Certificate not found: {tenant}/{cert_name}")
                except Exception as e:
                    logger.error(f"Error syncing {tenant}/{cert_name}: {e}")

        # Reload nginx if any certificate changed
        if self.cert_hashes:
            self.reload_nginx()

    def reload_nginx(self):
        """Send reload signal to Nginx"""
        try:
            subprocess.run(NGINX_RELOAD_CMD, check=True)
            logger.info("Nginx reloaded successfully")
        except subprocess.CalledProcessError as e:
            logger.error(f"Nginx reload failed: {e}")

    def run(self):
        """Main daemon loop"""
        logger.info("Starting Certificate Sync Daemon")
        self.ensure_directories()

        # Initial sync
        self.sync_certificates()

        # Main loop
        while True:
            time.sleep(POLL_INTERVAL)
            try:
                self.sync_certificates()
            except Exception as e:
                logger.error(f"Error in sync loop: {e}")


if __name__ == "__main__":
    daemon = CertSyncDaemon()
    daemon.run()
```

### systemd Unit 文件

```ini
# /etc/systemd/system/nginx-cert-sync.service
[Unit]
Description=Nginx Certificate Sync Daemon
After=network-online.target gcsfuse.service
Wants=gcsfuse.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/nginx-cert-sync
ExecStart=/opt/nginx-cert-sync/sync.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/nginx/certs /var/log/nginx-cert-sync

# GCP Service Account (使用 Workload Identity 或 Service Account Key)
Environment="GOOGLE_APPLICATION_CREDENTIALS=/etc/nginx-cert-sync/service-account.json"

[Install]
WantedBy=multi-user.target
```

### 优缺点

| 优点 | 缺点 |
|------|------|
| ✅ 完全控制，可定制化 | ❌ 需要开发/维护一个 Daemon |
| ✅ 支持 KMS 解密 | ❌ 需要处理权限、错误、重试 |
| ✅ 延迟低（30s 轮询或事件触发） | ❌ 单点：如果 Daemon 挂了需要手动恢复 |
| ✅ 无需 Rolling Update |  |

---

## 方案二：GCS 事件驱动 + Pub/Sub

### 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                        GCS Bucket                                │
│              (Object Change Notification)                        │
│                        │                                         │
│                        ▼                                         │
│               ┌─────────────────┐                                │
│               │    Pub/Sub      │                                │
│               │    Topic        │                                │
│               │  (cert-events)  │                                │
│               └────────┬────────┘                                │
│                        │                                         │
│                        ▼                                         │
│         ┌─────────────────────────────┐                          │
│         │   Cloud Function / Cloud Run │                         │
│         │   (Certificate Processor)    │                         │
│         │                              │                         │
│         │  1. Download from GCS        │                         │
│         │  2. Decrypt via KMS          │                         │
│         │  3. SSH to instance          │                         │
│         │  4. Write certificate        │                         │
│         │  5. Trigger nginx reload     │                         │
│         └─────────────────────────────┘                          │
│                           │                                      │
│                           │ HTTPS + Instance SSH                  │
│                           ▼                                      │
│               ┌─────────────────────┐                            │
│               │  Compute Engine     │                            │
│               │  Nginx Instance    │                            │
│               └─────────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

### Pub/Sub + Cloud Run 实现

```python
# main.py (Cloud Run)
from flask import Flask, request
import subprocess
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

NGINX_INSTANCE = os.environ.get("NGINX_INSTANCE")
SSH_KEY_PATH = os.environ.get("SSH_KEY_PATH", "/app/id_rsa")

# GCS bucket and KMS config
GCS_BUCKET = "your-certificates-bucket"
KMS_KEY = "projects/your-project/locations/global/keyRings/your-ring/cryptoKeys/your-key"


@app.route("/", methods=["POST"])
def handle_gcs_notification(request):
    """Handle GCS object change notification"""
    message = request.json
    data = message.get("message", {})
    attributes = data.get("attributes", {})

    # Get object details
    object_name = attributes.get("objectId")
    object_generation = attributes.get("objectGeneration")

    if not object_name or not object_name.startswith("tenants/"):
        return "ignored", 200

    logger.info(f"Received notification for: {object_name}")

    # Parse tenant and cert name
    parts = object_name.split("/")
    tenant = parts[1]
    cert_name = parts[2]

    try:
        # Step 1: Download from GCS
        content = download_from_gcs(GCS_BUCKET, object_name)

        # Step 2: Decrypt with KMS
        decrypted = decrypt_with_kms(content)

        # Step 3: Write to instance via SSH
        write_cert_and_reload(tenant, cert_name, decrypted)

        return "ok", 200
    except Exception as e:
        logger.error(f"Failed to process {object_name}: {e}")
        return "error", 500


def download_from_gcs(bucket_name, object_name):
    """Download certificate from GCS"""
    from google.cloud import storage
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_name)
    return blob.download_as_bytes()


def decrypt_with_kms(ciphertext):
    """Decrypt using KMS"""
    from google.cloud import kms
    client = kms.KeyManagementServiceClient()
    response = client.decrypt(name=KMS_KEY, ciphertext=ciphertext)
    return response.plaintext


def write_cert_and_reload(tenant, cert_name, content):
    """SSH to instance, write cert, and reload nginx"""
    import paramiko

    cert_path = f"/etc/nginx/certs/{tenant}/{cert_name}"
    instance_ip = get_instance_ip(NGINX_INSTANCE)

    # SSH to instance
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(
        hostname=instance_ip,
        username="admin",
        key_filename=SSH_KEY_PATH
    )

    # Write certificate
    sftp = ssh.open_sftp()
    with sftp.file(cert_path, "w") as f:
        f.write(content.decode("utf-8"))
        # Set permissions
        if cert_name.endswith(".key"):
            sftp.chmod(cert_path, 0o600)
        else:
            sftp.chmod(cert_path, 0o644)
    sftp.close()

    # Reload nginx
    stdin, stdout, stderr = ssh.exec_command("sudo nginx -s reload")
    exit_code = stdout.channel.recv_exit_status()

    if exit_code != 0:
        raise Exception(f"nginx reload failed: {stderr.read().decode()}")

    ssh.close()
    logger.info(f"Certificate updated: {tenant}/{cert_name}")


def get_instance_ip(instance_name):
    """Get instance external IP"""
    from google.cloud import compute_v1
    client = compute_v1.InstancesClient()
    # Get instance details and extract IP
    # This is simplified - in production use proper project/zone
    return "YOUR_INSTANCE_IP"  # Configure appropriately


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
```

### GCS 通知配置

```bash
# 创建 Pub/Sub Topic
gcloud pubsub topics create cert-events

# 创建通知
gsutil notification create \
  -t cert-events \
  -f json \
  -e OBJECT_FINALIZE \
  gs://your-certificates-bucket

# 创建订阅（Cloud Function/Run 作为 subscriber）
gcloud pubsub subscriptions create cert-events-sub \
  --topic cert-events \
  --push-endpoint=https://your-cloud-run-url.run.app/
```

### 优缺点

| 优点 | 缺点 |
|------|------|
| ✅ 事件驱动，延迟低（秒级） | ❌ 架构复杂，涉及多个 GCP 服务 |
| ✅ Cloud Run 自动扩缩 | ❌ 需要处理幂等性（消息可能重复） |
| ✅ 无需在实例上运行 Daemon | ❌ SSH 到实例需要权限和安全考虑 |
| ✅ 可观测性强（Cloud Logging + Monitoring） | ❌ 成本（Cloud Run + Pub/Sub + Cloud Function） |

---

## 方案三：GCP Secret Manager 替代 GCS

### 核心思路

将证书存储在 **GCP Secret Manager** 而不是 GCS，利用 Secret Manager 的版本管理和自动轮换能力。

```
┌─────────────────────────────────────────────────────────────┐
│                 GCP Secret Manager                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  secret: nginx-cert-tenant-a                         │   │
│  │  └── versions:                                       │   │
│  │       ├── 1: (内容: cert+key PEM)                    │   │
│  │       └── 2: (内容: 更新后的证书)  ← 当前版本        │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                   │
│                          ▼                                   │
│              ┌──────────────────────┐                        │
│              │  Secret Sync Agent   │                        │
│              │  (实例上的 Daemon)    │                        │
│              │                      │                        │
│              │  1. Poll Secret Mgr  │                        │
│              │  2. Detect new ver   │                        │
│              │  3. Write to disk   │                        │
│              │  4. nginx -s reload  │                        │
│              └──────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

### Secret Manager 的优势

| 特性 | GCS (KMS) | Secret Manager |
|------|-----------|---------------|
| **版本管理** | ❌ 需手动管理 | ✅ 原生版本支持 |
| **轮换** | 需自己实现 | ✅ 支持自动轮换 |
| **IAM 集成** | ✅ | ✅ 更细粒度 |
| **审计日志** | ✅ | ✅ |
| **访问控制** | Bucket ACL + KMS | Secret级别 IAM |
| **成本** | GCS + KMS | Secret Manager 存储成本 |

### Secret Manager + Daemon 实现

```python
#!/usr/bin/env python3
"""
Nginx Certificate Sync from Secret Manager
"""

import time
import logging
from pathlib import Path
from google.cloud import secretmanager

NGINX_CERT_DIR = Path("/etc/nginx/certs")
POLL_INTERVAL = 60  # Secret Manager 支持通知，但轮询更简单

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SecretManagerCertSync:
    def __init__(self, project_id: str):
        self.project_id = project_id
        self.client = secretmanager.SecretManagerServiceClient()
        self.version_hashes = {}

    def list_secrets(self):
        """List all nginx-cert-* secrets"""
        secrets = {}
        for secret in self.client.list_secrets(request={"parent": f"projects/{self.project_id}"}):
            if secret.name.startswith(f"projects/{self.project_id}/secrets/nginx-cert-"):
                tenant = secret.name.split("nginx-cert-")[1]
                secrets[tenant] = secret.name
        return secrets

    def get_latest_version(self, secret_name: str) -> tuple:
        """Get latest version content and hash"""
        # Get latest version name
        response = self.client.list_secret_versions(request={"parent": secret_name})
        latest_version = None
        for version in response:
            if version.state == secretmanager.SecretVersion.State.ENABLED:
                latest_version = version.name
                break

        if not latest_version:
            return None, None

        # Access the version
        response = self.client.access_secret_version(request={"name": latest_version})
        content = response.payload.data
        content_hash = hashlib.sha256(content).hexdigest()
        return content, content_hash

    def sync_certificates(self):
        """Sync certificates from Secret Manager"""
        secrets = self.list_secrets()
        logger.info(f"Found secrets: {list(secrets.keys())}")

        for tenant, secret_name in secrets.items():
            content, content_hash = self.get_latest_version(secret_name)
            if not content:
                continue

            # Check if changed
            if self.version_hashes.get(tenant) == content_hash:
                continue

            logger.info(f"Certificate updated for tenant: {tenant}")

            # Parse PEM content (expect cert and key together)
            # or split if stored separately
            cert, key = self.parse_pem(content)

            self.write_cert(tenant, "cert.pem", cert.encode())
            self.write_cert(tenant, "key.pem", key.encode())

            self.version_hashes[tenant] = content_hash

        if self.version_hashes:
            self.reload_nginx()

    def parse_pem(self, content: bytes) -> tuple:
        """Parse combined PEM into cert and key"""
        # Assume cert and key are stored together, separated by marker
        pem_str = content.decode("utf-8")
        parts = pem_str.split("-----BEGIN PRIVATE KEY-----")
        if len(parts) == 2:
            cert = parts[0]
            key = "-----BEGIN PRIVATE KEY-----" + parts[1]
        else:
            # Try RSA key marker
            parts = pem_str.split("-----BEGIN RSA PRIVATE KEY-----")
            if len(parts) == 2:
                cert = parts[0]
                key = "-----BEGIN RSA PRIVATE KEY-----" + parts[1]
            else:
                raise ValueError("Unknown PEM format")

        return cert, key

    def write_cert(self, tenant: str, filename: str, content: bytes):
        """Write certificate to disk"""
        tenant_dir = NGINX_CERT_DIR / tenant
        tenant_dir.mkdir(exist_ok=True)
        path = tenant_dir / filename

        with open(path, "wb") as f:
            f.write(content)
            os.fsync(f)

        if filename.endswith(".key"):
            os.chmod(path, 0o600)
        else:
            os.chmod(path, 0o644)

        logger.info(f"Written {path}")

    def reload_nginx(self):
        """Reload nginx"""
        subprocess.run(["nginx", "-s", "reload"], check=True)
        logger.info("Nginx reloaded")

    def run(self):
        """Main loop"""
        logger.info("Starting Secret Manager Cert Sync Daemon")
        while True:
            try:
                self.sync_certificates()
            except Exception as e:
                logger.error(f"Error: {e}")
            time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    import os
    import hashlib

    project_id = os.environ.get("GCP_PROJECT")
    if not project_id:
        raise ValueError("GCP_PROJECT not set")

    SecretManagerCertSync(project_id).run()
```

### Secret Manager 权限配置

```bash
# 创建 Service Account
gcloud iam service-accounts create nginx-cert-sync \
  --display-name="Nginx Certificate Sync"

# 授予 Secret Manager 读取权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:nginx-cert-sync@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"

# 将 Service Account 绑定到实例
gcloud compute instances add-iam-policy-binding $INSTANCE_NAME \
  --zone=$ZONE \
  --member="serviceAccount:nginx-cert-sync@$PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser"
```

### 优缺点

| 优点 | 缺点 |
|------|------|
| ✅ 原生版本管理 | ❌ 需要迁移现有证书存储 |
| ✅ 支持自动轮换 | ❌ Secret Manager 有容量限制（单 secret 65KB） |
| ✅ 更简单的 API | ❌ 如果证书很多，轮询有延迟 |
| ✅ 与 GCP IAM 深度集成 | |

---

## 方案四：GCS FUSE 直通（绕过 KMS 预解密）

### 核心思路

使用 **GCS FUSE** 直接挂载 bucket，实例启动时配置 **KMS key 的使用权限**，让 GCS 在读取时自动解密。

```
传统方式：
  GCS (KMS加密) → 下载 → 应用自行KMS解密 → 使用

GCS FUSE + CMEK：
  GCS (KMS加密) → GCS FUSE 挂载 → 自动解密 → 直接读取解密后内容
```

### 配置步骤

```bash
# 1. 创建使用 CMEK 的 GCS Bucket
gcloud storage buckets create gs://your-cert-bucket \
  --location=US \
  --default-kms-key=projects/your-project/locations/global/keyRings/your-ring/cryptoKeys/your-key

# 2. 确保实例有 KMS 解密权限
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SERVICE_ACCOUNT" \
  --role="roles/cloudkms.cryptoKeyDecrypter"

# 3. 安装 GCS FUSE
sudo snap install google-cloud-sdk --classic
# 或者
curl https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v1.0.0/gcsfuse_1.0.0_amd64.deb -O
sudo dpkg --install gcsfuse_1.0.0_amd64.deb

# 4. 挂载
google-cloud-sdk/gcsfuse/gcsfuse \
  --implicit-dirs \
  --enable-type-header \
  --enable-parallel-downloads \
  your-cert-bucket /gcs/certs

# 5. 设置自动挂载（/etc/fstab）
your-cert-bucket  /gcs/certs  gcsfuse  _netdev,implicit_dirs,enable-parallel-downloads  0  0
```

### Nginx 配置

```nginx
# /etc/nginx/conf.d/tenant-template.conf
# 每个租户一个 server block

server {
    listen 443 ssl;
    server_name tenant-a.example.com;

    ssl_certificate /gcs/certs/tenants/tenant-a/cert.pem;
    ssl_certificate_key /gcs/certs/tenants/tenant-a/key.pem;

    # SSL 配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://backend;
    }
}
```

### 证书更新流程（简化版）

```
新租户上线：
  1. 上传证书到 GCS: gs://cert-bucket/tenants/tenant-a/cert.pem
  2. GCS FUSE 立即可见（无延迟）
  3. 更新 nginx.conf 添加新 server block
  4. nginx -s reload
  5. 完成

更新证书：
  1. 上传新证书到 GCS（覆盖原文件）
  2. nginx -s reload（证书自动从 GCS FUSE 读取解密后的内容）
```

### 重要限制

```
⚠️  GCS FUSE 限制：
    - 不支持硬链接
    - 不支持某些 mmap 场景
    - 元数据操作（rename）可能不是原子的
    - 对于频繁读写的场景性能不如本地磁盘

⚠️  KMS + GCS FUSE 限制：
    - GCS FUSE 在读取时解密，但必须实例有权限
    - 如果 KMS key 改变，需要重新挂载

⚠️  Nginx reload 时的行为：
    - Nginx 在 reload 时读取证书文件
    - 第一次读取后缓存到内存
    - 如果证书文件在 reload 前被删除，可能失败
```

### 优缺点

| 优点 | 缺点 |
|------|------|
| ✅ 架构最简单 | ❌ GCS FUSE 性能和稳定性争议 |
| ✅ 无需 Daemon | ❌ 证书更新依赖 GCS 可见性（可能有几秒延迟） |
| ✅ KMS 自动解密，无需代码处理 | ❌ 不支持证书文件的原子替换 |
| ✅ 新增租户只需更新 nginx.conf | ❌ GCS FUSE 在大文件/频繁访问时可能有问题 |

---

## 方案对比

| 维度 | Daemon + GCS | Pub/Sub + Cloud Run | Secret Manager | GCS FUSE + CMEK |
|------|-------------|---------------------|----------------|-----------------|
| **复杂度** | 中 | 高 | 中 | 低 |
| **延迟** | 30s 轮询 | 秒级事件 | 60s 轮询 | 秒级（GCS） |
| **维护成本** | 中（Daemon） | 高（多组件） | 低 | 低 |
| **可靠性** | 单点 | 高（云服务） | 高（云服务） | 依赖 FUSE |
| **成本** | 实例资源 | Cloud Run + Pub/Sub | Secret Manager | GCS FUSE |
| **KMS 集成** | 原生 | 原生 | 不需要 | 原生（自动） |
| **适合规模** | 10-50 租户 | 任意规模 | 10-100 租户 | 5-20 租户 |

### 推荐选择

```
租户数量少（<10），追求简单：    → GCS FUSE + CMEK
租户数量中等（10-50），需要可控：→ Daemon + GCS/KMS
租户数量大，需要事件驱动：       → Pub/Sub + Cloud Run
使用 Secret Manager 已有积累：  → Secret Manager + Daemon
不想维护任何额外代码：          → GCS FUSE（接受其限制）
```

---

## 实现细节：nginx.conf 多租户配置

### 动态包含配置

```nginx
# /etc/nginx/nginx.conf
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    # 动态加载租户配置
    include /etc/nginx/conf.d/tenants/*.conf;

    # 默认 server（处理无 SNI 的连接）
    server {
        listen 443 ssl default_server;
        ssl_certificate /etc/nginx/certs/default.crt;
        ssl_certificate_key /etc/nginx/certs/default.key;
        return 444;
    }
}

stream {
    # TCP/UDP 代理（如需要）
    include /etc/nginx/stream.d/tenants/*.conf;
}
```

### 租户配置文件

```nginx
# /etc/nginx/conf.d/tenants/tenant-a.example.com.conf

server {
    listen 443 ssl;
    server_name tenant-a.example.com;

    # 证书路径 - 动态更新
    ssl_certificate /etc/nginx/certs/tenant-a/cert.pem;
    ssl_certificate_key /etc/nginx/certs/tenant-a/key.pem;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # 安全头
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    location / {
        proxy_pass http://tenant-a-backend:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    access_log /var/log/nginx/tenant-a.access.log;
    error_log /var/log/nginx/tenant-a.error.log;
}
```

### 自动生成配置（新增租户时）

```python
#!/usr/bin/env python3
"""
Generate Nginx config for new tenant
"""

from pathlib import Path
import subprocess

NGINX_TENANT_CONF_DIR = Path("/etc/nginx/conf.d/tenants")
TENANT_CERT_DIR = Path("/etc/nginx/certs")


def generate_nginx_config(tenant: str, domain: str):
    """Generate nginx server block for tenant"""
    config = f"""
server {{
    listen 443 ssl;
    server_name {domain};

    ssl_certificate {TENANT_CERT_DIR / tenant / "cert.pem"};
    ssl_certificate_key {TENANT_CERT_DIR / tenant / "key.pem"};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {{
        proxy_pass http://backend-{tenant}:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }}
}}
"""

    conf_path = NGINX_TENANT_CONF_DIR / f"{tenant}.conf"
    with open(conf_path, "w") as f:
        f.write(config)

    # Validate config
    result = subprocess.run(["nginx", "-t"], capture_output=True)
    if result.returncode != 0:
        conf_path.unlink()  # Remove invalid config
        raise ValueError(f"Invalid nginx config: {result.stderr.decode()}")

    return conf_path
```

---

## 安全考虑

### 权限最小化

```bash
# Nginx 证书目录权限
chown -R nginx:nginx /etc/nginx/certs
chmod 755 /etc/nginx/certs
chmod 755 /etc/nginx/certs/tenant-*  # 目录
chmod 644 /etc/nginx/certs/tenant-*/*.crt  # 证书
chmod 600 /etc/nginx/certs/tenant-*/*.key  # 私钥

# KMS 权限（Service Account）
# 只允许解密，不允许生成新密钥
gcloud kms keys add-iam-policy-binding $KEY \
  --member="serviceAccount:$SA" \
  --role="roles/cloudkms.cryptoKeyDecrypter" \
  --location=global

# GCS 权限
# 只允许读取，不允许列出或写入
gsutil iam ch serviceAccount:$SA:objectViewer gs://your-cert-bucket
```

### 审计日志

```yaml
# Cloud Logging 过滤
# 查看所有 KMS 解密操作
resource.type="kms_project"
protoPayload.serviceName="cloudkms.googleapis.com"
protoPayload.methodName="Decrypt"

# 查看证书文件访问
resource.type="gce_instance"
logName="syslog"
jsonPayload.program="nginx"
```

---

## 监控与告警

### 证书过期监控

```python
#!/usr/bin/env python3
"""Monitor certificate expiry"""

import ssl
import socket
from datetime import datetime, timedelta
from google.cloud import monitoring_v3

def check_cert_expiry(hostname: str, port: int = 443) -> dict:
    """Check SSL certificate expiry"""
    context = ssl.create_default_context()
    with socket.create_connection((hostname, port), timeout=10) as sock:
        with context.wrap_socket(sock, server_hostname=hostname) as ssock:
            cert = ssock.getpeercert()
            # cert 是一个 dict，包含 not_after 字段
            expiry = datetime.strptime(cert["notAfter"], "%b %d %H:%M:%S %Y %Z")
            days_until_expiry = (expiry - datetime.utcnow()).days
            return {"hostname": hostname, "days_left": days_until_expiry, "expiry": expiry}

def alert_expiring_certs(project_id: str, threshold_days: int = 30):
    """Alert on certificates expiring soon"""
    client = monitoring_v3.AlertPolicyServiceClient()

    # This would create an alerting policy
    # In practice, use Cloud Monitoring UI or Terraform
    pass
```

### Daemon 健康监控

```bash
# systemd watchdog 配置
[Service]
WatchdogSec=60
Restart=on-failure

# 定期检查 nginx 配置
*/5 * * * * /usr/sbin/nginx -t && /usr/bin/systemctl is-active nginx
```

---

## 迁移指南

### 从 Rolling Update 迁移

```
Phase 1: 并行运行
  1. 部署 Cert-Sync Daemon 到现有实例
  2. 验证 Daemon 能正常同步证书
  3. 验证 nginx -s reload 能生效

Phase 2: 切换流量
  1. 修改负载均衡器，将新实例加入池
  2. 旧实例继续 Rolling Update
  3. 新实例使用热更新

Phase 3: 清理
  1. 移除旧实例
  2. 移除 Rolling Update 触发逻辑
  3. 证书上传后自动生效
```

---

## 快速参考

### 命令速查

```bash
# 手动触发证书同步（Daemon 模式下）
python3 /opt/nginx-cert-sync/sync.py

# 手动 reload nginx
nginx -s reload

# 检查 nginx 配置
nginx -t

# 查看证书信息
openssl s_client -connect tenant-a.example.com:443 -showcerts

# 检查证书过期
echo | openssl s_client -connect tenant-a.example.com:443 2>/dev/null | openssl x509 -noout -dates

# GCS FUSE 挂载
gcsfuse --implicit-dirs bucket /gcs/certs

# KMS 解密（命令行）
gcloud kms decrypt \
  --key=$KEY \
  --plaintext-file=cert.pem \
  --ciphertext-file=cert.pem.encrypted
```

### 文件路径规范

```
/etc/nginx/
├── nginx.conf                 # 主配置
├── conf.d/
│   └── tenants/              # 租户配置
│       ├── tenant-a.example.com.conf
│       └── tenant-b.example.com.conf
└── certs/                    # 证书存储
    ├── default.crt
    ├── default.key
    └── tenant-a/
        ├── cert.pem
        └── key.pem

/opt/nginx-cert-sync/
├── sync.py                    # 主程序
└── service-account.json       # GCP SA 密钥

/gcs/
└── certs/                    # GCS FUSE 挂载点
    └── tenants/
        ├── tenant-a/
        │   ├── cert.pem
        │   └── key.pem
        └── tenant-b/
            ├── cert.pem
            └── key.pem
```

---

*Document version: 1.0 — Last updated: 2026-05-19*
