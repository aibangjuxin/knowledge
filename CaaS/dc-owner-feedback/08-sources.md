# 08 · 权威证据清单

> **为什么有这个文件.** 我在 `03-gcp-capability-profile.md` 里写的每条 GCP 结论都应当可追溯。
> RFC §8 明确要求画像记录能力状态;我在 `07-decisions-and-open-questions.md` D2 里进一步建议
> **每条结论带出处 + 查阅日期 + 新鲜度**。这个文件就是那条规则的第一版实例。
>
> **⚠️ 查阅日期:2026-09-29。** 超过 12 个月请重新核对(D2 规则)。

---

## 1. GKE 生命周期与版本

| 主题                             | 结论                                                                 | 来源                                                                                   |
| -------------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 版本支持窗口                     | 标准支持 14 个月 + 扩展支持 10 个月(Extended channel,额外按集群收费)= 最长 24 个月 | <https://docs.cloud.google.com/kubernetes-engine/versioning>                          |
| release channel 语义             | Rapid/Regular/Stable/Extended;**Rapid 明确排除在 GKE SLA 之外**     | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels>       |
| Extended channel 收费            | 需额外费用,按集群                                                  | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels>       |
| 版本发布与 EOL 日程表             | 各 minor 版本的确切日期以此表为准(逐月更新)                          | <https://docs.cloud.google.com/kubernetes-engine/docs/release-schedule>                |
| **控制面 90 天升级底线**          | **GKE 要求控制面至少每 90 天升一次 patch;超时 GKE 自动升级**          | <https://docs.cloud.google.com/kubernetes-engine/versioning>                          |
| **EOL 强制升级**                  | 到 EOL 时 GKE 强制升级,maintenance exclusion 无法阻止(紧急情况除外)   | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels>       |
| minor 升级频次                    | 约每年 3 次                                                          | <https://docs.cloud.google.com/kubernetes-engine/upgrades>                             |
| **两步升级(1.33+)**               | 从 1.33 起 minor 升级采用两步,可 soak、可回滚;1.33 之前不是          | <https://docs.cloud.google.com/kubernetes-engine/upgrades>                             |
| 版本倾斜约束                     | 节点不得落后控制面 2 个 minor 以上                                    | <https://docs.cloud.google.com/kubernetes-engine/upgrades>                             |
| maintenance exclusion             | 频道内集群可禁 minor 升级至 EOL;"No upgrades" 范围最多 90 天          | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/release-channels>       |
| **Rollout sequencing(灰度编排)**  | 需集群归入 **fleet**;每序列最多 5 组;soak 上限 30 天;需 `roles/gkehub.editor` | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/rollout-sequencing/manage-upgrades-with-rollout-sequencing> |
| Rollout sequencing(自定义阶段)   | 可用 label selector 选子集;需每 fleet 有 catch-all 阶段              | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/rollout-sequencing-custom-stages/manage-upgrades-with-rollout-sequencing> |

---

## 2. 配额与硬限制

| 主题                       | 结论                                                                    | 来源                                                                        |
| -------------------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 集群数量配额               | 每 zone 50 个 + 每 region 50 个 regional 集群(**默认配额,可申请调整**) | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| **Pods / Containers per cluster** | 200,000 Pods / 400,000 containers(Standard 与 Autopilot 同)              | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| **etcd 数据库大小**         | **6 GB**(集群级硬限制)                                                 | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| **并发操作数**              | **100**(集群级)—— 批量操作编排时会撞到                                  | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| API 读写配额                | 存在 API reads / API writes 项目级配额,**批量发现/对账会大量消耗**      | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| **Autopilot 集群配额**     | **Autopilot 集群预置为 regional 集群**,因此吃 regional 集群配额          | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| 节点数/集群                | Standard 最高 65,000(分档有基础设施要求);Autopilot 5,000               | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| 节点数/节点池/zone         | Standard 1,000(**硬限制**);Autopilot 不适用(无节点池)                   | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| Pods per node              | Standard 256(1.23.5 之前为 110);Autopilot 动态 8–256                    | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| **Accelerator / Performance 类 Pod** | **每节点仅限 1 个 Pod**                                            | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| TPU 节点数                 | 每 zone 2,000                                                          | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| **`gke-resource-quotas`**   | **节点数 <100 的集群,GKE 自动对每个 namespace 施加不可删除的资源配额,随节点数缩放** | <https://docs.cloud.google.com/kubernetes-engine/quotas> |
| 集群内配额不可删除          | 该配额由 GKE 施加,**不能移除**                                         | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |
| 查询方式                   | `kubectl get resourcequota gke-resource-quotas -o yaml`                  | <https://docs.cloud.google.com/kubernetes-engine/quotas>                  |

---

## 3. 身份与访问

| 主题                         | 结论                                                             | 来源                                                                                   |
| ---------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Workload Identity Federation | KSA ↔ GSA 通过 SA 注解 + GSA 上的 `roles/iam.workloadIdentityUser` binding 建立 | <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity>             |
| Workload Identity 启用范围     | 集群级可用 `gcloud container clusters update --workload-pool` 开启;**已存在的节点池不受影响**,需逐个 `node-pools update --workload-metadata GKE_METADATA`(触发滚动升级) | <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity> |
| **KSA 注解与 IAM binding**      | **可增删改** —— 在集群/节点池启用 WI 后,SA 注解与 GSA 上的 `roles/iam.workloadIdentityUser` binding 均可变更 | <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity> |
| **IAM 传播延迟**                | IAM binding 授权后**最长约 60 秒**生效                                 | <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity> |
| **跨项目访问**                  | GSA 需在**目标项目**具备权限,仅在集群所属项目有权限是不够的           | <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity> |
| 默认 SA 未配置 WI              | 每个 namespace 的默认 KSA **不自动**配置 Workload Identity           | <https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity> |
| 组织策略约束                 | 可管 `container.autopilotPrivilegedAdmission` 等                | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-autopilot-privileged-workloads> |
| **Autopilot 特权工作负载**   | 默认拒绝 privileged 容器;需 `WorkloadAllowlist` + `AllowlistSynchronizer`;**GKE 1.35+** | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-autopilot-privileged-workloads> |
| 最佳实践:先拒绝再放行       | 建议 org policy 设为"deny all, then allow some"                  | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/about-autopilot-privileged-workloads> |

---

## 4. Autopilot 能力边界

| 主题             | 结论                                                                 | 来源                                                                                 |
| ---------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 禁 privileged    | Autopilot **默认阻止** privileged 容器,例外为 partner 工作负载     | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |
| hostPath 限制    | 仅允许对 `/var/log` 前缀的**只读**访问                              | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |
| **禁 hostNetwork** | 无 hostNetwork(节点由 GKE 管理)                                    | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |
| seccomp           | 对所有 Pod 应用 `RuntimeDefault`,除非使用 GKE Sandbox              | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |
| 禁写态 hostPath  | hostPath 写模式被禁;仅只读 `/var/log`                               | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |
| GKE 托管命名空间  | 不允许向 GKE 托管命名空间(如 `kube-system`)部署工作负载             | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |
| 禁 unsafe sysctls | 策略规则拒绝使用不安全 sysctls 的 Pod                               | <https://docs.cloud.google.com/kubernetes-engine/docs/concepts/autopilot-security>    |

---

## 5. 机密计算

| 主题                     | 结论                                                                | 来源                                                                     |
| ------------------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| GA 时间                  | **2023-02-16 GA**,限 general purpose N2D / compute optimized C2D     | <https://cloud.google.com/blog/products/identity-security/announcing-general-availability-of-confidential-gke-nodes> |
| **不兼容 sole-tenant**   | Confidential GKE Nodes **不兼容 sole tenant nodes**                  | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes> |
| **仅 local SSD 临时存储** | **仅支持 local SSD 上的临时存储**,不支持一般 local SSD              | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes> |
| **不支持 Windows**       | 仅支持 Container-Optimized OS 与 Ubuntu 节点镜像                    | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes> |
| 节点自动配置限制         | NAP 仅支持 AMD SEV / SEV-SNP,需在节点池级别配置                    | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes> |
| Hyperdisk Balanced 限制  | Confidential mode 仅支持 AMD SEV 的 Confidential GKE Nodes;受 CMEK 限制 | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes> |
| 关闭需重建节点          | 禁用该特性需要重建节点,可能影响工作负载                              | <https://docs.cloud.google.com/kubernetes-engine/docs/how-to/confidential-gke-nodes> |

---

## 6. 策略、漂移与治理

| 主题                       | 结论                                                                    | 来源                                                                                   |
| -------------------------- | ------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| **Policy Controller**      | 基于 Gatekeeper;`enforcementAction` 支持 `deny` / `warn` / `dryrun`      | <https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/auditing-constraints> |
| 审计既有资源               | 可回溯审计**已存在**资源,不止拦截新变更                                | <https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/auditing-constraints> |
| **审计结果有上限**          | 当违规数超出上限时,超出部分**只计入 `totalViolations`,不列出明细** —— 证据包不能把计数当清单 | <https://open-policy-agent.github.io/gatekeeper/website/docs/audit/> |
| **被 admission 拒绝的违规** | **不写入日志**(只出现在 admission 响应里)→ 仅靠日志做证据会漏                | <https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/auditing-constraints> |
| 审计结果查询               | 违规追加到 Constraint 对象,audit 过程写入日志(被 admission 拒绝的不写日志) | <https://docs.cloud.google.com/kubernetes-engine/policy-controller/docs/how-to/auditing-constraints> |
| **Config Sync**            | 持续检测配置漂移并修复                                                  | <https://docs.cloud.google.com/kubernetes-engine/config-controller/docs/overview>       |
| **Config Controller**      | 托管版 Config Connector + Policy Controller + Config Sync 三件套         | <https://docs.cloud.google.com/kubernetes-engine/config-controller/docs/overview>       |
| 漂移检测与修复             | 文档明确将"自动检测并修复基础设施漂移"列为收益                            | <https://docs.cloud.google.com/kubernetes-engine/config-controller/docs/overview>       |
| Policy Bundle              | 官方维护的策略包,可作基线起点                                           | <https://docs.cloud.google.com/kubernetes-engine/policy-controller>                      |

---

## 7. 网络

| 主题                        | 结论                                                          | 来源                                                                                       |
| --------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| **Pod IP 泄漏(DPV2)**       | GKE Dataplane V2 存在容器运行时 bug 导致节点 Pod IP 泄漏耗尽;**官方提供清理 DaemonSet 缓解方案** | <https://docs.cloud.google.com/kubernetes-engine/networking/docs/known-issues> |
| 触发版本                     | 1.28.15-gke.1024000+ / 1.29.10+ / 1.30.8+ / 1.31.2+ / 1.32+ / 1.33+ | <https://docs.cloud.google.com/kubernetes-engine/networking/docs/known-issues>            |
| **设备插件 socket 名长度**   | 网络对象名**超过 41 字符**导致 device plugin bind 失败(Linux socket 路径上限 107 字节) | <https://docs.cloud.google.com/kubernetes-engine/networking/docs/known-issues>            |
| legacy network LB 中断      | legacy network 上 Ingress / Service LB 可能中断,1.33.1+ 修复  | <https://docs.cloud.google.com/kubernetes-engine/networking/docs/known-issues>            |

---

## 8. 我未能在本次核对中确认的(诚实留白)

| 主题                             | 状态           | 建议动作                                        |
| -------------------------------- | -------------- | ----------------------------------------------- |
| 跨项目 LB 绑定的具体 IAM 与 Service Directory 限制 | ⬜ **未核实** | 见服务网格/网络立场确认时一并查                 |
| GKE 上 etcd 备份的等价保障       | ⬜ **未核实**  | 与厂商确认托管控制面的备份承诺                   |
| Filestore regional 的具体支持范围 | ⬜ **未核实**  | 查 Filestore 文档                                 |
| Cluster API Provider GCP (CAPG) 生产可用性 | ⬜ **未核实** | 注意:其官网支持表仍停留在 v1beta1 / K8s 1.22,**与 GKE 现状严重脱节** |
| 各区域 GPU 机型可得性            | ⬜ **未核实**  | 以 `gcloud compute machine-types list` 实际查询为准 |
| DC 真实配额现值                  | 🔶 **需 DC 提供** | 只有你有这个数                                     |
| caep Kubernetes Security Standard | ⬜ **需安全架构师提供** | RFC §11 自己说明了该文档需 Confluence 认证,本机无法获取 |

> **关于 CAPG 的一句提醒**:如果你在 `caas-cluster-api.md` 里考虑用 Cluster API 作为底层,
> 请注意 **CAPG 官方支持策略页显示的兼容矩阵停留在 Cluster API v1beta1 / Kubernetes 1.22**。
> 这不代表 CAPG 不能用(社区维护活跃),但**它意味着 CAPG 落后于 GKE 的实际版本节奏** ——
> 而 GKE 现在已经在 1.35/1.36 了。这个差距要在 RFC 里讲清楚,否则 CaaS 排期会低估。
> 建议:若走 CAPG 路线,在 §8 能力目录里明确"Day-0 基础设施由 CAPI 承载,
> 版本兼容性由 CaaS 自行维护",不要假设 CAPG 会跟上 GKE。

---

## 8b. 跨云对比证据(2026-09-29 补充,支撑 `15-cross-cloud-framework.md`)

> **用途**:验证"版本长支持默认值"这一跨云论断。**这一节不是 GCP 事实,是横向对比证据。**

| 主题                     | GCP GKE                                                       | AWS EKS                                                                  | Azure AKS                          |
| ------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------- |
| 标准支持时长             | 14 个月                                                        | 14 个月(从 **EKS 发布日**起算,非 upstream 发布日)                       | ~12 个月                            |
| 长支持时长               | ~10 个月(Extended channel)                                    | 12 个月                                                                 | ~12 个月(LTS)                      |
| **长支持总时长**          | ~24 个月                                                      | **26 个月**                                                             | ~24 个月                            |
| **长支持默认开?**         | ❌ **需主动加入 Extended channel**                             | ⚛️ **是,`upgrade policy` 默认 `EXTENDED`**                              | ❌ 需选 LTS 且要 Premium 层          |
| 长支持定价               | 按集群加收                                                      | **控制面约 6 倍单价**                                                   | 含在 Premium 层                     |
| 长支持到期后             | GKE 强制升级,exclusion 无法阻止                               | **控制面被自动升级,不提前通知具体时间,且不能回滚**                     | 需自行处理                          |
| 官方文档                 | <https://docs.cloud.google.com/kubernetes-engine/versioning>    | <https://docs.aws.amazon.com/en_us/eks/latest/userguide/kubernetes-versions.html> | (待查)                |

### 三条由对比得出的结论

| #   | 结论                                                        | 依据                                                            |
| --- | ----------------------------------------------------------- | --------------------------------------------------------------- |
| **1** | **三家的结构高度相似**:都是"标准期 + 付费长支持 + 到期强制升级" | 上表三列                                                        |
| **2** | **但默认值不同**,这是成本风险的主要来源                        | EKS 默认 EXTENDED(静默进入 6 倍计费),GKE 需主动加             |
| **3** | **"升级"的范围也不同**                                        | EKS 到期强制升级**只动控制面**,节点不动 → 版本偏移风险         |

> **第 2 条是本次跨云盘点最有价值的一条**:只有横向读过三家的版本策略才会发现。
> 建议作为 §15 开放问题提出(见 `15-cross-cloud-framework.md` §5)。

---

## 9. 引用规则
本目录内所有文档引用的 GCP 事实,应满足:

1. 来自**官方 Google Cloud 文档**(本文件 §1–§7 全部满足)
2. 标注**查阅日期**(当前:2026-09-29)
3. 超过 12 个月**重新核对**
4. 社区博客 / 第三方教程**只作补充**,不作为四态判定的唯一依据

**理由**:RFC §8 写"'尚未评估'不得被解读为'已支持'"。
一份没有出处的能力目录,和一个没有出处的安全结论,在可信度上是一样的问题。
**证据是可追溯性的一部分,不是附加装饰。**

---

**修订记录**

| 日期       | 内容                                             |
| ---------- | ------------------------------------------------ |
| 2026-09-29 | 初版。GCP 侧 §1–§7 已核对;§8 诚实留白 7 项     |
