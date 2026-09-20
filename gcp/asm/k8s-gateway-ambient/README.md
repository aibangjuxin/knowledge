# K8s Gateway + Ambient Mesh 探索(独立目录)

> **目录定位**:在 `k8s-gateway/` 已落地的 K8s Gateway API + Istio 1.30 minimal 基础上,
> 探索 ambient 模式 / revision 升级机制 / ambient 下 policy 能力 — **所有探索文档放这里**。

## 0. 起点与边界

### 起点(已在 `k8s-gateway/` 跑通)

- 集群:`dev-lon-cluster-xxxxxx` @ `europe-west2`
- 安装方式:`istioctl install --set profile=minimal`(只装 istiod)
- 镜像:`proxyv2:1.30.3-distroless` + `pilot:1.30.3-distroless`(已 push 到 GAR)
- Gateway:K8s Gateway API v1.5.1 + `gatewayClassName: istio` + ListenerSet 多租户
- 业务 ns:已注入 sidecar

### 本目录要回答的问题(用户决策锁定)

1. **第一阶段 — Ambient 落地**:
   - `istioctl profile=minimal` 怎么升级/扩展成 ambient?
   - ambient 所需的 `ztunnel` / `istio-cni` 怎么装?(`minimal` 不包含)
   - waypoint 怎么引入?per-namespace 还是 per-service?
   - ambient 模式下业务 pod 真的能去掉 sidecar 吗?怎么验证?

2. **第二阶段 — 升级机制**(ambient 落地之后再单独探索):
   - 单 revision 升版 = 中断,怎么避免?
   - 双 revision canary 怎么切?
   - Helm 升级 vs `istioctl upgrade` 怎么选?

3. **第三阶段 — Ambient 模式下 Policy 知识库**:
   - AuthorizationPolicy / PeerAuthentication 在 ambient 下还能做什么?
   - L7 鉴权迁到 waypoint 之后,`selector` → `targetRefs` 怎么改?
   - 用户上传 / 下载 / header 限制 等业务场景,ambient 下能落地吗?

## 1. 文档清单(本目录)

| 文件 | 主题 | 阶段 | 类型 |
|---|---|---|---|
| `00-readme.md` | 本文件(目录索引) | - | 索引 |
| `01-ambient-vs-sidecar.md` | Ambient 与 sidecar 的本质差异、本场景适配分析 | 第一阶段 | 概览 |
| `02-install-ambient-helm.md` | Helm 安装 ambient 组件(istio-base / istiod / istio-cni / ztunnel) | 第一阶段 | 实操 |
| `03-waypoint-design.md` | Waypoint 部署方式、per-ns vs per-service、HA 设计 | 第一阶段 | 实操 |
| `04-runtime-migration.md` | 业务 namespace 从 sidecar → ambient 迁移步骤 | 第一阶段 | 实操 |
| `05-upgrade-strategies.md` | 单 revision vs 双 revision canary,Helm vs istioctl upgrade | 第二阶段 | 实操 |
| `06-policy-capabilities.md` | Ambient 下 AuthorizationPolicy / PeerAuthentication 能力矩阵(场景化) | 第三阶段 | 知识 |
| `07-feature-status-1.30.3.md` | Istio 1.30.3 各 feature GA/Beta/Alpha 状态矩阵 | 全局 | **深度探测** |
| `08-ambient-networkpolicy.md` | Ambient 与 K8s NetworkPolicy 协同,15008 必须 allow | 第一阶段 | **深度探测** |
| `09-ztunnel-redirection-app-compat.md` | ztunnel 拦截机制 + 应用代码兼容性边界 case | 第一阶段 | **深度探测** |
| `10-waypoint-gateway-coexistence.md` | Waypoint 与 K8s Gateway API Gateway 共存模式 | 第一阶段 | **深度探测** |
| `11-l7-zero-downtime-constraint.md` | 🚨 L7 策略迁移硬约束(zero-downtime **不支持**) | 第一阶段 | **深度探测** |
| `12-revision-canary-mtls-compat.md` | 双 revision canary 的 mTLS / 证书兼容细节 | 第二阶段 | **深度探测** |
| `13-multicluster-ambient-status.md` | Multicluster ambient 1.30 现状 + 生产可用性 | 未来 | **深度探测** |
| `14-parametersRef-vs-targetRefs-concept-clarity.md` | **`parametersRef` vs `targetRefs` 概念澄清**(两个 Refs 字段完全不同的语义)| 全局 | **概念澄清** |
| `15-istio-revision-mechanism-explained.md` | **Istio revision 机制详解**(K8s 资源管理视角,MutatingWebhook + Service + Deployment + Revision Tag)| 全局 | **概念澄清** |
| `16-revision-like-patterns-cloud-native.md` | **云原生生态 revision 横向对比**(resourceVersion / generation / Deployment / Helm / ArgoCD / Istio / OCI 共 6+ 种)| 全局 | **概念澄清** |
| `17-istio-image-tag-automation-sre-workflow.md` | **Istio image tag 自动化升级方案**(ArgoCD Image Updater / Flux Image Automation,patch tag → SRE 常规任务)| 第二阶段 | **深度探测** |
| `18-solo-distribution-vs-upstream-istio-comparison.md` | **Solo 分发 vs 上游 Istio 版本选型评估**(社区方案落地:Solo Standard 镜像 + 无 license + Helm 拆分)| 全局 | **版本评估** |
| `19-solo-agentgateway-ambient-install.md` + `19-solo-agentgateway-ambient-architecture.html` | Solo agentgateway + ambient install runbook + archify 架构图 | 全局 | **实操 + 架构图** |
| `20-solo-ambient-kong.md` | **Istio Gateway + KongDP + Ambient Runtime** 闭环(Ambient 模式下 Kong 在 Mesh 外)| 全局 | **场景化** |
| `21-solo-ambient-egress.md` + `21-solo-ambient-egress-architecture.html` | **Ambient 模式下 GKE Pod Egress**(Internal NHF 兼容 + Public L7 waypoint 迁移 + Namespace-level 出网白名单) + archify 架构图 | 全局 | **场景化 + 架构图** |
| `ADR-LOCAL-001-migrate-minimal-to-ambient.md` | 从 minimal 迁 ambient 的架构决策记录 | 全局 | **ADR 草稿** |
| `PERSONAL-FOCUS-LIST.md` | **Lex 个人关注清单**(本目录所有"个人关切"的集中追踪) | 全局 | **关注追踪** |
| `values/` | 02 文涉及的 4 个 Helm values 文件 | 配套 | 配置 |

## 1.1 探索类型说明

| 类型 | 含义 |
|---|---|
| **概览** | 把已有知识 + Gloo 探索材料整理成本场景适配版 |
| **实操** | 可 copy-paste 的安装 / 迁移 / 升级命令 |
| **知识** | 能力矩阵、字段表、场景化用法 |
| **深度探测** | **真价值** — 现有文档找不到的边界 case 答案 |
| **ADR 草稿** | 架构决策记录,本目录本地编号 `ADR-LOCAL-XXX` |
| **关注追踪** | Lex 个人关注清单,后续探索的问题收口 |
| **概念澄清** | 容易混淆的术语 / 字段 / 资源,横向对比 + 严格定义 |
| **版本评估** | 在多个产品 / 分发 / license tier 间做选型决策 |

**`07-13` 这 7 篇是 2026-09-17 第二轮"探测"的产出** — 每篇针对一个真问题,基于 Istio 1.30 官方文档原文。

## 2. 命名前缀规则(沿用知识库约定)

| 前缀 | 含义 | 例 |
|---|---|---|
| `01-..06-` | 阶段序号 | `01-ambient-vs-sidecar.md` |
| `-all-` | 全场景 / 概览 | (无) |
| `-design-` | 设计决策类 | `03-waypoint-design.md` |
| `-vs-` | 对比 / 选型 | `01-ambient-vs-sidecar.md` |
| `-strategies-` | 策略汇总 | `05-upgrade-strategies.md` |
| `-capabilities-` | 能力矩阵 | `06-policy-capabilities.md` |
| `-migration-` | 迁移路径 | `04-runtime-migration.md` |

## 3. 与原 `k8s-gateway/` 目录的关系

| 项 | `k8s-gateway/`(已落地) | `k8s-gateway-ambient/`(本目录,探索) |
|---|---|---|
| Istio profile | `minimal`(只 istiod) | `ambient`(istiod + istio-cni + ztunnel) |
| 数据面 | sidecar 注入 | ztunnel + waypoint(无 sidecar) |
| Gateway API | v1.5.1,已用 | 同 — 沿用,不破 |
| 安装工具 | `istioctl install` | Helm(推荐)/ `istioctl install`(可选) |
| 镜像 | `1.30.3-distroless` GAR | 沿用同一 tag,**不升版**,只换 profile |
| 升级路径 | 不存在(脚本重跑会中断) | 本目录 05 文专门探索 |
| 业务 ns | 已注入 sidecar | 待迁移(04 文) |

## 4. 探索路径(图)

```text
你正在看的目录
└─ k8s-gateway-ambient/
   ├─ 01-ambient-vs-sidecar.md    ← 先看这,理解为什么要做 ambient
   ├─ 02-install-ambient-helm.md  ← 装什么、怎么装、Helm 切到 ambient profile
   ├─ 03-waypoint-design.md       ← waypoint 设计决策
   ├─ 04-runtime-migration.md     ← 业务 ns 怎么从 sidecar 迁到 ambient
   ├─ 05-upgrade-strategies.md    ← 第二阶段:ambient 跑通后,再看这
   └─ 06-policy-capabilities.md   ← 第三阶段:ambient 下能做什么 policy 控制
```

## 5. 探索约定(写文档时遵守)

1. **覆盖双向** — 每篇都覆盖正向(谁来访问谁)和反向(谁授权、谁审计)。
2. **完整交付三件套** — 答案 + 来源(istio.io / cloud.google.com / solo.io 文档 URL)+ ADR 引用。
3. **简化 vs 严格原话分两栏** — 区分"简化解释"和"严格定义";严格侧给精确限定。
4. **不重复造轮子** — Gloo 探索材料里的已有结论直接 cite,不重写。
5. **可执行性** — 每篇都带可直接 copy 的 yaml/bash 片段。
6. **ID 可追溯** — 出现的任何 ID(revision label / namespace label / pod label / CRD group)都标来源。

## 6. 后续动作

- [ ] 第一阶段跑通后,把 `k8s-gateway/01-platform/install-istio.sh` 扩展为 `install-ambient.sh`(并行装 base / istiod / cni / ztunnel)
- [ ] 业务 namespace 全部迁移 ambient 后,把原 `install-istio.sh` 加 comment 标记为"已废弃,新流程见 k8s-gateway-ambient/02-.."
- [ ] 第二阶段(`05-upgrade-strategies.md`)单独深挖,不与第一阶段混

## 7. 参考(本目录文档通用)

- [Istio Ambient docs](https://istio.io/latest/docs/ambient/) — Istio 官方 ambient 总览
- [Istio Ambient install](https://istio.io/latest/docs/ambient/install/) — ambient profile 安装
- [Istio Waypoint](https://istio.io/latest/docs/ambient/usage/waypoint/) — waypoint 部署与用法
- [Istio Revision](https://istio.io/latest/docs/setup/install/multicluster/multi-primary/#customize-the-control-plane) — ControlPlaneRevision
- [Istio istioctl upgrade](https://istio.io/latest/docs/setup/install/upgrade/) — istioctl upgrade 命令
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-single.md` — 已有 Gloo 视角的 ambient 探索
- 同仓库 `~/git/knowledge/gcp/asm/gloo/gke-ambient-waypoint-multip.md` — 已有 Gloo 视角的多集群 ambient 探索
- 同仓库 `~/git/knowledge/gcp/asm/gloo/waypoint.md` — Waypoint 详解(本目录 03 文会引用)