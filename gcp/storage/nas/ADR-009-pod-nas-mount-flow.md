# ADR-009 · Pod 挂 NAS 完整链路与顺序概念澄清

> **本文档是 ADR-009 的派生概念文档** —— 专门回答"挂一个 NAS 到 GKE Pod,从头到尾发生了什么"以及"PSC(Private Service Connect)在什么位置"。
>
> **架构师 lane 边界**:本文档**只做概念澄清 + 流程图**,**不实施任何 provision / apply**,**不创建 PSC / PV / PVC / Secret**。

---

## 0. TL;DR —— 一句话总结

> **挂 NAS 不是"Pod 直接连 NAS"**,而是经过 **6 层抽象 + 1 条数据通路**:
>
> ```
> Pod 写 volumes:
>   → K8s API 接受,创建 PV/PVC 对象
>   → Pod 调度到 Node
>   → Kubelet 调 CSI driver (smb.csi.k8s.io)
>   → CSI driver 通过 SMB 协议(TCP 445)连公司 NAS
>   → NAS 鉴权(SMB signing / 共享 ACL),允许后 mount
>   → 容器内 /mnt/nas 可见,直接 read
> ```
>
> **PSC 在这条路里完全不存在**(NAS 是公司内网 SMB,不经过 GCP 任何服务)。如果未来走替代方案 B(Filestore),那时 PSC 才会出现。

---

## 1. 为什么需要概念澄清?

业务方在 review 中明确提出 3 个疑问,需要逐一澄清:

| 疑问 | 在本文档哪节 |
|---|---|
| 挂 NAS 的**完整链路**和**时序顺序**是什么? | §3(链路)+ §4(时序图) |
| **PSC** 和挂网盘有什么关系? | §5(PSC 位置澄清) |
| 为什么 NAS 跟 PV/PVC 体系**绕一圈**才能挂? | §2(为什么需要抽象) |

---

## 2. 为什么需要抽象?(K8s 的设计哲学)

### 2.1 如果没有 K8s 抽象会怎样?

如果 Pod 直接说"挂 NAS",Pod spec 会变成:

```yaml
# 假想的"直接挂"模式(实际不存在)
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: app
    image: my-app
    smbMount:                                # ❌ 假想字段
      server: nas.address.aibang
      share: hk/gsd/application
      credentials:
        username: svc-account
        password: xxx
      mountPath: /mnt/nas
```

**问题**:

- Pod spec 里出现 **NAS 服务器地址 + 凭据** —— **凭据泄漏**
- Pod spec 跟 **特定存储系统强耦合** —— 换 GCP PD / Filestore / AWS EBS 都要改 Pod
- Pod 直接负责**网络连通性 + 鉴权 + mount 协议** —— 跟业务逻辑混在一起
- **横向访问面失控** —— 任何 Pod 都能挂任何 NAS,平台无法统一管控

### 2.2 K8s 的解决方案:分层抽象

K8s 把"挂存储"这件事拆成 **3 个角色**:

```
┌─────────────────────────────────────────────────────────────┐
│  Pod (使用者)            —  只说"我要一块存储,挂到 /mnt/nas"  │
│   ↓                                                            │
│  PVC (申请单)            —  "我要 ≥ 10 GiB,read-only,某 SC"     │
│   ↓                                                            │
│  PV (货架)               —  "我是 PV-A,绑到 SMB CSI driver"   │
│   ↓                                                            │
│  CSI driver (翻译官)     —  把 K8s 指令翻译成 SMB 协议         │
│   ↓                                                            │
│  真实存储系统            —  公司 NAS(GCP PD / Filestore / ...)  │
└─────────────────────────────────────────────────────────────┘
```

**好处**:

- Pod 不知道也不需要知道底层是什么存储系统
- 凭据不进 Pod spec,放在 Secret 里由 CSI driver 读
- 平台通过 **NetworkPolicy + PodSecurity + Admission Webhook** 在 PVC / PV 层统一管控
- 切换存储系统只改 PV 的 `spec.csi.driver`,Pod 完全不动

---

## 3. 完整链路 —— 6 层抽象 + 1 条数据通路

### 3.1 6 层抽象(从外到内)

| # | 层 | 角色 | 创建方 | 关键字段 |
|---|---|---|---|---|
| **L1** | **Pod** | 业务负载 | 业务方 | `volumes:` + `volumeMounts:` |
| **L2** | **PVC** | 卷申请单 | 业务方(命名空间级) | `storageClassName:` / `accessModes:` / `resources.requests.storage:` |
| **L3** | **PV** | 卷本身 | 平台 / 动态 provisioner(命名空间级绑定到 L2) | `spec.csi.driver:` / `spec.csi.volumeAttributes:` / `spec.csi.nodePublishSecretRef:` |
| **L4** | **CSI driver** | 翻译官 | 平台(集群级 DaemonSet) | `smb.csi.k8s.io` / `pd.csi.storage.gke.io` / `nfs.csi...` |
| **L5** | **协议** | 网络层 | 由 CSI driver 决定 | SMB 445 / NFS 2049 / iSCSI / NVMe |
| **L6** | **真实存储** | 数据落地 | 外部系统 | 公司 NAS / GCP PD / Filestore / AWS EBS |

### 3.2 一条数据通路(SMB 场景)

```
应用代码                     GKE Node                         公司 NAS
   │                            │                              │
   │ read("/mnt/nas/foo.csv")   │                              │
   ├──────────────────────────► │                              │
   │                            │                              │
   │                            │ 容器内 /mnt/nas → bind mount │
   │                            │ ↓                            │
   │                            │ Node 本地 mount              │
   │                            │ /var/lib/kubelet/pods/<uid>/ │
   │                            │   volumes/.../csi-smb/       │
   │                            │ ↓                            │
   │                            │ CSI driver 维护 SMB 连接    │
   │                            │ (TCP 445 持久连接)           │
   │                            │ ↓                            │
   │                            │ SMB 协议读                   │
   │                            │ ───────────────────────────► │
   │                            │                              │
   │                            │                              │ NAS 鉴权
   │                            │                              │ (SMB signing + 共享 ACL)
   │                            │                              │ ↓
   │                            │                              │ 读 //hk/gsd/application/foo.csv
   │                            │                              │
   │                            │ ◄────── SMB read response ──│
   │                            │                              │
   │ ◄────── 文件内容 ─────────│                              │
   │                            │                              │
```

**关键观察**:

- 应用代码的 read() **直接拿到 NAS 文件**,中间没有任何"拷贝到 GCP"的动作
- NAS 文件**物理上始终在公司 NAS 上**,GKE 只做 SMB 协议转发
- CSI driver 维护**持久 TCP 连接**(不是每次 read 都重新握手),延迟 = SMB 协议开销 + NAS 物理盘 IO

---

## 4. 完整时序图 —— Pod 创建 → NAS 可读

```
时间轴   Pod 业务方           K8s API            Kubelet/调度器       CSI driver           公司 NAS
  │      │                     │                    │                    │                    │
  │  ①   │ 写 Pod manifest     │                    │                    │                    │
  │      │ 含 volumes:         │                    │                    │                    │
  │      │ - name: nas-folder  │                    │                    │                    │
  │      │   csi.driver: smb   │                    │                    │                    │
  │      │   csi.volumeAttrs   │                    │                    │                    │
  │      │     source: //nas/  │                    │                    │                    │
  │      │   csi.nodePublish   │                    │                    │                    │
  │      │     SecretRef: nas- │                    │                    │                    │
  │      │     smb-creds       │                    │                    │                    │
  │      │ volumeMounts:       │                    │                    │                    │
  │      │ - mountPath: /mnt/nas                    │                    │                    │
  │      │   readOnly: true    │                    │                    │                    │
  │ ───► │ kubectl apply ─────►│                    │                    │                    │
  │      │                     │                    │                    │                    │
  │  ②   │                     │ 验证 RBAC          │                    │                    │
  │      │                     │ (PodSecurity 标准) │                    │                    │
  │      │                     │ 创建 Pod 对象     │                    │                    │
  │      │                     │ ────────► etcd     │                    │                    │
  │      │                     │                    │                    │                    │
  │  ③   │                     │                    │ 调度器选 Node      │                    │
  │      │                     │ ◄───────────────── │                    │                    │
  │      │                     │                    │ (Pending →          │                    │
  │      │                     │                    │  ContainerCreating)│                    │
  │      │                     │                    │                    │                    │
  │  ④   │                     │                    │ 检测 volumes[].csi │                    │
  │      │                     │                    │ → RPC:             │                    │
  │      │                     │                    │ NodePublishVolume  │                    │
  │      │                     │                    │ ─────────────────► │                    │
  │      │                     │                    │                    │                    │
  │  ⑤   │                     │                    │                    │ 读 Secret           │
  │      │                     │                    │                    │ nas-smb-creds       │
  │      │                     │                    │                    │ 从 K8s API          │
  │      │                     │                    │                    │                    │
  │  ⑥   │                     │                    │                    │ SMB TCP 445         │
  │      │                     │                    │                    │ 连接 NAS            │
  │      │                     │                    │                    │ ──────────────────► │
  │      │                     │                    │                    │                    │
  │  ⑦   │                     │                    │                    │ Negotiate Protocol  │
  │      │                     │                    │                    │ (SMB 3.0+ 协商)     │
  │      │                     │                    │                    │                    │
  │      │                     │                    │                    │ Session Setup       │
  │      │                     │                    │                    │ (auth / signing)    │
  │      │                     │                    │                    │                    │
  │      │                     │                    │                    │ Tree Connect        │
  │      │                     │                    │                    │ (挂载共享           │
  │      │                     │                    │                    │  //hk/gsd/...)      │
  │      │                     │                    │                    │ ◄────────────────── │
  │      │                     │                    │                    │                    │
  │  ⑧   │                     │                    │                    │ mount -t cifs       │
  │      │                     │                    │                    │ 在 Node 本地        │
  │      │                     │                    │                    │ /var/lib/kubelet/   │
  │      │                     │                    │                    │   pods/<uid>/...    │
  │      │                     │                    │ ◄──── 完成 ─────── │                    │
  │      │                     │                    │                    │                    │
  │  ⑨   │                     │                    │ bind mount 进容器 │                    │
  │      │                     │                    │ namespace           │                    │
  │      │                     │                    │                    │                    │
  │  ⑩   │ 容器启动              │                    │                    │                    │
  │      │ /mnt/nas 真实可见 ──►│                    │                    │                    │
  │      │ read(open())        │                    │                    │                    │
  │      │ 直接走 SMB ──────── │ ────────────────── │ ────────────────── │ ──────────────────►│
  │      │                     │                    │                    │                    │
  ▼      ▼                     ▼                    ▼                    ▼                    ▼
```

### 4.1 时序图要点解读

| 步骤 | 谁来做 | 做什么 | 跟业务方有关吗 |
|---|---|---|---|
| ① | 业务方 | 写 Pod manifest,声明 volumes | ✅ 业务方的事 |
| ② | K8s API | RBAC + PodSecurity 校验 | ❌ 平台的事 |
| ③ | 调度器 | 选 Node | ❌ 平台的事 |
| ④ | Kubelet | 检测 CSI volume,调 CSI driver | ❌ 平台的事 |
| ⑤ | CSI driver | 读 Secret 拿凭据 | ⚠ 凭据是平台创建 |
| ⑥-⑦ | CSI driver | SMB 协议握手 + 鉴权 | ❌ 协议细节 |
| ⑧ | CSI driver | Node 本地 mount | ❌ 平台的事 |
| ⑨ | Kubelet | bind mount 进容器 namespace | ❌ 平台的事 |
| ⑩ | 业务方 | 容器启动,read("/mnt/nas/...") | ✅ 业务方的事 |

**业务方只需要关心 ① 和 ⑩** —— 中间 8 步全部由平台 + CSI driver + 协议自动完成。

---

## 5. PSC(Private Service Connect)在哪里?

### 5.1 业务方疑问的来源

"挂 NAS"听起来像"内网互通",而 GCP 文档里讲"内网互通"经常提到 **PSC(Private Service Connect)**。**PSC 跟 NAS 挂载没关系**,但容易混淆。

### 5.2 PSC 是什么?

> **PSC(Private Service Connect)**:GCP 提供的**私有访问**机制,让 VPC 内的资源**不经过公网**访问 GCP 托管服务(如 Cloud SQL、Filestore、自定义 Service)。

**典型场景**:

```
GKE Pod → Cloud SQL(默认走公网,需授权 IP)
                   ↓
                   改成 PSC:
GKE Pod → VPC 内网 → PSC Endpoint → Service Attachment → Cloud SQL 实例
```

**PSC 的 3 个角色**:

| 角色 | 是什么 | 谁创建 |
|---|---|---|
| **Service Attachment** | 服务提供方(如 Cloud SQL 服务)暴露的"内部入口" | GCP 托管服务侧(用户不能创建) |
| **PSC Endpoint** | 消费方(如 GKE Pod 所属 VPC)创建的一个**私有 IP**,映射到 Service Attachment | 业务方 |
| **DNS** | 业务方 Pod 用域名访问(如 `cloudsql-psc.googleapis.com`),DNS 解析到 PSC Endpoint IP | GCP 自动 |

### 5.3 PSC 跟挂 NAS 有什么关系?

| 场景 | 用 PSC 吗? | 原因 |
|---|---|---|
| **挂公司内网 NAS(本 ADR 主体)** | ❌ **不用** | NAS 不在 GCP,**PSC 是 GCP 内部机制**,用于访问 GCP 托管服务,不适用跨公司内网 |
| **挂 GCP Filestore(替代方案 B)** | ⚠ **看情况** | Filestore 是 GCP 托管,**但同 VPC 内不需 PSC**(Filestore 直接在 VPC 内);跨 VPC 才需要 PSC |
| **挂 GCP NetApp Volumes(替代方案 C)** | ⚠ **看情况** | 同 Filestore |
| **挂 GCP PD(既有 PV 设计)** | ❌ **不用** | PD 是节点本地或 zone 内,不走网络抽象 |

### 5.4 一张图说明 PSC 的位置(以及为什么 NAS 不用)

```
                          GCP 内部                                 公司内网
  ┌─────────────────────────────────────────────┐    ┌──────────────────────────┐
  │                                              │    │                          │
  │   GKE Pod                                    │    │                          │
  │      │                                       │    │                          │
  │      │ (1) 挂 NAS(本 ADR)                  │    │                          │
  │      │     → SMB TCP 445                     │    │                          │
  │      │     ────────────────────────────────► │ ─► │ 公司 NAS                 │
  │      │     (走场景 A 路由或 Cloud VPN)       │    │ (SMB 3.1.1)             │
  │      │                                       │    │                          │
  │      │ (2) 访问 GCP Cloud SQL(替代场景)   │    │                          │
  │      │     → PSC Endpoint (10.20.0.5)       │    │                          │
  │      │     (在 VPC 内,不经公网)            │    │                          │
  │      │     ──────────────────────────────►  │    │                          │
  │      │                          │            │    │                          │
  │      │                          ▼            │    │                          │
  │      │                       PSC Endpoint   │    │                          │
  │      │                          │            │    │                          │
  │      │                          ▼            │    │                          │
  │      │                       Service         │    │                          │
  │      │                       Attachment      │    │                          │
  │      │                          │            │    │                          │
  │      │                          ▼            │    │                          │
  │      │                       Cloud SQL       │    │                          │
  │      │                       (GCP 托管)      │    │                          │
  │                                              │    │                          │
  └─────────────────────────────────────────────┘    └──────────────────────────┘
```

**关键区别**:

- **(1) NAS**:走 SMB 协议,出 GCP VPC,**不经过 PSC**
- **(2) Cloud SQL**:在 GCP 内,通过 PSC 走 VPC 内网,**不经过公网**

### 5.5 如果未来想用 PSC 替代 NAS,会怎样?

假设业务方后来想走替代方案 B(Filestore),PSC 路径是:

```
GKE Pod (api-ns)
   │
   │ (1) 挂 Filestore NFS
   │     → mount -t nfs 10.10.20.5:/vol1 /mnt/nas
   │     (Filestore 实例 IP,同 VPC 内,无需 PSC)
   │
   │ (2) 同时还想访问 Cloud SQL(假设)
   │     → PSC Endpoint (10.10.30.100) → Service Attachment → Cloud SQL
```

**重点**:

- **Filestore 同 VPC 内访问,不需 PSC**(直接走 VPC 路由)
- **跨 VPC 访问 Filestore 才需要 PSC**(比如 GKE cluster A 想用 cluster B 所在 VPC 的 Filestore)
- **访问 GCP 托管服务(如 Cloud SQL)才需要 PSC**

---

## 6. 业务方疑问 FAQ

| 疑问 | 答复 |
|---|---|
| 挂 NAS 跟 PV 是什么关系? | PV 是 K8s 抽象,跟"什么存储系统"无关。NAS 走 `smb.csi.k8s.io` driver,跟 GCP PD 走 `pd.csi.storage.gke.io` driver 在 PV 抽象层完全平行(详见 ADR-009 §12) |
| 挂 NAS 跟 PSC 是什么关系? | **没关系**。NAS 是公司内网 SMB,PSC 是 GCP 内部私有访问机制,适用场景完全不同(详见 §5) |
| 挂 NAS 时 NAS 数据会经过 GCP 吗? | **不会**。Pod read() → CSI driver → SMB TCP 445 → 公司 NAS。数据通道**不进任何 GCP 服务** |
| 挂 NAS 跟 Filestore 有什么区别? | NAS = 公司内网 SMB(本 ADR);Filestore = GCP 托管 NFS(替代方案 B,数据在 GCP VPC 内) |
| 业务方写 Pod spec 时,需要知道 NAS 地址吗? | **不需要**。Pod spec 只写 `csi.driver: smb.csi.k8s.io` + `volumeAttributes.source: //nas/...`,CSI driver 才知道连哪个 NAS。**业务方不用关心 NAS IP / 鉴权 / 协议** |
| 挂 NAS 跟挂 Filestore 在 Pod spec 层有什么区别? | **几乎没区别**。只差 `csi.driver` 字段(smb vs nfs)和 `volumeAttributes.source` 字段(//nas/... vs 10.x.x.x:/vol1)。Pod spec 写法是一致的 |

---

## 7. 跟 ADR-009 章节的映射

| 本文档 | ADR-009 对应章节 | 关系 |
|---|---|---|
| §3 完整链路 | ADR-009 §12 概念澄清 | 互补(本文档更细,加 PSC) |
| §4 时序图 | ADR-009 §12.3 时序图 | 复用 + 扩展(本文档加 ①-⑩ 步骤标签) |
| §5 PSC 位置 | ADR-009 无(本次新增) | **ADR-009 之前漏掉的关键点** |
| §6 FAQ | ADR-009 §12.5 FAQ | 互补(本文档加 PSC / Filestore 对比) |

---

## 8. 架构师 lane 边界(重申)

| 能做 | 不做 |
|---|---|
| ✅ 写概念文档(本文档) | ❌ 创建 PV / PVC / Secret / PSC |
| ✅ 画架构图 | ❌ 跑 gcloud / kubectl / terraform |
| ✅ 评审回执 | ❌ 持有 GCP 凭证 |
| ✅ 维护 ADR-009 配套 | ❌ 替业务方 / 决策者拍板选方案 |

---

> **作者声明**:本文档只做概念澄清,**不实施任何 provision / apply**。若业务方基于本文档决定挂 NAS,实际部署由 infra-gcp + devops-gcp 在 ADR-010 实施阶段完成。
