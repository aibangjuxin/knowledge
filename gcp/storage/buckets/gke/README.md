# ADR-011 · Bucket 跨项目访问部署参考集

> **本目录是 ADR-011 的"实施层参考"**,专门给**业务方 / infra-gcp / devops-gcp / qa-gcp** 看的部署示例 + 流程文档。
>
> **架构师 lane 边界声明**:
> - 本目录**只生成设计参考 + YAML 模板**,**不执行任何 provision / apply / gcloud / kubectl**
> - 实际部署由 **infra-gcp profile** 走 SA 身份执行(见 ADR-009 §13)
> - **业务方不要**亲自 `kubectl apply` 这些资源

---

## 0. 先看这两件事再继续

| 必读 | 是什么 |
|---|---|
| [ADR-011 主文档 §6 红线表](../ADR-011-gke-pod-cross-project-bucket-security-review.md#6-不存用户数据原则的边界深度分析) | Bucket 写 = 档 1 红线,业务方写 YAML 前必须 PM 评估 |
| [ADR-011 主文档 §1.3 阻塞问题](../ADR-011-gke-pod-cross-project-bucket-security-review.md#13-必须先澄清的业务语义交付前阻塞项) | 6 个阻塞问题(Q1 读写 / Q3 数据归属 / G1-G7)必须先答 |

---

## 1. 目录导览

```
gke/
├── README.md                          ← 你正在读
├── 01-deployment-yaml-template.md     ← Deployment YAML + KSA + WIF annotation
├── 02-bucket-policy-guide.md          ← 跨 project IAM policy 设置 + 模板
├── 03-full-flow-process.md             ← 端到端流程 + RACI
├── 04-quick-start-sh.md                ← infra-gcp 5 分钟跑通
└── examples/
    ├── deployment-with-bucket.yaml        ← 业务方 review 用
    ├── ksa-with-wif-annotation.yaml       ← KSA + Workload Identity 绑定
    ├── bucket-iam-policy.json            ← 跨 project IAM policy 模板
    └── namespace-with-labels.yaml         ← namespace + SA + RBAC + PodSecurity
```

---

## 2. 文档使用建议

| 你是谁 | 先读什么 | 后读什么 |
|---|---|---|
| **业务方** | ADR-011 §6 红线 | `01-deployment-yaml-template.md` + `examples/deployment-with-bucket.yaml` |
| **infra-gcp(Bot)** | ADR-011 §8.1 实施清单 | `02-bucket-policy-guide.md` + `04-quick-start-sh.md` + `examples/` 全套 |
| **devops-gcp(Bot)** | ADR-011 §6 + §2.4 审计链 | `03-full-flow-process.md` |
| **qa-gcp(Bot)** | ADR-011 §6 + 4 红线 CI | ADR-011 验证清单(待生成)|

---

## 3. 核心概念速查(再读一次,避免重复犯错)

**Bucket 跨 project 访问的 4 层抽象**:

```
Pod (业务方接触)
   ↓ serviceAccountName
KSA (K8s identity)
   ↓ WIF annotation
Workload Identity Federation (GCP metadata server)
   ↓ 短期 token
GCS Bucket + IAM (user-bucket-project)
```

**关键事实**:
- Pod **不需要** GOOGLE_APPLICATION_CREDENTIALS 环境变量
- **不**需要挂 SA key 文件
- 应用代码用 GCS SDK,**自动**用 KSA token
- 业务方**完全不用知道** IAM / project 边界

---

## 4. 4 条红线速查(写 YAML 时自检)

每条红线对应的违规示例 + 检测方法,详见 ADR-011 §6:

| 红线 | 自检命令 |
|---|---|
| **R1 不持久化到 GCP 服务** | ⚠ **Bucket 写入触发红线 1**,业务方必须先 PM 评估 |
| **R2 不写 log / metric 暴露** | `grep -E "object.*path\|gs://" deployment.yaml log_schema.yaml` 应为空 |
| **R3 不主动观察用户行为** | Cloud Audit Logs 自动记录,**只记操作类型,不记内容** |
| **R4 Pod lifecycle 与 Bucket 解耦** | Pod 删了,object 还在(Object 级独立)|

---

## 5. 端到端流程一句话

业务方提供 YAML → PM/Manager 评估(档 1 红线必走)→ infra-gcp 在 user-bucket-project 配 IAM policy + master-project 配 KSA/WIF → devops-gcp 配监控 + audit → qa-gcp 端到端验证 → 生产。**完整流程见 `03-full-flow-process.md`**。

---

## 6. 当前状态

- **本目录是设计参考**,**不是执行脚本**
- **0 变更** — 没有真实 K8s 资源 / GCP IAM 被 apply
- **infra-gcp 当前 holding pattern** —— 等决策者给 profile 配专属 GCP SA
- **业务方角度**:你现在可以做的事 = 评审 YAML 是否符合业务需求 + PM 评估,**不要**直接 `kubectl apply`

---

> **作者声明**:本文档只生成 YAML 模板 + 流程参考。**任何真实 apply 操作由 infra-gcp 用专属 SA 执行**。