# ADR-009: GKE Pod 挂载公司内部 NAS 的安全与架构影响评估

> Status: **Proposed** · Date: 2026-08-28 · Author: **architect-gcp** · Reviewers: **infra-gcp** / **devops-gcp** / **qa-gcp**
>
> 用户场景:把 `\\nas.address.aibang\hk\gsd\application\`(公司内部 NAS)挂载到 GKE API Pod,使其能读取远端文件。本 ADR 仅做"是否可行 + 风险面 + 加固建议"的架构评估,**不替业务方决定是否迁移存储**(用户的原始需求就是挂载访问)。

---

## 0. TL;DR(30 秒读完)

| 简化解释 | 严格原话(一手来源) |
|---|---|
| **可行,但必须分层加固;裸挂载等于把 NAS 暴露给同 namespace 每个 Pod。** | "By default, a pod is non-isolated for egress; all outbound connections are allowed." — [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) |
| **GKE Pod 与公司 NAS 之间的连通性分两种场景:底层路由已打通 → 直连内网(无 VPN);底层未打通 → 必须 Cloud VPN。** **绝不可走公网 SMB 直连。** | "Cloud VPN securely extends your peer network to Google's network through an IPsec VPN tunnel. Traffic is encrypted and travels between the two networks over the public internet." — [Google Cloud VPN](https://cloud.google.com/network-connectivity/docs/vpn) |
| **SMB CSI 协议是 SMB 3.0+,支持 encryption + signing,但"安全"前提是 NAS 端也启用。** | "SMB Encryption uses the Advanced Encryption Standard (AES)-GCM and CCM algorithm to encrypt and decrypt the data." — [Microsoft SMB Security](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-security) |
| **PVC 是 namespace-scoped,挂同一个 PVC 的 Pod 默认共享读写权限;同 namespace 其他 Pod 通过 hostPath/subPath 二次挂载即可旁路。** | "PVC / Pod: namespace-scoped,业务方操作" — [既有 `gke-pv-creation-through-pod-mount.md`](../gke-pv-creation-through-pod-mount.md) §核心概念速查 |
| **既有 PV 多租户体系(Tenant CRD / per-tenant CMEK / quota)对 NAS 不生效 —— NAS 不在 GCP 内,KMS/label/CRD 整套都用不上。** | 结论性归纳,基于 [既有 `gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) §2 设计 |

**一句话总结**:技术上 100% 可挂;但默认配置下,挂载 = 在 GKE namespace 里开一个 "NAS 隧道" 给所有 Pod,**且现有 PV 多租户隔离机制对 NAS 完全失效**。要不要走,要先回答 4 个治理问题(见 §8)。

---

## 1. 背景 —— 这到底在说什么

### 1.1 用户的真实需求

```text
\\nas.address.aibang\hk\gsd\application\
```

这是一个**公司内部文件服务器**(Windows File Server / SMB 协议),`aibang` 是公司内网域。GKE API Pod 需要**读取**该路径下的文件(具体读写语义待业务方澄清 —— §1.3)。

### 1.2 NAS 与 GCP 内存储的关键差异

| 维度 | GCP Persistent Disk(既有 PV 设计) | 公司内部 NAS(本 ADR 主体) |
|---|---|---|
| **物理位置** | GCP,master project 内 | 公司内网,跨网络边界 |
| **协议** | block device(iSCSI / NVMe) | SMB/CIFS(TCP 445) |
| **加密** | GCP-managed CMEK,per-tenant KMS key | 取决于 NAS 端配置(SMB 3.0+ 才支持 encryption) |
| **谁能看** | 通过 PVC namespace + RBAC | 通过 NAS 共享权限(AD 域用户 / 共享 ACL) |
| **审计** | GKE audit log + GCP Cloud Audit Logs | NAS 端 audit(SMB event log),**GKE 侧不可见** |
| **多租户标签** | GCP labels: `tenant=<tnt-id>` | 无标签概念,只能靠共享权限 |
| **配额** | Tenant CRD `spec.quota` | 无;NAS 是公司全局资源 |
| **API 平台"不存用户数据"原则** | 满足(PV 存的是平台元数据) | **需重新评估**(见 §6) |

> 来源对比:本 ADR 通过对比 [`gcp/storage/gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) §2 + [`gcp/storage/gke-pv-creation-through-pod-mount.md`](../gke-pv-creation-through-pod-mount.md) §核心概念速查 得出。

### 1.3 必须先澄清的业务语义(交付前阻塞项)

#### 1.3.1 原始 3 个问题

| # | 问题 | 默认假设 | 影响 |
|---|---|---|---|
| Q1 | **读写语义** —— Pod 只读 NAS,还是要写回? | **默认 ro(只读)** | 写回 = 双向数据流 = 复杂度 +1 档 |
| Q2 | **挂载范围** —— 整个 namespace 还是单个 Pod? | **单个目标 Pod** | namespace 级 = 横向访问面变大 |
| Q3 | **数据归属** —— NAS 上的文件是谁的? | **公司业务侧所有** | 决定"是否构成事实上的用户数据代理"(见 §6) |

> **Q2 已在 review 轮次确认** —— 挂载范围 = **单个目标 Pod**(单 PVC 单 Pod 绑定)。NetworkPolicy 的 PodSelector 因此可以精确锁到这一个 Pod。

#### 1.3.2 Review 轮次扩展 3 个问题

业务方在 review 中追加的 3 个问题,**经业务方 review 后已假设为非 blocker**(假设企业内部已经具备这些条件):

| # | 问题 | 业务方判断 | 谁来答 | 状态 |
|---|---|---|---|---|
| Q4 | **Pod 性能影响** —— NAS 挂载对 Pod 启动 / 运行时延迟有多大? | **假设无性能问题**(企业内部 NAS 性能可接受,不需要 initContainer 预加载) | architect-gcp + infra-gcp 联合评估 | ✅ 假设通过 |
| Q5 | **NAS 信任网络** —— NAS 端是否对来源 IP / AD 域有受信白名单? | **假设已配置**(企业内部 GKE Node IP 段已在白名单) | infra-gcp + 公司 IT 联合验证 | ✅ 假设通过 |
| Q6 | **路由连通性** —— GKE VPC 到公司内网的底层打通方式是什么? | **假设场景 A 成立**(底层路由已打通,不需要 Cloud VPN) | architect-gcp + infra-gcp + Security | ✅ 假设通过 |

> ⚠ **重要声明**:Q4/Q5/Q6 均为**业务方假设**("我们企业内部本身应该是通的"),实际实施前仍需 infra-gcp + Security 联合验证。若任一假设不成立,触发 ADR-010 实施细节的重新评审。

> 详见 §11 Review Notes —— 本轮追加 3 点的完整展开。

---

## 2. Blast Radius —— 6 个冲击维度

### 2.1 维度 ① 网络平面冲击

GKE Pod 默认在 VPC 内,公司 NAS 在公司内网,**两端默认不通**。必须打通:

| 桥接方案 | 适用 | 备注 |
|---|---|---|
| **Cloud VPN** | 中小流量 / POC | IPsec over 公网,加密;带宽有限(一般 ≤ 3 Gbps/tunnel) |
| **Dedicated Interconnect** | 大流量 / 生产 | 物理专线 10/100 Gbps,需运营商合作 |
| **Partner Interconnect** | 中等流量 / 跨地域 | 通过支持的 service provider |
| **直连 SMB over 公网** | **❌ 禁止** | 把 NAS 直接暴露在公网,任何能拿到 IP 的人都能尝试 SMB auth |

来源:[Google Cloud VPN](https://cloud.google.com/network-connectivity/docs/vpn) — "securely extends your peer network to Google's network through an IPsec VPN tunnel"。

### 2.2 维度 ② Pod 横向访问面

**关键事实**:**挂载在 Pod A 上的 SMB 卷,Pod B 看不见** —— 这是 PV/PVC 的 namespace-scoped 设计保证。

> 来源:[既有 `gke-pv-creation-through-pod-mount.md`](../gke-pv-creation-through-pod-mount.md) §核心概念速查:"PVC / Pod: namespace-scoped,业务方操作"。

但是,**有 4 种旁路路径**会让其他 Pod 也拿到访问能力:

| 旁路路径 | 是否默认允许 | 防护手段 |
|---|---|---|
| 同 namespace 业务方创建第二个 Pod 挂同一个 PVC | **是**(PVC 是 cluster-resource,但 bind 是 1:1,单 RWX PVC 可多 Pod 挂) | `accessModes: ReadOnlyMany` 限定;Gatekeeper 校验 PVC 是否被多 Pod 引用 |
| 攻击者获得 namespace 内任意 Pod shell(`kubectl exec`) | 是(若有过度授权的 KSA) | KSA 最小权限 + PodSecurity restricted |
| 同 node 上其他 Pod 通过 hostPath 读 kubelet mount | **是,除非 PodSecurity 限制** | `restricted` 标准禁止 hostPath |
| 网络层 Pod-to-Pod → SMB 端口直接打 NAS | **是**(默认 NetworkPolicy 是 allow-all) | **必须配 egress NetworkPolicy**(见 §4) |

来源:[Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/) — "By default, a pod is non-isolated for egress; all outbound connections are allowed."

### 2.3 维度 ③ RBAC 边界

K8s RBAC **只能控制谁能在 K8s 里 create/get/delete PVC**,**不能控制谁能在文件层面读 NAS 上的某个文件** —— 文件权限由 NAS 端的共享 ACL 决定。

> 来源:[Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) — RBAC 控制的是 Kubernetes API 资源,非挂载后的文件系统。

**结论**:RBAC 是"粗粒度准入",NAS 端共享 ACL 是"细粒度授权",**两者必须配合**,缺一就有漏洞。

### 2.4 维度 ④ Pod Security Standards 影响

GKE 支持 [Pod Security Standards](https://cloud.google.com/kubernetes-engine/docs/concepts/pod-security) 三档:`privileged` / `baseline` / `restricted`。

NAS 挂载通常需要 SMB CSI driver(节点级),典型配置:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-with-nas
spec:
  volumes:
  - name: nas-app-folder
    csi:
      driver: smb.csi.k8s.io
      readOnly: true
      volumeAttributes:
        source: "//nas.address.aibang/hk/gsd/application"
      nodePublishSecretRef:
        name: nas-smb-credentials
        namespace: api-ns
  containers:
  - name: api
    image: ...
    volumeMounts:
    - name: nas-app-folder
      mountPath: /mnt/nas
      readOnly: true
```

> 来源:[kubernetes-csi/csi-driver-smb](https://github.com/kubernetes-csi/csi-driver-smb) — CSI plugin name `smb.csi.k8s.io`,project status GA,supports K8s 1.21+。

**关键问题**:`restricted` 标准**禁止 `hostPath`、禁止 privileged container**;CSI driver 自身以 DaemonSet 跑在节点上,需要**单独的 namespace + privileged 权限**,这就是为什么多数平台把 storage system namespaces 标 `privileged`、业务 namespace 标 `baseline` 或 `restricted`。

来源:[Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-admission/) — baseline "Prevents known privilege escalations. Blocks things like host networking, host PID, privileged containers"。

### 2.5 维度 ⑤ 审计链(覆盖双向纪律)

| 审计来源 | 能看到什么 | 不能看到什么 |
|---|---|---|
| **GKE audit log** | 谁创建了 PVC、谁更新了 PV、谁 `kubectl exec` 进了 Pod | Pod 里 read(2)/open()了哪个 NAS 文件 |
| **Cloud Audit Logs(管理员活动)** | VPC firewall 规则变更、VPN tunnel 配置 | 文件 I/O |
| **NAS 端 SMB event log** | 哪个 Windows 账号从哪个 IP 访问了哪个共享 | 是哪个 K8s Pod、哪个 namespace、哪个 workload 触发的 |

> **断点**: GKE audit 链和 NAS audit 链 **没有自然拼接**。一旦出问题,需要跨两个系统的 eventID/时间戳/CIDR 关联定位,**平均排查时间显著高于 GCP PD 场景**。

### 2.6 维度 ⑥ "不存用户数据"原则的边界

这是最微妙的一项。**严格意义**:"我们不存用户数据"指的是平台不维护与用户身份绑定的数据(账号、行为、订单、内容)。**挂载 NAS** 本身确实是"只读访问",没有持久化进平台。

**但有 3 个灰色地带**:

1. **Pod 内存里有文件副本** —— Pod 启动时 read 一份文件进内存,如果 Pod 是有状态的(不推荐),这部分内容**事实上**经过 GKE 控制面/worker node;
2. **临时文件 / 缓存** —— 如果应用代码读 NAS 后写到 `/tmp`(emptyDir),emptyDir 生命周期跟着 Pod,Pod 重建后清空,**但若 Pod 被驱逐并 reschedule 到另一个 node,emptyDir 数据可能漂移**;
3. **Operator 行为可观测** —— Pod 启动时读 NAS,如果 Pod log/metric 把"读了哪个文件"暴露出来,这就是"对用户行为的间接观察",平台**事实上**知道谁访问了什么 —— 这跟"不观察用户行为"原则可能有冲突。

> **结论**:**挂载本身不违规**;但要在应用层做 4 件事:(a) 不持久化 NAS 内容到 PV/PVC;(b) 不把 NAS 文件路径写入 log/metric;(c) 不基于 NAS 内容生成 user-facing event;(d) Pod lifecycle 与 NAS 文件 access pattern 解耦。

---

## 3. 协议与网络路径(用户问:"用什么协议出栈?")

### 3.1 SMB 协议本身

| 特性 | SMB 1.0(CIFS) | SMB 2.0 | SMB 3.0 | SMB 3.1.1 |
|---|---|---|---|---|
| 加密 | ❌ | ❌ | ✅ AES-128-CCM | ✅ AES-128-GCM |
| 签名 | 弱 | HMAC-SHA256 | AES-CMAC | AES-GMAC |
| Pre-auth integrity | ❌ | ❌ | ❌ | ✅ |
| 默认禁用建议 | **✅ 必须禁** | (Windows Server 2025 默认禁) | ✅ | ✅(最推荐) |

> 来源:[Microsoft SMB Security](https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-security) — SMB 3.1.1 "Preauthentication integrity is a mandatory feature... protects against any tampering with Negotiate and Session Setup messages"。

**部署前必须验证 NAS 端**:
- SMB 1.0 已禁用(`Disable-WindowsOptionalFeature -Online -FeatureName smb1protocol`)
- 仅允许 SMB 3.0+ 协商
- 共享 ACL 配置(具体由 infra-gcp 联合 IT 验证)

### 3.2 端口与协议栈

#### 3.2.1 协议本身

```
Pod (GKE Node)                              公司 NAS (aibang 内网)
    │                                              │
    │   SMB over TCP 445                          │
    │   ─────────────────────────►                │
    │                                              │
```

- SMB 默认端口 **445/TCP**(也支持 139/TCP,但已不推荐)
- SMB 3.0+ 支持 Multichannel(并行多 TCP 流,适合大文件流式读)

#### 3.2.2 网络路径分两个场景(关键澄清)

业务方在 review 中明确:**底层路由已经打通,GKE Pod 与公司内网在 TCP 层是直通的,不需要再走 Cloud VPN**。这点 ADR-009 之前的版本表述有误,本节明确分场景。

##### 场景 A:底层路由已打通(本 ADR 主场景,业务方现实)

```
Pod (GKE VPC, e.g. 10.10.x.x)
    │
    │  TCP 445 SMB
    │  ─────────────────────────►
    │  路径: Pod → VPC 内 → 跨 VPC/Interconnect/Peering → 公司内网 (e.g. 10.20.x.x)
    │       → NAS
    │
    │  ⚠ 这段链路是否加密?取决于底层打通方式(见 §3.2.3)
```

**特点**:
- ✅ Pod → NAS 是**纯内网 / 跨网路由**,不进公网
- ✅ 不需要 Cloud VPN,**不需要 Dedicated Interconnect**(后者是物理专线,场景 A 通常用不上)
- ⚠ **但**:链路是否加密?是否符合公司合规?这是本场景下**真正要回答的问题**(见 §3.2.3)

##### 场景 B:底层路由未打通(ADR-009 之前的默认假设)

```
Pod (GKE VPC)
    │
    │  TCP 445 SMB
    │  经: GKE Node → VPC → Cloud VPN tunnel (IPsec)
    │       → Internet(加密) → 公司 VPN GW
    │       → 公司内网 → NAS (TCP 445)
    ▼
```

**特点**:
- Cloud VPN tunnel 是 **IPsec**,意味着 SMB 流量在公网上是加密
- 但**公司 VPN 终结点到 NAS 这一段是公司内网**(走 NAS 自身加密或内网隔离)
- 如果中间跨多个 ASN/运营商,网络抖动可能放大 SMB 延迟(微软建议 SMB over WAN 启用 SMB Multichannel)
- 这种场景下加密是默认保证的,因为 IPsec 强制

#### 3.2.3 场景 A 的关键问题:链路加密与合规

**infra-gcp review(2026-08-28)补强**:链路加密 vs NAS 端 SMB encryption 是**两个独立维度**,必须分别验证。

| 维度 | 控制层 | 谁来验证 |
|---|---|---|
| **链路加密**(P6) | 物理 / 网络层(底层打通方式本身的加密属性) | infra-gcp 网络侧 |
| **SMB encryption**(P2) | NAS 端 SMB 共享属性(Windows Server 2012+ 支持) | 公司 IT + infra-gcp |

**两个维度都 ✅ 才能保证 Pod → NAS 的全链路不出现明文 SMB**:
- 链路加密 = 路由层 / 物理层安全(防止中间链路 tap)
- SMB encryption = 协议层安全(防止 SMB 协议被降级到明文)

**业务方认知(完全正确)**:路由通 ≠ 加密。

| 底层打通方式 | 链路加密 | SMB 流量可见性 |
|---|---|---|
| **Dedicated Interconnect(物理专线)** | ❌ 明文,依赖物理隔离 | 抓包可读(若有人能 tap 光纤) |
| **Partner Interconnect(运营商中转)** | ❌ 明文,依赖运营商隔离 + 物理 | 同上 |
| **VPC Peering(同公司跨项目)** | ❌ 明文,依赖 Google 网络隔离 | Google 内部可读(但有 BAA/DPA 保护) |
| **WireGuard / IPsec tunnel(在 routing 之上再加一层)** | ✅ 已加密 | 抓包不可读 |
| **MPLS / 私有 WAN** | 取决于运营商 | 取决于运营商 SLA |

**所以对业务方反问的明确答复**:

> "如果 Egress 能到达对应网络,底层路由已打通,**就不需要走 Cloud VPN** —— 这点完全正确。"
>
> "但路由通 ≠ 安全。**链路本身的加密属性 + 公司合规框架对这条链路的接受度**,是两个独立的问题,必须分别答。"

#### 3.2.4 实施前必须澄清(交 infra-gcp + Security)

| # | 问题 | 默认假设 | 答 |
|---|---|---|---|
| Q6-a | 底层打通方式是什么?(Interconnect / Peering / WireGuard / 其他) | 未知 | infra-gcp 答 |
| Q6-b | 该链路上 SMB 流量是否加密?(明文 / IPsec / 其他) | 未知 | infra-gcp + Security 答 |
| Q6-c | 公司合规框架接受这条链路上 SMB 明文吗? | 未知 | Security 答 |
| Q6-d | NAS 端共享 ACL 是否要求"加密 SMB"作为强制项?(Windows Server 2022+ 默认 SMB signing,可配 SMB encryption 强制) | 未知 | 公司 IT + infra-gcp 答 |

**任一答案为"否 / 未知"** → 必须在 §3.2.2 场景 A 的基础上,叠加一层 WireGuard/IPsec tunnel(在 routing 之上),或升级到场景 B(Cloud VPN)。

> ⚠ **业务方明确(2026-08-28 review)**:企业内部的 SMB 链路**必须强制加密**,合规框架对 SMB 明文零容忍。因此即使 Q6-a 答 "Peering/Interconnect 明文"、Q6-b 答 "明文",也**必须**叠加 SMB Encryption(在 NAS 端开启)或 WireGuard tunnel(在 routing 之上)。
>
> **Security 必查项**(强调):Q6-c(合规接受度)在企业内部 = **不接受明文 SMB**,这是硬性要求,不是软选项。infra-gcp 实施时必须把 SMB Encryption / WireGuard 任一作为强制项。

#### 3.2.5 性能影响(review Q4 展开)

NAS 走 SMB/CIFS over TCP,**延迟比 GCP PD 高 1-2 个数量级**:

| 存储类型 | 典型 read latency | 备注 |
|---|---|---|
| GCP PD SSD(节点本地或 zone 内) | < 1 ms | 既有 PV 路径 |
| GCP Filestore(NFS) | 1-3 ms | 区域托管 |
| **公司 NAS over 已打通内网(场景 A)** | **3-15 ms** | 省 VPN 加密 + 省公网段,仍有 SMB 开销 + NAS 物理盘 |
| 公司 NAS over Cloud VPN(场景 B) | 5-30 ms | 加公网 VPN 加密 + 跨运营商 |

**具体影响**:

- **Pod 启动慢**:如果应用启动时要加载 NAS 上的配置文件 / 模型 / 静态资源,Pod 启动时间会显著拉长(几百毫秒变成几秒甚至十几秒)
- **冷启动放大**:GKE 节点扩容时,新节点上的第一个 Pod 要走完整 SMB 握手;NodeLocal DNSCache 帮不到,因为是 DNS 层
- **小文件密集读灾难**:SMB 是"连接级"协议,每次 TCP 往返都有开销;读 100 个小文件,延迟会叠加
- **大文件流式读 OK**:SMB 3.0+ 有 Multichannel,能跑满链路带宽

**应对**:

| 策略 | 何时用 | 谁负责 |
|---|---|---|
| **initContainer 预加载到 emptyDir** | NAS 内容 < 500 MB + 启动期必读 | 应用 owner |
| **SMB Multichannel 开启**(NAS 端 + CSI driver) | 单文件 > 100 MB 或大流量流式读 | infra-gcp + 公司 IT |
| **监控 `smb_request_duration_seconds` P99** | 所有场景 | devops-gcp |
| **缓存层(应用内 memory cache 或 Redis)** | 同文件高频重复读 | 应用 owner |
| **预签名 URL / CDN 替换**(若可迁移) | 静态资源 + 可外移 | architect-gcp 评估 |

> 例:`histogram_quantile(0.99, sum(rate(smb_request_duration_seconds_bucket[5m])) by (le))` 跟踪 SMB 请求 P99 延迟。

### 3.3 DNS 解析

NAS 主机名 `nas.address.aibang` —— 必须在 GKE 集群内能解析。3 个方案:

| 方案 | 复杂度 | 推荐度 | 备注 |
|---|---|---|---|
| (a) GKE Pod 直接走公司 DNS(经场景 A 路由 或 场景 B VPN tunnel) | 中 | ✅(干净) | **场景 A 适用** |
| (b) GKE 内 CoreDNS 配 stub zone 把 `address.aibang` 转发到公司 DNS | 高 | ✅(更可控) | 场景 A/B 都适用 |
| (c) 用 IP 写死(`//10.x.x.x/hk/gsd/...`) | 最低 | ⚠ | NAS IP 变了就断;不推荐,但调试期可用 |

> **场景 A 下**:`kube-dns` 出栈 DNS 流量走底层路由即可,不需要 VPN tunnel。

---

## 4. 同 namespace 横向访问 —— NetworkPolicy 设计

### 4.1 默认行为(不配 NetworkPolicy)

> "By default, a pod is non-isolated for egress; all outbound connections are allowed."

来源:[Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)。

意味着:**业务 namespace 里任何 Pod 都能直接打 NAS 的 TCP 445**,无须通过目标 API Pod。

### 4.2 必须配置的 NetworkPolicy

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-only-api-pod-to-nas
  namespace: api-ns
spec:
  podSelector:
    matchLabels:
      app: api
      role: nas-consumer
  policyTypes:
  - Egress
  egress:
  # 允许到公司 NAS CIDR 的 SMB 流量(走 VPN tunnel)
  - to:
    - ipBlock:
        cidr: 10.20.0.0/16   # 公司 NAS 所在子网,具体由 infra-gcp 确认
        except:
        - 10.20.0.0/24       # 例外:不直接打到 NAS management IP
    ports:
    - protocol: TCP
      port: 445
  # 允许到 kube-dns(解析 nas.address.aibang)
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      ports:
    - protocol: UDP
      port: 53
  # 允许到 GCP API(节点级 metadata server,业务 Pod 通常不用,但允许避免奇怪问题)
  - to: []
    ports:
    - protocol: TCP
      port: 443
```

**效果**:
- 业务 namespace 内只有带 `app=api, role=nas-consumer` label 的 Pod 能出栈 SMB
- 其他 Pod 即便拿到 shell 也连不上 TCP 445
- 这是**纵深防御的最后一层**(即使 NAS 凭据泄露,也只能从受控 Pod 出去)

---

## 5. 跨 namespace / 跨用户隔离

### 5.1 默认隔离

K8s namespace 是天然隔离边界:**默认情况下,namespace A 的 Pod 不能看到 namespace B 的 PVC/PV**。RBAC 也是 namespaced(除非显式 ClusterRoleBinding)。

来源:[Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/) — "A Role always sets permissions within a particular namespace"。

### 5.2 必须警惕的跨 namespace 风险

| 风险场景 | 是否可能 | 防护 |
|---|---|---|
| 跨 namespace Pod 通过 K8s API 偷 PVC 引用 | ❌(RBAC 默认 deny) | 维持 RBAC 最小权限 |
| 跨 namespace Pod 通过 node-level mount 偷数据 | ✅(如果 privileged + hostPath) | PodSecurity `restricted` 禁止 hostPath |
| 跨 namespace Pod 通过 service 偷 SMB proxy | ✅(若有人故意暴露 SMB proxy Service) | 禁止任何 namespace 创建 LoadBalancer/NodePort 指向 445 |
| 用户 A 的 Pod 通过 RBAC 误授权访问用户 B 的 PVC | ✅ | 用 Tenant CRD `scAllowlist` 限定(但 NAS 不在 SC 体系下,见 §7) |

---

## 6. "不存用户数据"原则的边界(深度分析)

### 6.1 三档语义

| 档位 | 描述 | 是否被 NAS 挂载打破 |
|---|---|---|
| **绝对档** | 平台持久层(PV / DB / Cache)零用户数据 | ✅ 未打破(NAS 不进 PV) |
| **观察档** | 平台不观察、不记录用户行为 | ⚠ 有条件打破(见 §2.6 的 4 个灰色地带) |
| **代理档** | 平台不做 user-data 的"中转 / 代理 / 镜像" | ⚠ **read 模式** = 短期内存代理;**rw 模式** = 长期代理 |

### 6.2 read-only vs read-write 的本质差异

| 模式 | 平台角色 | 风险等级 |
|---|---|---|
| **ro(只读)** | Pod 启动时加载 NAS 文件到内存 | 低(若 Pod 无状态) |
| **rw(读写)** | Pod 把运行时数据写回 NAS | **高** —— 这等于把 NAS 当成平台的"持久层",GKE 故障域 ≠ NAS 故障域,数据一致性 / 备份 / 审计全是问题 |

### 6.3 推荐做法

1. **默认 ro,除非业务方明确要求 rw + 给出业务理由**
2. 若必须 rw,**额外引入一层抽象** —— 让 Pod 写 GCS bucket(走 IAM 鉴权),由同步任务把 GCS 镜像回 NAS;这样 NAS 是 "冷归档",不是 "热存储"
3. 在 Tenant CRD(若未来引入 NAS 维度)或单独 `NasSharePolicy` CRD 里**显式标注 read_only / read_write**,并对 `rw` 强制走审批

---

## 7. 既有 PV 多租户设计是否被 NAS 绕过

**结论**:**完全被绕过**。原因如下:

| 设计要素 | 对 GCP PD 的覆盖 | 对 NAS 的覆盖 |
|---|---|---|
| Tenant CRD `scAllowlist` | ✅(SC 名 → 准用) | ❌(NAS 不走 StorageClass) |
| Tenant CRD `quota.totalStorageGiB` | ✅(PD 计费可归因) | ❌(NAS 容量公司侧独立管理) |
| Per-tenant CMEK | ✅(每个 tenant 独立 KMS key 加密 PD) | ❌(SMB encryption 是 NAS 端全局配置,无法 per-tenant 隔离) |
| GCP labels `tenant=<tnt-id>` | ✅(BigQuery billing 归因) | ❌(NAS 无标签概念) |
| ValidatingWebhook(PVC admission) | ✅ | ❌(NAS 挂载不走 PVC admission) |

> 来源:综合对比 [既有 `gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) §2 设计 + SMB CSI driver 文档。

**影响**:
1. **审计归因失效** —— 哪个 tenant 用了 NAS 多少流量,无法靠 GCP 标签自动归因;必须靠 NAS 端 ACL + 业务侧日志手工对账
2. **加密隔离失效** —— NAS encryption 是 NAS 端开关;一旦共享 key,所有租户共用
3. **配额失效** —— NAS 是公司全局资源,某 tenant 大量读 NAS 可能影响其他业务,**需走公司侧配额流程**

### 7.1 推荐的修补路径

在 `gke-pv-multi-tenant-design.md` 增加一节 **"§11 NAS 例外路径"**,内容要点:

- NAS 挂载必须显式标注为 `legacy` / `non-conformant`
- Tenant CRD 增加字段 `nasShareAllowlist: [string]`,由平台团队手工维护
- 任何 NAS 挂载都必须经 `NasSharePolicy` admission webhook 校验
- BigQuery 归因改用 NAS 端的 per-share audit log(若可获取),否则归入 "shared infrastructure cost"

---

## 8. 决策树与建议方案

### 8.1 主路径 (A) —— 走 NAS 原状,严格加固

**适用场景**:**业务方原始需求就是访问现有 NAS 路径,数据无法迁移**(用户原话)。

**前置条件**(4 个治理问题,全部 ✅ 才走):

| # | 问题 | 必须的答案 |
|---|---|---|
| G1 | 读写语义? | `read-only` 优先;若 `read-write` 必须有审批 |
| G2 | 业务方是否接受 NetworkPolicy 强制限制? | ✅(不接受 = 不上线) |
| G3 | NAS 端 SMB 1.0 是否已禁用? | ✅(由 infra-gcp + IT 联合验证) |
| G4 | 是否接受 NAS 不在 GCP 多租户隔离体系内? | ✅(默认接受,后续补 §7.1 修补路径) |

**实施清单**(交 infra-gcp):

1. ☐ Cloud VPN tunnel 搭建(VPC ↔ 公司内网)
2. ☐ SMB CSI driver 安装(DaemonSet,独立 `csi-system` namespace,privileged)
3. ☐ NAS 凭据 Secret 创建(KSA-bound,不在 manifest 留明文)
4. ☐ PV / PVC 创建(readOnly: true)
5. ☐ NetworkPolicy 应用(§4.2)
6. ☐ PodSecurity 标准:`api-ns` 标 `baseline`(允许 SMB CSI driver sidecar),目标 Pod 标 `restricted`
7. ☐ Audit:SMB 端 event log 开启;GKE audit log 验证 PVC 行为可追溯
8. ☐ 文档:在 [`gke-pv-multi-tenant-design.md`](../gke-pv-multi-tenant-design.md) 增加 "§11 NAS 例外路径" 章节

**未做的明确事项**(不在本 ADR 范围):
- ❌ 不替换 NAS 为 GCP 方案
- ❌ 不修改业务 Pod 的应用代码
- ❌ 不下任何执行令 —— 等 infra-gcp 接收 handoff

### 8.2 替代方案 (B) —— 用 GCP Filestore(NFS)替代

| 维度 | 评价 |
|---|---|
| **原理** | Filestore 是 GCP 托管 NFS,与 GKE 在同一 VPC,免 VPN |
| **协议** | NFSv3 / NFSv4(非 SMB) |
| **隔离** | 走回 GCP PD 体系,CMEK / labels / quota **全部生效** |
| **痛点** | **数据迁移** —— 业务方的 NAS 文件需要同步到 Filestore,需评估同步策略(cron sync / Storage Transfer Service / rsync) |
| **何时推荐** | NAS 数据可迁移、延迟敏感、需要 CMEK 隔离 |

> 来源:[GKE Filestore CSI driver](https://cloud.google.com/filestore/docs/csi-driver) — "fully-managed NFS storage through the Kubernetes APIs (kubectl)... supports Filestore multishares for GKE"。
> 来源:[GKE persistent volumes](https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes) — "Filestore is a NFS solution on Google Cloud"。

### 8.3 替代方案 (C) —— 用 Google Cloud NetApp Volumes(SMB 协议)

| 维度 | 评价 |
|---|---|
| **原理** | Google Cloud NetApp Volumes 提供 **SMB 协议** 的托管文件存储(企业级 ONTAP) |
| **协议** | SMB 3.0+(与 NAS 同协议,业务侧可保持 SMB 工作流) |
| **隔离** | 同样在 GCP 内,CMEK / VPC Service Controls 可用 |
| **痛点** | **数据迁移**(同上);成本高于 Filestore;部分区域未 GA |
| **何时推荐** | 业务侧强需求 SMB 协议 + 不想改应用代码 + 数据可迁移 |

> 来源:[Google Cloud NetApp Volumes](https://cloud.google.com/netapp-volumes) — 官方文档(具体页索引在引用 §9)。

### 8.4 不推荐 / 禁止方案

| 方案 | 为什么禁止 |
|---|---|
| 把 NAS 直接暴露在公网(端口转发) | 任何拿到 IP 的人都能尝试 SMB 暴力破解;违反零信任 |
| 给所有业务 Pod 同一个 PVC | 横向访问面 = namespace × Pod count |
| 用 privileged Pod + hostPath 直挂 | 旁路 CSI driver 的所有审计,违反 PodSecurity restricted |
| 把 NAS 凭据写在 Pod manifest env | 凭据泄漏风险,K8s Secret 是底线 |

---

## 9. 一手引用与上游文档(全部 2026-08-28 验证)

| 编号 | 主题 | URL |
|---|---|---|
| R1 | SMB CSI driver for Kubernetes(GA, supports K8s 1.21+) | https://github.com/kubernetes-csi/csi-driver-smb |
| R2 | GKE persistent volumes & provisioning(确认 Filestore 是 NFS) | https://cloud.google.com/kubernetes-engine/docs/concepts/persistent-volumes |
| R3 | Filestore CSI driver(完全托管,multishare 支持) | https://cloud.google.com/filestore/docs/csi-driver |
| R4 | Kubernetes Network Policies(default egress allow-all) | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| R5 | Kubernetes RBAC Authorization(namespaced by default) | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| R6 | Google Cloud VPN(IPsec tunnel) | https://cloud.google.com/network-connectivity/docs/vpn |
| R7 | Microsoft SMB Security Enhancements(SMB 3.1.1 + encryption + signing) | https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-security |
| R8 | Microsoft SMB Security Hardening(signing default-on in Win Server 2025) | https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-security-hardening |
| R9 | Kubernetes Pod Security Standards(baseline/restricted profile) | https://kubernetes.io/docs/concepts/security/pod-security-admission/ |
| R10 | GKE Pod Security(Autopilot 默认 baseline,Standard 由 namespace label 决定) | https://cloud.google.com/kubernetes-engine/docs/concepts/pod-security |
| R11 | Google Cloud NetApp Volumes(SMB on GCP) | https://cloud.google.com/netapp-volumes |
| R12 | 既有 PV 多租户设计(本 ADR §7 比对对象) | [gcp/storage/gke-pv-multi-tenant-design.md](../gke-pv-multi-tenant-design.md) |
| R13 | 既有 PV 创建流程(本 ADR §2 比对对象) | [gcp/storage/gke-pv-creation-through-pod-mount.md](../gke-pv-creation-through-pod-mount.md) |

---

## 10. 下一步

1. **本 ADR 等待 review**:infra-gcp / devops-gcp / qa-gcp 各自 review 自己的 lane
2. **业务方澄清**:§1.3 的 3 个阻塞问题 + §8.1 的 4 个治理问题
3. **如决策走 A**:生成 ADR-010(实施细节) + handoff 给 infra-gcp
4. **如决策走 B/C**:生成 ADR-010(迁移方案) + 触发 Storage Transfer Service / NetApp Volume 设计
5. **配套文档同步**:`gke-pv-multi-tenant-design.md` 增加 "§11 NAS 例外路径"(本 ADR §7.1)

---

## 11. Review Notes —— 业务方 review 轮次扩展内容

> **本节记录**:业务方在第一轮 review(2026-08-28)后追加的问题 + architect-gcp 的展开答复。这是 ADR 的"决策轨迹",**不替换主体内容**,而是把新约束显式化,让所有后续 reviewer 能看到完整上下文。

### 11.1 Review 时间线

| 轮次 | 日期 | 内容 | 状态 |
|---|---|---|---|
| Round 1 (initial) | 2026-08-28 | ADR-009 初稿交付:3 个业务语义 + 6 个 blast radius + 决策树 | ✅ 交付 |
| Round 2 (review) | 2026-08-28 | 业务方 review 后追加 3 个问题(性能 / NAS 信任 / 路由连通性) + 澄清 1 个原有回答(Q2 挂载范围) | ✅ 已回填到 §1.3 + §3.2 |

### 11.2 Q2 已确认 — 挂载范围 = 单个目标 Pod

业务方明确:**挂到单个目标 Pod,不是整个 namespace**。

**影响回填**:

- §4.2 NetworkPolicy 的 `podSelector` 可以精确锁定单一 Pod(如 `app: api-pod-with-nas`),**不必担心误伤其他业务 Pod**
- §1.2 既有 PV 设计的 namespace-scoped 隔离,**在单 Pod 场景下天然生效**(PVC bind 到唯一 Pod,其他 Pod 看不到)
- §2.2 维度 ② 横向访问面的 4 种旁路路径中,**第 1 种**(同 namespace 其他 Pod 通过 RBAC 创建第二个 Pod 挂同一个 PVC)**风险等级降低**——但仍需保留 PodSecurity restricted 防止 hostPath 旁路

### 11.3 Q4 新增 — Pod 性能影响

完整展开见 §3.2.5。核心结论:

| 场景 | 接受度 | 应对 |
|---|---|---|
| NAS 内容 < 100 MB,启动期一次读 | ✅ 接受 | Pod 启动慢 2-10 秒,可接受 |
| NAS 内容 100-500 MB | ⚠ 需评估 | initContainer 预加载到 emptyDir |
| NAS 内容 > 500 MB 或热读 | ❌ 不推荐 | 考虑 §8 决策树替代方案 B/C |
| 单文件 > 100 MB 流式读 | ✅ 接受 | 开启 SMB Multichannel |

**对 devops-gcp 的监控要求**(原 ADR §2.5 + §3.2.5 提到的):

```promql
# SMB 请求 P99 延迟
histogram_quantile(0.99,
  sum(rate(smb_request_duration_seconds_bucket[5m])) by (le, pod)
)
# Pod 启动时间(含 NAS 挂载)
histogram_quantile(0.99,
  sum(rate(kube_pod_startup_duration_seconds_bucket[5m])) by (le, pod)
)
```

### 11.4 Q5 新增 — NAS 信任网络白名单

**关键提醒**(业务方认知对齐):

> 路由通 ≠ NAS 端允许。**NAS 通常有三层信任机制**,任一不通过都会"路由通但被拒":

| NAS 端机制 | 检测方式 | 由谁答 |
|---|---|---|
| **IP 白名单**(NAS 防火墙只放行受信网段) | 从 GKE Node 外部 IP 测 TCP 445 是否可达 | infra-gcp |
| **SMB signing 强制**(Windows Server 2022+ 默认要求) | smbclient 握手时观察 `SMB3` 协商结果 | infra-gcp + 公司 IT |
| **AD 域计算机账户**(只允许加入 AD 的机器) | smbclient 会话是否被拒绝(`NT_STATUS_NOT_AUTHENTICATED`) | 公司 IT |

**验证清单**(架构师不下执行令,交给 infra-gcp):

```bash
# 1. TCP 层连通性
kubectl run nas-tcp-test --rm -it --image=ubuntu:22.04 --namespace=debug -- bash
# 容器内: nc -zv nas.address.aibang 445

# 2. SMB 协议层握手
apt-get update && apt-get install -y smbclient cifs-utils
smbclient -L //nas.address.aibang -U <test-account>%<test-password>

# 3. 模拟 GKE Node 视角的 IP(GKE Node 的 external IP)
kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}'
# 用这个 IP 去问 IT:"NAS 信任网络白名单是否包含这个 IP 段?"
```

**答不全的兜底方案**:

- 如果 IP 不在白名单 → 申请公司 IT 把 GKE Node CIDR 加进白名单,或用 NAT gateway 统一出口 IP
- 如果 SMB signing 失败 → 升级 SMB CSI driver 版本,或在 NAS 端放宽 signing 要求(配合 §3.2.3 链路加密评估)
- 如果 AD 域账户被拒 → 让公司 IT 把 GKE Node 加入 AD 域,或申请专用 service account

### 11.5 Q6 新增 — 路由连通性(对业务方反问的明确答复)

**业务方原话**:
> "如果我们的 Egress 能到达对应网络,比如内部底层已经打通了,其实就不需要走 VPN 了,是不是这样?"

**architect-gcp 明确答复**:✅ 是的,这个理解**完全正确**。

**校正点**:ADR-009 §3.2 之前的版本默认假设"必须走 Cloud VPN",这是**错误的**。本轮 review 后已修正为:

- **场景 A(底层路由已打通,业务方现实)** = 直接走内网路由,**不需要 Cloud VPN**
- **场景 B(底层未打通)** = 才需要 Cloud VPN

**新澄清:路由通 ≠ 安全**

即使场景 A 路由直通,仍有两个独立的问题必须答:

1. **链路本身是否加密**(明文 / IPsec / WireGuard / 物理隔离?)
2. **公司合规框架是否接受这条链路上的 SMB 明文**(若 NAS 在另一国家/地区、有数据驻留要求、涉及行业规范)

这两个问题的答案决定了是否需要在场景 A 上**叠加一层 WireGuard/IPsec tunnel**(在 routing 之上),或升级到场景 B(Cloud VPN)。

**实施前必须澄清**(4 个问题,完整见 §3.2.4):

| # | 问题 | 默认假设 | 答 |
|---|---|---|---|
| Q6-a | 底层打通方式是什么?(Interconnect / Peering / WireGuard / 其他) | 未知 | infra-gcp 答 |
| Q6-b | 该链路上 SMB 流量是否加密? | 未知 | infra-gcp + Security 答 |
| Q6-c | 公司合规框架接受这条链路上 SMB 明文吗? | 未知 | Security 答 |
| Q6-d | NAS 端共享 ACL 是否要求"加密 SMB"作为强制项? | 未知 | 公司 IT + infra-gcp 答 |

**任一答案为"否 / 未知"** → 必须在场景 A 基础上叠加 WireGuard/IPsec,或升级到场景 B(Cloud VPN)。

### 11.6 Review 后的决策树更新

基于本次 review,Q2 已确认 + Q4/Q5/Q6 **已假设通过** + G7 链路**强制加密**(企业合规硬要求),**§8 决策树中主路径 A 的前置条件从 4 个扩展为 7 个**,且 G7 不再是软选项:

| # | 原条件 | 状态 | 来源 |
|---|---|---|---|
| G1 | 读写语义 | ⚠ 待业务方答 | §1.3 Q1 |
| G2 | 业务方接受 NetworkPolicy 强制 | ⚠ 待业务方答 | §8.1 |
| G3 | NAS 端 SMB 1.0 已禁用 | ⚠ 待 infra-gcp + IT 验证 | §3.1 |
| G4 | 接受 NAS 不在 GCP 多租户体系内 | ⚠ 待业务方答 | §7 |
| **G5**(新) | NAS 性能影响可接受(< 100 MB 启动读 / 或有 initContainer 预加载方案) | ✅ 假设通过(企业内部 NAS 性能 OK) | §3.2.5 |
| **G6**(新) | NAS 信任网络验证通过(IP / SMB signing / AD 账户) | ✅ 假设通过(GKE Node IP 在白名单) | §11.4 |
| **G7**(新) | 路由连通性 4 个子问题已答 + **企业合规强制加密** | ⚠ 待 infra-gcp + Security 验证(链路加密是硬要求) | §3.2.4 + §3.2.3 强制加密声明 |

**全部 ✅ 才走主路径 A**;否则回到 §8 决策树(B/C 替代方案,或拒绝需求)。

### 11.7 业务方 review 后确认事项汇总(2026-08-28)

| 事项 | 业务方答复 | 影响 |
|---|---|---|
| Q2 挂载范围 | 单个目标 Pod | NetworkPolicy 精确锁定 |
| Q4 性能影响 | 假设无问题(企业内部 NAS 性能 OK) | G5 假设通过 |
| Q5 NAS 信任网络 | 假设已配置(GKE Node IP 在白名单) | G6 假设通过 |
| Q6 路由连通性 | 假设场景 A 成立(底层已打通) | 实施清单第 1 条 **Cloud VPN 略过** |
| **链路合规** | **企业内部强制加密,SMB 明文零容忍** | G7 中 Q6-c 答"否",**必须叠加 SMB Encryption 或 WireGuard** |

### 11.8 配套 ADR-010 任务清单(回填影响)

回填到 §10 下一步清单:

- [ ] 业务方答 §1.3 原始 3 个阻塞问题(Q1 读写语义、Q3 数据归属)
- [ ] infra-gcp + 公司 IT 答 §3.1 NAS 端 SMB 1.0 已禁用(G3)
- [ ] infra-gcp 答 §3.2.4 Q6-a/d(底层打通方式 + NAS 端加密 SMB 强制项)
- [ ] infra-gcp + 公司 IT 验证 §11.4 G6 假设是否成立(NAS 信任网络 3 个机制)
- [ ] Security 答 §3.2.3 G7 加密合规(SMB Encryption 或 WireGuard 任一必选)
- [ ] **架构师沉淀** —— 把"infra-gcp profile 必须有专属 GCP identity(SA,非借 user OAuth)"写进 ADR-011 或 §13,作为永久纪律
- [ ] 上述全部 ✅ → 决策走 A → 生成 ADR-010 实施细节

---

## 13. Bot 协作纪律 —— Agent vs 真人身份边界(2026-08-28 review 沉淀)

> **本节回应 infra-gcp 跨轮 push back 暴露的系统性问题**:infra-gcp 误把 architect-gcp(Hermes agent)当成 <DECISION_MAKER>(真人),连续两轮等 architect-gcp 刷 gcloud auth。**这是 4-Bot team 协作的架构级教训**,必须就地文档化。

### 13.1 实体矩阵

| 实体 | 类型 | 有本机? | 有浏览器? | 有 GCP 身份? | 能 gcloud auth login? |
|------|------|----------|-----------|--------------|----------------------|
| **<DECISION_MAKER>** | 真人 | ✅ | ✅ | ✅ wide-scope user OAuth | ✅ |
| **architect-gcp** | Hermes agent | ❌ | ❌ | ❌(也不该有) | ❌ |
| **infra-gcp** | Hermes agent | ❌ | ❌ | **应有自己的专属 SA** | ❌(无浏览器) |
| **devops-gcp** | Hermes agent | ❌ | ❌ | 应有自己的专属 SA | ❌ |
| **qa-gcp** | Hermes agent | ❌ | ❌ | 应有自己的专属 SA | ❌ |

### 13.2 关键规则(永久,违反即红线)

1. **每个 agent profile 必须有专属 GCP identity**(推荐:SA + 最小权限,**不**借真人 OAuth)
3. **agent 不能借真人 OAuth** —— `~/.config/gcloud/` 下的 user token 是 <DECISION_MAKER> 真人的 wide-scope,**agent 一旦共用就违反最小权限 + 审计隔离**
2. **agent 不"刷 auth"** —— agent 跑在沙盒里,**没有浏览器**,交互式 auth 物理上不可能
3. **agent 卡的 GCP 阻塞项,push back 给真人,不 push back 给 architect** —— architect 是 agent,不刷 auth
4. **architect 不下场跑 gcloud / kubectl / terraform apply** —— 跨 lane 协调,不执行

### 13.3 后果(为什么这条规则重要)

- **审计失效**:真人 OAuth 是 wide-scope,所有 agent 用同一个 token,审计无法区分"谁跑的命令"
- **权限失控**:agent 拿到真人 wide-scope token = 拥有真人所有 GCP 权限,**违反最小权限**
- **边界破窗**:一次破例后,agent 默认会持续借,最后架构师 / infra-gcp / devops-gcp / qa-gcp 都用同一个 token,**整个 4-Bot team 身份隔离崩溃**

### 13.4 解决方案:profile-specific SA + 最小权限(infra-gcp 推荐路径)

参考 infra-gcp 提的路径 (b):

```
/Users/${USER}/.hermes/profiles/infra-gcp/secrets/infra-gcp-sa.json
```

- 每个 agent profile 一个 SA
- SA key 放 profile 专属目录,**其他 profile 不可读**
- 最小权限:Q6-a 验证只需要 `compute.networks.list/read` + `compute.interconnects.list` + `compute.vpnTunnels.list` + `compute.routers.list` + `compute.interconnectAttachments.list`
- `gcloud auth activate-service-account --key-file=...` 后立即能用,无需浏览器

### 13.5 触发红线时的应对(架构师视角)

如果未来任何 agent 再次出现 "等 architect-gcp 刷 auth" / "architect-gcp 本机" / "architect-gcp 跑 gcloud" 的假设:

1. **架构师立即 push back 一次**(已做了两次)
2. **如果仍不修正** → 主动叫停 + 上报 <DECISION_MAKER>,不继续 holding pattern
3. **不礼貌性沉默** —— 沉默会让对方误以为假设成立,下次还犯

### 13.6 跨 ADR 引用

本节作为**永久纪律**,应在未来所有 Bot 协作的 ADR / handoff message 顶部加一行:

> **前置提醒** — Bot 协作的实体矩阵见 [ADR-009 §13](../gcp/storage/nas/ADR-009-gke-pod-mount-internal-nas-security-review.md#13)。每个 agent 必须有自己的 GCP identity,不借真人 OAuth,不指望 architect-gcp 跑 gcloud。

---

## 12. 概念澄清 —— Pod 挂 NAS 跟 PV/PVC 到底是什么关系

> **本节回应业务方的核心疑问**:"我只是想挂个 NAS,为什么一定要先有 PV?PV 是 GCP PD 的东西,跟 NAS 有什么关系?"
>
> 这个疑问非常合理 — 业务方之前的认知是"PV = GCP Persistent Disk",所以看到 ADR 里写"创建 PV/PVC"会本能地觉得"是不是把 NAS 数据复制到 GCP 的盘上了?"**完全不是**。
>
> 本节用 3 个层次 + 一张时序图把这件事讲清楚。

### 12.1 核心结论(一句话)

> **PV/PVC 是 Kubernetes 的"通用抽象" —— 它不是 GCP PD 的专属概念。PV 的 `spec.csi.driver` 字段决定了"底层到底是什么存储系统",所以同一个 PV/PVC 机制,可以挂 GCP PD,可以挂 Filestore NFS,可以挂公司 NAS SMB,也可以挂 AWS EBS。PV 是"壳",CSI driver 才是"肉"。**

### 12.2 三个层次的理解

#### 层次 1:Kubernetes 把"挂存储"这件事抽象成 3 个角色

```
┌────────────────────────────────────────────────────────────────────┐
│  Pod spec 里写:                                                    │
│    volumes:                                                        │
│    - name: nas-app-folder                                          │
│      csi:                                                          │
│        driver: smb.csi.k8s.io          ← ① "用什么工具挂"          │
│        readOnly: true                                              │
│        volumeAttributes:                                           │
│          source: "//nas.address.aibang/hk/gsd/application"          │
│        nodePublishSecretRef:                                      │
│          name: nas-smb-credentials                                  │
│    containers:                                                     │
│    - volumeMounts:                                                 │
│      - name: nas-app-folder                                        │
│        mountPath: /mnt/nas               ← ② "容器里看到什么路径"   │
└────────────────────────────────────────────────────────────────────┘
```

**Pod 不直接说"挂 NAS",而是说"挂一个卷"`volumes:`** —— 它只描述:**我需要一块文件系统,在容器里是 `/mnt/nas`**。**它不知道也不关心底层是什么存储系统**。

#### 层次 2:PV 是"卷的身份证",PVC 是"卷的申请单"

K8s 把"卷"也抽象成 API 对象(PV / PVC),这是为了**让 Pod 不需要关心卷的具体技术细节**:

| 概念 | 角色 | 类比 |
|---|---|---|
| **PV(PersistentVolume)** | **卷本身** — 集群范围的资源,声明"我代表一块存储" | 仓库里的一台货架 |
| **PVC(PersistentVolumeClaim)** | **卷的申请单** — Pod 所属 namespace 下的资源,声明"我需要一块什么样的存储" | 业务方填的领料单 |
| **Pod + volumeMounts** | **使用方** — 实际 mount 到容器文件系统的某个路径 | 工人把料搬到自己工位 |

**核心机制**:
- Pod 写 `volumes:` 引用 PVC 名字(或直接引用 PV)
- PVC 跟 PV 通过 `claimRef` / `selector` / `storageClassName` 匹配
- 匹配上后,PV 的细节(`spec.csi.driver` / `volumeHandle` / `volumeAttributes`)就被 Kubelet 拿去执行实际的 mount 操作

#### 层次 3:CSI driver 是"翻译官" —— 把 K8s 的抽象翻译成具体存储的 API

```
┌──────────────────┐       ┌──────────────────┐       ┌──────────────────────┐
│ Pod              │       │ Kubelet          │       │ CSI driver           │
│ (容器内 /mnt/nas)│ ←──→  │ (节点级)         │ ←──→  │ (DaemonSet,特权)     │
│                  │       │  知道"该挂哪个   │       │  知道"怎么跟具体存储 │
│  不关心底层       │       │   存储"           │       │   系统说话"           │
└──────────────────┘       └──────────────────┘       └──────────────────────┘
                                                                │
                                                                │ SMB over TCP 445
                                                                ▼
                                                       ┌──────────────────┐
                                                       │ 公司 NAS          │
                                                       │ nas.address.aibang│
                                                       └──────────────────┘
```

**关键点**:
- `smb.csi.k8s.io` 这个 CSI driver 是 K8s 社区官方项目,GA,K8s 1.21+ 支持
- 它以 **DaemonSet** 形式跑在每个 GKE Node 上(privileged,允许做节点级 mount)
- 它收到 Kubelet 的"挂载这个 SMB 共享"指令后,会用 SMB 协议去连 NAS,把 NAS 的共享目录 mount 到节点的本地路径(比如 `/var/lib/kubelet/pods/<pod-uid>/volumes/...`),然后 bind mount 到容器内 `/mnt/nas`
- **整个过程 NAS 文件物理上仍然在公司 NAS 上,没有任何数据拷贝到 GCP**

### 12.3 完整时序图 —— Pod 启动 → 挂 NAS 成功

```
时间轴   Pod                              Kubelet                CSI driver (smb.csi.k8s.io)           公司 NAS
  │      │                                  │                              │                              │
  │  ①   │  kubectl apply pod.yaml         │                              │                              │
  │ ───► │                                  │                              │                              │
  │      │                                  │                              │                              │
  │  ②   │                                  │  调度器把 Pod 分配到 Node A   │                              │
  │      │  Pending → ContainerCreating    │ ◄── schedule                │                              │
  │      │                                  │                              │                              │
  │  ③   │                                  │  检测到 volumes[].csi       │                              │
  │      │                                  │  → 调用 CSI driver NodePublishVolume       │
  │      │                                  │ ─────────────────────►       │                              │
  │      │                                  │                              │                              │
  │  ④   │                                  │                              │  读 Secret nas-smb-credentials│
  │      │                                  │                              │  (从 K8s API)                │
  │      │                                  │                              │                              │
  │  ⑤   │                                  │                              │  SMB TCP 445 连接到 NAS      │
  │      │                                  │                              │ ────────────────────────────► │
  │      │                                  │                              │                              │
  │  ⑥   │                                  │                              │  Negotiate Protocol (SMB 3.1.1)
  │      │                                  │                              │  Session Setup (auth)        │
  │      │                                  │                              │  Tree Connect (挂载共享)    │
  │      │                                  │                              │ ◄──────────────────────────── │
  │      │                                  │                              │                              │
  │  ⑦   │                                  │                              │  在 Node A 本地: mount -t cifs │
  │      │                                  │                              │  //nas.address.aibang/hk/gsd  │
  │      │                                  │                              │  → /var/lib/kubelet/pods/...  │
  │      │                                  │ ◄─────── 完成 ────────        │                              │
  │      │                                  │                              │                              │
  │  ⑧   │  Container 启动                  │  bind mount 进容器 namespace │                              │
  │      │  /mnt/nas 真实可见 ───────────►   │                              │                              │
  │      │  (容器内 read/open() 直接走 NAS)  │                              │                              │
  │      │                                  │                              │                              │
  ▼      ▼                                  ▼                              ▼                              ▼
```

**关键观察**:
- 步骤 ①-③ 是 K8s 调度流程,与存储无关
- 步骤 ④-⑦ 是**核心挂载动作**,全部由 CSI driver 跟 NAS 之间的 SMB 协议完成
- 步骤 ⑧ 容器启动后,`/mnt/nas` 直接读到的就是 NAS 上的文件 —— **NAS 文件不在 GCP 上**
- **NAS 文件没有任何拷贝动作**;Pod 的 read/open 是直接走 SMB 协议到公司 NAS

### 12.4 PV / PVC / GCP PD / NAS 的关系(一张图)

```
                    ┌────────────────────────────────────┐
                    │ K8s 通用抽象                       │
                    │  ┌─────────┐         ┌──────────┐ │
                    │  │  PV     │◄───绑定─┤  PVC     │ │
                    │  └────┬────┘         └────┬─────┘ │
                    │       │                   │       │
                    │  spec.csi.driver 决定走哪条路:    │
                    │       │                   │       │
                    └───────┼───────────────────┼───────┘
                            │                   │
              ┌─────────────┼───────────────────┼─────────────┐
              │             │                   │             │
              ▼             ▼                   ▼             ▼
      ┌────────────┐  ┌────────────┐    ┌────────────┐  ┌────────────┐
      │ pd.csi...  │  │ nfs.csi... │    │ smb.csi... │  │ 其他       │
      │ GCP PD     │  │ Filestore  │    │ 公司 NAS   │  │ (EBS,...)  │
      │ (block)    │  │ (NFS)      │    │ (SMB)      │  │            │
      └────────────┘  └────────────┘    └────────────┘  └────────────┘
            ▲               ▲                  ▲
            │               │                  │
       既有 PV 设计    替代方案 B          本 ADR 主体
       (PD 体系)       (Filestore)        (NAS 路径)
```

**结论**:
- PV 是抽象,**不是某一种存储的代名词**
- 同一个 K8s 集群里,可以同时存在 PV-A 指向 GCP PD、PV-B 指向 Filestore、PV-C 指向公司 NAS
- 业务方只需要"申请 PVC",**不需要知道 PV 底层是什么存储系统** —— 这是 K8s 抽象的好处
- 对 ADR-009 来说:**挂 NAS 跟 PV 体系完全兼容**,只是 CSI driver 从 `pd.csi.storage.gke.io`(GCP)换成 `smb.csi.k8s.io`(SMB)而已

### 12.5 对业务方的明确答复

| 业务方疑问 | 答复 |
|---|---|
| "我只是想挂 NAS,为什么要先有 PV?" | PV 是 K8s 的抽象概念,跟"什么存储系统"无关。挂 NAS 跟挂 GCP PD 一样,都需要 PV/PVC 这个 K8s 抽象 |
| "PV 是不是把 NAS 数据复制到 GCP 的盘上了?" | **完全不是**。PV 在 K8s 里只是一份"卷的声明文件",不存任何数据。CSI driver 接到 mount 指令后,直接走 SMB 协议到公司 NAS,**NAS 数据物理上始终在公司 NAS 上** |
| "那 PVC 是不是数据容器?" | PVC 是"我要申请一块存储"的声明,跟 Pod 申请 CPU/内存是一类东西。**PVC 不是数据**,只是一个 API 对象 |
| "如果 Pod 重建,数据会丢吗?" | **不会丢**。NAS 数据在 NAS 上,跟 Pod 生命周期无关。Pod 删除/重建后,CSI driver 重新挂载,`/mnt/nas` 看到的是同一份 NAS 数据 |
| "挂 NAS 跟以前设计 GCP PV 多租户有什么冲突?" | **有冲突**(详见 §7)。PV 多租户设计的 CMEK / labels / Tenant CRD.scAllowlist 只对 GCP 内存储生效;NAS 走 `smb.csi.k8s.io`,**完全绕过**这套体系。这是 §7 + §11 修补路径要解决的问题 |

---

> **作者声明**:本 ADR 仅评估挂载 NAS 在 GKE 中的技术可行性与安全风险,**不就业务本身的合规性做结论**。若业务方对"读取公司 NAS"是否触犯其他合规约束(数据驻留、跨境、行业规范)有疑问,需走法务/合规审查。
