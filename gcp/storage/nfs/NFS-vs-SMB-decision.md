# SMB vs NFS 决策表(精简版)

> **本节是"业务方该选 SMB 还是 NFS"的快速决策表**
>
> **架构师 lane 边界**:本文档只做对比 + 决策框架,**不替业务方拍板**。业务方 / PM 看完后选。

---

## 0. 🚨 强制加密声明(必读)

> **NFS 全系列(NFSv3 / v4.0 / v4.1 / v4.2)默认明文传输,直接违反企业安全规范。**
>
> **绝不允许生产环境用明文 NFS**。业务方**必须**回答下面 4 个问题,才能选 NFS:

| # | 强制问题 | 必答 |
|---|---|---|
| **E1** | 选哪种加密方案? | ☐ NFS-over-TLS (`xprtsec=tls`, Linux 6.5+) / ☐ WireGuard 隧道 / ☐ IPsec / ☐ **N/A,选 SMB 或 GCS** |
| **E2** | 加密层覆盖范围? | ☐ 仅 Pod → NFS 链路 / ☐ Pod → NFS + NFS server 内部 |
| **E3** | NFS server 是否支持所选方案? | ☐ 已验证(server OS + 版本) |
| **E4** | 走公网 / VPN 链路? | ☐ 否 / ☐ 是(必须配加密)|

**任一项未答 → 选 SMB 或 GCS,不要选 NFS**。详见 [NFS-deployment-guide.md §0](./NFS-deployment-guide.md) + [STORAGE-3-PROTOCOLS-COMPARISON.md §0.5](../STORAGE-3-PROTOCOLS-COMPARISON.md)。

---

## 1. 一句话决策

> **看数据源操作系统**:
> - 数据源是 **Windows / NAS 设备** → 选 SMB(ADR-009),**默认加密,无需额外配置**
> - 数据源是 **Linux / Unix NFS server** → 选 NFS(本目录),**⚠ 必须配加密层(NFS-over-TLS / WireGuard)**
> - **不确定** → 问 IT 数据源端是什么系统,IT 答复后选

---

## 2. 详细对比表

| 维度 | SMB 445(ADR-009) | NFS 2049(NFS 指南) | 业务方选择 |
|---|---|---|---|
| **协议来源** | Windows 主导 | Linux / Unix 主导 | 看数据源 OS |
| **数据源系统** | Windows File Server / NAS 设备 | Linux NFS server | 看 IT |
| **典型延迟** | 5-30 ms(over VPN)| **3-15 ms**(内网,无加密)| NFS 略快 |
| **典型吞吐** | 受 SMB 协议开销限制 | 较高(Linux 优化)| NFS 略高 |
| **大文件读写** | 良好 | **优秀** | 视频 / 模型 / 备份 → NFS |
| **小文件密集读** | 一般 | 一般 | 都不强,加缓存 |
| **鉴权** | user/pass + signing | **无**(靠 IP + UID)| SMB 更强(显式鉴权)|
| **加密(协议层)** | SMB 3.0+ AES-CCM/GCM(默认开)| **NFSv3 / v4.0 / v4.1 / v4.2 默认明文;NFS-over-TLS (kTLS, Linux 6.5+) 可配;WireGuard 兜底** | SMB 略强,但 NFS 配 kTLS 后接近 |
| **权限粒度** | 共享 ACL(user 级)| UID/GID(文件级)| 看业务方需求 |
| **容器支持** | smb.csi.k8s.io(GA)| **nfs.csi.k8s.io(GA)** | 都成熟 |
| **K8s Secret 需求** | **需要** SMB user/pass | **不需要** | NFS 更简单 |
| **Pod spec 复杂度** | 较高(mountOptions 多)| **较简单** | NFS 更简单 |
| **跨平台 client** | Windows / Linux / macOS | Linux / macOS / Windows(需装)| SMB 更通用 |
| **文件锁** | opportunistic | mandatory(NFSv4) | NFS 略强 |
| **运维工具** | Windows 工具链 | Linux 工具链 | 看团队 |

---

## 3. 何时用 SMB / 何时用 NFS(决策树)

```
┌────────────────────────────────────────┐
│  业务方要"挂网络存储到 GKE Pod"        │
└─────────────┬──────────────────────────┘
              │
              ▼
┌────────────────────────────────────────┐
│  数据源是什么系统?                    │
│  (问 IT)                              │
└──────┬──────────────┬──────────────────┘
       │              │
   Windows/Linux    Linux/Unix
   NAS设备          NFS server
       │              │
       ▼              ▼
   SMB 445         NFS 2049
   (ADR-009)      (本目录)
       │              │
       └──────┬───────┘
              │
              ▼
┌────────────────────────────────────────┐
│  Q4 高并发读?                         │
│  (>10 client 同读)?                  │
└──────┬──────────────┬──────────────────┘
      YES             NO
       │              │
       ▼              ▼
   NFS 优          两者都行
   (NFS 并发       (看 IT 习惯)
    强)            │
       │              │
       └──────┬───────┘
              │
              ▼
┌────────────────────────────────────────┐
│  Q5 文件大小?                        │
│  大文件(>100MB)?                    │
└──────┬──────────────┬──────────────────┘
      YES             NO
       │              │
       ▼              ▼
   NFS 优          两者都行
   (大文件         │
    强)            │
       │              │
       └──────┬───────┘
              │
              ▼
┌────────────────────────────────────────┐
│  Q6 需要显式鉴权                      │
│  (user/pass)?                       │
└──────┬──────────────┬──────────────────┘
      YES             NO
       │              │
       ▼              ▼
   SMB 优          选 IP 白名单
   (有 user/pass)  (NFS 默认)
              │
              ▼
┌────────────────────────────────────────┐
│  Q7 需要 Pod spec 简单?              │
│  (无 Secret mount)?                 │
└──────┬──────────────┬──────────────────┘
      YES             NO
       │              │
       ▼              ▼
   NFS 优          两者都行
   (无 Secret)     │
              │
              ▼
        最终选择
```

---

## 4. 业务方选型 checklist(决策前)

| 问题 | 答 | 影响 |
|---|---|---|
| 数据源是 Windows / NAS 设备? | ☐ 是 → SMB / ☐ 否 | 决定协议 |
| 数据源是 Linux NFS server? | ☐ 是 → NFS / ☐ 否 | 决定协议 |
| 多个 Pod 同时读? | ☐ 是 → NFS 优 / ☐ 否 | 决定性能优先级 |
| 单文件 > 100MB? | ☐ 是 → NFS 优 / ☐ 否 | 决定性能优先级 |
| 需要 user/pass 鉴权? | ☐ 是 → SMB / ☐ 否 | 决定协议 |
| 团队熟悉 Linux mount 选项? | ☐ 是 → NFS 友好 / ☐ 否 | 决定协议 |
| 公司合规接受明文传输? | ☐ 否 → SMB 加密 / ☐ 是 | 决定协议 |
| 数据可以迁到 GCP Filestore? | ☐ 是 → 替代方案 B / ☐ 否 | 走 ADR-009 决策树 |

**答完上面 8 题,选哪个协议基本就清楚了**。

---

## 5. 关键差异对业务方的影响

### 5.1 NFS 比 SMB 简单在哪

- ✅ **不需 Secret**(NFS 无 user/pass)
- ✅ **Pod spec 简洁**(mountOptions 少)
- ✅ **Linux 内核原生支持**(不用装 cifs-utils)
- ✅ **mount 性能略高**(Linux 优化)

### 5.2 NFS 比 SMB 弱在哪

- ❌ **无原生鉴权**(NFS 靠 IP 白名单,**SMB 有 user/pass**)
- ❌ **NFSv3 明文**(NFSv4.1+ 可加密,但默认配置常是 v3)
- ❌ **跨平台 client 弱**(Windows 需装 NFS client)

### 5.3 业务方合规视角(沿用 ADR-009 §6.3 4 红线)

| 红线 | SMB 影响 | NFS 影响 |
|---|---|---|
| R1 不持久化到 GCP | 同 | 同 |
| R2 不写 log 暴露 | 同 | 同 |
| R3 不主动观察 | 跨 platform 复杂 | 相对简单(NFS 端可审计) |
| R4 Pod lifecycle 解耦 | 同 | 同 |

**关键**:**NFS 不需要 Secret = 少一个凭据泄漏风险点**(vs SMB 必须管理 Secret)。

---

## 6. 业务方选型速查表(给业务方看)

> **🚨 业务方选 NFS 时,必须确认 §0 的 4 个加密问题答完。任何一项未答 → 选 SMB 或 GCS。**

| 业务场景 | 推荐 | 理由 |
|---|---|---|
| 公司有 Windows File Server | **SMB** | 数据源就是 SMB 共享,默认加密 |
| 公司有 Linux NFS server(老 ERP / 业务系统)| **NFS + 必配加密** | 数据源是 NFS,但 **NFS 默认明文不合规** → 配 NFS-over-TLS 或 WireGuard |
| 公司有 NAS 设备(群晖 / QNAP 等) | **看设备支持** + **必配加密** | 多数两种都支持,问设备管理员;**NAS 走公网/不合规 = 暂停** |
| 公司用 GCP Filestore | **NFS + 加密(走 K8s 抽象)** | Filestore 走 NFS 协议,Linux 6.5+ 自带 kTLS |
| AI 训练 / 大模型 checkpoint | **NFS + 加密 或 GCS** | 大文件 + 高并发读 |
| Web 应用静态资源(图片 / CSS) | **GCS 优**(S3-compatible)| CDN + 全球缓存,默认加密 |
| 日志文件存储 | **GCS 更合适** | 不是文件存储场景 |
| 数据库备份 | **GCS / 冷存储** | 不是文件存储场景 |

---

## 7. 不要做的事

| 做法 | 为什么 |
|---|---|
| 同时挂 SMB 和 NFS 到同一 Pod 同一 mount 路径 | 协议冲突,Mount 失败 |
| 业务方自行在 IT 申请 NFS server | 这是 IT 决策,不是业务方能决定的 |
| 改 NFS server 的 `/etc/exports` 让所有 GKE Pod 都能 mount | 安全风险,必须走平台团队配置 |

---

> **作者声明**:本文档只做对比 + 决策框架,**不替业务方拍板**。业务方选哪个协议后,实际部署由 infra-gcp 走 SA 执行(详见 [NFS-deployment-guide.md](./NFS-deployment-guide.md))。