# PSP Pod Security Policies — Gatekeeper 版安全策略集

## 概述

Gatekeeper 的 **PSP (Pod Security Policies) 库**是 gatekeeper-library 中最完整的安全策略集，将原生 K8s PSP 的能力迁移到了 OPA Gatekeeper 的 ConstraintTemplate 格式。

PSP 在 K8s 1.21 被废弃（但未移除），Gatekeeper 提供了完整的替代方案。

---

## PSP 模板概览

gatekeeper-library 的 PSP 库包含 **20+ 个模板**，分为几类：

### 基础安全（Baseline）

| 模板 | Kind | 说明 |
|------|------|------|
| `K8sPSPPrivilegedContainer` | `K8sPSPPrivilegedContainer` | 禁止 privileged 容器 |
| `K8sPSPHostNamespace` | `K8sPSPHostNamespace` | 禁止共享 host PID/IPC |
| `K8sPSPHostNetworkPorts` | `K8sPSPHostNetworkPorts` | 禁止 host 网络和端口 |
| `K8sPSPAllowPrivilegeEscalationContainer` | `K8sPSPAllowPrivilegeEscalationContainer` | 禁止特权升级 |
| `K8sPSPReadOnlyRootFilesystem` | `K8sPSPReadOnlyRootFilesystem` | 要求根文件系统只读 |
| `K8sPSPVolumes` | `K8sPSPVolumes` | 限制允许的 volume 类型 |
| `K8sPSPSeccomp` | `K8sPSPSeccomp` | 控制 seccomp 配置 |
| `K8sPSPCapabilities` | `K8sPSPCapabilities` | 限制 Linux capabilities |
| `K8sPSPForbiddenSysctls` | `K8sPSPForbiddenSysctls` | 禁止特定 sysctl |
| `K8sPSPFlexVolumeDrivers` | `K8sPSPFlexVolumeDrivers` | 限制 FlexVolume 驱动 |
| `K8sPSPApparmor` | `K8sPSPApparmor` | 要求 AppArmor 注解 |
| `K8sPSPSeccompv2` | `K8sPSPSeccompv2` | Seccomp v2（ARM64） |
| `K8sPSPFSGroup` | `K8sPSPFSGroup` | 控制 FSGroup |
| `K8sPSPHostProcess` | `K8sPSPHostProcess` | 禁止 Windows HostProcess |
| `K8sPSPUsers` | `K8sPSPUsers` | 限制运行用户/组 |
| `K8sPSPHostFilesystem` | `K8sPSPHostFilesystem` | 限制 hostPath 挂载 |
| `K8sPSPHostProbesLifecycle` | `K8sPSPHostProbesLifecycle` | 禁止 hostProbe/hostLifecycle |

### 完整受限（Restricted）

| 模板 | Kind | 说明 |
|------|------|------|
| `K8sPSPAllowPrivilegeEscalationContainer` | `K8sPSPAllowPrivilegeEscalationContainer` | 禁止特权升级（Restricted 级别） |

---

## 1. K8sPSPPrivilegedContainer — 禁止 Privileged 容器

### 核心概念

Privileged 容器拥有宿主机的所有 capabilities，等同于宿主上的 root 权限。这是**最危险的容器安全风险**之一。

```yaml
# 这是一个 privileged 容器 — 完全禁止
spec:
  containers:
  - name: evil
    securityContext:
      privileged: true   # ← 这就是问题所在
```

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `exemptImages` | array[string] | 豁免的镜像列表（支持 `*` 前缀） |

### 完整 Constraint YAML

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: deny-privileged-containers
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    exemptImages:
    - "gke.gcr.io/*"           # GKE 系统组件
    - "registry.k8s.io/pause*"  # pause 容器
```

### Rego 核心逻辑

```rego
violation[{"msg": msg}] {
    not is_update(input.review)           # UPDATE 操作不检查（不可变字段）
    c := input_containers[_]
    not is_exempt(c)
    c.securityContext.privileged         # 直接检查 privileged 字段
    msg := sprintf("Privileged container is not allowed: %v", [c.name])
}

input_containers[c] {
    c := input.review.object.spec.containers[_]
}
input_containers[c] {
    c := input.review.object.spec.initContainers[_]
}
input_containers[c] {
    c := input.review.object.spec.ephemeralContainers[_]
}
```

---

## 2. K8sPSPHostNamespace — 禁止共享 Host 命名空间

### 核心概念

Pod 可以共享宿主机的 PID、IPC、网络命名空间。共享后，Pod 可以看到宿主机上的进程、进行进程间通信、甚至绑定宿主机的端口。

```yaml
# 禁止这些配置
spec:
  hostPID: true     # Pod 可以看到宿主机所有进程
  hostIPC: true    # Pod 可以与宿主机进程通信
```

### 完整 Constraint YAML

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPHostNamespace
metadata:
  name: deny-host-namespace
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - monitoring
```

### Rego 核心逻辑

```rego
violation[{"msg": msg}] {
    not is_update(input.review)
    input_share_hostnamespace(input.review.object)
    msg := sprintf("Sharing the host namespace is not allowed: %v", [input.review.object.metadata.name])
}

input_share_hostnamespace(o) {
    o.spec.hostPID    # 共享 host PID
}
input_share_hostnamespace(o) {
    o.spec.hostIPC    # 共享 host IPC
}
```

---

## 3. K8sPSPAllowPrivilegeEscalationContainer — 禁止特权升级

### 核心概念

`allowPrivilegeEscalation: true` 允许容器中的进程获取比父进程更多的权限。安全的做法是显式设为 `false`。

```yaml
# 不安全 — 允许特权升级
securityContext:
  allowPrivilegeEscalation: true

# 安全 — 禁止特权升级（显式）
securityContext:
  allowPrivilegeEscalation: false
```

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `exemptImages` | array[string] | 豁免的镜像列表 |

### 完整 Constraint YAML

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPAllowPrivilegeEscalationContainer
metadata:
  name: deny-privilege-escalation
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    exemptImages:
    - "gke.gcr.io/*"
```

### Rego 核心逻辑

```rego
violation[{"msg": msg}] {
    not is_update(input.review)
    c := input_containers[_]
    not is_exempt(c)
    input_allow_privilege_escalation(c)
    msg := sprintf("Privilege escalation container is not allowed: %v", [c.name])
}

# 如果没有 securityContext → 违规
input_allow_privilege_escalation(c) {
    not has_field(c, "securityContext")
}
# 如果有 securityContext 但 allowPrivilegeEscalation != false → 违规
input_allow_privilege_escalation(c) {
    not c.securityContext.allowPrivilegeEscalation == false
}
```

---

## 4. K8sPSPReadOnlyRootFilesystem — 要求根文件系统只读

### 核心概念

容器默认有可写的根文件系统。如果容器被攻击，可写根文件系统允许攻击者修改系统二进制文件。

```yaml
# 不安全
securityContext:
  readOnlyRootFilesystem: false   # 或不设置

# 安全 — 只读根文件系统
securityContext:
  readOnlyRootFilesystem: true
```

### 完整 Constraint YAML

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPReadOnlyRootFilesystem
metadata:
  name: require-readonly-root-fs
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
    - logging
  parameters:
    exemptImages:
    - "gke.gcr.io/*"
    - "registry.k8s.io/pause*"
```

### Rego 核心逻辑

```rego
violation[{"msg": msg}] {
    not is_update(input.review)
    c := input_containers[_]
    not is_exempt(c)
    not c.securityContext.readOnlyRootFilesystem == true
    msg := sprintf("only read-only root filesystem container is allowed: %v", [c.name])
}
```

---

## 5. K8sPSPSeccomp — 控制 Seccomp 配置

### 核心概念

Seccomp（Secure Computing Mode）限制容器可以进行的系统调用。GKE 默认使用 `RuntimeDefault`（容器运行时默认配置）。

### 参数说明

| 参数 | 类型 | 说明 |
|------|------|------|
| `allowedProfiles` | array[string] | 允许的 seccomp profile 列表 |
| `allowedLocalhostFiles` | array[string] | 允许的 localhost profile JSON 文件 |
| `exemptImages` | array[string] | 豁免镜像 |

### allowedProfiles 值说明

| 值 | 说明 |
|---|------|
| `runtime/default` | 容器运行时默认（推荐） |
| `docker/default` | Docker 默认（等同于 runtime/default） |
| `unconfined` | 完全不限制（**禁止**） |
| `localhost/*` | 自定义 localhost profile |
| `Localhost` | securityContext 命名方式 |
| `RuntimeDefault` | securityContext 命名方式 |
| `*` | 允许所有 profile |

### 完整 Constraint YAML

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPSeccomp
metadata:
  name: require-seccomp
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    excludedNamespaces:
    - kube-system
  parameters:
    allowedProfiles:
    - "runtime/default"         # 必须使用运行时默认 seccomp
    - "docker/default"
    - "localhost/*"             # 允许自定义 localhost profile
    allowedLocalhostFiles:
    - "profiles/*"              # 允许 profiles/ 下的 JSON 文件
    exemptImages:
    - "gke.gcr.io/*"
```

### Seccomp Profile 设置位置

Seccomp 可以在多个位置设置（Gatekeeper 按优先级处理）：

```yaml
# 位置 1: Pod securityContext（最优先）
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault    # ← 使用容器运行时默认配置

# 位置 2: Container securityContext
spec:
  containers:
  - name: app
    securityContext:
      seccompProfile:
        type: Localhost
        localhostProfile: profiles/my-app.json

# 位置 3: Pod 注解（已废弃，但仍支持）
metadata:
  annotations:
    seccomp.security.alpha.kubernetes.io/pod: "runtime/default"

# 位置 4: Container 注解（已废弃）
metadata:
  annotations:
    container.seccomp.security.alpha.kubernetes.io/app: "localhost/profiles/app.json"
```

---

## PSP 组合使用：Baseline 级别

```yaml
# === PSP Baseline 策略组合 ===

# 1. 禁止 privileged 容器
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata:
  name: psp-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    exemptImages: ["gke.gcr.io/*"]

---
# 2. 禁止 host 命名空间共享
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPHostNamespace
metadata:
  name: psp-host-namespace
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]

---
# 3. 禁止特权升级
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPAllowPrivilegeEscalationContainer
metadata:
  name: psp-privilege-escalation
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    exemptImages: ["gke.gcr.io/*"]

---
# 4. 要求只读根文件系统
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPReadOnlyRootFilesystem
metadata:
  name: psp-readonly-root-fs
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    exemptImages: ["gke.gcr.io/*"]

---
# 5. Seccomp 配置
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPSeccomp
metadata:
  name: psp-seccomp
spec:
  enforcementAction: deny
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    allowedProfiles:
    - "runtime/default"
    exemptImages: ["gke.gcr.io/*"]
```

---

## PSP 与 GKE Pod Security

GKE 提供了原生的 **Pod Security**（基于 GKE Policy Controller），可以直接使用：

```bash
# 查看 GKE Policy Controller 策略
kubectl get constraint

# 查看 GKE 预置的策略
kubectl get gkepolicystatus

# GKE Policy Controller 的 pod-security-policy 约束模板
kubectl get constrainttemplates | grep psp
```

---

## 常见问题

### Q1: `exemptImages` 有什么用？

豁免列表用于系统组件（如 GKE 自身的管理面组件），它们必须有特权但不应该影响业务 Pod：

```yaml
parameters:
  exemptImages:
  - "gke.gcr.io/*"               # GKE 管理组件
  - "registry.k8s.io/pause*"      # K8s pause 容器
  - "sha256*"                     # SHA 固定的镜像是可信的
```

### Q2: 为什么有 `is_update` 检查？

部分安全字段（如 `privileged`、`readOnlyRootFilesystem`）在 Pod 创建后不可修改。Gatekeeper 在 UPDATE 操作时跳过这些字段的检查，避免已运行的 Pod 因策略更新而被阻止重启。

### Q3: GKE 已经内置 PSP 吗？

GKE 原生已废弃 PSP，但 GKE Policy Controller（Gatekeeper 的 Fleet 管理版本）提供了完整的 PSP 等效模板。推荐使用 GKE Policy Controller 而非手动安装独立 Gatekeeper。

---

## 快速命令参考

```bash
# 应用所有 PSP Baseline 约束
kubectl apply -f psp-baseline.yaml

# 查看 PSP 约束状态
kubectl get constraint | grep PSP

# 查看某个 PSP 的 violations
kubectl get k8spspprivilegedcontainer deny-privileged-containers \
  -o jsonpath='{.status.violations}' | jq

# 查看具体违规 Pod
kubectl get pods -A -o jsonpath='{.items[*].metadata.name}' \
  | tr ' ' '\n' | while read pod; do
    echo "Checking $pod..."
  done
```

---

## 源文件路径

- PSP 库: `library/pod-security-policy/`
  - `privileged-containers/template.yaml`
  - `host-namespaces/template.yaml`
  - `allow-privilege-escalation/template.yaml`
  - `read-only-root-filesystem/template.yaml`
  - `seccomp/template.yaml`
  - `capabilities/`
  - `host-network-ports/`
  - `volumes/`
  - `fsgroup/`
  - 等等（共 20+ 个）
