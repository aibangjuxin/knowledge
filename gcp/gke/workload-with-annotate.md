# Workload Identity 与 Namespace Annotate 深度解析

本文档基于以下材料整理：

- [workload-identify.md](/Users/lex/git/knowledge/gcp/gke/workload-identify.md)
- [workload-identify.md](/Users/lex/git/knowledge/safe/gcp-safe/workload-identify.md)
- [About Workload Identity Federation for GKE](https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity)
- [Authenticate to Google Cloud APIs from GKE workloads](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
- [About service accounts in GKE](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/service-accounts)
- [Apply predefined Pod-level security policies using PodSecurity](https://cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission)
- [Configure GKE node service accounts](https://docs.cloud.google.com/kubernetes-engine/security/configure-node-service-accounts)

目标是回答三个问题：

1. 这两个现有文档在讲什么
2. 下面这两个命令分别做了什么
3. 如果不做，会影响什么

```bash
kubectl label --overwrite ns $namespace pod-security.kubernetes.io/enforce=baseline

kubectl annotate serviceaccount \
  --namespace $namespace \
  $gke_sa \
  iam.gke.io/gcp-service-account=$rt_sa
```

---

## 1. 两个文档的简单汇总

### 文档一：[gcp/gke/workload-identify.md](/Users/lex/git/knowledge/gcp/gke/workload-identify.md)

这份文档偏“脚本和操作解释”，核心讲了三件事：

- 创建 Kubernetes ServiceAccount（KSA）
- 给 namespace 打 Pod Security Standards 标签
- 给 KSA 加 `iam.gke.io/gcp-service-account` annotation，用于 Workload Identity

它更强调：

- 每一步命令在做什么
- 什么时候必须配
- 什么时候可以不配

### 文档二：[safe/gcp-safe/workload-identify.md](/Users/lex/git/knowledge/safe/gcp-safe/workload-identify.md)

这份文档偏“概念和安全价值解释”，核心在讲：

- Workload Identity 是什么
- 为什么它比静态 SA key 更安全
- 它如何帮助实现最小权限原则
- 它把 KSA 和 GCP IAM 身份打通后，对访问 Google Cloud API 的意义

它更强调：

- 安全性
- 身份边界
- 访问控制模型

### 两份文档合并后的核心结论

如果把两份文档压缩成一句话：

**Namespace label 主要是约束 Pod 安全姿态；ServiceAccount annotation 主要是给 Pod 建立访问 Google Cloud 资源时的身份映射。**

也就是说，它们不是同一类能力。

---

## 2. 第一个动作到底做了什么

### 命令

```bash
kubectl label --overwrite ns $namespace pod-security.kubernetes.io/enforce=baseline
```

### 本质作用

这个动作是在 namespace 级别启用 **Pod Security Admission / Pod Security Standards** 的 `baseline` 策略。

它的本质不是 IAM，也不是 GCP 资源访问，而是：

**限制这个 namespace 里的 Pod 不能使用一些明显高风险的运行方式。**

根据 GKE 官方文档，给 namespace 打 `pod-security.kubernetes.io/enforce=baseline` 之后，违反 baseline 规则的 Pod 会被拒绝创建。[来源](https://cloud.google.com/kubernetes-engine/docs/how-to/podsecurityadmission)

### 它约束的大致方向

`baseline` 主要防止的是常见的权限提升和高风险运行模式，例如：

- 特权容器
- `hostNetwork`
- `hostPID`
- `hostIPC`
- 某些危险 abjability
- 某些不安全的 host namespace / hostPath 用法

### 它不做什么

这个 label：

- 不给 Pod GCP 权限
- 不影响 Workload Identity
- 不决定 Pod 能否访问 Secret Manager
- 不负责 image pull 的认证

它只管：

**这个 Pod 的安全姿态是否允许进入这个 namespace。**

---

## 3. 如果不打这个 namespace label，会影响什么

### 不打的直接后果

如果你不配置：

```bash
pod-security.kubernetes.io/enforce=baseline
```

那么这个 namespace 会缺少这层 Pod 安全基线约束。

这意味着：

- 某些高风险 Pod 配置不会被 admission 阶段直接拦截
- 开发或运维可以更容易把权限过高的 Pod 部署进去

### 这不会直接影响的东西

不打这个 label，通常**不会直接影响**：

- image pull
- Secret Manager 访问
- GCS / Pub/Sub / BigQuery / Spanner / Cloud SQL API 调用
- Workload Identity 本身

### 这可能影响的东西

它更可能影响的是：

- 特权工作负载是否被允许部署
- 某些 DaemonSet / Agent / 调试 Pod 是否被拦截
- 某些需要 `hostNetwork`、`hostPath`、`privileged` 的应用是否能成功创建

所以它影响的是：

**Pod 能不能按某种高权限方式运行**

而不是：

**Pod 能不能访问 Google Cloud 服务**

---

## 4. 第二个动作到底做了什么

### 命令

```bash
kubectl annotate serviceaccount \
  --namespace $namespace \
  $gke_sa \
  iam.gke.io/gcp-service-account=$rt_sa
```

### 本质作用

这个 annotation 的作用是：

**把 Kubernetes ServiceAccount（KSA）和一个 Google Cloud IAM Service Account（GSA）建立映射关系。**

在你现在的实现模式里，它属于：

- KSA -> GSA impersonation 方式
- 也就是 Pod 使用 KSA，在 GKE metadata server / Workload Identity 流程中，最终拿到 GSA 身份来调用 Google Cloud API

官方文档说明了两类思路：

- 直接把 IAM 权限授给 KSA 对应的 workload identity principal
- 或通过 KSA 绑定到 GSA，让 workload 以 GSA 身份访问 Google Cloud API  
  [来源](https://cloud.google.com/iam/docs/workload-identities) [来源](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)

而你这里显然用的是第二种。

### 它在整个链路里扮演什么角色

它不是完整配置的全部，但它是关键的一环。

整个链路通常是：

1. Pod 使用某个 KSA 运行
2. KSA 上有 `iam.gke.io/gcp-service-account=...`
3. GSA 上授予：
   - `roles/iam.workloadIdentityUser`
   - 给对应 KSA principal
4. Pod 通过 GKE metadata server 获取短期凭证
5. Pod 用该 GSA 身份访问 Google Cloud API

如果只做 annotation，不做 IAM binding，也是不完整的。

---

## 5. 如果不做这个 serviceaccount annotation，会影响什么

这里要分开讲，避免误解。

### 5.1 Pod 会不会启动

**通常仍然可以启动。**

因为这个 annotation 不是 Pod 启动的硬性前提。

Pod 是否能启动，更取决于：

- image 是否可拉取
- PodSpec 是否合法
- namespace 安全策略
- 调度和资源

### 5.2 会不会影响 image pull

**通常不会直接影响普通 Pod 镜像拉取。**

这一点非常关键。

根据 GKE 官方文档，GKE 节点拉取私有 Artifact Registry 镜像时，通常使用的是 **node service account** 的权限，而不是 Pod 的 KSA / Workload Identity。[来源](https://docs.cloud.google.com/kubernetes-engine/security/configure-node-service-accounts)

所以对大多数标准场景来说：

- `iam.gke.io/gcp-service-account` annotation
- 不决定 kubelet 能不能帮你 pull image

### 5.3 会直接影响什么

它最直接影响的是：

**Pod 内部应用代码能不能以预期的 GCP 身份访问 Google Cloud API。**

例如这些场景会直接受影响：

- Secret Manager
- Cloud Storage
- Pub/Sub
- BigQuery
- Spanner
- Cloud KMS
- Cloud SQL 相关 API / connector
- 任何依赖 Application Default Credentials 调 Google API 的代码

如果 annotation 缺失，并且你又没有采用“直接给 KSA principal 授 IAM”的新路径，那么常见结果是：

- Pod 内部获取不到预期 GSA 凭证
- 调 Google API 返回 `403` 或认证失败

### 5.4 Secret Manager 会有什么表现

如果应用依赖：

- Secret Manager API 动态拉取 secret

但 KSA 没有正确映射到 GSA，或者 GSA 没有相应 IAM 权限，那么通常表现为：

- 容器能启动
- 但应用初始化时拉 secret 失败
- 进而导致 readiness 失败、启动失败或业务逻辑异常

### 5.5 Cloud SQL / 其他业务逻辑会有什么表现

同理，如果应用依赖：

- Cloud SQL Auth Proxy / connector
- GCS 配置文件读取
- Pub/Sub 收发消息
- BigQuery 查询
- 调用任何 Google API

但没做正确身份映射，就会出现：

- 应用逻辑报错
- 鉴权失败
- token 获取失败
- 403 / permission denied

所以它影响的是：

**Pod 启动后的业务能力**

而不是：

**Pod 本身能不能被调度起来**

---

## 6. 这两个动作之间是什么关系

很多人会把它们混在一起，但它们实际上是两条不同控制线：

### Namespace Pod Security Label

解决的是：

- Pod 安全姿态
- 运行权限边界
- admission 阶段是否允许部署

### ServiceAccount Workload Identity Annotation

解决的是：

- Pod 对外访问 Google Cloud API 时用什么身份
- IAM 权限边界
- Google Cloud 资源访问控制

所以更准确地说：

- 前者是 **运行时安全基线**
- 后者是 **云资源访问身份**

---

## 7. 从架构角度，这个配置组合实现了什么

如果把你的脚本动作合在一起看，它做的是一套很典型的 GKE workload 安全落地：

### 第一层：Namespace 安全约束

```bash
kubectl label --overwrite ns $namespace pod-security.kubernetes.io/enforce=baseline
```

作用：

- 防止 namespace 成为“高权限 Pod 随意落地”的地方

### 第二层：Pod 身份最小化

```bash
kubectl create sa $gke_sa -n $namespace
```

作用：

- 不用 default SA
- 每类 workload 有独立身份

### 第三层：云资源访问身份映射

```bash
kubectl annotate serviceaccount ... iam.gke.io/gcp-service-account=$rt_sa
```

作用：

- 让这个 workload 用特定 GSA 身份访问 Google Cloud

### 合起来的架构意义

这套设计本质上是在同时解决两件事：

1. **这个 Pod 能不能以安全姿态运行**
2. **这个 Pod 运行后能以什么云身份访问外部资源**

这就是它的真正价值。

---

## 8. 如果不做这套处理，可能带来的实际影响

下面按你最关心的方式总结。

### 不做 Pod Security namespace label

可能带来的影响：

- 高权限 Pod 更容易被部署进来
- 某些危险配置不会被 admission 阶段拦住
- 集群安全基线变弱

不太会直接影响：

- image pull
- Secret Manager
- GCP API 权限

### 不做 serviceaccount annotation

可能带来的影响：

- Pod 能启动，但访问 GCP API 时身份不对
- Secret Manager 拉取失败
- Cloud Storage / Pub/Sub / BigQuery / KMS / Spanner / Cloud SQL 等访问失败
- 应用启动后才暴露问题，而不是创建 Pod 时立即报错

通常不直接影响：

- Namespace 创建
- Pod admission
- 普通镜像拉取

### 不创建独立 KSA，只用 default SA

可能带来的影响：

- 身份边界不清晰
- 多个 workload 共用默认身份
- 后续 RBAC 和 IAM 审计更难做

---

## 9. 最关键的结论

如果把你贴出来的两条命令总结成一句话：

**`pod-security.kubernetes.io/enforce=baseline` 是在约束 workload “怎么运行”，而 `iam.gke.io/gcp-service-account=...` annotation 是在决定 workload “以什么云身份访问 GCP”。**

再进一步压缩：

- 前者主要影响 **安全姿态和准入**
- 后者主要影响 **GCP API 访问能力**

所以如果你问：

> 不做这个对应处理会不会影响 image pull？还是 Secret Manager？还是其他业务？

最准确的回答是：

- **PSS label**：更偏 Pod 安全和准入，不是 image pull / Secret Manager
- **KSA annotation**：更偏 Google Cloud API 访问能力，会明显影响 Secret Manager 和其他 GCP 服务访问
- **Image pull**：大多数标准 GKE 场景下，更常由 node service account 决定，而不是这个 annotation

---

## 10. 推荐实践

如果你的 workload 需要访问 Google Cloud 资源，我建议继续保留这套做法，并再确认这几件事：

- [ ] Namespace 是否有合适的 Pod Security label
- [ ] 是否为 workload 创建了独立 KSA，而不是直接用 default
- [ ] KSA 是否加了正确的 `iam.gke.io/gcp-service-account` annotation
- [ ] GSA 是否已经授予 `roles/iam.workloadIdentityUser`
- [ ] GSA 本身是否拥有目标 GCP 资源所需 IAM 权限
- [ ] Node service account 是否具备私有镜像拉取权限（如果你用的是私有 Artifact Registry）

这样你就能把：

- 集群内身份
- 准入安全
- 云资源访问
- 节点镜像拉取

这四类责任边界分清楚。
