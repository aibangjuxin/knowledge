# CaaS (Cluster-as-a-Service) — 设计与交付文档库

> 把"创建一个生产级 Kubernetes 集群"沉淀为**自助式产品能力**:业务方通过统一 Portal 提交申请 →
> 自动经过合规 / 成本 / 技术校验 → 自动跨云创建 → 自动注入合规、可观测、FinOps 基线。
>
> 本目录是 app.caep CaaS RFC 的**完整设计底稿 + 向该 RFC 交付的输入侧工作包**。
> 状态:**设计阶段**。可运行的只有 Portal 编排层 demo;CaaS Controller 本身尚未实现。

---

## 一、这个目录分四块

```
CaaS/
├── 00-index.md              索引(旧版入口,内容仍在维护)
├── caas-master-doc.md       TL;DR + 8 个核心决策点 + 阅读路径
│
├── 【A】底稿 9 份           CaaS 怎么实现(建-side)
├── 【B】RFC 三份            app.caep CaaS RFC 本体(英文 / 中文 / OCR 原文)
├── 【C】dc-owner-feedback/  20 份:以 DC/GCP Owner 视角向 RFC 交付(喂-side)
└── 【D】caas-portal-temporal-demo/  唯一可运行的最小可执行件
```

| 块            | 文件数        | 回答什么问题                                  | 面向                       |
| ------------- | ------------- | --------------------------------------------- | -------------------------- |
| **A 底稿**    | 1 索引 + 1 master + 9 专题 | "每个能力维度怎么统一 + 怎么留逃逸舱口" | 架构师 / 平台 SRE Lead     |
| **B RFC**     | 3             | "app.caep 到底要什么"(被交付的对象)          | 全员                       |
| **C 喂-side** | 20            | "DC/GCP Owner 要往 RFC 里交什么、交到什么程度" | **CTOi 云工程师 / 应用归属方** |
| **D Demo**    | 1(+1506 行)  | "审批流编排层真的能跑吗"                      | 想看效果的人               |

---

## 二、【A】底稿 9 份 —— 建议阅读顺序

| #   | 文件                                                       | 主题                             | 一句话定位                                              | 行数  |
| --- | ---------------------------------------------------------- | -------------------------------- | ------------------------------------------------------- | ----- |
| 00  | [caas-master-doc.md](./caas-master-doc.md)                 | TL;DR + 决策树                  | 8 个核心决策点 + 4 种读者的阅读路径 + 三件不要做的事    | 129   |
| 01  | [caas-concepts.md](./caas-concepts.md)                     | CaaS 高阶抽象                   | 生命周期 5 阶段 + 适配层分层 + 典型对外能力              | 69    |
| 02  | [gke-caas.md](./gke-caas.md)                               | **GKE 单云落地深水区(最长)**    | ClusterSpec → CRD/CEL → Controller → Shard 自动迁移     | 847   |
| 03  | [caas-providers.md](./caas-providers.md)                   | 跨云 Provider 横向对比          | 四朵云 6 维度真实差异 + "必须逃逸"能力清单              | 189   |
| 04  | [caas-compliance-baseline.md](./caas-compliance-baseline.md) | 安全 / 合规基线                | 等保 2.0 / SOC2 / ISO27001 / PCI-DSS / PIPL 矩阵 + 模板库 | 310   |
| 05  | [caas-finops.md](./caas-finops.md)                         | FinOps & 成本归集               | 成本对象 → 账单回流 → Chargeback → **创建前成本预演**     | 387   |
| 06  | [caas-day2-ops.md](./caas-day2-ops.md)                     | Day-2 运维 & SLA / 灾备         | 升级 / 备份 / DR / 扩缩容 / 证书 / 监控能力矩阵         | 376   |
| 07  | [caas-portal.md](./caas-portal.md)                         | 自助门户 / 审批流 / 通知        | Portal 能力分层、Temporal 审批流、**Portal 与 K8S API 边界** | 407 |
| 08  | [caas-onprem.md](./caas-onprem.md)                         | 自建 K8S 治理模式               | `ClusterRegistration` 而非 `ClusterRequest`,Kyverno Audit | 402 |
| 09  | [caas-cluster-api.md](./caas-cluster-api.md)               | Cluster API 作为基础设施        | 你的能力 × CAPI 能力映射 + 三条决策路径(X/Y/Z)          | 431   |

**分层结构**:产品层(`07`)→ 业务逻辑层(`03/04/05/06/08`)→ 基础设施层(`02` + `09`)→ 外部依赖(Velero / cert-manager / Kyverno / FinOps Adapter)。

### 8 个核心决策点(摘自 `caas-master-doc.md` §2)

| #   | 决策点           | 选择                                              | 为什么不选替代方案                                          |
| --- | ---------------- | ------------------------------------------------- | ---------------------------------------------------------- |
| 1   | 多云策略         | **80% 统一 + 20% 逃逸舱口**(`providerOverrides`)  | 全量统一抽象会变四不像;不统一则业务方领错账单              |
| 2   | 开发/部署模式    | 自研 Controller **+ Cluster API 作为底层**(路径 X) | 纯自研要自己维护每个云的脏活;直接 Rancher/OpenShift 装不下业务字段 |
| 3   | 集群基线         | 团队级共享 + Namespace 隔离为主,Standard 作逃逸舱口 | 全独立集群 = 成本黑洞(你刚处理完的 ~1000 API 迁移就是教训) |
| 4   | 网关配额治理     | **Day-0 强制分片**(`initialShards` 必填)          | "事后补"已被 URL Map size limit 阻塞证明失败               |
| 5   | 合规基线         | Day-0 强制注入 + Kyverno 模板库分版本,豁免走双签   | 事后插控会被"先上线再说合规"绑架                          |
| 6   | FinOps 模型      | 创建前预演 + 创建后 Showback + 先软提醒后硬 Hold   | 一上来 hard limit 会拖垮跨部门结算                        |
| 7   | 审批引擎         | **Schema 驱动表单 + Temporal 工作流**             | 用 K8S Controller 写审批 saga 很别扭;现有 OA 表达力不够   |
| 8   | 自建 K8S 接入    | **治理层而非交付层**                              | 强行套 `ClusterRequest` 会写出"空白缺字段"资源          |

### 三条绝对不要做的事

1. **不要做"四朵云完全统一的适配层"** —— 80% 时间花在写 eviter/转换器,业务方对哪个云的封装都不满意。
2. **不要自研审批流引擎** —— 审批 + retry + 超时 + 跨子系统持久化,半年内必崩。
3. **不要相信云厂商计费页数字** —— 只有 CaaS 自建的 estimator 才知道你的合规状态、日志量、备份策略,才能给出接近真实的月成本。

### 贯穿全库的 6 条设计纪律

1. **80% 统一 + 20% 逃逸**:`providerOverrides` + `FeatureCatalog` + 自建 K8S 作治理层
2. **基线前置**:`managed-by=caas`、`compliance.frameworks`、`costAllocation`、`sla.target` 都是 CRD **强字段**,不是事后补
3. **演练强制而非自愿**:DR 演练、策略升级、证书续期这类"失败要出事"的能力必须 CaaS 编排
4. **可读性 > 代码复用**:每框架一份模板、每 SLI 一份 runbook,拒绝"一千行 Rego"合并
5. **不要做超集抽象**:跨域同形才复用,否则抽象一定会变成障碍
6. **自研 vs 复用 CAPI**:Day-0 基础设施尽量用 CAPI,CaaS 只做"产品化 + 业务字段 + 治理逻辑"

---

## 三、【B】RFC 三份 —— 这是被交付的对象

| 文件                                                       | 说明                                                                                 |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **[rfc.md](./rfc.md)**                                     | RFC 英文版(**主用**),15 章 + 2 个附录。§9 BYOC / §14 决策 / §15 开放问题最关键        |
| [rfc-cn.md](./rfc-cn.md)                                   | RFC 中文版,与英文版逐节对应                                                          |
| [rfc-ocr-original.md](./rfc-ocr-original.md)               | OCR 原始输出,只用于 diff,不要读                                                        |

> **读 RFC 前要知道**:`rfc.md` 是从 OCR 结果重建的。结构损坏(全部表格、Mermaid 状态图、章节编号)
> 已修复并登记在 `rfc.md` 附录 A/B;内容层面的不确定处标为 `**[TBD]**` / `**[?]**`,**未做臆造**。
> 表头 `Scope` / `Author` / `Last updated` 三字段在原文档中就是空的,需要作者回填。

RFC 章节骨架:`1 Background` → `2 Goals` → `3 Non-Goals` → `4 Terminology` → `5 Service Principles` →
`6 Service Model` → `7 Workload Hosting Scenarios` → **`8 Provider Coverage and Capability Profiles`** →
**`9 Bring Your Own Cluster (BYOC)`** → `10 Control-Plane Automation` → `11 Security Standard Automation` →
`12 Operations and Service Management` → `13 Alternatives Considered` → **`14 Decisions`** → **`15 Open Issues`**

**RFC 里最硬的一条**:§8 写明"'尚未评估'不得被解读为'已支持'";§3 非目标明确包含
"在各责任方验证之前,先行确定云厂商产品选型、区域允许清单、服务等级或数值化 SLO"。
→ 交付方给的是**能力与约束**,数值化 SLO 留给 SRE。

---

## 四、【C】dc-owner-feedback/ —— 20 份,向 RFC 交付的工作包

> 上面 9 份底稿全是**建-side**(CaaS 怎么实现)。这个目录是**喂-side**:
> 站在 **CTOi 云工程师 / 应用归属方**角度,把 RFC 逐行对照后挑出"属于你的那部分",
> 整理成可执行工作包。**如果你是 Lex,主要看这个目录。**

| #   | 文件                                                        | 用途                                                    |
| --- | ----------------------------------------------------------- | ------------------------------------------------------- |
| 00  | [00-index.md](./dc-owner-feedback/00-index.md)              | 入口 · 帽子判断 · 只做一件事的话看这页                  |
| 01  | **[01-workplan.md](./dc-owner-feedback/01-workplan.md)**    | **核心交付物** —— WP-0..WP-7 工作清单(P0/P1/P2 带完成判据) |
| 02  | [02-rfc-todo-audit.md](./dc-owner-feedback/02-rfc-todo-audit.md) | RFC 全文 `[待补充]` 归属审计,你能一笔勾掉哪些        |
| 03  | [03-gcp-capability-profile.md](./dc-owner-feedback/03-gcp-capability-profile.md) | **§8 能力目录 schema + GCP 侧 20 维草案**(已回填) |
| 04  | [04-input-templates.md](./dc-owner-feedback/04-input-templates.md) | 申请 / 声明模板(新建 + BYOC 双路径),可直接填        |
| 05  | [05-byoc-onboarding-pack.md](./dc-owner-feedback/05-byoc-onboarding-pack.md) | 存量集群纳管交付物,对齐 RFC §9.2 八阶段             |
| 06  | [06-boundary-and-raci.md](./dc-owner-feedback/06-boundary-and-raci.md) | 管理边界 + break-glass + RACI,填 §9.3 / §9.4 空缺   |
| 07  | [07-decisions-and-open-questions.md](./dc-owner-feedback/07-decisions-and-open-questions.md) | §14 / §15 草案,含"未解决时的影响"列        |
| 08  | [08-sources.md](./dc-owner-feedback/08-sources.md)          | 权威证据清单(GCP 官方文档 URL),每条 GCP 事实的出处      |
| 09  | **[09-p0-execution-pack.md](./dc-owner-feedback/09-p0-execution-pack.md)** | **今天就开始** —— 3 个 P0 展开成按半天排的可执行包(约 1.5 天) |
| 10  | [10-role-paths.md](./dc-owner-feedback/10-role-paths.md)    | 按角色裁剪阅读路径(云侧 / 业务侧)                       |
| 11  | **[11-section-14-15-submission.md](./dc-owner-feedback/11-section-14-15-submission.md)** | **可直接粘贴进 RFC** 的 §14 / §15 提交稿,无旁白  |
| 12  | [12-byoc-scaleup-playbook.md](./dc-owner-feedback/12-byoc-scaleup-playbook.md) | 批量 BYOC:A/B/C 分类 + 批次节奏 + 3 条新反馈(N1/N2/N3) |
| 13  | [13-gap-review.md](./dc-owner-feedback/13-gap-review.md)    | 缺口盘点 —— 交付物第二层 / 规模化陷阱 / RFC 漏网 4 条    |
| 14  | [14-doc-conflict-review.md](./dc-owner-feedback/14-doc-conflict-review.md) | **9 份底稿 × RFC 反向校验** —— 9 条冲突(2 阻断 / 4 重要 / 3 提示) |
| 15  | [15-cross-cloud-framework.md](./dc-owner-feedback/15-cross-cloud-framework.md) | 跨云框架 —— 能力 schema + 20 维提问集,AWS/阿里/IKP 照填 |
| 16  | [16-backfill-from-dc-experience.md](./dc-owner-feedback/16-backfill-from-dc-experience.md) | DC 实战回填 ① —— 用本地 GCP 知识库把 `🔶` 变实证 |
| 17  | [17-backfill-round2.md](./dc-owner-feedback/17-backfill-round2.md) | DC 实战回填 ② —— 服务两分类 / 跨区 PSC / WI 边界 / GAR 实践 |
| 18  | [18-gpu-ai-assessment.md](./dc-owner-feedback/18-gpu-ai-assessment.md) | GPU / AI 评估 —— DC 不支持,为什么,以及扩展位模板       |
| 19  | [19-observability-backfill.md](./dc-owner-feedback/19-observability-backfill.md) | 可观测性回填 —— Log Scopes vs Log Sinks 选型 + 归属缺口 |

**已确认的立场(2026-09-29)**:云侧 + 业务侧**两顶帽子都戴**,且**存量 GKE 集群较多、确定要交 CaaS**。
由此:WP-6(BYOC)升为 P0;交付顺序必须**先 A(云侧)后 B(业务侧)**——业务侧申请单会被云侧能力目录校验,反了返工。

**只做一件事的话**:打开 [`15-cross-cloud-framework.md`](./dc-owner-feedback/15-cross-cloud-framework.md)——
它是 `03` 抽出来的跨云框架,AWS / 阿里云 / IKP 都能照着填,不用重新想该问什么。

### 三条交付纪律

1. **每个能力标记必须带证据与日期** —— RFC §8 要求"'尚未评估'不得被解读为'已支持'"。建议加一条正交的第五维:**证据新鲜度**。
2. **"不支持"比"尚未评估"更值钱** —— 一份全是 ✅ 的能力目录对 CaaS 没有任何用;能让 CaaS 提前知道"这条走不通",能省它一整个季度的适配工作。
3. **不要替 CaaS 承诺你没承诺过的东西** —— 你给能力与约束,SLO 数值留给 SRE。

---

## 五、【D】可运行 Demo(唯一能真跑的东西)

**[`caas-portal-temporal-demo/`](./caas-portal-temporal-demo/)** —— 把 `caas-portal.md` §二 那套审批流变成 `docker compose up` 起来可看的链路。
1506 行 Python + 340 行前端。

```
Browser UI (frontend/index.html)
   │  POST /api/v1/requests
   ▼
FastAPI (api/)  ──kick off──►  Temporal workflow (workflow/cluster_request.py)
   ▲                                  │ 1. validate_compliance_and_cost
   │  SSE status feed                 │ 2. approval(team_leader)
   └──────────────────────────────────┤ 3. approval(pm)             [prod]
                                      │ 4. approval(security_lead)  [pci-dss]
                                      │ 5. approval(platform_sre)
                                      │ 6. trigger_k8s_apply
                                      ▼
                             K8S stub (k8s_stub/) —— 模拟 CaaS Controller
                             POST /apply · 内存记录 · 模拟 Terraform 3-6s
```

### 5 分钟跑通

```bash
cd caas-portal-temporal-demo
cp .env.example .env
docker compose up -d --build     # 7 个服务: postgres temporal temporal-ui api worker k8s_stub nginx
open http://localhost:8080       # Portal 前端(dark theme 表单 + 实时状态条)
open http://localhost:8081       # Temporal UI(看 workflow events timeline)
```

浏览器里默认值就是合法请求(`bbuk-team-a-prod` / `gcp` / `asia-east1` / `autopilot` / `private`),
点提交 → SSE 实时推进 → **约 10 秒后**全绿并出现 "Cluster is **Ready**"。

| Stage                        | 实耗时 |
| ---------------------------- | ------ |
| 校验(CEL 规则)               | 0.5s   |
| team_leader 审批(自动点头)   | 1.5s   |
| pm / security 审批(条件触发) | 0s     |
| K8S stub 模拟 Terraform      | 3-6s   |
| 策略基线注入                  | 1s     |
| **合计**                     | **~10s** |

**失败路径也能试**:提交 `tier=autopilot` + `network=public` → CEL 校验在 `VALIDATING` 阶段直接 rejected;
或在 `.env` 加 `K8S_STUB_FAILURE_RATE=1.0` 重启 stub → `K8S_PROVISIONING` 阶段失败。

完整走查见 [`docs/walkthrough.md`](./caas-portal-temporal-demo/docs/walkthrough.md)(10 步,含
"怎么接飞书/Slack 真人审批"和"怎么把 stub 换成真实 Terraform/CAPI")。

### Demo 的边界

| Demo 里的                              | 真实世界对应                                        |
| -------------------------------------- | --------------------------------------------------- |
| `k8s_stub` 的 `POST /apply`             | 真实 GKE/EKS/ACK Adapter 或 Terraform / CAPI Apply   |
| `k8s_stub` 的内存字典 `_APPLIES`        | 真实 `ClusterRequest` CRD(`gke-caas.md` 里的定义)     |
| `request_human_approval`(自动点头)     | 飞书 / Slack webhook + 真人点同意                    |
| `apply_policy_baseline`(sleep 1s)      | ClusterResourceSet / Kyverno API                    |
| 成本估算(`.env` 里的单价常量)          | `caas-finops.md` §五 的 cost estimator               |

**编排层不动 I/O,每次替换只动一个文件** —— 这是这套 demo 想证明的架构性质。

---

## 六、按角色的阅读路径

| 你是                                    | 读什么                                                                                                              | 耗时 |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---- |
| 领导 / 合作方                           | `caas-master-doc.md` §1 + §2                                                                                        | 2min |
| 架构师 / 平台 SRE Lead                 | `caas-master-doc.md` §2 → `caas-concepts.md` → `caas-providers.md` → `caas-cluster-api.md`,重点是"我同意哪些决策" | 15min |
| 业务方 Owner                            | `caas-master-doc.md` §1 → `caas-portal.md` §一(Portal 长什么样)                                                     | 5min  |
| 接手 CaaS 实现的研发                    | 全部 9 份顺序读完 → 然后跑 `caas-portal-temporal-demo/`                                                             | 半天  |
| **CTOi 云工程师(Lex 主线)**             | `dc-owner-feedback/00` → `09`(今天就开始)→ 需要展开回 `01` 对应 WP → 提交评审用 `11`                              | 1.5天 |
| 多云对接                                | `dc-owner-feedback/15-cross-cloud-framework.md`                                                                      | 30min |
| 想知道还有什么没考虑到                  | `dc-owner-feedback/13-gap-review.md`                                                                                | 20min |
| 想知道 9 份底稿哪里和 RFC 打架          | `dc-owner-feedback/14-doc-conflict-review.md`                                                                       | 30min |

---

## 七、已知冲突与未决项(先读这个再看设计)

[`dc-owner-feedback/14-doc-conflict-review.md`](./dc-owner-feedback/14-doc-conflict-review.md) 对 9 份底稿与 RFC
做了反向校验,结论:**9 条冲突,2 阻断 / 4 重要 / 3 提示**。摘最要紧的几条:

| 级别     | 冲突                                       | 一句话                                                                       |
| -------- | ------------------------------------------ | ---------------------------------------------------------------------------- |
| 🔴 阻断  | C1 `onprem` 必填字段自相矛盾               | 治理层场景下"必填"的是业务字段,但 CRD 把它定义成基础设施字段,套上去就是空壳  |
| 🔴 阻断  | C2 状态机与 RFC §6.2 几乎不重叠            | 底稿自定义的 phase 命名跟 RFC 的状态契约对不上,CaaS 侧实现会跑偏            |
| 🟠 重要  | C3 `default: autopilot` 与 DC 现实相反     | 底稿把 Autopilot 当默认值,但 DC 立场是 **Standard + Stable channel**          |
| 🟠 重要  | C4 缺少"数据分级"作为一等字段              | PIPL / 等保都要数据分级,CRD 里没有这个字段                                   |
| 🟠 重要  | C5 集群级 CRD 缺失                         | 定义了 `ClusterRequest` 和 `ClusterRegistration`,却没定义"集群"本身的 CRD      |
| 🟠 重要  | C6 `multiTenancy` 取值与 Autopilot 兼容性未验证 | "团队共享 + NS 隔离" 首选方案与 Autopilot 组合的可行性没有证据           |
| 🟡 提示  | C7 命名不一致 `ack` vs `aliyun`            | 跨云枚举值拼写不统一                                                          |
| 🟡 提示  | C8 缺少 IKP(内部云)这一整个 Provider       | RFC 明确要求支持 IKP,底稿的 `enum` 里没有                                   |
| 🟡 提示  | C9 版本策略缺失                             | 9 份文档**没一处提到 GKE release channel**,但"版本会过期"是 WP-3 的核心交付物     |

每条冲突都标了**谁该改 + 怎么改**(9 条全部要改 `gke-caas.md`,只有 C7/C8 是全局命名问题)——处理顺序见该文件末尾。

其他尚未闭环的:

- **GPU / AI** —— DC 明确不支持,理由与扩展位模板见 `dc-owner-feedback/18`。
- **可观测性归属** —— 纳管后(logs / metrics / audit)归谁、Log Scopes vs Log Sinks 怎么选,见 `dc-owner-feedback/19`。
- **网络底座边界** —— `dc-owner-feedback/06` §3 自评为"我认为最危险的一条"。
- **DC 立场(已确认)**:GKE 集群模式 = **Standard(非 Autopilot)**、channel = **Stable**。二者是不同概念勿混用;
  Standard 意味着节点池自己管 → CaaS 节点编排是**必需项**;Stable 的 minor 区间窄,版本过高的存量集群加不进来。

---

## 八、维护约定

- **文档纪律**:每个能力标记带**证据 + 日期**;每条架构决策能回溯到具体 config 字段,不接受黑盒 ID。
- **新增文档必须同时更新** `00-index.md` 和 `caas-master-doc.md` §7 的引用图。
- **底稿改动要回写 `dc-owner-feedback/14-doc-conflict-review.md`** —— 改完不复查,冲突表立刻失真。
- **区分"简化说法"与"严格口径"**:表格里的简化结论后面跟一行严格表述(见 `caas-providers.md` §一 注)。
- **`rfc-ocr-original.md` 只读**:任何 RFC 修正都改在 `rfc.md` / `rfc-cn.md`,OCR 原文保留作 diff 基准。
- **本目录不是生产配置**。设计稿 ≠ 实施方案;接入真实集群前先看第七节的冲突表。

---

## 修订记录

| 日期       | 内容                                                             |
| ---------- | ---------------------------------------------------------------- |
| 2026-10-05 | 建库 README:整合索引、底稿 9 份、RFC 3 份、喂-side 20 份、demo 跑法、已知冲突 |
| 2026-09-29 | `dc-owner-feedback/` 回填至 19;DC 立场确认(Standard + Stable)   |
| 2026-09-28 | 底稿 9 份 + master doc 定稿                                      |
