# CaaS 系列文档索引

把"高阶概念 + GKE 单云落地深水区"两条底稿写完,以及四份横向能力(跨云、合规、FinOps、Day-2)展开后,继续把**"产品化层 + 自建治理模式 + 基础设施选择"**这三份补齐——它们决定 CaaS 是不是"真能用、真有人用、真不累"。

| #   | 文件                            | 主题                                | 一句话定位                                                                                      | CaaS 自有 vs 复用外部基础设施           |
| --- | ------------------------------- | ----------------------------------- | ----------------------------------------------------------------------------------------------- | ----------------------------- |
| 00  | [caas-master-doc.md](./caas-master-doc.md)     | TL;DR + 决策树             | 8 个核心决策点 + 阅读路径 + 三件不要做的事                    | 跨层导览                          |
| 01  | [caas-concepts.md](./caas-concepts.md) | CaaS 高阶抽象                 | 生命周期 + 适配层 + 典型能力                                                                      | 自有                            |
| 02  | [gke-caas.md](./gke-caas.md)           | GKE 单云落地深水区             | ClusterSpec → CRD → Controller → Shard 自动迁移(已有,无需重读)                                | 自有                            |
| 03  | [caas-providers.md](./caas-providers.md)         | 跨云 Provider 横向对比     | 四朵云在 6 个维度的真实差异点 + "必须逃逸"的能力清单                                                | 自有(Adapter 层)                |
| 04  | [caas-compliance-baseline.md](./caas-compliance-baseline.md) | 安全 / 合规基线 | 等保 2.0 / SOC2 / PIPL 维度矩阵 + ConstraintTemplate 模板库组织 + 多集群差异配置策略         | 自有(策略库)                      |
| 05  | [caas-finops.md](./caas-finops.md)             | FinOps & 成本归集           | 四朵云计费模型统一化 → 成本对象 / 拆分规则 / 账单回流 → Chargeback 报告                              | 自有(Adapter+DB)             |
| 06  | [caas-day2-ops.md](./caas-day2-ops.md)         | Day-2 运维 & SLA / 灾备     | 升级/备份/DR/扩缩容/证书/监控能力矩阵 + 跨云差异点 + 集群生命周期归属 & Break-glass 流程            | 自有(编排层) + 复用 Velero/cert-mgr |
| 07  | [caas-portal.md](./caas-portal.md)             | 自助门户 / 审批流 / 通知       | Portal 能力分层、审批流(Temporal)、通知体系、UX 原则、Portal 与 K8S API 边界                          | 自有(产品层)                     |
| 08  | [caas-onprem.md](./caas-onprem.md)             | 自建 K8S 治理模式              | ClusterRegistration 登记、治理基线(审计模式)、IDC 折算、break-glass 流程                  | 自有(治理层)                     |
| 09  | [caas-cluster-api.md](./caas-cluster-api.md)   | Cluster API 作为基础设施       | 你的能力 × CAPI 能力映射、三条决策路径(X/Y/Z)、CAPI 选型与落地要点                                  | 复用 CAPI 作为底层                 |
| 10  | [caas-portal-temporal-demo/](./caas-portal-temporal-demo/) | 可运行 Demo             | 一个真正能跑的最小可执行件: 提交 ClusterRequest → Temporal 跑审批流 → K8S stub 创建 → Ready | 编排层 demo(可替换为真实 backend)        |
| 11  | [dc-owner-feedback/](./dc-owner-feedback/) | **DC/GCP Owner 视角(向 RFC 交付)** | 站在 CTOi 云工程师 / 应用归属方角度,把 RFC 逐行对照后拆成 **8 个工作包** + 能力目录(已按 DC 实战回填)+ 跨云框架 + 决策/开放问题草案 | 喂-side(输入侧)   |

---

## 设计纪律(贯穿 9 份文档)

1. **"80% 统一 + 20% 逃逸"**:`providerOverrides` + `FeatureCatalog` + 自建 K8S 作为"治理层而非交付层"
2. **基线前置**:`managed-by=caas` + `compliance.frameworks` + `costAllocation` + `sla.target` 都是 CRD 强字段,不是事后补
3. **演练强制而非自愿**:DR 演练、Kyverno 策略升级、HTTPS 证书都属于"失败要出事"的能力,必须 CaaS 编排而非业务方自愿
4. **可读性 > 代码复用**:模板、合规、Day-2 拒绝"一千行 Rego"合并,坚持"每框架一份模板、每 SLI 一份 runbook"
5. **不要做超集抽象**:Adapter 不要做"通用 helper",跨域同形才复用,否则一定会变障碍
6. **自研 vs 复用 CAPI**(新增):CaaS 是"产品化 + 业务字段 + 治理逻辑"的层;Day-0 基础设施(集群创建、节点池、健康检查)尽量用 CAPI,不要重新造
