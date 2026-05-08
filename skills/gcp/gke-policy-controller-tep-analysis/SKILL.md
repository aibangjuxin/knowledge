---
name: gke-policy-controller-tep-analysis
description: GKE Policy Controller TEP 覆盖度分析模式。当需要对比 GKE Policy Controller 安装后的 Constraint Template (TEP) 列表与自定义策略设计文档时使用。包含覆盖度矩阵生成、差异表格、描述补充和双仓库同步流程。
category: gcp
---

# GKE Policy Controller TEP Coverage Analysis Pattern

## 何时使用

当需要执行以下任务时使用本模式：
- 对比 GKE Policy Controller 安装后的 Constraint Template (TEP) 列表与自定义策略设计文档
- 生成 GKE 内置 TEP vs 自定义策略的覆盖度分析表
- 为 `step-by-step-install.md` 中的原始 TEP 列表补充描述

## 典型输入

| 文件 | 内容 |
|------|------|
| `step-by-step-install.md` | GKE Policy Controller 安装记录，Section 5.4 含 82 个 TEP 名称列表（原始无描述） |
| `policy-layer.md` | 自定义策略设计文档，55 条策略含分层模型（L1 平台全局 / L2 租户可调） |

## 分析维度

### 覆盖率匹配度定义

| 匹配度 | 含义 |
|--------|------|
| ✅ 精确匹配 | GKE TEP 名称/功能与 Policy-Layer 策略一一对应，可直接使用 |
| 🟡 部分覆盖 | 可通过扩展参数或组合多个 TEP 实现同等效果 |
| 🔴 无覆盖 | Policy-Layer 策略在 GKE TEP 中无对应，需自定义 ConstraintTemplate |

### Policy-Layer 分类统计维度

按类别统计：Container — Deny/Whitelist/Capabilities/Image, Pod — Deny/Whitelist, RBAC, DNS, Gateway, Ingress, Namespace, PersistentVolume, StorageClass, ASM, CRD, Certificate, Flux, Prometheus 等。

## 输出文件

### 1. 覆盖度分析文档

创建 `gke-policy-control-with-tep.md`，包含：
- **第1章**：GKE TEP 完整列表 + 每个 TEP 的中文描述（按 PSP/通用/ASM/GCP/网络安全分组）
- **第2章**：Policy-Layer 与 GKE TEP 映射表（精确匹配 / 部分覆盖 / 无覆盖 三级）
- **第3章**：汇总统计表（按类别统计覆盖率）+ 高优先级待自定义清单
- **第4章**：分阶段实施建议

### 2. 更新的安装文档

在 `step-by-step-install.md` 的 `### Check Installed Constraint Templates` 节：
- 将原始 TEP 列表（只有 NAME 和 AGE 两列）更新为三列格式：NAME / AGE / DESCRIPTION
- 在表格末尾添加分组说明（PSP 19个 / Kubernetes 通用 39个 / ASM 10个 / GCP 3个 / 网络安全类）

### 3. GKE TEP 描述参考

**PSP 相关（19个）**
| 模板名称 | 描述 |
|----------|------|
| k8spspprivilegedcontainer | 禁止运行特权容器（privileged: true） |
| k8spspallowprivilegeescalationcontainer | 禁止容器启用 privilege escalation |
| k8spspapparmor | 要求容器必须使用已批准的 AppArmor Profile |
| k8spspautomountserviceaccounttokenpod | 禁止 Pod 自动挂载 ServiceAccount Token |
| k8spspcapabilities | 限制容器可添加的 Linux capabilities |
| k8spspflexvolumes | 白名单允许的 FlexVolume driver 路径 |
| k8spspforbiddensysctls | 禁止使用特定的 sysctl 参数 |
| k8spspfsgroup | 要求 Pod 必须指定 fsGroup |
| k8spsphostfilesystem | 限制容器对宿主机文件系统目录的访问 |
| k8spsphostnamespace | 禁止 Pod 使用宿主机 PID/IPC/Network 命名空间 |
| k8spsphostnetworkingports | 禁止 Pod 使用宿主机网络端口（hostPort） |
| k8spspprocmount | 限制容器对宿主进程空间的挂载 |
| k8spspreadonlyrootfilesystem | 要求容器根文件系统必须为只读 |
| k8spspseccomp | 要求 Pod/容器必须使用已批准的 Seccomp Profile |
| k8spspselinuxv2 | 要求容器必须指定 SELinux 安全上下文 |
| k8spspvolumetypes | 白名单允许的 volume 类型 |
| k8spspwindowshostprocess | 禁止 Windows 容器使用宿主进程 |
| k8spssrunasnonroot | 要求容器必须声明为非 root 运行 |
| k8spspallowedusers | 限制 Pod 运行的用户 UID 范围 |

**Kubernetes 通用（节选）**
| 模板名称 | 描述 |
|----------|------|
| k8sallowedrepos | 白名单允许的容器镜像仓库 |
| k8snoenvvarsecrets | 禁止将 Secret 挂载为容器环境变量 |
| k8srequiredlabels | 要求命名空间必须包含特定 labels |
| k8scontainerlimits | 要求容器必须设置 CPU 和 Memory 的 limits |
| k8srequiredprobes | 要求容器必须配置 liveness 和 readiness probe |
| k8shttpsonly | 要求 Ingress 必须使用 HTTPS |
| k8simagedigests | 要求镜像必须指定 SHA256 digest |
| ... | ... |

**ASM/Anthos Service Mesh（10个）**
| 模板名称 | 描述 |
|----------|------|
| asmpeerauthnstrictmtls | 要求 PeerAuthentication 必须设置 STRICT mTLS |
| asmsidecarinjection | 要求命名空间必须启用/禁用 Istio sidecar injection |
| destinationruletlsenabled | 要求 DestinationRule 必须启用 TLS |
| ... | ... |

## 关键结论模板

每次分析应产出：

```
核心发现：Policy-Layer 的 N 条策略中，仅约 X% 可直接通过 GKE Policy Controller 内置模板实现。
剩余 Y% 需要自定义 Gatekeeper Constraint Templates，主要集中在 [ASM/Gateway/DNS/容器安全] 领域。
建议优先实现高优先级的 N 个自定义模板以覆盖最关键的安全需求。
```

## 同步流程

```bash
# 1. 复制到 gcp 仓库并提交
cp gke-policy-control-with-tep.md ~/git/gcp/OPA-Gatekeeper/
cp step-by-step-install.md ~/git/gcp/OPA-Gatekeeper/
cd ~/git/gcp
git add OPA-Gatekeeper/gke-policy-control-with-tep.md OPA-Gatekeeper/step-by-step-install.md
git commit -m "docs(OPA-Gatekeeper): add TEP comparison analysis and template descriptions"
git push

# 2. 复制到 knowledge 仓库并提交
cp gke-policy-control-with-tep.md ~/git/knowledge/OPA-Gatekeeper/
cp step-by-step-install.md ~/git/knowledge/OPA-Gatekeeper/
cd ~/git/knowledge
git add OPA-Gatekeeper/gke-policy-control-with-tep.md OPA-Gatekeeper/step-by-step-install.md
git commit -m "docs(OPA-Gatekeeper): add TEP comparison analysis and template descriptions"
git push
```

## 已知数据（截至 2026-05-08）

- GKE Policy Controller TEP 总数：**82 个**（v1.23.1）
- Policy-Layer 策略总数：**55 条**
- 精确匹配：14 条（25%）
- 部分覆盖：11 条（20%）
- 需完全自定义：30 条（55%）
- PSP 相关：19 个 TEP（全覆盖）
- ASM 相关：10 个 TEP（Policy-Layer 无 ASM 策略）

## 相关 Skill

- `gatekeeper-multi-tenant-governance`: 多租户治理，包含豁免机制和 per-tenant Constraint 设计
- `gatekeeper-constraints`: ConstraintTemplate 探索文档编写规范
