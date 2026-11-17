# GKE Pod Security Admission (PSA) 详解

## 什么是 PSA？

Pod Security Admission (PSA) 是 Kubernetes 内置的一种准入控制器（Admission Controller），用于实施 Pod 安全标准（Pod Security Standards, PSS）。它是 Kubernetes 从 1.25 版本开始正式作为 Pod Security Policy (PSP) 的替代方案推出的标准安全机制。

在 GKE 环境中，PSA 是一项关键的安全功能，用于确保集群中运行的工作负载符合预定义的安全基线，防止特权提升、容器逃逸等安全风险。

## 为什么需要 PSA？

随着 Pod Security Policy (PSP) 在 Kubernetes 1.25 中被弃用并移除，PSA 成为了原生的替代方案。它的设计目标是：

- **开箱即用**：无需安装额外的 CRD 或第三方工具。
- **配置简单**：通过命名空间标签（Namespace Labels）即可控制。
- **分级明确**：基于官方定义的 Pod 安全标准（PSS）。

## PSA 的三个安全标准 (Pod Security Standards)

PSA 依赖于三个预定义的策略级别，分别对应不同的安全宽容度：

| 级别           | 名称   | 说明                                                                         | 适用场景                                        |
| :------------- | :----- | :--------------------------------------------------------------------------- | :---------------------------------------------- |
| **Privileged** | 特权级 | 没有任何限制，允许完全的权限访问（如 `privilege: true`，HostPath 等）。      | 系统级组件（如 CNI 插件、存储驱动、日志代理）。 |
| **Baseline**   | 基线级 | 限制了最常见的已知特权升级风险，但允许常规的容器配置。                       | 普通的应用程序，不需要特殊硬件访问权限。        |
| **Restricted** | 受限级 | 最严格的策略，强制执行最佳实践（如必须非 Root 运行、禁止 Capabilities 等）。 | 高度敏感的应用，需要最高安全等级的工作负载。    |

## PSA 的三种控制模式 (Modes)

对于上述的每个安全标准，你可以在命名空间级别配置三种不同的操作模式：

1. **Enforce（强制）**: 如果 Pod 违规，直接拒绝创建（拦截）。
2. **Audit（审计）**: 允许 Pod 创建，但在审计日志中记录违规事件。
3. **Warn（警告）**: 允许 Pod 创建，但在用户执行 `kubectl apply` 时返回警告信息。

## 在 GKE 中如何配置 PSA

PSA 的配置完全基于 **Namespace 标签**。你不需要编写复杂的 YAML 策略文件，只需给命名空间打上特定的标签即可。

### 标签格式

```yaml
pod-security.kubernetes.io/<MODE>: <LEVEL>
pod-security.kubernetes.io/<MODE>-version: <VERSION>
```

### 示例配置

假设我们要在一个名为 `app-production` 的命名空间中强制执行 **Restricted（受限）** 标准：

**1. 创建命名空间时指定：**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: app-production
  labels:
    # 强制执行 restricted 标准
    pod-security.kubernetes.io/enforce: restricted
    # 对基线标准主要用于警告（可选，帮助开发人员自查）
    pod-security.kubernetes.io/warn: baseline
    # 锁定版本，防止 K8s 升级导致策略变化影响应用
    pod-security.kubernetes.io/enforce-version: v1.28
```

**2. 使用命令行为现有命名空间打标签：**

```bash
kubectl label --overwrite ns app-production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```
