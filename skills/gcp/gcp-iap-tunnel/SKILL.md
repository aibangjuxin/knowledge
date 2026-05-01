---
name: gcp-iap-tunnel
description: GCP IAP TCP Tunneling - gcloud compute ssh --tunnel-through-iap 详解。用于解释 IAP 隧道原理、NumPy 安装位置、以及常见 Warning 修复。
---

# GCP IAP TCP Tunneling

## Core Concepts

### What is --tunnel-through-iap?

`gcloud compute ssh --tunnel-through-iap` 通过 GCP Identity-Aware Proxy 建立 SSH 隧道，替代传统的公网 SSH 访问。

**核心优势**：
- 零公网暴露：实例不需要 External IP
- IAM 身份认证：必须使用 Google 账号 + 正确的 IAM 角色
- 审计日志：所有连接记录在 Cloud Audit Logs

### Architecture

```
LOCAL (Mac Mini)
  │
  │ localhost:local-port
  ▼
GCP Identity-Aware Proxy (IAM 验证)
  │
  │ Google 内部网络
  ▼
Remote VM (私有 IP, 无需公网 IP)
```

---

## Critical: NumPy Installation Location

**WARNING**: Common misconception! NumPy must be installed on the **LOCAL** machine, NOT the remote VM.

GCP official docs:
> *"To increase the IAP TCP upload bandwidth, consider installing NumPy in the same machine where gcloud CLI is installed."*

Source: https://cloud.google.com/iap/docs/using-tcp-forwarding#increasing_the_tcp_upload_bandwidth

```bash
# Install on LOCAL machine only
pip3 install numpy

# Verify
python3 -c "import numpy; print(numpy.__version__)"
```

---

## Common Warnings & Fixes

### Warning 1: NumPy Performance

```
WARNING: To increase the performance of the tunnel, consider installing NumPy.
```

**Fix**: `pip3 install numpy` on LOCAL machine (not remote).

---

### Warning 2: setlocale LC_ALL

```
bash: warning: setlocale: LC_ALL: cannot change locale (zh_CN.UTF-8)
```

**Fix**: In `~/.ssh/config`:

```
Host *
  SendEnv none
```

---

## Quick Reference

```bash
# Standard IAP SSH command
gcloud compute ssh <instance-name> \
  --zone=<zone> \
  --tunnel-through-iap \
  --command="<remote command>"

# With specific local port
gcloud compute ssh <instance> \
  --zone=<zone> \
  --tunnel-through-iap \
  --local-host-port=localhost:2222
```

---

## Related Skills

- `gcp`: General GCP/Linux Infrastructure
- `architectrue`: GKE Platform Architecture
