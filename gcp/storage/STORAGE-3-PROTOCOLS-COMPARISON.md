# GKE 存储挂载 3 协议对照总表(SMB / NFS / Bucket)

> **本目录地图** —— 一页纸对比 GKE Pod 挂载存储的 3 种协议,作为业务方 / 架构师做最终架构决策的入口。
>
> **架构师 lane 边界**:本文档**只做对比 + 决策框架**,**不替业务方拍板**。每个协议的详细实施请跳到对应子目录。
>
> **状态**:Provisional(随场景演进更新)

---

## 0. 一页纸决策(30 秒)

```
┌──────────────────────────────────────────────────────────────┐
│  问业务方 1 个问题:你的数据源在哪个系统?                     │
│                                                                │
│  Windows File Server / NAS 设备 ──────►  SMB TCP 445         │
│                                         → ADR-009 + gke/      │
│                                                                │
│  Linux / Unix NFS server ────────────►  NFS TCP 2049        │
│                                         → nfs/ 目录           │
│                                         ⚠ 必配加密(见下)    │
│                                                                │
│  GCP Cloud Storage(跨 project) ──────►  HTTPS / gRPC         │
│                                         → ADR-011 + gke/      │
│                                                                │
│  不确定?问 IT 数据源端是什么系统,IT 答复后选                 │
└──────────────────────────────────────────────────────────────┘
```

---

## 0.5 🚨 强制加密声明(NFS 场景必读)

> **🚨 NFS 全系列(NFSv3 / v4.0 / v4.1 / v4.2)默认明文传输,直接违反企业安全规范。**
>
> **绝不允许生产环境用明文 NFS**。任何"先用明文跑通,后期补加密"的方案 **不允许** —— **先配加密,再 apply**。
>
> **业务方 + infra-gcp 必填的安全门控表**:
>
> | # | 强制问题 | 必答 |
> |---|---|---|
> | G-Enc-1 | 你选哪种加密方案? | ☐ NFS-over-TLS (`xprtsec=tls`, Linux 6.5+) / ☐ WireGuard 隧道 / ☐ IPsec |
> | G-Enc-2 | 加密方案覆盖范围? | ☐ 仅 Pod → NFS / ☐ Pod → NFS + NFS server 内部 |
> | G-Enc-3 | NFS server 是否支持所选方案? | ☐ 已验证 |
> | G-Enc-4 | 走公网 / VPN 链路? | ☐ 否 / ☐ 是(必须配加密)|
>
> **任一项未答或不勾选 → 暂停,先解决加密层**。详见 [`nfs/NFS-deployment-guide.md`](nfs/NFS-deployment-guide.md) §0 / §7.5。

---

## 1. 3 协议核心对比(15 维度)

| # | 维度 | SMB 445(ADR-009)| NFS 2049(NFS/) | Cloud Storage(ADR-011)|
|---|---|---|---|---|
| 1 | **协议** | SMB / CIFS | NFSv3 / NFSv4.1+ | HTTPS / gRPC over GCP 内网 |
| 2 | **端口** | TCP 445 | TCP/UDP 2049 | 443(HTTPS)|
| 3 | **数据源系统** | Windows 主导 | Linux / Unix 主导 | GCP 托管(任何 client)|
| 4 | **跨平台 client** | Windows / Linux / macOS 原生 | Linux / macOS 原生,Windows 需装 | **任何**(SDK 全平台)|
| 5 | **CSI driver** | `smb.csi.k8s.io`(GA) | `nfs.csi.k8s.io`(GA) | **不用 CSI**(API 调用)|
| 6 | **鉴权** | user/pass + signing | **无**(IP + UID)| **KSA → WIF → 短期 token** |
| 7 | **协议层加密** | SMB 3.0+ AES-CCM/GCM(默认开)| **NFSv3 / v4.0 / v4.1 / v4.2 默认明文;NFS-over-TLS (kTLS, Linux 6.5+) 可配** | HTTPS 默认加密 |
| 8 | **K8s Secret 需求** | **需要** SMB user/pass | **不需要** | **不需要**(WIF 自动)|
| 9 | **挂载方式** | 文件系统 mount | 文件系统 mount | **API 调用**(`storage.Objects.Insert`)|
| 10 | **数据物理位置** | 公司内网 | 公司内网 / 任何 NFS server | **GCP 内,跨 project** |
| 11 | **多租户隔离** | NAS 端共享 ACL(弱)| UID/GID(中等)| **GCP IAM(强,完整覆盖)**|
| 12 | **审计** | GKE + NAS event log(**断链**)| 同 SMB | **GKE + GCS 同 GCP 体系(强)**|
| 13 | **典型延迟(内网)** | 5-30 ms(加密 VPN)| **3-15 ms**(明文内网)| 10-50 ms(跨 project IAM 验证)|
| 14 | **大文件 / 高并发** | 良好 | **优秀**(Linux 优化)| **优秀**(GCS 专门优化) |
| 15 | **Pod spec 复杂度** | 较高(mountOptions + Secret)| **较简单**(无 Secret)| 中(SA + WIF annotation)|

---

## 2. 业务场景 → 协议映射(给业务方看)

| 业务场景 | 推荐 | 理由 |
|---|---|---|
| 公司有 Windows File Server,业务方要访问 | **SMB** | 数据源就是 SMB 共享 |
| 公司有 Linux NFS server(老 ERP / 业务系统)| **NFS + 必配加密** | 数据源是 NFS,但 **NFS 默认明文不合规** → 配 NFS-over-TLS 或 WireGuard |
| 公司有 NAS 设备(群晖 / QNAP / Synology)| **看设备支持** + **必配加密** | 多数两种都支持,问设备管理员;**NAS 走公网/不合规 = 暂停** |
| AI 训练 / 大模型 checkpoint / 视频文件 | **NFS + 加密 或 GCS** | 大文件 + 高并发 |
| Web 应用静态资源(图片 / CSS / JS) | **GCS 优**(S3-compatible)| CDN + 全球缓存 |
| 公司有 Windows AD 域控(强鉴权) | **SMB** | AD 集成 + signing |
| 跨 region 跨 project 数据共享 | **GCS** | 原生跨 region,无 VPN |
| 公司合规要求强制加密(in transit)| **SMB 3.0+ 或 GCS(默认加密)**| NFSv3 / v4.1 默认明文,即使 WireGuard 也不符合"协议层加密"严要求 |
| 日志文件存储 | **GCS** | 不是文件存储场景 |
| 数据库备份 | **GCS / 冷存储** | 不是文件存储场景 |
| 临时文件 / 缓存 | **NFS + 加密 或 emptyDir** | 不用持久化 |
| 多 Pod 共享读写(数据竞争) | **❌ 三种协议都不推荐** | 应改用 DB / 队列 |

---

## 3. 4 红线适用矩阵(沿用 ADR-009 §6.3)

| 红线 | SMB(ADR-009)| NFS(本目录) | Bucket(ADR-011)|
|---|---|---|---|
| **R1 不持久化到 GCP** | ✅ 适用 | ✅ 适用 | ⚠ **必触发**(Bucket 写 = 档 1)|
| **R2 不写 log / metric 暴露** | ✅ 适用 | ✅ 适用 | ✅ 适用 |
| **R3 不主动观察** | ⚠ 跨 platform 断链 | ⚠ 同 SMB | ✅ Cloud Audit Logs 自动 |
| **R4 Pod lifecycle 解耦** | ✅ 适用 | ✅ 适用 | ✅ 适用(Object 独立)|

**关键**:**Bucket 场景的 R1 比 SMB/NFS 更敏感** —— 写 Bucket = 持久化到 GCP = 档 1 红线,业务方必须 PM 评估 + 走档 1 例外审批。

---

## 4. 4 协议选择决策树(精简)

```
                      ┌──────────────────────────────────┐
                      │ 业务方要"挂存储到 GKE Pod"     │
                      └──────────────┬───────────────────┘
                                     │
                                     ▼
                      ┌──────────────────────────────────┐
                      │  数据在哪个系统?               │
                      │  (问 IT)                       │
                      └──┬─────┬─────┬─────┬──────────┘
                         │     │     │     │
                  Windows│ Linux│     │ GCP │
                         │     │     │     │
                         ▼     ▼     │     │
                    ┌────┐ ┌────┐  │     │
                    │SMB │ │NFS │  │     │
                    │445 │ │2049│  │     │
                    └────┘ └────┘  │     │
                         │     │     │     │
                         └────┴─────┴─────┘
                              │
                              ▼
                ┌────────────────────────────────────┐
                │  Q:需要持久化到 GCP 内(跨 project)? │
                └────────┬─────────────────────┬────┘
                      YES │                NO │
                          ▼                ▼
                    ┌────────┐         (SMB / NFS 继续)
                    │ Bucket │
                    │(HTTPS)│
                    │(ADR-011)│
                    └────────┘
                          │
                          ▼
                ┌────────────────────────────────────┐
                │  PM + Manager 档 1 例外审批       │
                │  + POC 验证                       │
                └────────────────────────────────────┘
```

---

## 5. 4 协议技术参数速查

| 协议 | 端口 | CSI driver | K8s Secret | IAM/认证 | 加密(默认) |
|---|---|---|---|---|---|
| **SMB 445** | TCP 445 | `smb.csi.k8s.io` | 需要(user/pass)| NAS 端共享 ACL | SMB 3.0+ AES |
| **NFS 2049** | TCP/UDP 2049 | `nfs.csi.k8s.io` | 不需要 | IP 白名单 + UID(默认明文,**必配 NFS-over-TLS 或 WireGuard**)| NFSv3 **明文**,NFSv4.1+ 可加密 |
| **GCS HTTPS** | TCP 443 | **不用 CSI** | 不需要(WIF)| GCP IAM(KSA → GSA)| HTTPS + CMEK |

---

## 6. 业务方选型 8 问 checklist(给业务方 review 用)

回答下面 8 题,选哪个协议基本就清楚了:

| # | 问题 | 答 | 指向 |
|---|---|---|---|
| 1 | 数据源是 Windows / NAS 设备? | ☐ 是 → SMB / ☐ 否 | 决定协议 |
| 2 | 数据源是 Linux NFS server? | ☐ 是 → NFS / ☐ 否 | 决定协议 |
| 3 | 想把数据放到 GCP Bucket? | ☐ 是 → Bucket / ☐ 否 | 决定协议 |
| 4 | 多个 Pod 同时读? | ☐ 是 → NFS/Bucket 优 / ☐ 否 | 决定性能优先级 |
| 5 | 单文件 > 100MB? | ☐ 是 → NFS/Bucket 优 / ☐ 否 | 决定性能优先级 |
| 6 | 需要 user/pass 鉴权? | ☐ 是 → SMB / ☐ 否 | 决定协议 |
| 7 | 公司合规要求强制加密? | ☐ 是 → SMB 3.0+ 或 Bucket / ☐ 否 → **NFS 仍需 WireGuard / NFS-over-TLS(默认明文不合规)** | 决定协议 |
| 8 | 数据可以迁到 GCP? | ☐ 是 → Bucket 优 / ☐ 否 | 决定是否走替代方案 B/C |

**答完上面 8 题,选哪个协议基本就清楚了**。

---

## 7. 文档目录树(所有 storage 相关文档)

```
/Users/${USER}/git/knowledge/gcp/storage/
├── STORAGE-3-PROTOCOLS-COMPARISON.md   ← 本文档(总览地图)
│
├── nas/                                 ← SMB 挂 NAS 场景(ADR-009)
│   ├── ADR-009-gke-pod-mount-internal-nas-security-review.md
│   ├── ADR-009-decision-tree.md
│   ├── ADR-009-q6a-path-decision.md
│   ├── ADR-009-pod-nas-mount-flow.md
│   ├── ADR-009-pod-nas-mount-flow.html
│   ├── ADR-009-section-6-3-compliance-flow.html
│   ├── pod-nas-mount-flow-eli5.html
│   ├── ADR-009-english-status-update.md
│   ├── pv-with-pvc.md                   ← PV/PVC 概念澄清
│   ├── pv-with-pvc-eli5.html
│   └── gke/                              ← SMB 部署参考集(11 个文件)
│
├── buckets/                              ← 跨 project Bucket(ADR-011)
│   ├── ADR-011-gke-pod-cross-project-bucket-security-review.md
│   ├── ADR-011-decision-tree.md
│   ├── ADR-011-pod-bucket-flow.md
│   ├── ADR-011-pod-bucket-flow.html
│   ├── pod-bucket-flow-eli5.html
│   └── gke/                              ← Bucket 部署参考集(8 个文件)
│
├── nfs/                                  ← NFS 挂载场景(精简版)
│   ├── README.md
│   ├── NFS-deployment-guide.md
│   ├── NFS-vs-SMB-decision.md
│   ├── NFS-redlines-eli5.html
│   └── gke/                              ← NFS 部署参考集(2 个 YAML)
│
├── gke-pv-creation-through-pod-mount.md       (既有 PV 入门)
├── gke-pv-multi-tenant-design.md             (既有 PV 多租户设计)
├── gke-pv-provisioning-flow.md                (既有 PV provision 流程)
├── gke-pv-storage-flow.html                   (既有 PV 架构图)
├── gke-pv-storageclass-choice.md              (既有 SC 选择)
├── cloud-bak.md                                (既有,无关)
└── cloud-storage-transfer-service.md          (既有,无关)
```

**4 协议关键文档入口**:
- **SMB** → `nas/ADR-009-...` + `nas/gke/`
- **NFS** → `nfs/NFS-deployment-guide.md` + `nfs/gke/`
- **Bucket** → `buckets/ADR-011-...` + `buckets/gke/`

---

## 8. ADR 编号索引(跨 storage 目录)

| ADR | 主题 | 状态 | 位置 |
|---|---|---|---|
| 008 | K8s v1.37 Static Pod | Proposed | `gcp/adr/` |
| 009 | GKE Pod 挂 NAS(SMB)| Proposed | `gcp/storage/nas/` |
| **010** | **NAS 实施细节(预留)**|未来 | 待生成 |
| 011 | GKE 跨 project 访问 Bucket | Proposed | `gcp/storage/buckets/` |
| 012 | NFS 挂载(如果需要 ADR 化)| 未来 | (本目录建议跳过,精简版足够)|

---

## 9. 实施 checklist(给 infra-gcp)

### 9.1 SMB 路径(详见 `nas/gke/`)

- [ ] SMB server 可达性(`nc -zv <server> 445`)
- [ ] NAS 端 SMB 1.0 已禁用(AD-009 G3)
- [ ] KSA + Secret 创建(`smb-secret` in api-ns)
- [ ] PV + PVC + NetworkPolicy 部署
- [ ] 4 红线 CI 检查

### 9.2 NFS 路径(详见 `nfs/gke/`)

- [ ] NFS server 可达性(`nc -zv <server> 2049` + `showmount -e`)
- [ ] PV 创建(`nfs.csi.k8s.io`,无 Secret)
- [ ] PVC + NetworkPolicy 部署
- [ ] 4 红线 CI 检查

### 9.3 Bucket 路径(详见 `buckets/gke/`)

- [ ] GKE cluster 启用 Workload Identity Federation
- [ ] KSA + WIF annotation 创建
- [ ] user-bucket-project Bucket 创建
- [ ] 跨 project IAM policy 配(带 condition 限定 prefix)
- [ ] Deployment + 4 红线 CI 检查
- [ ] **PM + Manager 档 1 例外审批**(必走,因 R1 触发)

---

## 10. 4 红线速查(3 协议通用)

| 红线 | 自检命令 |
|---|---|
| **R1 不持久化到 GCP 服务** | `grep -E "gcs\|firestore\|bigquery\|cloudsql\|bq" deployment.yaml` 应为空(注:bucket 场景 R1 是讨论焦点,需 PM 审批) |
| **R2 不写 log / metric 暴露** | `grep -E "nas.*path\|nfs.*path\|/mnt/(nas\|nfs)\|gs://" deployment.yaml` 应为空(mount path 合法) |
| **R3 不主动观察用户行为** | 应用层 owner 自查 — audit 字段不含 file_path / file_content |
| **R4 Pod lifecycle 与存储解耦** | `grep -E "configMapRef.*(nas\|nfs\|bucket)\|secretRef.*(nas\|nfs\|bucket)" deployment.yaml` 应为空 |

---

## 11. 业务方最终决策建议

**最简决策**:**问 IT 一个问题** —— "**这个数据源是什么系统?**"

| IT 答 | 你选 |
|---|---|
| Windows File Server | SMB |
| Linux NFS server | NFS |
| 想用 GCP Cloud Storage(可迁移) | Bucket |
| 不确定 | **先问 IT,再选**;不要猜 |

**之后**:走对应协议的部署参考集,业务方 review + PM 评估 → infra-gcp 执行。

---

> **作者声明**:本文档是总览地图,**不重复**各协议的详细实施。具体实施请跳到对应子目录(`nas/gke/` / `nfs/gke/` / `buckets/gke/`)。