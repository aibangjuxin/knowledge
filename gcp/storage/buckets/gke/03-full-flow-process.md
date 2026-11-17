# 03 · 端到端流程 —— 业务方到生产的完整链路

> **本节是 4-Bot 协作 + 业务方 + PM/Manager 的端到端流程参考**

---

## 1. 全景图

```
┌────────────────────────────────────────────────────────────────┐
│ Phase 1:业务方准备 (1-3 天)                                  │
│ ─────────────────────                                        │
│ 业务方提供:                                                  │
│  • Deployment YAML(只写 serviceAccountName)               │
│  • 数据流向说明(读/写/写哪些 prefix/不写什么)              │
│  • 业务场景描述                                             │
│ 输出: deployment.yaml + 业务说明                            │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ Phase 2:PM/Manager 评估(1-3 天) **必走**                   │
│ ────────────────────────────────                            │
│ 业务方走 PM 流程 → Manager 拍板                              │
│                                                                │
│ PM 必查:                                                      │
│  • 7 行为判定矩阵(ADR-011 §6.2)                              │
│  • 4 红线自检(ADR-011 §6.1)                                 │
│  • 档 1 红线特批(写 Bucket = 持久化到 GCP)                   │
│  • Cloud Audit Logs 知情同意(GCS 写必留 trace)              │
│                                                                │
│ Manager 拍板:                                                │
│  • ✅ 通过 → Phase 3                                          │
│  • ⚠ 灰色 → POC 验证                                          │
│  • ❌ 驳回 → 重新设计或拒绝                                   │
│                                                                │
│ 输出: 评估文档 + PM 通过邮件 + Manager 签字                    │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ Phase 3:POC 验证 (1-2 周,如有需要)                          │
│ ────────────────────────────────                            │
│ infra-gcp 在 dev cluster 部署:                              │
│  • 在 master-project 启用 WIF on cluster                       │
│  • 创建 dev namespace + dev KSA + WIF annotation                │
│  • 在 user-bucket-project 创建 dev bucket + IAM policy         │
│  • 创建 dev Deployment                                         │
│                                                                │
│ qa-gcp 验证:                                                  │
│  • Pod 启动后,GCS SDK 调通(看 metadata server log)           │
│  • 跨 project IAM policy 生效                                 │
│  • PodSecurity 限制                                            │
│  • 4 红线 grep 自检                                            │
│  • Cloud Audit Logs 数据事件可查询                            │
│                                                                │
│ 业务方确认:                                                    │
│  • 数据流向符合预期                                            │
│  • 性能可接受(GCS SDK 延迟 < 100ms)                          │
│  • 应用层无违规(log / metric 检查)                          │
│                                                                │
│ 输出: POC 验收报告                                            │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ Phase 4:生产部署 (1-2 天)                                    │
│ ────────────────────────                                    │
│ infra-gcp 在生产 cluster:                                      │
│  • 创建生产 namespace + KSA + WIF annotation                  │
│  • 在 user-bucket-project 创建生产 bucket + IAM policy          │
│  • 创建生产 Deployment(经 CI/CD)                             │
│                                                                │
│ devops-gcp:                                                    │
│  • CI/CD pipeline 接入                                         │
│  • 监控:Cloud Audit Logs → BigQuery export                     │
│  • 告警:档 1 红线触发(写敏感 prefix / 越界写)               │
│  • 4 红线 CI 集成                                              │
│                                                                │
│ qa-gcp:                                                       │
│  • 生产端到端验证                                              │
│  • 4 红线 grep + Cloud Audit Logs 审计                        │
│                                                                │
│ 输出: 生产部署报告 + 监控仪表板                              │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ Phase 5:持续运营 (持续)                                       │
│ ─────────────────────────────                                │
│ devops-gcp:                                                    │
│  • 月度 review Cloud Audit Logs                                │
│  • 定期检查 IAM policy 漂移                                   │
│  • KSA 轮换 + IAM policy audit                                │
│                                                                │
│ infra-gcp:                                                     │
│  • KSA / IAM policy 修订                                      │
│  • 新业务方 onboarding(其他 tenant)                          │
│  • Tenant CRD 扩展(Bucket 维度)                              │
│                                                                │
│ qa-gcp:                                                       │
│  • 季度 chaos test(模拟 token 过期 / IAM 错配)                │
│  • 季度合规 review(4 红线 + 7 行为矩阵)                       │
└────────────────────────────────────────────────────────────────┘
```

---

## 2. 各角色职责矩阵(RACI)

| 活动 | 业务方 | PM | Manager | infra-gcp | devops-gcp | qa-gcp | architect-gcp |
|---|---|---|---|---|---|---|---|
| 提供 Deployment YAML | **R** | I | I | C | I | I | C |
| 7 行为判定矩阵自检 | **R** | C | I | I | I | C | C |
| 档 1 红线评估(Bucket 写)| C | C | **A** | I | I | I | I |
| 治理问题 G1-G7 验证 | I | C | **A** | **R** | I | C | C |
| 在 master-project 创建 KSA + WIF | C | I | I | **R** | I | I | I |
| 在 user-bucket-project 配 IAM | C | I | I | **R** | I | I | C |
| 部署 Deployment | C | I | I | **R** | I | I | C |
| CI/CD 接入 | C | I | I | C | **R** | I | I |
| Cloud Audit Logs 配 BigQuery | I | I | I | C | **R** | I | C |
| 端到端验证 | C | I | I | C | C | **R** | I |
| 4 红线 CI 集成 | C | I | I | C | **R** | C | C |
| 定期 chaos test | I | I | I | C | C | **R** | I |

**R = 执行, A = 拍板, C = 咨询, I = 知情**

---

## 3. 关键检查点(Gate)

| Gate | 内容 | 通过标准 | 由谁拍板 |
|---|---|---|---|
| **G1** 业务方提交 | YAML + 数据流向 + 业务场景 | 4 红线 grep 全空 | 业务方 + architect-gcp 评审 |
| **G2** PM 评估 | 业务合理性 + 7 行为矩阵 + 档 1 红线特批 | PM 通过 + Manager 签字 | PM + Manager |
| **G3** POC 验收 | 端到端连通 + IAM + 红线 | qa-gcp 报告 + 业务方书面确认 | qa-gcp + 业务方 |
| **G4** 生产部署 | CI/CD + 监控 + 告警 | devops-gcp + qa-gcp 双签 | devops-gcp + qa-gcp |
| **G5** 持续运营 | 月度合规 review | architect-gcp 抽样 | architect-gcp |

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
| 业务方提交的 YAML | ⏳ 业务方尚未提交 |
| PM 评估 | ⏳ 未启动 |
| infra-gcp 执行 | ⏳ holding(等决策者给 profile 配 GCP SA) |
| devops-gcp 监控规则 | ⏳ 未启动 |
| qa-gcp 验证 | ⏳ 未启动 |

---

## 6. 后续可扩展方向

- **多业务方复用**:gke/ 目录可直接复用到其他业务方
- **自动化 Bucket onboarding**:开发 admission webhook,自动给带 `role: bucket-writer` label 的 namespace 配 KSA + IAM policy
- **Tenant CRD 扩展**:在 `gke-pv-multi-tenant-design.md` 加 `bucketAllowlist` 字段
- **跨 region 扩展**:跨 region Bucket 访问需要 Private Service Connect(详见 ADR-011 §3.5)

---

> **作者声明**:本文档只描述流程,**不执行任何 provision**。任何 apply 由对应 lane 的 Bot 用专属 SA 执行。