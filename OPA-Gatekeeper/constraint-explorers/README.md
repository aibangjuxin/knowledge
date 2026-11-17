# Gatekeeper Constraint 探索索引

本目录收录了 OPA Gatekeeper 核心 ConstraintTemplate 的深度探索文档，格式参考 `k8srequiredlabels.md`。

## 目录结构

```
constraint-explorers/
├── README.md                        ← 本文件
├── block-loadbalancer-services.md   ← 禁止 LoadBalancer Service
├── block-nodeport-services.md       ← 禁止 NodePort Service
├── externalip.md                    ← 限制 Service externalIPs
├── containerlimits.md               ← 容器资源限制
├── allowed-repos.md                 ← 镜像仓库白名单
├── disallowed-repos.md              ← 禁止特定镜像仓库（黑名单）
├── https-only.md                    ← 强制 Ingress HTTPS
├── storageclass.md                  ← 存储类限制
├── replica-limits.md                ← 副本数限制
├── required-probes.md               ← 强制健康检查探针
├── psp-pod-security.md              ← PSP 安全策略全集
└── immutable-fields.md              ← 禁止修改特定字段（自定义）
```

## 概览表

| 文档                             | 约束类型     | 适用对象                  | 关键参数                        |
| -------------------------------- | ------------ | ------------------------- | ------------------------------- |
| `block-loadbalancer-services.md` | Deny         | Service.type=LoadBalancer | 无参数                          |
| `block-nodeport-services.md`     | Deny         | Service.type=NodePort     | 无参数                          |
| `externalip.md`                  | Deny         | Service.spec.externalIPs  | `allowedIPs`                    |
| `containerlimits.md`             | Deny + Audit | Pod                       | `cpu`, `memory`, `exemptImages` |
| `allowed-repos.md`               | Deny         | Pod (所有容器)            | `repos`                         |
| `disallowed-repos.md`            | Deny         | Pod (所有容器)            | `repos`（禁止列表）             |
| `https-only.md`                  | Deny         | Ingress                   | `tlsOptional`                   |
| `storageclass.md`                | Deny         | PersistentVolumeClaim     | `allowedStorageClasses`         |
| `replica-limits.md`              | Deny         | Deployment/ReplicaSet     | `min`, `max`                    |
| `required-probes.md`             | Deny         | Pod                       | `probes`, `probeTypes`          |
| `psp-pod-security.md`            | Deny         | Pod                       | 20+ PSP 模板                    |
| `immutable-fields.md`            | Deny         | 任意资源                  | `fieldSpecs`（自定义）          |

## 按用途分类

### 网络安全类
- **K8sBlockLoadBalancer** — 阻止 LoadBalancer Service（公网暴露）
- **K8sBlockNodePort** — 阻止 NodePort Service（节点端口暴露）
- **K8sExternalIPs** — 限制 Service externalIPs 白名单 ✓已探索（见 externalip.md）

→ 三个组合使用，实现 Service 暴露策略的完全控制

### 资源管理类
- **K8sContainerLimits** — 强制容器设置 CPU/内存 limits
- **K8sReplicaLimits** — 限制副本数量

### 镜像安全类
- **K8sAllowedRepos** — 限制镜像来源仓库（白名单）
- **K8sDisallowedRepos** — 禁止特定镜像仓库（黑名单）

### Ingress 安全类
- **K8sHttpsOnly** — 强制 Ingress HTTPS

### 存储治理类
- **K8sStorageClass** — 限制 PVC 使用的存储类

### 健康与可观测性
- **K8sRequiredProbes** — 强制健康检查探针

### PSP Pod 安全策略（20+ 模板）
- **K8sPSPPrivilegedContainer** — 禁止 privileged 容器
- **K8sPSPHostNamespace** — 禁止 host PID/IPC 共享
- **K8sPSPAllowPrivilegeEscalationContainer** — 禁止特权升级
- **K8sPSPReadOnlyRootFilesystem** — 要求只读根文件系统
- **K8sPSPSeccomp** — Seccomp 配置控制
- **K8sPSPCapabilities** — Linux Capabilities 限制
- **K8sPSPHostNetworkPorts** — 禁止 host 网络/端口
- **K8sPSPVolumes** — Volume 类型限制
- ...（共 20+ 个，见 psp-pod-security.md）

### 变更控制类
- **K8sImmutableFields** — 禁止修改特定字段（自定义模板）

## 模板来源

所有模板定义来自官方 [open-policy-agent/gatekeeper-library](https://github.com/open-policy-agent/gatekeeper-library/tree/master/library/general)：

```
library/general/
├── block-loadbalancer-services/
├── block-nodeport-services/
├── externalip/                  ← 限制 externalIPs ✓已探索
├── containerlimits/
├── allowedrepos/
├── httpsonly/
├── storageclass/
├── replicalimits/
├── requiredlabels/        ← 已有 k8srequiredlabels.md
└── ...（共 20+ 个模板）
```

## 使用建议

### 推荐启动组合（多租户集群）

```bash
# 1. 网络暴露控制
kubectl apply -f K8sBlockLoadBalancer.yaml   # 阻止 LoadBalancer
kubectl apply -f K8sBlockNodePort.yaml     # 阻止 NodePort
kubectl apply -f K8sExternalIPs.yaml       # 限制 externalIPs

# 2. 资源保护
kubectl apply -f K8sContainerLimits.yaml    # 强制 limits

# 3. 镜像安全
kubectl apply -f K8sAllowedRepos.yaml       # 限制镜像仓库

# 4. HTTPS 强制
kubectl apply -f K8sHttpsOnly.yaml         # Ingress HTTPS
```

## 建议探索顺序

1. `k8srequiredlabels.md` — 理解 ConstraintTemplate 结构
2. `containerlimits.md` — 理解带参数的约束
3. `block-loadbalancer-services.md` — 理解简单 deny 约束
4. `externalip.md` — 理解 Service externalIPs 限制
5. `block-nodeport-services.md` — 理解 NodePort 阻断
6. `allowed-repos.md` — 理解镜像安全
7. `https-only.md` — 理解 Ingress 约束
8. `storageclass.md` — 理解 inventory 数据源
9. `replica-limits.md` — 理解 workload 约束
10. `required-probes.md` — 理解探针与 UPDATE 操作处理
11. `disallowed-repos.md` — 理解黑白名单组合
12. `psp-pod-security.md` — PSP 安全策略完整生态
13. `immutable-fields.md` — 自定义模板设计与 Rego 深度

## 探索更多模板

gatekeeper-library 还有更多模板值得探索：

```
library/general/
├── block-loadbalancer-services/ ← 阻止 LoadBalancer ✓已探索
├── block-nodeport-services/     ← 阻止 NodePort ✓已探索
├── externalip/                  ← 限制 externalIPs ✓已探索
├── containerlimits/             ← 容器资源限制 ✓已探索
├── allowedrepos/               ← 镜像白名单 ✓已探索
├── disallowedrepos/            ← 镜像黑名单 ✓已探索
├── httpsonly/                  ← 强制 HTTPS ✓已探索
├── storageclass/               ← 存储类限制 ✓已探索
├── replicalimits/              ← 副本数限制 ✓已探索
├── requiredprobes/             ← 强制探针 ✓已探索
├── immutablefields/            ← 字段不可变 ✓已探索
├── K8sNoEnvVarSecrets/         ← 禁止 secrets 作为环境变量
├── K8sIngressHostCollision/    ← 防止 ingress host 冲突
├── K8sSpreadNamespace/          ← 强制 Pod 分布策略
├── K8sRequiredLabels            ← ✓已有 k8srequiredlabels.md
└── ...

library/pod-security-policy/    ✓已探索 PSP 全集
├── baseline/                   ← PSP Baseline ✓
├── restricted/                 ← PSP Restricted
├── privileged-containers/      ← ✓
├── host-namespaces/            ← ✓
├── seccomp/                    ← ✓
└── ...（共 20+ 个）
```

如需扩展更多探索文档，在 `constraint-explorers/` 下按 `template-name.md` 命名创建即可。
