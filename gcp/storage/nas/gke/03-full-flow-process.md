# 03 · 端到端流程 —— 业务方到生产的完整链路

> **本节是 4-Bot 协作 + 业务方 + PM/Manager 的端到端流程参考**
>
> 业务方看"我该做什么",infra-gcp / devops-gcp / qa-gcp 看"我该接什么",PM/Manager 看"什么时候该拍板"。

---

## 1. 全景图

```
┌────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  Phase 1:业务方准备 (1-3 天)                                       │
│  ─────────────────────                                             │
│  业务方提供:                                                         │
│  • YAML manifest(Deployment + PVC)                                  │
│  • 数据流向说明(读什么、写不写、写哪里)                              │
│  • 业务场景描述(为什么需要挂 NAS)                                  │
│                                                                      │
│  工具:gke/ 目录下 YAML 模板                                          │
│  输出: deployment.yaml + pvc.yaml + 业务说明                       │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Phase 2:PM/Manager 评估 (1-3 天)                                  │
│  ────────────────────────────────                                  │
│  业务方走 PM 流程 → Manager 评估                                    │
│                                                                      │
│  PM 负责:                                                            │
│  • 业务合理性(真的需要挂 NAS 吗?)                                   │
│  • 合规自检(7 种行为判定矩阵,见 ADR-009 §6.3)                      │
│  • 资源估算(挂载对集群的影响)                                       │
│  • G7 治理问题(G1-G7,见 ADR-009 §11.6)                            │
│                                                                      │
│  Manager 拍板:                                                       │
│  • ✅ 通过 → 进 POC 流程                                              │
│  • ⚠ 灰色 → 需要 POC 验证                                            │
│  • ❌ 驳回 → 重新设计或拒绝                                          │
│                                                                      │
│  输出: 评估文档 + PM 通过邮件                                       │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Phase 3:POC 验证 (1-2 周,如有需要)                               │
│  ────────────────────────────────                                  │
│  infra-gcp 在 dev cluster 部署:                                       │
│  • 创建 dev namespace                                                │
│  • 创建 dev SA + dev Secret                                          │
│  • 创建 dev PV + dev PVC                                             │
│  • 创建 dev NetworkPolicy                                            │
│  • 创建 dev Deployment                                               │
│                                                                      │
│  qa-gcp 验证:                                                        │
│  • SMB 路径连通性(从 Pod 到 NAS)                                     │
│  • NetworkPolicy 生效(同 ns 其他 Pod 不能出栈)                       │
│  • PodSecurity 限制(不能 hostPath / privileged)                      │
│  • 红线 4 条自检(grep YAML)                                          │
│                                                                      │
│  业务方确认:                                                          │
│  • 数据流向符合预期                                                  │
│  • 性能可接受(实测 P99 延迟)                                        │
│  • 应用层无违规(log / metric 检查)                                │
│                                                                      │
│  输出: POC 验收报告                                                 │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Phase 4:生产部署 (1-2 天)                                          │
│  ────────────────────────                                          │
│  infra-gcp 在生产 cluster:                                            │
│  • 创建生产 namespace + SA + Secret                                  │
│  • 创建生产 PV + PVC + NetworkPolicy                                │
│  • 创建生产 Deployment(经 CI/CD)                                     │
│                                                                      │
│  devops-gcp:                                                          │
│  • CI/CD pipeline 接入 devops-gcp profile                            │
│  • 监控规则(`smb_request_duration_seconds` P99)                       │
│  • 告警规则(NetworkPolicy 违规、红线 1/2 触发)                     │
│  • Log 收集(Pod log → Cloud Logging,过滤敏感字段)                  │
│                                                                      │
│  qa-gcp:                                                             │
│  • 生产端到端验证(健康检查 + NetworkPolicy 测试)                    │
│  • 红线 4 条 CI 集成                                                 │
│                                                                      │
│  输出: 生产部署报告 + 监控仪表板                                    │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────┐
│  Phase 5:持续运营 (持续)                                            │
│  ─────────────────────────────                                     │
│  devops-gcp:                                                          │
│  • 监控指标告警(红线触发 = 立刻下线)                                │
│  • 定期 review Pod log(自动化 grep)                                  │
│  • 版本升级(K8s / GKE / SMB CSI driver / NAS 端)                     │
│                                                                      │
│  infra-gcp:                                                          │
│  • PV / PVC / NetworkPolicy 修订                                    │
│  • 新 namespace onboarding(其他业务方接入)                          │
│  • Tenant CRD 扩展(NAS 维度)                                        │
│                                                                      │
│  qa-gcp:                                                             │
│  • 定期 chaos test(模拟 NAS 端故障 / 网络中断 / 凭据过期)            │
│  • 季度合规 review(4 红线 + 7 行为矩阵)                             │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
```

---

## 2. 各角色职责矩阵(RACI)| 活动 | 业务方 | PM | Manager | infra-gcp | devops-gcp | qa-gcp | architect-gcp |
|---|---|---|---|---|---|---|---|
| 提供 Deployment YAML | **R** | I | I | C | I | I | C(评审)|
| 7 行为判定矩阵自检 | **R** | C | I | I | I | C | C |
| PM 评估 + 拍板 | I | **R** | **A** | I | I | I | I |
| 治理问题 G1-G7 验证 | I | C | **A** | **R** | I | C | C |
| 创建 namespace / SA / Secret | C | I | I | **R** | I | I | I |
| 创建 PV + PVC | C | I | I | **R** | I | I | C |
| 创建 NetworkPolicy | C | I | I | **R** | I | C | C |
| 创建 Deployment | C | I | I | **R** | I | I | C |
| CI/CD 接入 | C | I | I | C | **R** | I | I |
| 监控 + 告警 | I | I | I | C | **R** | I | C |
| 端到端验证 | C | I | I | C | C | **R** | I |
| 红线 4 条 CI 集成 | C | I | I | C | **R** | C | C |
| 定期 chaos test | I | I | I | C | C | **R** | I |

**R = Responsible(执行), A = Accountable(拍板), C = Consulted(咨询), I = Informed(知情)**

---

## 3. 关键检查点(Gate)

每个 Phase 之间都有 Gate,**Gate 不通过不能进下一个 Phase**:

| Gate | 内容 | 通过标准 | 由谁拍板 |
|---|---|---|---|
| **G1** 业务方提交 | YAML + 数据流向说明 + 业务场景 | 4 红线 grep 全空 | 业务方 + architect-gcp 评审 |
| **G2** PM 评估 | 业务合理性 + 合规自检 + 资源估算 | 7 行为矩阵 + G1-G7 全 ✅ | PM + Manager |
| **G3** POC 验收 | 端到端连通 + NetworkPolicy + 红线 | qa-gcp 报告 + 业务方书面确认 | qa-gcp + 业务方 |
| **G4** 生产部署 | CI/CD + 监控 + 告警 + 红线 CI | devops-gcp + qa-gcp 双签 | devops-gcp + qa-gcp |
| **G5** 持续运营 | 月度合规 review | architect-gcp 抽样 review | architect-gcp |

---

## 4. 沟通渠道

| 阶段 | 主沟通 | 抄送 |
|---|---|---|
| Phase 1 | 业务方 → PM | architect-gcp |
| Phase 2 | PM → Manager | 业务方 + architect-gcp |
| Phase 3 | infra-gcp → qa-gcp | 业务方 + PM + architect-gcp |
| Phase 4 | devops-gcp → infra-gcp | qa-gcp + architect-gcp |
| Phase 5 | architect-gcp 月度 review | 全部 |

---

## 5. 当前 holding 状态(架构师 lane)

| 项 | 状态 |
|---|---|
| 业务方提交的 YAML | ⏳ 业务方尚未提交(等业务方准备好)|
| PM 评估 | ⏳ 未启动(等业务方提交)|
| infra-gcp 执行 | ⏳ holding(等决策者给 profile 配 GCP SA,见 ADR-009-q6a-path-decision.md) |
| devops-gcp 监控规则 | ⏳ 未启动(等 infra-gcp 部署完)|
| qa-gcp 验证 | ⏳ 未启动(等 devops-gcp 完成)|

**架构师能动 / 不能动**:
- ✅ 能:评审 YAML / 提供模板 / 监督流程 / 维护 ADR 文档
- ❌ 不能:`kubectl apply` / 创建 PV / 创建 SA / 配监控 / 跑测试

---

## 6. 后续可扩展方向

- **多业务方复用**:ADR-009-pod-nas-mount-flow + gke/ 目录可直接复用到其他业务方
- **自动化 NAS onboarding**:开发 admission webhook,自动给带 `role: nas-consumer` label 的 namespace 配 NetworkPolicy + Secret
- **Tenant CRD 扩展**:在 `gke-pv-multi-tenant-design.md` 加 `nasShareAllowlist` 字段,把 NAS 纳入多租户体系
- **替代方案落地**:如果 Filestore / NetApp Volumes 更合适,流程同样适用,只换 CSI driver 和 PV/PVC 字段

---

> **作者声明**:本文档只描述流程,**不执行任何 provision**。任何 apply 由对应 lane 的 Bot 用专属 SA 执行。