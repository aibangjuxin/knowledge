# NFS 挂载参考集(GKE 平台)

> 👉 **3 协议总览(SMB / NFS / Bucket)对比** 见 [`../STORAGE-3-PROTOCOLS-COMPARISON.md`](../STORAGE-3-PROTOCOLS-COMPARISON.md)
>
> **本目录是"挂载 NFS 协议存储到 GKE Pod"的精简版操作指南**。
>
> **架构师 lane 边界**:
> - 本目录**只生成设计参考 + YAML 模板**,**不执行任何 provision / apply / gcloud / kubectl**
> - 实际部署由 infra-gcp profile 走 SA 身份执行
> - **业务方不要**亲自 `kubectl apply` 这些资源

---

## 0. 必读前置

| 必读 | 是什么 |
|---|---|
| [ADR-009 主文档 §6.3 红线表 + 4 红线](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#63-推荐做法扩展版行为判定矩阵--4-条红线--流程图) | 挂载任何存储(包含 NFS)**都触发** 4 红线,业务方写 YAML 前必读 |
| [ADR-009 §12 概念澄清](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#12-概念澄清--pod-挂-nas-跟-pvpvc-到底是什么关系) | PV/PVC/CSI driver 概念(本目录不重复) |
| [ADR-009 §1.3 阻塞问题](../nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#13-必须先澄清的业务语义交付前阻塞项) | 6 个阻塞问题(NFS 场景同样适用)|

---

## 1. 目录导览

```
nfs/
├── README.md                          ← 你正在读
├── NFS-deployment-guide.md             ← 主文档:具体怎么实施 + 操作步骤
├── NFS-vs-SMB-decision.md             ← SMB vs NFS 决策表
├── NFS-redlines-eli5.html             ← 5岁版解释(给小白 onboarding)
└── gke/
    └── examples/
        ├── deployment-with-nfs.yaml       ← Deployment 模板
        └── pv-nfs-static.yaml             ← PV 模板(静态方式,推荐)
```

---

## 2. 核心概念(再读一次)

**NFS 挂载链路**(同 NAS,只是协议层换):

```
Pod (业务方接触)
   ↓ volumes: [nfs-mount]
PVC (申请单,namespace-scoped)
   ↓ volumeName
PV (货架,cluster-scoped)
   ↓ spec.csi.driver: nfs.csi.k8s.io
CSI driver (翻译官,DaemonSet,privileged)
   ↓ NFS 协议 (TCP 2049)
真实存储(NFS server)
```

**关键事实**:
- NFS 用 **TCP 2049**(vs SMB TCP 445)
- NFS CSI driver `nfs.csi.k8s.io` 是 K8s 社区官方,GA,K8s 1.21+
- NFS **没有 SMB 那种 user/pass 鉴权** — 主要靠 IP 白名单 + UID/GID 映射

---

## 3. 4 红线速查(同 NAS,直接复用)

| 红线 | NFS 场景具体含义 |
|---|---|
| **R1 不持久化到 GCP 服务** | 跟 NAS 同 — Pod 不要把 NFS 内容写到 GCS / PD |
| **R2 不写 log / metric 暴露** | `grep -E "nfs.*path\|/mnt/nfs" deployment.yaml` 应为空 |
| **R3 不主动观察用户行为** | NFS 服务端可审计,需要确认权限边界 |
| **R4 Pod lifecycle 与 NAS 解耦** | 跟 SMB 同 — Pod 删了,NFS 数据还在 |

---

## 4. 何时用 SMB vs NFS(决策表)

| 维度 | SMB 445(ADR-009) | NFS 2049(本目录) |
|---|---|---|
| 协议来源 | Windows 主导 | Linux 主导 |
| 端口 | TCP 445 | TCP 2049 |
| 鉴权 | user/pass + 共享 ACL | **无原生鉴权**(靠 IP 白名单 + UID) |
| 加密 | SMB 3.0+ 加密(AES-CCM/GCM)| **NFS 4.1+ 可加密(KRB5 / kTLS),NFSv3 明文** |
| 文件锁 | opportunistic + lease | mandatory + lease(NFSv4)|
| 大文件 | 一般(Windows 优化) | **强**(Linux/Unix 优化) |
| 高并发读 | 一般 | **强**(并行 N 个 client 读) |
| 容器场景 | ✅(smb.csi.k8s.io)| ✅(nfs.csi.k8s.io)|

**业务方选择指南**:
- 数据源是 **Windows 文件服务器 / NAS 设备** → SMB(ADR-009)
- 数据源是 **Linux NFS server / Unix 传统文件共享** → NFS(本目录)
- 不确定 → 业务方问 IT 数据源端是什么系统,IT 答复后选

---

## 5. 实施前置条件

infra-gcp 跑前必查:

```bash
# 1. NFS server 可达性
nc -zv <nfs-server> 2049

# 2. NFS server 防火墙是否放行 GKE Node IP 段
# (问 IT 拿到 NFS server 所在 CIDR + GKE Node CIDR)

# 3. NFS export 列表(看 IT 是否给权限)
showmount -e <nfs-server>

# 4. K8s cluster 内核支持 NFS(默认 Linux 节点都支持)
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}'
# 期望:Linux(Container-Optimized OS / Ubuntu / etc.)
```

---

## 6. 当前状态

- **本目录是设计参考**,**不是执行脚本**
- **0 变更** — 没有真实 K8s 资源被 apply
- **infra-gcp 当前 holding pattern** —— 等决策者给 profile 配专属 GCP SA
- **业务方角度**:评审 YAML + 答 6 阻塞问题 + PM 评估,**不要**直接 `kubectl apply`

---

> **作者声明**:本文档只生成 YAML 模板 + 流程参考。**任何真实 apply 由 infra-gcp 用专属 SA 执行**。