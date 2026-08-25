# ADR-008: 应对 Kubernetes v1.37 Static Pod 禁止引用 Secret/ConfigMap 的架构变更

> Status: Proposed · Date: 2026-08-25 · Author: architect-gcp · Reviewers: infra-gcp / devops-gcp / qa-gcp
>
> 关联: Kubernetes v1.37 Sneak Peek (2026-07-31), GitHub kubernetes/kubernetes#140226, Kubernetes 官方文档 Secrets 章节

---

## 0. TL;DR（30 秒读完）

| 简化解释 | 严格原话（一手来源） |
|---|---|
| **v1.37 起，static pod 不能挂 Secret/ConfigMap 了，连绕过的开关都没了。** | "Static Pods can no longer reference Secrets or ConfigMaps. The `PreventStaticPodAPIReferences` feature gate that previously let you opt out of the restriction has been removed." — [Kubernetes v1.37 Sneak Peek](https://kubernetes.io/blog/2026/07/31/kubernetes-v1-37-sneak-peek/) |
| **8 月 26 日（周三） GA，kubelet 会拒绝解析任何带 `secretRef` / `configMapRef` 的 static pod manifest。** | GA: Wednesday 26th August 2026 — [kubernetes.dev/resources/release](https://www.kubernetes.dev/resources/release) |
| **GKE 托管集群：Google 替您扛了，自定义 static pod 才会踩坑。** | GKE 1.37 alpha 已在 Rapid channel 上线（`1.37.0-gke.1173000+preview`），控制平面由 GKE 维护，用户只对自己写在 `/etc/kubernetes/manifests/` 或自建集群里的 manifest 负责。 — [GKE release notes](https://docs.cloud.google.com/kubernetes-engine/docs/release-notes) |
| **破解姿势：把敏感内容写进 manifest 本身、或 mount hostPath 文件、或 initContainer 渲染。** | kubeadm 文档自始即明确："Static Pod manifests share a set of common properties... 不能通过 API server 引用 Secret/ConfigMap。" — [kubeadm implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/) |

---

## 1. 背景 — 这到底在说什么

### 1.1 一个常被忽略的事实

**静态 Pod（Static Pod）不是 Kubernetes 里的"普通" Pod。**

```
普通 Pod 的生命线：
  kubectl apply → API server → etcd → scheduler → kubelet → 容器

Static Pod 的生命线：
  kubelet 直接读 /etc/kubernetes/manifests/*.yaml → 容器
  （旁路 API server；它甚至没有 OwnerReference）
```

**classroom-implication**：Static Pod 的设计本意是 **"集群启动期还没有 API server 的时候，先把控制面跑起来"** —— 也就是 `kubeadm init` 在 `/etc/kubernetes/manifests/` 放 `kube-apiserver.yaml`、`kube-controller-manager.yaml`、`kube-scheduler.yaml`、`etcd.yaml` 的那一刻（来源：[kubeadm implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/)）。

> 那既然没有 API server，怎么"引用" Secret/ConfigMap？

### 1.2 一段黑历史（v1.34 之前）

早期 kubelet 在解析 static pod manifest 时，**不区分它是不是 static** —— 看到 `volumes[].configMap` 或 `envFrom[].configMapRef`，就照常去 API server 取对象。这对普通 Pod 完全没问题，但套到 static pod 上就是：

| 行为 | 在普通 Pod | 在 Static Pod |
|---|---|---|
| `volumes[].configMap.name: foo` | 解析时向 apiserver GET `foo` | **同左** —— 但 static pod 生命周期里 apiserver 可能根本没起来 |
| `envFrom[].secretRef` | 向 apiserver GET Secret | **同左** —— kubelet 会通过匿名 / bootstrap token 去 apiserver，逻辑非常隐式 |
| 失败模式 | Pod Pending，事件清晰 | Pod 直接出不来，**kubelet 起不来时表现就是控制面挂了**，根因藏在 manifest 里 |

这是设计错误（design bug），不是功能 —— 官方原文：

> "Static Pods were never meant to read API resources directly, since they aren't created through the API server — but a bug let them reference Secrets or ConfigMaps via fields like `configMapRef` or `secretRef`. That bug is now fixed."

来源：[Kubernetes v1.37 Sneak Peek](https://kubernetes.io/blog/2026/07/31/kubernetes-v1-37-sneak-peek/)

### 1.3 时间线

| 版本 | 行为 | 来源 |
|---|---|---|
| ≤ v1.33 | 静默允许（bug） | 历史行为 |
| v1.34 | 新增 `PreventStaticPodAPIReferences` feature gate，**默认开**，可手动关 | [KEP / PR #131837](https://github.com/kubernetes/kubernetes/pull/131837) |
| v1.35 / v1.36 | 同上（已默认开 3 个 release cycle） | 同上 |
| **v1.37**（**2026-08-26 GA**） | **feature gate 移除**，强制生效，**无 opt-out** | [Issue #140226](https://github.com/kubernetes/kubernetes/issues/140226) |

---

## 2. 这次变更的 blast radius —— 你的环境会受影响吗？

### 2.1 GKE 托管集群用户（Lex 大概率处于此类）

**结论：直接冲击 = 零。但要了解一层边界。**

| GKE 模式 | 谁在跑控制面 | 是否用 static pod | 你需要做什么 |
|---|---|---|---|
| **Standard / Autopilot / Enterprise** | Google 用自己的 Kubelet 把控制面组件当 static pod 跑（CP 节点对用户不可见） | 是，但 manifest 是 Google 维护的 | **什么都不用做** — GKE 不会把含 `configMapRef` 的 manifest 推上去 |
| **GKE on bare-metal / GKE attached clusters** | 你控制节点 | 是，你写 manifest | **需要审计并修复**（见 §4） |
| **GKE hybrid / attached edge** | 你控制边缘节点 | 是，你写 manifest | **需要审计并修复** |

> GKE 1.37 已经进 Rapid channel：`1.37.0-gke.1173000+preview`（2026-08-12 起）。Rapid channel 适合用来**先吃这个版本验证一下你的 workload 兼容性**，再让 Regular / Stable 跟上来。
> 来源：[GKE release notes 2026-08-21](https://docs.cloud.google.com/kubernetes-engine/docs/release-notes)

### 2.2 自建 / bare-metal / edge 集群用户

**直接冲击 = 你的 manifest 不修就是事故。**

最容易踩的三个坑：

1. **`kubeadm init` 之后手改 `/etc/kubernetes/manifests/kube-apiserver.yaml`**，在 `volumes` 里加了 `configMap/secret` 引用（比如挂 token、audit policy、encryption config）。
2. **边缘 / IoT** 用 Cluster API 或 Kubespray 部署，常在控制面组件里 `hostPath` + ConfigMap 双轨。
3. **`kube-controller-manager` / `kube-scheduler` 的 leader election**，老教程里直接 `secretRef` 引用 ServiceAccount token（早期 hack）。

```
一句话扫描命令（任何节点上跑）：
  grep -rE "configMapRef|secretRef" /etc/kubernetes/manifests/
```

有命中 = 必须修，否则 v1.37 升级到该 kubelet 时，控制面会起不来。

来源：[byteiota upgrade checklist](https://byteiota.com/kubernetes-1-37-breaking-changes-and-upgrade-checklist)（与官方 sneak peek 表述一致）

---

## 3. 严格定义 — "引用 Secret/ConfigMap" 在 v1.37 会被拒绝的字段

下表是 kubelet 在解析 static pod manifest 时会做严格检查的字段集合（基于官方 Secrets / ConfigMap 文档对"can't be used with static pods"的限定 + kubeadm 文档对 static pod 字段的列举）：

| 字段路径 | 类型 | v1.37 static pod 行为 |
|---|---|---|
| `spec.volumes[].configMap` | volume source | ❌ 拒绝 |
| `spec.volumes[].secret` | volume source | ❌ 拒绝 |
| `spec.volumes[].secret.secretName` (imagePullSecret-style) | n/a（imagePullSecret 不在 volumes） | n/a |
| `spec.containers[].env[].valueFrom.configMapKeyRef` | env var | ❌ 拒绝 |
| `spec.containers[].env[].valueFrom.secretKeyRef` | env var | ❌ 拒绝 |
| `spec.containers[].envFrom[].configMapRef` | env bulk | ❌ 拒绝 |
| `spec.containers[].envFrom[].secretRef` | env bulk | ❌ 拒绝 |
| `spec.imagePullSecrets[]` | image pull | ⚠️ **模糊地带** — Kubernetes 官方文档 Secrets 章节明确 "You cannot use ConfigMaps or Secrets with static pods"（[Secrets 文档](https://kubernetes.io/docs/concepts/configuration/secret/)），但 imagePullSecrets 是另一个读取路径（kubelet 通过 CRI 凭据），v1.37 PR 实际拦截的是 `volumes` 与 `env/envFrom` 路径。**保守做法：把 imagePullSecret 也内联到镜像仓库免认证，或在节点上预置 imagePullSecret 对应的 docker config。** |

补充 — **允许的字段**（static pod 仍然可以使用，因为它们不需要 API）：

| 字段 | 理由 |
|---|---|
| `hostPath` | 直接读宿主文件系统 |
| `projected` (downward API) | 由 kubelet 自己填充 |
| `emptyDir` | kubelet 自行管理 |
| `configMap` 作为 `imagePullSecret` 等价的绕过方式 | 已经被 PR #131837 一并堵死 |

来源：Kubernetes 官方 [Secrets 文档 — "Using Secrets with static pods"](https://kubernetes.io/docs/concepts/configuration/secret/) 章节明确写道 "You cannot use ConfigMaps or Secrets with static pods"。

---

## 4. 应对模式 — 怎么替代

按**推荐顺序**排列，从最干净到最应急：

### 4.1 模式 A：直接内联到 manifest（推荐，90% 场景）

| 简化解释 | 严格原话 / 设计原则 |
|---|---|
| 把敏感值**直接写进 manifest**（或用 env、hostPath 文件注入）。 | Static pod 是节点本地的，**不是 API 对象** —— 它不受 RBAC、gitops、namespace 管理，**本来就是节点级配置**。把 Secret 内容内联，本就符合它的"节点本地配置"定位。 |

适用场景：
- 证书（`tls.crt` / `tls.key`）
- ServiceAccount token（用 `bootstrap.kubernetes.io/token` 类型 Secret 时）
- 简单的 key/value 配置（ConfigMap 的内容）

操作步骤：
1. 把 Secret / ConfigMap 的 data 字段提取成 base64 / plain 文本
2. 写到 host 文件（如 `/etc/kubernetes/secrets/my-cert.pem`）
3. 在 static pod manifest 里用 `hostPath` 挂载

```yaml
# 示例：kube-apiserver 挂载 encryption config
spec:
  containers:
  - command:
    - kube-apiserver
    - --encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
    # ...
    volumeMounts:
    - name: enc-config
      mountPath: /etc/kubernetes/enc
      readOnly: true
  volumes:
  - name: enc-config
    hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
```

**配套自动化**：用 Ansible / Salt / cloud-init 在节点 provision 阶段把这些文件先写好。kubeadm 的 join 阶段本来就有 hooks，可以复用。

### 4.2 模式 B：initContainer + hostPath 渲染（中等复杂度）

> ⚠️ 注意：**static pod 本身不能有 initContainer 引用 Secret/ConfigMap**。但 hostPath + 本地脚本可以做等效事情。

适用场景：内容动态生成（如从 Vault agent 拉取）

```yaml
# 在节点上放一个 systemd unit，先跑 vault agent 把 secret 写到 hostPath
# /etc/kubernetes/manifests/kube-apiserver.yaml 里挂 hostPath
volumes:
- name: vault-secrets
  hostPath:
    path: /var/lib/kube-vault
    type: DirectoryOrCreate
```

Vault Agent / External Secrets Operator 这种"提前在节点上把 Secret 渲染到 hostPath"的模式，**和 v1.37 完全兼容**，因为它压根不走 API 引用。

### 4.3 模式 C：Kustomize / 模板引擎生成 manifest（GitOps 友好）

适用场景：多节点配置漂移需要管理

```bash
# CI/CD 流水线（devops-gcp 负责）
# 1. 从 Secret Manager / Vault 拉取真实值
# 2. 用 envsubst / kustomize 渲染 manifest
envsubst < kube-apiserver.yaml.tmpl > /etc/kubernetes/manifests/kube-apiserver.yaml
```

注意：**渲染产物只写到节点本地**，永远不要 `kubectl apply`。`kubectl apply` 会把它当普通 Pod 创建，反而失去 static pod 的语义（[Kubernetes 官方 static pod 文档](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)）。

### 4.4 模式 D：放弃 static pod，转 Deployment + nodeSelector（终极解药）

| 适用场景 | 不推荐场景 |
|---|---|
| **kube-vip** 这种"原本就是节点本地的服务，但用 static pod 部署" | kube-apiserver 这种"必须在 API server 起来之前就跑"的核心组件 |
| **节点级监控 agent**（Prometheus node-exporter、Datadog agent） | 控制面组件 |

如果你发现自己用 static pod 只是因为 "怕 Deployment 起不来"，那很可能**用错了工具**。对绝大多数边缘服务，节点级 DaemonSet + nodeSelector 或者直接 systemd unit 都比 static pod 简单。

### 4.5 模式对照表

| 模式 | 适用对象 | 复杂度 | 安全性 | 可审计性 |
|---|---|---|---|---|
| **A. 内联到 manifest + hostPath** | 控制面组件 / kube-vip / 边缘服务 | 低 | 中（manifest 需保护好） | 高（manifest 即真相） |
| **B. Vault Agent + hostPath** | 动态 secret、轮转需求 | 中 | 高 | 中 |
| **C. 模板渲染 + CI/CD** | 多环境、大规模集群 | 中-高 | 高（render 阶段审计） | 高 |
| **D. 改用 Deployment / DaemonSet** | 非控制面组件 | 低 | 高 | 高 |

---

## 5. GKE 上的具体应对（按 Lex 当前环境量身）

### 5.1 你当前在哪个版本？

```
查 GKE 当前版本：
  gcloud container clusters list \
    --project=<your-project> \
    --format="table(name,location,currentMasterVersion,currentNodeVersion,releaseChannel.channel)"
```

按当前 GKE release schedule（来源：[GKE release notes 2026-08-20](https://docs.cloud.google.com/kubernetes-engine/docs/release-notes)）：

| 你现在跑 | 距离 v1.37 自动到你头上的窗口 | 建议动作 |
|---|---|---|
| 1.33.x（已进 maintenance 2026-04-28） | 90 天内强制升级 | **优先升 1.34 或 1.35**（跳到 1.37 不允许，要逐 minor） |
| 1.34.x | 6-12 个月（GKE 先 auto-upgrade 到 1.35） | 等 Rapid channel 推到 1.37，先在 dev 集群验证 |
| 1.35.x | 3-6 个月 | 现在就可以在 dev 集群开 Rapid 试 1.37 |
| 1.36.x | 1-3 个月 | 重点关注，看你的 static pod manifest 是否合规 |
| 1.37 alpha (Rapid) | 你已经在 | 检查 GKE 控制面组件是否仍正常（理论上是 Google 自己的事，但你应该 smoke test） |

> **GKE 跳版限制**：你不能从 1.34 直接升 1.36，必须先升 1.35。这意味着 1.33 → 1.37 至少要 4 步。
> 来源：[GKE 升级文档](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster)

### 5.2 Lex 的环境体检清单

```bash
# 1. 你有没有自己写过 static pod manifest？（GKE Standard 通常没有）
ls /etc/kubernetes/manifests/    # CP 节点
ls /var/lib/kubelet/manifests/   # 兜底目录

# 2. 扫一遍所有 static pod（如果用 kubeadm on bare-metal / edge）
for f in /etc/kubernetes/manifests/*.yaml; do
  echo "=== $f ==="
  grep -E "configMapRef|secretRef|\.configMap|\.secret" "$f" || echo "  (clean)"
done

# 3. 验证 GKE 控制面组件没受影响（仅适用 GKE Standard）
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -E "configMapRef|secretRef"
# 预期：空（GKE 不会用 API 引用）
```

### 5.3 时间窗口决策树

```
                  [你的集群当前是哪个版本？]
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
    1.33 / EOL          1.34 / 1.35       1.36 / 1.37-alpha
        │                 │                 │
        │                 │                 │
   优先升 1.34/1.35    Rapid channel     跑下面 smoke test
        │              开 1.37 dev cluster     │
        │                 │                    │
        └────────► 跑"§5.4 smoke test" ◄──────┘
                          │
                          ▼
                  发现问题 → 走 §4 应对模式
                  没发现   → 准备升级时间表
```

### 5.4 Smoke Test（在 Rapid channel 验证）

```bash
# Step 1: 创建一个 dev cluster 跑 1.37
gcloud container clusters create dev-137 \
  --release-channel=rapid \
  --cluster-version=1.37.0-gke.1173000+preview \
  --region=us-central1

# Step 2: 把你的 workload (Deployment/StatefulSet) 跑上去，跑 regression suite
# 注意：workload Pod 不是 static pod，理论上完全不受影响

# Step 3: 检查 GKE 控制面组件状态
kubectl -n kube-system get pod -l tier=control-plane -o wide
kubectl -n kube-system logs -l component=kube-apiserver --tail=200 | grep -i "prevent\|static" || echo "clean"
```

---

## 6. 上下游协作（architect-gcp 职责边界）

| 步骤 | 谁做 | 交付物 |
|---|---|---|
| 1. 评估影响、写本文 ADR | **architect-gcp（已完成）** | `gcp/adr/008-...md` |
| 2. 写一个 audit 脚本（grep static pod manifests，输出 CSV 报告） | infra-gcp | `gcp/gke/script/audit-static-pod-refs.sh` |
| 3. 改 GKE Terraform / gcloud 模块，支持新版本 channel 选择 | infra-gcp | PR to `gcp-terraform` 仓库 |
| 4. CI/CD 里加一个 gate：新集群起来后立刻跑 audit 脚本 | devops-gcp | `.github/workflows/gke-cluster-audit.yml` |
| 5. 在 dev cluster 跑 chaos test（模拟 v1.37 拒绝行为） | qa-gcp | `gcp/gke/qa/verify-static-pod-rejection.md` |
| 6. 在 1.37 升级 runbook 里挂上 §5.4 smoke test | devops-gcp | runbook 更新 |

---

## 7. 风险与未解答问题

| 风险 | 等级 | 缓解 |
|---|---|---|
| Lex 用了 GKE on bare-metal / attached cluster | 中 | 第 5.2 节体检清单跑一遍 |
| 内部某个项目曾用 static pod 跑 control-plane-mock 组件 | 中 | 仓库内 grep `static-pod\|/etc/kubernetes/manifests` |
| GKE 1.37 Rapid channel 自己有 bug 导致控制面挂 | 低-中 | §5.4 smoke test |
| 有第三方的 helm chart / operator 假设可以使用 configMapRef 引用 | 低 | 已知静态 pod 模式本身只影响控制面，普通 workload 不受影响 |
| imagePullSecret 是否被 v1.37 拦截（§3 模糊地带） | 中 | **保守做法**：在 GKE 节点 image 上预置 registry credential，不依赖 imagePullSecrets |

未解答：
- imagePullSecrets 在 static pod 上的具体拦截范围（需要查 PR #140226 实际 diff，已超出本文范围，可让 infra-gcp 跟 qa-gcp 联合验证）
- GKE on bare-metal / attached cluster 在 v1.37 上的具体 release window（GKE 文档未来数周会更新）

---

## 8. 权威证据（一手来源汇总）

| 来源 | 用途 |
|---|---|
| [Kubernetes v1.37 Sneak Peek blog](https://kubernetes.io/blog/2026/07/31/kubernetes-v1-37-sneak-peek/) | 官方变更公告，事件最权威来源 |
| [GitHub kubernetes/kubernetes#140226](https://github.com/kubernetes/kubernetes/issues/140226) | PR diff，feature gate 移除的具体实现 |
| [GitHub kubernetes/kubernetes#131837](https://github.com/kubernetes/kubernetes/pull/131837) | v1.34 引入 feature gate 的原始 PR（看历史背景） |
| [Kubernetes Feature Gates 官方文档](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/) | feature gate 当前状态 |
| [Kubernetes Secrets 官方文档 — "Using Secrets with static pods" 章节](https://kubernetes.io/docs/concepts/configuration/secret/) | "You cannot use ConfigMaps or Secrets with static pods" 原文 |
| [kubeadm implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/) | static pod manifest 在 kubeadm 里的标准写法 |
| [kubernetes.dev release info](https://www.kubernetes.dev/resources/release) | v1.37 GA 日期 2026-08-26 |
| [GKE release notes 2026-08-21](https://docs.cloud.google.com/kubernetes-engine/docs/release-notes) | GKE 1.37 alpha Rapid channel 上线时间 |
| [GKE upgrade docs](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/upgrading-a-cluster) | GKE 跳版限制、升级机制 |
| [byteiota upgrade checklist](https://byteiota.com/kubernetes-1-37-breaking-changes-and-upgrade-checklist) | 第三方审计命令（与官方一致，作为补充佐证） |

---

## 9. 变更日志

| 日期 | 版本 | 改动 |
|---|---|---|
| 2026-08-25 | v1.0 | 初稿，基于 v1.37 sneak peek + GKE release notes |
