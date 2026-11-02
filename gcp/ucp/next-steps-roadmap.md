# UCP · 下一步知识探索路线图

> 面向：明早验收的人
> 基线：Argo CD **v3.5.6**（本目录 `install.yaml`）· Crossplane Core **v2.4.3** ·
> provider-gcp-container **v3.1.0** · function-go-templating **v0.13.2** · function-auto-ready **v0.7.3**
> 本文的定位：**不重复**同目录已有的 8 篇文档，只做「缺口 → 探索项 → 验证方式 → 产出物」的排期。

---

## 0. 一句话结论

**Argo CD 侧的机制挖掘已经很深，短板不在 Argo CD，在 Crossplane 侧和"可交付产物"上。**

现有文档把 Argo CD 讲到了可以直接排障的程度（组件边界、RBAC、AppProject、同步语义、
跨集群凭据、API/CLI、故障矩阵都齐了）。真正还缺三样东西：

| 缺口 | 表现 | 影响 |
|---|---|---|
| **① Crossplane 侧深度不足** | 目录里 Crossplane 只有 PoC 配置片段；Composition 流水线、Function 调试、MRAP/Safe Start、XRD 渲染机制基本没展开 | 集群建不出来 / 卡住时，没有判断依据 |
| **② 没有可直接 apply 的产物** | 所有 YAML 都是文档片段，没有真实目录树、没有端到端验收脚本 | 明天开工仍要从 Markdown 里抄 YAML，抄错无从发现 |
| **③ 版本基线不一致** | `poc-minimax.md` 写 "ArgoCD ≥ 2.4.8"，其余文档基线是 v3.5.6；health.lua 被写成"必须手工配"，但 v3.x 已内置 | 已在本轮直接修正（见 §8） |

**优先级排序原则：先能跑（P0），再能交付（P1），再能治理（P2），最后才扩云（P3）。**

---

## 1. 现有资产盘点

| 文档 | 覆盖内容 | 深度 | 状态 |
|---|---|---|---|
| `requirement.md` | 平台方/开发方边界、ownership 表、跨云控制面设计 | 概念层 | 可作为设计基线 |
| `poc.md` | Crossplane 控制集群 + provider-gcp-container 的最小 PoC | 步骤级 | 有版本存疑点 |
| `poc-minimax.md` | UCP 总体方案：分层架构、两条流水线、版本矩阵、RACI、资源清单、9 步实施顺序 | 方案级 | **本文的主干** |
| `poc-argocd-integration.md` | Argo CD × Crossplane 控制面分工、字段所有权、prune/selfHeal、namespace 覆盖规则 | 机制级（最硬） | 已核实 |
| `poc-argocd-git-to-apply-trigger.md` | Git → apply 四阶段、三条触发路径与延迟、失败恢复矩阵 | 机制级（最硬） | 已核实 |
| `argocd-admin-guide.md` | RBAC / SSO / AppProject / ApplicationSet / 同步语义 / 跨集群 / 通知 / 运维 / 排障表 / 4 周路线图 | 机制 + 运维级 | 已核实 |
| `argocd-cli-guide.md` | CLI 全命令树、认证、context、权限预检、CI 用法 | 参考级 | 已核实 |
| `argocd-api.md` | v3.5.6 REST 全量清单 + gRPC + 调用示例 | 参考级 | 已核实 |
| `argo-api-claude.md` | API 清单的另一份整理（与上重复） | 参考级 | 可合并，见 G-11 |
| `argocd-application-guide.md` | `Application` CRD 字段逐个解释 + 9 个示例 + 四种创建方式 + 坑位速查 | 机制级 | 本轮新增（已对上游 v3.5.6 核对） |
| `examples/argocd-application/` | 9 个可直接改造的 `Application` / `ApplicationSet` 示例 YAML | 示例级 | 本轮新增 |
| `eli5/` | 四张给非工程师看的图解 HTML + 索引 | 科普级 | 本轮新增 |

**读法建议**：`poc-minimax.md` 是主线，`poc-argocd-*.md` 是它的深挖附录，
`argocd-admin-guide.md` 是通用运维手册，`argocd-api.md` / `argocd-cli-guide.md` 是查表用的参考。

---

## 2. 缺口清单（按优先级）

| ID | 缺口 | 为什么现在卡住 | 探索什么 | 验证方式 | 产出物 | 预估 |
|---|---|---|---|---|---|---|
| **G-01** | 没有真实的 manifests 目录 | 所有 YAML 是片段，抄错无法发现；AppProject 的 `destinations` 与目录名/`namespace` 必须三处一致，人工对不齐 | 把 `poc-minimax.md` 的模板落成 `platform/` + `teams/` 真实目录树 | `kubectl apply --dry-run=server` 全量通过；`argocd app diff` 无差异 | `ucp/manifests/` 目录树 | 1.5 天 |
| **G-02** | 没有端到端验收脚本 | 阶段 1 的退出标准是"提 PR → 自动建集群"，没有脚本就没法一键判定 | 把验收标准写成可重复执行的检查脚本 | 脚本在干净环境跑通，输出 pass/fail 清单 | `ucp/scripts/verify-poc.sh` | 1 天 |
| **G-03** | Crossplane Composition / Function 调试手段缺失 | 集群建不出来时不知道卡在 Function 渲染还是 Provider 调用 | `crossplane render` / `trace` / `function` 调试 / `compositionRevisions` / `conditions` 解读 | 人为写错一个 Function 模板，用 trace 定位到具体步骤 | Crossplane 调试手册（新文档） | 1 天 |
| **G-04** | MRAP / Safe Start 未落地 | `poc-minimax.md` §4.5.8 明确标【待核实】：只激活 `*.container.gcp.m.upbound.io` 的写法与默认策略调整方式 | `ManagedResourceActivationPolicy` 语义、CRD 激活与 `RuntimeActive=False` 的关系 | `kubectl get mrd` 全部 `state: Active`；未激活的 MRD 处于 `AwaitingActivation` 且不报错 | 修订 §4.5.8（把待核实项落成确定写法） | 0.5 天 |
| **G-05** | XRD 渲染契约与字段所有权没验证 | Composition 里的 `status.atProvider.id` 提取路径标【待核实】；XR 的 `spec` 谁写、`status` 谁写没在真实环境验证过 | XRD `scope: Namespaced` 的行为、Composition 字段透传、MR `status.atProvider` 真实字段名 | 建一个假 Composition，故意改一个字段，观察 XR/MR 的 diff 归属 | 修订 §4.5.5–4.5.7 | 1 天 |
| **G-06** | Argo CD 3.x 与 Crossplane 的 health / diff 行为未实测 | 文档说 v3.5.6 内置 health.lua，但"内置"与"实际显示 Healthy"是两回事 | `argocd-cm` 的 `resource.customizations` 与内置 lua 的优先级；XR 长期 `Progressing` 的排查 | 建一个假 XR 看 UI 状态是否为 Healthy | 修订 `poc-minimax.md` §3.4 | 0.5 天 |
| **G-07** | CI 门禁未定义 | 文档说"kubeconform → crossplane render"，但没有校验规则、失败阈值、CRD schema 从哪来 | kubeconform 的 CRD schema 来源问题、crossplane render 的本地预览用法 | 故意提交一个非法 YAML，CI 必须失败 | `ucp/scripts/ci-validate.sh` + 说明 | 1 天 |
| **G-08** | 环境晋级（promotion）与"切换环境"只讲概念 | `argocd-admin-guide.md` §6.3/§6.7 有讲法，但与 UCP 的 XR 提交流没接上 | Argo CD Application 的 promotion、`values` 参数化、tracking-id 残留清理 | 同一套参数在 dev/prod 分别 apply，资源不串 | 补一节「UCP 的环境晋级模型」 | 1 天 |
| **G-09** | 恢复与备份只有结论没有 runbook | 阶段 3 硬指标是"完成一次恢复演练并有记录"，但没有步骤 | Velero vs etcd 快照的取舍、XR/MR 的 `crossplane.io/external-name` 核对、`managementPolicies: ["Observe"]` 切换 | 在预生产真删一个控制集群并恢复成功 | `ucp/runbook-recovery.md` | 1.5 天 |
| **G-10** | 身份与权限模型只覆盖 Workload Identity 主路径 | 多 Project、多团队时 ProviderConfig 隔离、节点 GSA 的 `serviceAccountUser` 授权链容易漏 | GSA→KSA 联邦、ProviderConfig 拆分粒度、Kyverno/OPA 准入校验 XR 参数 | 越权 XR 被准入策略拒绝 | 补进 `poc-minimax.md` §2.2 | 1 天 |
| **G-11** | 文档冗余与索引缺失 | `argocd-api.md` 与 `argo-api-claude.md` 内容高度重叠；目录无 README；根 README 只列了 3 篇 | — | — | `ucp/README.md` 索引 + 标注冗余关系 | 0.5 天 |
| **G-12** | 多云扩展（AWS/Azure/阿里云）没有评估口径 | requirement 提到三云，但 `poc-minimax.md` 阶段 6 只写"单独立项评估阿里云 Provider 覆盖度" | Provider 覆盖度矩阵、XRD 抽象边界（哪些适合统一、哪些会变成最小公分母） | 出一张覆盖度表并给结论 | 新文档《多云抽象边界评估》 | 1.5 天 |

---

## 3. 主线 A · Crossplane 侧机制补齐（P0）

这是最该先补的一块：**Argo CD 侧已经能排障了，但集群建不出来时，Crossplane 侧还没有排查手册。**

| 知识点 | 要回答的问题 | 学习路径（按顺序） | 验证 |
|---|---|---|---|
| A1 Composition 流水线 | 一个 XR 经过哪些 Function、每个 Function 的输入输出长什么样 | `crossplane/docs` `content/v2.4/composition/` → 官方示例 `crossplane render` 输出 | 跑通 `crossplane render xr.yaml composition.yaml` |
| A2 Function 调试 | 渲染错了改哪里、怎么单步 trace | `crossplane trace` / functions 调试文档 | 人为写坏模板 → trace 里定位到步骤 |
| A3 XRD 与 CRD 契约 | XRD 生成什么 CRD、`scope` 怎么影响 MR 的 namespace、`status` 有哪些 condition | `crossplane/docs` `content/v2.4/crds/` | `kubectl explain xr.spec` / `kubectl get crd -o yaml` |
| A4 MRAP / Safe Start | 不激活的 MRD 会怎样、CRD 何时被激活、`RuntimeActive=False` 是不是故障 | `crossplane/docs` `content/v2.4/managed-resources/` + `mrapi` CRD | `kubectl get mrd` 全 Active |
| A5 Provider 与身份 | `InjectedIdentity` 与静态 `Credentials` 的差别、Workload Identity 链路 | `crossplane/docs` `content/v2.4/guides/` + provider-gcp 仓库 README | Provider `HEALTHY=True` 且能列出目标 Project 的集群 |
| A6 外部资源身份 | `crossplane.io/external-name` 怎么记录 GCP 资源 ID、恢复时怎么核对 | provider CRD 的 `status.atProvider` 实际字段 | 建一个集群后 `kubectl get mr -o yaml` 看真实字段名 |
| A7 冲突与保护 | `deletionPolicy: Orphan`、`Usage`、`deletionProtection` 三者怎么组合 | `crossplane/docs` `content/v2.4/` 相关章节 | 删 XR 时云集群不被删 |

**产出**：`ucp/crossplane-troubleshooting.md`（Crossplane 侧排障手册，与
`argocd-admin-guide.md` §12 的 Argo CD 侧速查表对齐格式）。

---

## 4. 主线 B · 从"文档"到"仓库"（P0）

### 4.1 目标目录树（建议放在 `ucp/manifests/`，或直接建 `ucp-platform` 仓库）

```
ucp-platform/
├── platform/                     # 流水线 A：平台组件，ArgoCD App: crossplane-platform
│   ├── providers/
│   │   └── provider-gcp-container.yaml     # Provider + DeploymentRuntimeConfig
│   ├── functions/
│   ├── xrd/gkeclusters.yaml                 # XRD
│   ├── compositions/gkecluster-gcp.yaml     # Composition（Pipeline）
│   ├── providerconfigs/                     # ClusterProviderConfig gcp-target-a / -b
│   └── mrap/gcp-container-only.yaml         # MRAP
├── teams/
│   ├── team-a/
│   │   ├── applicationset.yaml              # ApplicationSet（git directories generator）
│   │   └── project-a/gkecluster.yaml        # XR —— 团队唯一需要写的东西
│   └── team-b/
└── argocd/
    ├── appproject-team-a.yaml
    └── argocd-cm-patch.yaml                 # 三项配置（版本要求见 §8）
```

### 4.2 三处命名必须一致（G-01 的核心约束）

```
Git 目录名  =  ApplicationSet 生成的 namespace  =  AppProject.destinations 允许的 namespace
teams/team-a/project-a/          project-a                 project-a
```

不一致时 Argo CD 直接拒同步，报 `not match any of the allowed destinations`。
**这条应该由脚本断言，而不是靠人记。**

### 4.3 验收脚本要判定的内容（对应阶段 1 的退出标准）

| # | 检查项 | 命令要点 |
|---|---|---|
| 1 | Argo CD 健康 | `kubectl -n argocd get pods` 全 Running；`argocd version` 与 CLI 版本一致 |
| 2 | Application 已生成且 Synced | `argocd app list` 全部 `Synced` |
| 3 | 目录名 / namespace / AppProject 一致 | 解析三个 YAML 比对字符串 |
| 4 | XR 出现在目标 namespace | `kubectl get xgkeclusters.platform.example.org -A` |
| 5 | MR 已创建且 Provider 健康 | `kubectl get managedresources` + `providers` `HEALTHY=True` |
| 6 | 云上集群真的存在且 Ready | `gcloud container clusters list` + 集群状态 |
| 7 | 幂等：重复同步无 diff | `argocd app diff <app> --revision HEAD` 空 |
| 8 | 逆操作：revert PR 后集群被回收 | 只在 PoC 目标集群做，且 `prune` 打开才验证 |

---

## 5. 主线 C · CI 门禁与交付流水线（P1）

| 环节 | 规则 | 失败即拒 |
|---|---|---|
| YAML 语法 / schema | `kubeconform`（CRD schema 需指向 Crossplane + provider 的 CRD，不能用默认 k8s schema） | 是 |
| Composition 渲染 | `crossplane render` 渲染每个团队 XR + Composition | 是 |
| 命名一致性 | 目录名 = namespace = AppProject 允许名单 | 是 |
| 越权检测 | XR 里出现未授权字段（如自选 ProviderConfig）→ 拒绝 | 是 |
| 镜像/包版本 | 所有 Provider/Function/Configuration 版本固定，禁止 `latest` | 是 |
| 签名与发布 | OCI Configuration 包签名后按环境晋级 | 阶段 2 |

**已知坑**：`kubeconform` 的 CRD schema 位置极易配错，导致校验"看起来通过了"其实什么都没校验。
这条要在 G-07 里用「故意提交非法 YAML 必须失败」来反证。

---

## 6. 主线 D · Argo CD 生产化（P1，原理已在 admin-guide 覆盖，只需落地）

| 主题 | 文档位置 | 待落地动作 |
|---|---|---|
| SSO + 用户分组 | §2.2 / §2.3 | 接 Dex 或 Keycloak，`scopes: [groups]` |
| RBAC 策略 | §2.1–2.4 | `policy.default: role:readonly` + `policy.csv`，业务账号隔离 |
| 通知 | §8.1–8.2 | `argocd-notifications-cm` + subscriptions，同步失败可告警 |
| Webhook 降延迟 | §8.3 | GitHub webhook → `/api/webhook/github`，把 120s 降到 10s 级 |
| 高可用 / 备份 / 升级 | §10.1–10.3 | Argo CD 自身不是有状态强依赖，但 Redis + etcd 快照必须做 |
| 巡检 | §10.4 | 每周巡检脚本（不健康应用 / 长期 OutOfSync / 落在 default project 的应用） |

**优先级判断**：PoC 阶段 SSO/RBAC 可以缓，**通知 + webhook 建议早做**——
否则每次同步是否成功都要人肉看 UI，联调效率会被拖死。

---

## 7. 主线 E · 安全、恢复与多云（P2/P3）

| 主题 | 硬指标 | 关联缺口 |
|---|---|---|
| 身份最小化 | 一个 ProviderConfig 对应一个目标账号；按 团队 × 环境 × 云 拆分 | G-10 |
| 准入控制 | Kyverno 或 OPA 校验 XR 参数（区域白名单、规格上限、必填标签） | G-10 |
| 爆炸半径 | Platform Dev 与 Customer Prod 的控制集群隔离 | — |
| 恢复演练 | 真删一次 + 恢复成功 + 记录 RTO/RPO | G-09 |
| 漂移与自愈 | 手工改云上资源，Argo CD 期望值被 `selfHeal` 拉回 | G-08 |
| 多云抽象边界 | 出一张 Provider 覆盖度矩阵 + "哪些资源不适合统一"的结论 | G-12 |

---

## 8. 本轮已直接应用的修改

你授权"按建议直接应用"，以下是**不涉及决策、可逆、纯一致性**的修改，已完成：

| # | 文件 | 修改 | 原因 |
|---|---|---|---|
| 1 | `poc-minimax.md` §3.4 | 版本要求从"≥ 2.4.8"改为**以 v3.5.6 为基线**，并说明 2.4.8 是官方下限而非目标版本 | 全目录其余 6 篇文档基线均为 v3.5.6，`install.yaml` 也是 v3.5.6 |
| 2 | `poc-minimax.md` §3.4 | health.lua 段落加注：v3.5.6 已内置 `_.upbound.io` / `_.crossplane.io`，手工贴 lua 仅 <3.x 必要 | 与 `poc-argocd-integration.md` §3.8 的核实结论对齐（原表述会让人白贴一段） |
| 3 | `ucp/README.md`（新增） | 目录索引：9 篇文档 + ELI5 图解 + 本路线图，标注主/辅关系与冗余关系 | 目录原本无索引，8 篇文档的阅读顺序不清晰 |
| 4 | 根 `README.md` | 在 Argo CD 速查表后补两行，指向 `ucp/README.md` 与本路线图 | 沿用仓库既有索引习惯 |
| 5 | `ucp/next-steps-roadmap.md`（新增） | 本文件 | — |
| 6 | `ucp/scripts/verify-poc.sh`（新增） | G-02 的验收脚本骨架：8 项检查（组件健康 / Application 状态 / 命名一致性 / XR 落位 / Provider 与 MR / 云上集群 / 追踪方式），纯只读，带 PASS-FAIL-SKIP 汇总 | 阶段 1 的退出标准此前无法一键判定 |
| 7 | `ucp/scripts/ci-validate.sh`（新增） | G-07 的 CI 门禁骨架：YAML 语法、禁止 `latest`、**禁止在 `teams/` 下提交 MR/平台组件**、按团队校验命名一致性、可选 kubeconform / crossplane render | 这两条是文档里反复强调、却完全没有自动化的不变量 |

两个脚本已通过 `bash -n`（含 macOS 自带 bash 3.2）与构造反例的实测：
反例 `teams/` 下混入 `ManagedResource` 会被门禁拦下（FAIL，退出码 1），
命名一致性按 **团队维度** 校验（`team-a/project-a` 对 `appproject-team-a.yaml`，
不会拿 A 团队的名单去卡 B 团队的目录）。缺 `kubeconform` / `crossplane` / PyYAML 时自动降级为 WARN。
本机有 `yq` v4，YAML 语法检查已可用。

**仍未做**（需要真实集群/仓库才能推进）：`verify-poc.sh` 尚未在真集群跑过（当前环境无集群），
`ci-validate.sh` 尚未接入 GitHub Actions（需要 D1 决定仓库归属后再写 workflow）。

**没有改的**（需要你明天拍板，见 §9）：任何架构性取舍、任何会影响现有 YAML 语义的字段、
任何 `prune` / `deletionPolicy` 相关的默认策略。

---

## 9. 明天需要你拍板的 5 件事（每件都带我的建议）

| # | 决策点 | 选项 | **我的建议** | 影响面 |
|---|---|---|---|---|
| D1 | manifests 放哪 | A. 本仓库 `ucp/manifests/` 　B. 另建 `ucp-platform` 仓库 | **B**（另建仓库），PoC 阶段先在 `ucp/manifests/` 放同一份内容做过渡 | 影响 CODEOWNERS、审批流、CI |
| D2 | Argo CD 与 Crossplane 拓扑 | A. 同集群 　B. 独立 GitOps 集群 | **PoC 用 A，生产用 B**（`poc-argocd-integration.md` §3.1 已有此判据） | 决定要不要做 cluster secret 与网络打通 |
| D3 | `prune` 默认值 | A. 关 　B. 开 | **PoC 关闭，生产按应用灰度开**。阶段 1 的验收标准"revert PR → 集群被删"需要临时开 | 爆炸半径，误删风险 |
| D4 | Crossplane 版本基线 | A. v2.4.x 直接上 　B. 从 v1 迁移 | **A**。`poc.md` §3 已指出 v1.20 于 2026-11 结束维护 | 影响所有 XRD/Composition 写法 |
| D5 | `argo-api-claude.md` | A. 保留两份 　B. 合并进 `argocd-api.md` 归档 | **B**：内容高度重叠，`argocd-api.md` 更完整 | 仅文档层 |

你可以直接回"同意建议"或只改其中几条。

---

## 10. 两周执行日历（建议）

| 天 | 做什么 | 产出 | 依赖 |
|---|---|---|---|
| D1 | 决策 D1–D5 拍板；G-04/G-05 在真实集群上核实待核实项 | 修订后的 `poc-minimax.md` §4.5.5–4.5.8 | 你起床后 10 分钟内可完成 |
| D2–D3 | G-01：落 `ucp/manifests/` 全套 manifest + 目录树 | 可 `kubectl apply` 的目录 | D1 |
| D4 | G-02：写 `verify-poc.sh`，对着目录跑 | 一键验收脚本 | G-01 |
| D5 | G-03：Crossplane 排障手册（先 A1/A2/A6） | `crossplane-troubleshooting.md` | 控制集群可用 |
| D6–D7 | G-07：CI 校验脚本（kubeconform + crossplane render + 命名一致性） | PR 门禁 | G-01 |
| D8 | G-06：health / diff 行为实测，修订 §3.4 | 文档修订 | G-01 |
| D9–D10 | G-08：环境晋级模型；补进 admin-guide §6.3 | 文档修订 | — |
| D11 | G-09：写恢复 runbook（**先不执行破坏性演练**） | `runbook-recovery.md` | 备份方案定稿 |
| D12–D14 | G-10/G-12：准入策略 + 多云覆盖度矩阵 | 两份文档 | 需要你参与评审 |

---

## 11. 明早验收清单

- [ ] `ucp/next-steps-roadmap.md` 是否覆盖了你心里"下一步该研究什么"的判断
- [ ] §9 的 D1–D5 是否同意我的建议（可直接回"同意"）
- [ ] §8 的 5 处修改是否认可（尤其 `poc-minimax.md` 的版本表述改动）
- [ ] 缺口清单里有没有我漏掉的、或者你优先级排错的项
- [ ] 是否需要把 §2 的某个缺口提前到第一周

---

## 附录 A. 本文的核实方式

- 目录现状：`ls -l ucp/`、各文档标题与章节结构（本地读取，非推测）
- 版本基线：`ucp/install.yaml`（v3.5.6）、`argocd-api.md` / `argocd-cli-guide.md` 的版本声明
- 【待核实】计数：`poc-minimax.md` 4 处、`argocd-admin-guide.md` 4 处、
  `poc-argocd-git-to-apply-trigger.md` 1 处、`poc-argocd-integration.md` 2 处 —— 均已在 §2 映射到具体缺口
- health.lua 内置结论：沿用 `poc-argocd-integration.md` §3.8 与附录 A 的核实结果，
  本轮**未联网复核**（沙箱无网络），安装后请用 §4.3 的检查项 1 与 G-06 实测确认

## 附录 B. 相关文档

| 文档 | 定位 |
|---|---|
| `poc-minimax.md` | 总体方案主线 |
| `poc-argocd-integration.md` | Argo CD × Crossplane 控制面分工（机制级） |
| `poc-argocd-git-to-apply-trigger.md` | Git → apply 逐阶段链路（机制级） |
| `argocd-admin-guide.md` | Argo CD 通用管理与运维 |
| `argocd-api.md` / `argocd-cli-guide.md` | 参考手册 |
| `eli5/index.html` | 给非工程师看的四张图解 |
