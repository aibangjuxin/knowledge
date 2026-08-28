# ADR-009 · 决策树清单(GKE 挂 NAS)

> **A 是主路径**(用户原始需求,**不替业务方迁移数据**)。B/C 是**可行性参考**,只在业务方对原始需求松动时才考虑。
>
> 详细分析见 [`ADR-009-gke-pod-mount-internal-nas-security-review.md`](./ADR-009-gke-pod-mount-internal-nas-security-review.md) §8。

---

## 路线总览

| 路线 | 协议 | GCP 内/外 | 数据迁移 | 多租户隔离 | 复杂度 | 推荐场景 |
|---|---|---|---|---|---|---|
| **A · NAS 原状加固** | SMB 3.1.1 | **外**(公司内网) | 无 | ❌ 失效,需修补 | 中 | **用户原始需求** |
| **B · GCP Filestore** | NFSv3/v4 | 内(GCP VPC) | **需迁移** | ✅ 完整 PV 体系 | 低 | 业务方同意迁移,NFS 可接受 |
| **C · NetApp Volumes** | SMB 3.0+ | 内(GCP VPC) | **需迁移** | ✅ PV 体系 + SMB 协议 | 中 | 业务方同意迁移,强需求 SMB |

---

## 主路径 (A) 详表

### A 的 7 个治理问题(必须全部 ✅)

**本节经 review 扩展**(原 4 个 + 新增 3 个 G5/G6/G7,完整对应 ADR-009 §11.6):

| # | 问题 | 必须的答案 | 影响 |
|---|---|---|---|
| G1 | 读写语义 | **read-only 优先**(除非业务方有具体理由 + 走审批) | ro = 单向数据流;rw = 双向 = 复杂度 +1 档 |
| G2 | 业务方是否接受 NetworkPolicy 强制 | ✅ | 不接受 = 不上线 |
| G3 | NAS 端 SMB 1.0 是否已禁用 | ✅ | SMB 1 = 历史漏洞多发,任何版本都不允许 |
| G4 | 是否接受 NAS 不在 GCP 多租户体系内 | ✅ | 默认接受,后续补 §7.1 修补路径 |
| **G5**(新) | NAS 性能影响可接受 | ✅ **假设通过**(业务方 review 答复"企业内部 NAS 性能 OK") | NAS > 500 MB 或热读 = 改走 B/C 路径 |
| **G6**(新) | NAS 信任网络验证通过(IP / SMB signing / AD 账户 3 个机制) | ✅ **假设通过**(业务方答复"GKE Node IP 在白名单") | 任一不通 = 走兜底方案(白名单申请 / driver 升级 / AD 加入) |
| **G7**(新) | 路由连通性 + **企业合规强制加密** | ⚠ 待 infra-gcp + Security 验证(链路加密是硬要求) | 任一"否/未知" = 叠加 SMB Encryption 或 WireGuard |

### A 的实施清单(交 infra-gcp,**场景 A 修订版 — 业务方 2026-08-28 review**)

1. ☐ ~~Cloud VPN tunnel 搭建~~ **场景 A 业务方答复:企业内部路由已通,此项略过**
2. ☐ **SMB 加密合规**(G7 强制项二选一):
   - ☐ NAS 端开启 SMB Encryption(Windows Server 2012+ 支持,SMB 3.0+ 才生效),或
   - ☐ 在路由之上叠加 WireGuard / IPsec tunnel
3. ☐ SMB CSI driver 安装(DaemonSet,独立 `csi-system` namespace,privileged)
4. ☐ NAS 凭据 Secret 创建(KSA-bound,不在 manifest 留明文)
5. ☐ PV / PVC 创建(readOnly: true,**绑到单个目标 Pod**)
6. ☐ NetworkPolicy 应用(精确锁定单一 Pod → TCP 445 only,场景 A 下还允许 → 公司内网 CIDR)
7. ☐ PodSecurity:`api-ns` 标 `baseline`,目标 Pod 标 `restricted`
8. ☐ Audit:SMB 端 event log 开启;GKE audit log 验证;监控 `smb_request_duration_seconds` P99
9. ☐ 文档:`gke-pv-multi-tenant-design.md` 增加 "§11 NAS 例外路径"

### A 的代价

| 维度 | 代价 |
|---|---|
| **安全** | 纵深防御靠 NetworkPolicy + PodSecurity + 凭据 Secret + NAS ACL,**任一失效就破** |
| **审计** | GKE 侧和 NAS 侧审计**断链**,事件关联需手工 |
| **多租户** | CMEK / labels / quota 全失效,需补 NasSharePolicy 体系 |
| **成本** | **场景 A**:跨网链路流量费(按 GB,但比 Cloud VPN 便宜)+ NAS 端 SMB 性能开销;<br>**场景 B**:Cloud VPN 流量费 + 跨公网加密延迟 |
| **运维** | NAS 端 SMB 升级 / 共享权限变更 / 链路故障 = 平台停摆,需 runbook |

---

## 替代方案 (B) — GCP Filestore(NFS)

### B 的关键事实

| 维度 | 评价 |
|---|---|
| **原理** | Filestore 是 GCP 托管 NFS,与 GKE 在同一 VPC,**免 VPN** |
| **协议** | NFSv3 / NFSv4(非 SMB) |
| **隔离** | 走回 GCP PD 体系,CMEK / labels / quota **全部生效** |
| **最小实例** | 1 TiB(最小档,可能比 NAS 现有容量大) |
| **支持的 GKE 版本** | 随 Kubernetes minor 版本(由 Filestore service tier 决定) |
| **Linux only** | Filestore CSI driver **不支持 Windows node** |

### B 适用场景

- ✅ NAS 数据**可整体迁移**(用 `rsync` / Storage Transfer Service)
- ✅ 应用层**接受 NFS 协议**(Linux/macOS 原生,Windows 需客户端)
- ✅ 延迟敏感(免 VPN,延迟 < 1ms)
- ✅ 需要 CMEK 隔离

### B 的代价

| 代价 | 备注 |
|---|---|
| **数据迁移** | 全量迁移 + 增量同步;同步期间需 NAS + Filestore 双写 |
| **最小 1 TiB** | 若 NAS 实际只用 100 GiB,Filestore 仍按 1 TiB 计费 |
| **Linux only** | 若有 Windows node / 应用,NFS 不通 |

来源:[GKE Filestore CSI driver](https://cloud.google.com/filestore/docs/csi-driver)

---

## 替代方案 (C) — Google Cloud NetApp Volumes(SMB)

### C 的关键事实

| 维度 | 评价 |
|---|---|
| **原理** | Google Cloud NetApp Volumes 提供 **SMB 协议** 的托管文件存储(企业级 ONTAP) |
| **协议** | SMB 3.0+ |
| **隔离** | 同样在 GCP 内,CMEK / VPC Service Controls 可用 |
| **GA 状态** | 部分区域 GA,部分区域 Preview(部署前需确认 region) |

### C 适用场景

- ✅ NAS 数据**可迁移**
- ✅ 应用层**强需求 SMB 协议**(不想改应用代码)
- ✅ 企业级特性需求(snapshots, multi-protocol access, performance tiering)
- ✅ 接受成本高于 Filestore

### C 的代价

| 代价 | 备注 |
|---|---|
| **数据迁移** | 同 B |
| **成本** | 高于 Filestore(企业级定价) |
| **GA 不全** | 部分 region 未 GA,需提前确认 |
| **Vendor 锁定** | NetApp 专有 feature,迁移到其他云不通用 |

来源:[Google Cloud NetApp Volumes](https://cloud.google.com/netapp-volumes)

---

## 禁用方案

| 方案 | 禁止原因 |
|---|---|
| NAS 直连公网(端口转发 / DMZ) | 任何拿到 IP 的人都能尝试 SMB 暴力破解;违反零信任 |
| 整个 namespace 共享一个 NAS PVC | 横向访问面 = namespace × Pod count;违反最小权限 |
| privileged Pod + hostPath 直挂 | 旁路 CSI driver 的所有审计;违反 PodSecurity restricted |
| NAS 凭据写在 Pod manifest env | 凭据泄漏 → 任何人 `kubectl get pod -o yaml` 即可拿到 |

---

## 决策流程

```
        ┌────────────────────────────┐
        │ 业务方原始需求: 挂 NAS     │
        └─────────────┬──────────────┘
                      │
                      ▼
        ┌────────────────────────────┐
        │ 数据能否迁移出 NAS?       │
        └──────┬──────────────┬──────┘
               │              │
              NO             YES
               │              │
               ▼              ▼
        ┌──────────┐    ┌────────────────┐
        │ 走路径 A │    │ 应用能接受 NFS? │
        └────┬─────┘    └───┬────────┬───┘
             │              YES       NO
             │              │         │
             ▼              ▼         ▼
        ┌──────────┐   ┌────────┐ ┌────────┐
        │ 4 个治理 │   │ 走 B   │ │ 走 C   │
        │ 问题全通?│   │        │ │        │
        └──┬───┬───┘   └────────┘ └────────┘
          YES  NO
           │   │
           ▼   ▼
        ┌────┐ ┌────────────────┐
        │实施│ │ 拒绝 + 回到 B/C │
        └────┘ └────────────────┘
```

---

## 推荐结论

> **如果业务方对"挂 NAS"是硬需求(数据不动):走 A,但必须先答完 4 个治理问题。**
>
> **如果业务方对"挂 NAS"是软需求(可协商):优先推荐 B(NFS / Filestore),其次 C(SMB / NetApp)。A 仅作为最后选项。**

---

## 下一步

- ADR-009 待 review(infra-gcp / devops-gcp / qa-gcp 各自 lane)
- 业务方澄清 §1.3 的 3 个阻塞问题 + §8.1 的 4 个治理问题
- 如决策走 A:生成 ADR-010(实施细节) + handoff 给 infra-gcp
- 如决策走 B/C:生成 ADR-010(迁移方案) + 触发 Storage Transfer Service / NetApp Volume 设计
