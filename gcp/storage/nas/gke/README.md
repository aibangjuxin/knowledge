# ADR-009 · NAS 挂载部署参考集(GKE 平台)

> **本目录是 ADR-009 的"实施层参考"**,专门给**业务方 / infra-gcp / devops-gcp / qa-gcp** 看的部署示例 + 流程文档。
>
> **架构师 lane 边界声明**:
> - 本目录**只生成设计参考 + YAML 模板**,**不执行任何 provision / apply / gcloud / kubectl**
> - 实际部署由 **infra-gcp profile** 走 SA 身份执行(见 ADR-009 §13 + Q6-a 路径决策)
> - **业务方不要**亲自 `kubectl apply` 这些资源,除非以 infra-gcp 身份操作

---

## 0. 先看这两件事再继续

| 必读 | 是什么 | 为什么 |
|---|---|---|
| [ADR-009 §6.3 红线表 + 4 红线](../ADR-009-gke-pod-mount-internal-nas-security-review.md#63-推荐做法扩展版行为判定矩阵--4-条红线--流程图) | "挂 NAS 本身不算存储用户数据,但取决于怎么用"的判定矩阵 + 4 条工程红线 | 你(业务方)在写 YAML 前**必须**自检 — 不要触红线 |
| [ADR-009 §11.7 业务方 review 后确认事项](../ADR-009-gke-pod-mount-internal-nas-security-review.md#117-业务方-review-后确认事项汇总2026-08-28) | 你之前 review 确认的 4 件事(Q2/Q4/Q5/Q6 + 加密合规硬要求) | 这些是 YAML 的"前置假设",如果哪条不成立,流程要重评 |

---

## 1. 目录导览

```
gke/
├── README.md                          ← 你正在读
├── 01-deployment-yaml-template.md     ← Deployment YAML 完整模板 + 字段注释 + 安全要点
├── 02-pv-creation-guide.md            ← PV 创建方式 + 绑 PVC 流程 + 与 PVC 的关系
├── 03-full-flow-process.md             ← 端到端流程:业务方 → PM → 4-Bot → 生产
├── 04-quick-start-sh.md                ← infra-gcp 执行版 5 分钟跑通
└── examples/
    ├── deployment-with-nas.yaml        ← 可直接用的 Deployment(业务方 review 用)
    ├── pv-nas-template.yaml            ← PV 模板(infra-gcp 套字段)
    ├── pvc-nas-template.yaml           ← PVC 模板(infra-gcp 套 namespace)
    ├── network-policy-nas.yaml         ← 锁定单 Pod 出栈 SMB(必配)
    ├── smb-secret-template.yaml        ← K8s Secret 模板(凭据不入 manifest)
    └── namespace-with-labels.yaml     ← namespace + tenant labels
```

---

## 2. 文档使用建议(按角色)| 你是谁 | 先读什么 | 后读什么 |
|---|---|---|
| **业务方 / PM** | ADR-009 §6.3 红线表 | `01-deployment-yaml-template.md` + `examples/deployment-with-nas.yaml` |
| **infra-gcp(Bot)** | ADR-009 §11.7 任务清单 | `02-pv-creation-guide.md` + `04-quick-start-sh.md` + `examples/` 全套 |
| **devops-gcp(Bot)** | ADR-009 §6.3 红线 2 | `03-full-flow-process.md` + 后续 ADR-010 实施细节 |
| **qa-gcp(Bot)** | ADR-009 §6.3 红线 1/2/4 | ADR-010 验证清单(待生成) |

---

## 3. 核心概念速查(再读一次,避免重复犯错)

**挂 NAS 到 GKE Pod 的 6 层抽象**(详见 ADR-009 §12 + ADR-009-pod-nas-mount-flow.md):

```
Pod 写 volumes:                 (业务方接触)
   ↓
PVC (申请单)                    (业务方接触,namespace-scoped)
   ↓
PV (货架)                       (平台管理,cluster-scoped)
   ↓
CSI driver (翻译官)             (平台管理,DaemonSet)
   ↓
SMB 协议 (TCP 445)              (协议层)
   ↓
公司 NAS (数据物理位置)          (外部系统)
```

**关键事实**:
- Pod 不需要知道 NAS 地址(CSI driver 知道)
- NAS 数据**不在 GCP**(只走 SMB 协议,无副本)
- 业务方只需要写**Pod + PVC** 两层,其他平台管

---

## 4. 4 条红线速查(写 YAML 时自检)

每条红线对应的违规示例 + 检测方法,详见 ADR-009 §6.3 + §1.3.3:

| 红线 | 自检命令(写完 Deployment 后跑一下)|
|---|---|
| **R1 不持久化到 GCP 服务** | `grep -E "gcs\|firestore\|bigquery\|cloudsql" deployment.yaml` 应为空 |
| **R2 不写 log / metric 暴露** | `grep -E "nas.*path\|/mnt/nas" deployment.yaml log_schema.yaml` 应为空 |
| **R3 不主动观察用户行为** | 应用层 owner 自查 — audit 字段不含 file_path / file_content |
| **R4 Pod lifecycle 与 NAS 解耦** | `grep -E "configMapRef\|secretRef.*nas" deployment.yaml` 应为空 |

---

## 5. 端到端流程一句话

业务方提供 YAML → PM/Manager 评估 → infra-gcp 套 SA 身份执行 PV/PVC/NetworkPolicy/Secret → devops-gcp 配 CI/CD + 监控 → qa-gcp 端到端验证 → 生产上线。**完整流程见 `03-full-flow-process.md`**。

---

## 6. 当前状态

- **本目录是设计参考**,**不是执行脚本**
- **0 变更** — 没有真实 K8s 资源被 apply
- **infra-gcp 当前 holding pattern** —— 等决策者给 profile 配专属 GCP SA(见 [ADR-009-q6a-path-decision.md](../ADR-009-q6a-path-decision.md))
- **业务方角度**:你现在可以做的事 = 评审 YAML 是否符合业务需求,**不要**直接 `kubectl apply`

---

> **作者声明**:本文档只生成 YAML 模板 + 流程参考。**任何真实 apply 操作由 infra-gcp 用专属 SA 执行**。