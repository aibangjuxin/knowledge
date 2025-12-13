| **GCP-GKE-CTRL-51** | IDAM.5 - 特权访问控制 | 只有策略管理员必须有权创建准入策略。<br>注意:非策略管理员不得有权创建/更新/删除准入策略。 | CAEP team | 是 | 是 | 
| GCP-GKE-CTRL-51 | IDAM.5 - Privileged Access Control | Only policy administrators MUST have privileges to create admission policies.<br>Note: Non-policy admins must not have privileges to create/update/delete admission policies. | CAEP team | Yes | Yes | |
### **合规性说明与实施方案**
---
#### **1. 概念澄清：“准入策略”在GKE中指什么？**

在GKE的语境中，“准入策略”（Admission Policy）通常指 **Kubernetes准入控制器策略**

*   **Kubernetes准入控制器**：是GKE集群内部的安全屏障，它拦截发往Kubernetes API的请求（如创建Pod、更新Deployment），并根据策略决定是“允许”、“拒绝”还是“修改”该请求。这是实现集群内部资源合规性、安全性和最佳实践的强大工具。
*   **实现方式**：这些策略通常通过 **Policy Controller**（GKE Enterprise功能）或开源的 **OPA Gatekeeper** 来定义和强制执行。

因此，本控制项的核心是**限制谁可以在GKE集群内创建、更新和删除这些准入策略**。

---
#### **2. 如何定义“策略管理员”并控制权限？**

“策略管理员”（Policy Administrator）并非一个预设的角色，而是一个需要通过Kubernetes RBAC明确定义的**职责**。要实现权限控制，应遵循以下步骤：

1.  **创建专用的`ClusterRole`**：
    创建一个名为`policy-admin-role`的`ClusterRole`，专门授予管理准入策略相关资源的权限。这些关键资源包括：
    *   `constrainttemplates`
    *   所有具体的约束（Constraint）资源，例如 `k8srequiredlabels`
    *   `validatingwebhookconfigurations`
    *   `mutatingwebhookconfigurations`

    **`policy-admin-role.yaml` 示例：**
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: policy-admin-role
    rules:
    - apiGroups: ["templates.gatekeeper.sh", "constraints.gatekeeper.sh"]
      resources: ["*"]
      verbs: ["create", "update", "delete", "get", "list", "watch"]
    - apiGroups: ["admissionregistration.k8s.io"]
      resources: ["validatingwebhookconfigurations", "mutatingwebhookconfigurations"]
      verbs: ["create", "update", "delete", "get", "list", "watch"]
    ```

2.  **使用Google群组进行集中管理**：
    创建一个专门的Google群组，例如 `gke-policy-admins@your-domain.com`，用于管理所有策略管理员。

3.  **创建`ClusterRoleBinding`**：
    将`policy-admin-role`与`gke-policy-admins`群组绑定，从而将权限授予该群组。

    **`policy-admin-binding.yaml` 示例：**
    ```yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: policy-admin-binding
    subjects:
    - kind: Group
      name: "gke-policy-admins@your-domain.com"
      apiGroup: rbac.authorization.k8s.io
    roleRef:
      kind: ClusterRole
      name: policy-admin-role
      apiGroup: rbac.authorization.k8s.io
    ```

4.  **限制其他角色**：
    确保其他角色（尤其是`cluster-admin`）的授予受到严格限制，因为`cluster-admin`默认包含管理准入策略的所有权限。非策略管理员（如普通开发者）不应被授予这些高权限角色。

---
#### **3. 验证方法：如何证明只有策略管理员有权限？**

您可以通过以下命令审计RBAC设置，以证明只有授权的管理员才能管理准入策略。

**前提条件：**
*   已安装并配置`kubectl`以连接到您的GKE集群。
*   已安装`jq`工具，用于解析JSON输出。

**步骤1：查找哪些角色可以管理准入策略（以`constrainttemplates`为例）**

运行以下命令，查找所有能够创建、更新或删除`constrainttemplates`的`ClusterRole`。

```bash
# 查找可以写constrainttemplates的ClusterRole
kubectl get clusterroles -o json | \
jq -r '.items[] | select(.rules[]? | select((.resources[]? | index("constrainttemplates")) and ((.verbs[]? | index("create")) or (.verbs[]? | index("update")) or (.verbs[]? | index("delete")) or (.verbs[]? | index("*"))))) | .metadata.name'
```

**合规性预期输出**：
输出的角色列表应该非常短，理想情况下只包含您定义的`policy-admin-role`以及内置的`cluster-admin`等少数几个高权限角色。

**步骤2：检查谁被绑定到了这些高权限角色**

假设上一步找到了`policy-admin-role`和`cluster-admin`，现在检查谁被绑定到了这些角色。

```bash
# 检查谁被绑定到 policy-admin-role
kubectl get clusterrolebindings -o json | \
jq -r '.items[] | select(.roleRef.name=="policy-admin-role") | .subjects[] | .name'

# 检查谁被绑定到 cluster-admin (需要严格审计)
kubectl get clusterrolebindings -o json | \
jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .subjects[] | .name'
```

**合规性分析**：
*   绑定到`policy-admin-role`的应该是且仅应该是`gke-policy-admins@your-domain.com`群组。
*   绑定到`cluster-admin`的主体（用户或群组）列表必须是经过严格审批和备案的最高权限管理员。

通过提供上述`ClusterRole`和`ClusterRoleBinding`的审计结果，并与您的授权策略管理员列表进行比对，您就可以有力地证明`GCP-GKE-CTRL-51`得到了满足。

---
### **补充说明：Pod安全准入（PSA）作为另一种准入策略**

如您所发现，**Pod Security Admission (PSA)** 是GKE中另一种内置的、非常重要的准入策略。它专注于强制执行[Pod安全标准](https://kubernetes.io/docs/concepts/security/pod-security-standards/)（例如 `privileged`, `baseline`, `restricted`），是取代已弃用的PodSecurityPolicy（PSP）的官方方案。

#### **PSA如何工作？**

PSA通过为**命名空间（Namespace）添加标签**来工作。策略管理员通过修改命名空间上的标签来定义该命名空间内所有Pod必须遵循的安全级别。

**示例**：要在一个名为 `my-app` 的命名空间中强制执行 `baseline` 策略，管理员会执行：
```bash
kubectl label ns my-app pod-security.kubernetes.io/enforce=baseline
```

#### **PSA的“策略管理员”权限**

从上面的示例可以看出，**创建/更新/删除PSA策略的权限，直接等同于创建/更新/删除`namespaces`资源（尤其是其标签）的RBAC权限**。

因此，PSA的“策略管理员”就是指那些有权修改`namespaces`资源的用户或群组。这是一项非常高的权限，因为它可以影响整个命名空间的设置。

#### **PSA的权限验证方法**

要验证只有授权管理员才能管理PSA策略，您需要审计谁有权修改`namespaces`资源。

**步骤1：查找哪些`ClusterRole`可以修改`namespaces`**

```bash
kubectl get clusterroles -o json | \
jq -r '.items[] | select(.rules[]? | select((.resources[]? | index("namespaces")) and ((.verbs[]? | index("update")) or (.verbs[]? | index("patch")) or (.verbs[]? | index("*"))))) | .metadata.name'
```
**合规性预期输出**：
此命令通常会返回`cluster-admin`, `admin`, `edit`等内置的高权限角色。关键在于审计谁被绑定到了这些角色。

**步骤2：检查谁被绑定到了这些高权限角色**

```bash
# 以检查"admin"角色为例
kubectl get clusterrolebindings -o json | \
jq -r '.items[] | select(.roleRef.name=="admin") | .subjects[] | .name'
```
**合规性分析**：
确保绑定到这些角色的用户或群组是经过授权的管理员。普通开发者不应出现在此列表中。

**步骤3：审计当前集群中PSA策略的配置状态**

您可以通过以下命令快速查看所有命名空间当前正在实施的PSA策略，这可以作为合规性的现状证据。

```bash
kubectl get namespaces -o=jsonpath='{range .items[*]}{"Namespace: "}{.metadata.name}{"\n  Enforce: "}{.metadata.labels.pod-security\.kubernetes\.io/enforce}{"\n  Warn: "}{.metadata.labels.pod-security\.kubernetes\.io/warn}{"\n  Audit: "}{.metadata.labels.pod-security\.kubernetes\.io/audit}{"\n\n"}{end}'
```
**合规性预期输出示例**：
```
Namespace: my-app
  Enforce: baseline
  Warn: baseline
  Audit: baseline

Namespace: kube-system
  Enforce: privileged
  Warn: 
  Audit: 
...
```
此输出清晰地展示了每个命名空间所强制执行的Pod安全级别。