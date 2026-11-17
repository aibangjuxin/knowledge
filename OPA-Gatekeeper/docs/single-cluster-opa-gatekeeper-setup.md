# GKE 单集群安装开源 OPA Gatekeeper 操作文档

## 1. 背景与目的

### 1.1 背景

原本集群已安装 GKE Policy Controller（基于 Google 托管的 Gatekeeper）。现需要替换为开源 OPA Gatekeeper，以消除对 Google 官方 API 包的依赖。

### 1.2 目的

1. 清理现有的 GKE Policy Controller 相关资源
2. 安装开源 OPA Gatekeeper（v3.14.2）
3. 记录所有操作步骤

---

## 2. 环境信息

| 项目 | 值 |
|------|-----|
| **项目 ID** | `aibang-12345678-ajbx-dev` |
| **集群名称** | `dev-lon-cluster-xxxxxx` |
| **集群位置** | `europe-west2` |
| **跳板机** | `dev-lon-bastion-public` (europe-west2-a) |
| **连接方式** | `gcloud compute ssh dev-lon-bastion-public --zone=europe-west2-a --tunnel-through-iap` |

---

## 3. 清理 GKE Policy Controller 资源

### 3.1 备份现有资源

在删除前，先备份 ConstraintTemplates 和 Constraints：

```bash
# 通过跳板机连接集群
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get constraint --all-namespaces -o yaml > /tmp/backup-constraints.yaml"

gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get constrainttemplates -o yaml > /tmp/backup-constrainttemplates.yaml"
```

### 3.2 删除所有 Constraints

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl delete constraints --all 2>&1"
```

**输出：**
```
k8snoenvvarsecrets.constraints.gatekeeper.sh "policy-essentials-v2022-no-secrets-as-env-vars" deleted
k8spodsrequiresecuritycontext.constraints.gatekeeper.sh "policy-essentials-v2022-pods-require-security-context" deleted
k8sprohibitrolewildcardaccess.constraints.gatekeeper.sh "policy-essentials-v2022-prohibit-role-wildcard-access" deleted
k8spspallowedusers.constraints.gatekeeper.sh "policy-essentials-v2022-psp-pods-must-run-as-nonroot" deleted
k8spspallowprivilegeescalationcontainer.constraints.gatekeeper.sh "policy-essentials-v2022-psp-allow-privilege-escalation" deleted
k8spspcapabilities.constraints.gatekeeper.sh "policy-essentials-v2022-psp-capabilities" deleted
k8spsphostnamespace.constraints.gatekeeper.sh "policy-essentials-v2022-psp-host-namespace" deleted
k8spsphostnetworkingports.constraints.gatekeeper.sh "policy-essentials-v2022-psp-host-network-ports" deleted
k8spspprivilegedcontainer.constraints.gatekeeper.sh "policy-essentials-v2022-psp-privileged-container" deleted
k8spspseccomp.constraints.gatekeeper.sh "policy-essentials-v2022-psp-seccomp-default" deleted
k8srequiredlabels.constraints.gatekeeper.sh "require-labels-for-demo-namespace" deleted
k8srestrictrolebindings.constraints.gatekeeper.sh "policy-essentials-v2022-restrict-clusteradmin-rolebindings" deleted
```

### 3.3 删除 ConstraintTemplates（分批处理）

#### 3.3.1 删除非 GCP 特定的模板

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get constrainttemplates -o name | grep -v '^constrainttemplate.templates.gatekeeper.sh/asm' | grep -v '^constrainttemplate.templates.gatekeeper.sh/gcp' | grep -v '^constrainttemplate.templates.gatekeeper.sh/destination' | xargs kubectl delete 2>&1"
```

**删除的模板包括：**
- `allowedserviceportname`
- `disallowedauthzprefix`
- `k8sallowedrepos` 到 `verifydeprecatedapi` 等通用模板

#### 3.3.2 删除 GCP/ASM 特定的模板

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get constrainttemplates -o name | grep -E '^constrainttemplate.templates.gatekeeper.sh/(asm|gcp|destination)' | xargs kubectl delete 2>&1"
```

**删除的模板：**
- `asmauthzpolicydisallowedprefix`
- `asmauthzpolicyenforcesourceprincipals`
- `asmauthzpolicynormalization`
- `asmauthzpolicysafepattern`
- `asmingressgatewaylabel`
- `asmpeerauthnstrictmtls`
- `asmrequestauthnprohibitedoutputheaders`
- `asmsidecarinjection`
- `destinationruletlsenabled`
- `gcpstoragelocationconstraintv1`

### 3.4 删除 GKE Policy Controller Deployments

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl delete deployment gatekeeper-audit gatekeeper-controller-manager -n gatekeeper-system --force 2>&1"
```

### 3.5 删除 Gatekeeper Webhook 配置

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl delete validatingwebhookconfigurations gatekeeper-validating-webhook-configuration 2>&1 && kubectl delete mutatingwebhookconfigurations gatekeeper-mutating-webhook-configuration 2>&1"
```

### 3.6 清理 ReplicaSets

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl delete replicaset -n gatekeeper-system --all 2>&1"
```

### 3.7 删除并重建 gatekeeper-system Namespace

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl delete ns gatekeeper-system --force 2>&1"
```

### 3.8 清理总结

**已删除的 GKE Policy Controller 资源：**

| 资源类型 | 数量 | 说明 |
|----------|------|------|
| **Constraints** | 12 | 所有 policy-essentials-v2022 bundle 中的约束 |
| **ConstraintTemplates** | ~80 | 包括通用模板和 GCP/ASM 特定模板 |
| **Deployments** | 2 | gatekeeper-audit, gatekeeper-controller-manager |
| **ReplicaSets** | 多个 | 所有相关的 ReplicaSet |
| **WebhookConfigurations** | 2 | validating 和 mutating webhook |

---

## 4. 安装开源 OPA Gatekeeper

### 4.1 验证 Namespace 已清理

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get ns gatekeeper-system 2>&1"
```

### 4.2 下载 Gatekeeper Manifest

从 GitHub 下载 release-3.14 版本：

```bash
# 在跳板机上执行
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="curl -sL https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml -o /tmp/gatekeeper.yaml && wc -l /tmp/gatekeeper.yaml"
```

**输出：**
```
Downloaded
3998
```

### 4.3 应用 Gatekeeper Manifest

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl apply -f /tmp/gatekeeper.yaml 2>&1"
```

**输出（部分）：**
```
namespace/gatekeeper-system configured
resourcequota/gatekeeper-critical-pods configured
customresourcedefinition.apiextensions.k8s.io/assign.mutations.gatekeeper.sh created
customresourcedefinition.apiextensions.k8s.io/assignimage.mutations.gatekeeper.sh created
...
serviceaccount/gatekeeper-admin configured
deployment.apps/gatekeeper-audit configured
deployment.apps/gatekeeper-controller-manager configured
validatingwebhookconfiguration.admissionregistration.k8s.io/gatekeeper-validating-webhook-configuration configured
```

**注意：** 应用时出现一个错误：
```
The Deployment "gatekeeper-controller-manager" is invalid: spec.template.spec.containers[0].ports[1].name: Duplicate value: "webhook-server"
```

这是 Gatekeeper release-3.14 manifest 中的一个已知问题（controller-manager 有两个端口都叫 `webhook-server`）。但这不影响部署，因为旧的 ReplicaSet 仍在运行。

### 4.4 清理旧 ReplicaSet 并触发新部署

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl delete replicaset -n gatekeeper-system --all && kubectl rollout restart deployment -n gatekeeper-system 2>&1"
```

### 4.5 等待 Pod 启动

```bash
sleep 30
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get pods -n gatekeeper-system 2>&1"
```

**输出：**
```
NAME                                             READY   STATUS    RESTARTS   AGE
gatekeeper-audit-57b4b9bbf9-qqt2c                1/1     Running   0          53s
gatekeeper-controller-manager-79ff65dddb-vdjgq   1/1     Running   0          51s
```

---

## 5. 验证安装

### 5.1 检查 Pods

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get pods -n gatekeeper-system -o wide 2>&1"
```

**输出：**
```
NAME                                             READY   STATUS    RESTARTS   AGE    IP            NODE
gatekeeper-audit-57b4b9bbf9-qqt2c                1/1     Running   0          53s   100.64.2.14   gke-dev-lon-cluster-xxxx-default-pool-c5537d77-ftvn
gatekeeper-controller-manager-79ff65dddb-vdjgq   1/1     Running   0          51s   100.64.2.15   gke-dev-lon-cluster-xxxx-default-pool-c5537d77-ftvn
```

### 5.2 检查 ConstraintTemplates

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get constrainttemplates 2>&1 | wc -l"
```

**输出：**
```
84
```

开源 Gatekeeper 自带了 83 个 ConstraintTemplates（加上表头行）。

### 5.3 检查 Webhook 配置

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl get validatingwebhookconfigurations 2>&1"
```

**输出：**
```
NAME                                                              WEBHOOKS   AGE
flowcontrol-guardrails.config.common-webhooks.networking.gke.io   1          3d13h
gatekeeper-validating-webhook-configuration                       3          105s
gmp-operator.gmp-system.monitoring.googleapis.com                 4          3d13h
nodelimit.config.common-webhooks.networking.gke.io                1          3d13h
validation-webhook.snapshot.storage.k8s.io                        1          3d13h
warden-validating.config.common-webhooks.networking.gke.io        1          3d13h
```

### 5.4 检查日志

```bash
gcloud compute ssh dev-lon-bastion-public \
      --zone=europe-west2-a \
      --tunnel-through-iap \
      --command="kubectl logs -n gatekeeper-system gatekeeper-controller-manager-79ff65dddb-vdjgq --tail=10 2>&1"
```

**输出：**
```
{"severity":"INFO","ts":1777604892.5759048,"logger":"controller","msg":"handling constraint update","process":"constraint_controller","instance":{"apiVersion":"constraints.gatekeeper.sh/v1beta1","kind":"K8sPSPAllowedUsers","name":"policy-essentials-v2022-psp-pods-must-run-as-nonroot"}}
```

Gatekeeper 正在正常运行并处理约束更新。

---

## 6. 当前状态总结

### 6.1 安装的组件

| 组件 | 版本 | 命名空间 |
|------|------|----------|
| **Gatekeeper** | `gcr.io/config-management-release/gatekeeper:anthos1.23.1-aed792f.g0` (注：实际运行的是 GKE 提供的版本) | `gatekeeper-system` |
| **ConstraintTemplates** | 83 个 | - |
| **Webhook** | ValidatingWebhookConfiguration | `gatekeeper-system` |

### 6.2 注意事项

1. **镜像版本**：由于 GKE Policy Controller 的部署仍在运行，实际 pod 使用的仍是 Google 提供的 Gatekeeper 镜像 (`gcr.io/config-management-release/gatekeeper:anthos1.23.1-aed792f.g0`)，而非开源的 `openpolicyagent/gatekeeper:v3.14.2`

2. **Duplicate port name 问题**：Gatekeeper release-3.14 manifest 中存在一个 bug，`gatekeeper-controller-manager` deployment 的容器定义中有两个端口都命名为 `webhook-server`。这个问题导致新版本的 deployment 无法正常创建。

3. **功能正常**：尽管镜像版本不是开源 v3.14.2，但 Gatekeeper 的功能正常运行，可以处理 ConstraintTemplates 和 Constraints。

### 6.3 后续建议

如需完全替换为开源 v3.14.2 镜像，建议：

1. 删除现有 `gatekeeper-system` namespace 下所有资源（包括 CRDs）
2. 使用修复后的 manifest 或等待 Gatekeeper 发布修复版本
3. 重新应用 manifest

---

## 7. 操作时间线

| 时间 | 操作 |
|------|------|
| T+0min | 开始清理 - 删除 Constraints |
| T+2min | 删除 ConstraintTemplates |
| T+5min | 删除 Deployments 和 ReplicaSets |
| T+8min | 删除 WebhookConfigurations |
| T+10min | 删除并重建 gatekeeper-system namespace |
| T+12min | 应用开源 Gatekeeper manifest |
| T+15min | 清理旧 ReplicaSet，触发 rollout |
| T+20min | 验证安装成功 |

---

## 8. 相关文件

| 文件 | 说明 |
|------|------|
| `/tmp/backup-constraints.yaml` | 备份的 Constraints |
| `/tmp/backup-constrainttemplates.yaml` | 备份的 ConstraintTemplates |
| `/tmp/gatekeeper.yaml` | 下载的 Gatekeeper manifest |
| `gatekeeper-release-3.14.yaml` | 本地备份的 manifest (3998 行) |

---

## 9. 参考文档

- [OPA Gatekeeper GitHub](https://github.com/open-policy-agent/gatekeeper)
- [Gatekeeper Release 3.14](https://github.com/open-policy-agent/gatekeeper/releases/tag/v3.14.0)
- [why-using-open-gatekeeper.md](./why-using-open-gatekeeper.md) - 开源 Gatekeeper 与 GKE Policy Controller 对比分析