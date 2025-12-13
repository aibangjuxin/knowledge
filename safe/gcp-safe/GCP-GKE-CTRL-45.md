| GCP-GKE-CTRL-45 | IDAM.5 - Privileged Access Control | Privileged access MUST comply with aibang corporate PAM standards | CAEP team | Yes | Yes | 通过组合使用GCP IAM和Kubernetes RBAC，并结合Google群组进行集中管理，可以实现最小权限和职责分离，满足PAM要求。 |

### **合规性说明与实施方案**

为了使GKE中的特权访问满足企业PAM标准，需要综合运用 **Google Cloud IAM** 和 **Kubernetes RBAC** 两个层面的控制能力，并遵循最小权限原则（PoLP）和职责分离（SoD）的最佳实践。

---

#### **1. 实现原理：GKE特权访问如何工作？**

GKE的访问控制是一个分层模型：

*   **第一层：GCP IAM (平台级)**
    *   **作用**：控制谁可以对GKE集群本身进行操作（例如：创建、删除、修改集群配置、获取集群凭据）。这是进入集群的第一道大门。
    *   **特权身份**：拥有 `roles/container.admin` 或更广泛的 `roles/owner`, `roles/editor` 的用户/服务帐户被视为平台级特权用户。
    *   **关键链接**：当用户执行 `gcloud container clusters get-credentials` 时，GCP IAM会验证用户身份。只有验证通过，用户才能获取访问集群所需的 `kubeconfig` 文件。

*   **第二层：Kubernetes RBAC (集群内部)**
    *   **作用**：控制已经通过IAM认证的用户能在集群*内部*做什么（例如：创建Pod、查看Secret、删除Deployment）。
    *   **认证**：GKE会将用户的Google身份（IAM用户或服务帐户）传递给Kubernetes API Server进行认证。
    *   **授权**：认证成功后，RBAC系统根据 `(Cluster)Role` 和 `(Cluster)RoleBinding` 来决定用户的具体操作权限。
    *   **特权身份**：被绑定到 `cluster-admin` 这一 `ClusterRole` 的用户/组是集群内部的最高特权身份。

**核心机制**：用户的Google身份是贯穿两层的统一身份。IAM负责“进门”，RBAC负责“在屋里能干什么”。

---

#### **2. 控制方法：如何设计才能达到合规要求？**

要达到PAM标准，必须精细化地管理上述两个层级的权限。

1.  **使用Google群组集中管理权限 (Centralized Management)**
    *   **实践**：为不同的职责创建专门的Google群组（例如 `gke-cluster-admins`, `gke-namespace-developers`, `gke-auditors`）。
    *   **授权**：在IAM和RBAC中，将权限直接授予这些Google群组，而不是单个用户。
    *   **好处**：当需要授权或撤销用户权限时，只需在Google Workspace中将其加入或移出对应群组即可。这使得权限变更流程化、可审计，并避免了直接修改代码或命令行配置。

2.  **实施最小权限原则 (Principle of Least Privilege)**
    *   **IAM层面**：
        *   **禁止**：避免使用 `owner` 或 `editor` 等基本角色。
        *   **授予**：为开发者授予如 `roles/container.developer`（允许获取凭据和访问集群，但不能修改集群）的精细化角色。为审计人员授予 `roles/container.viewer`。
    *   **RBAC层面**：
        *   **严格限制 `cluster-admin`**：仅将其绑定给极少数管理员群组。
        *   **使用命名空间**：为不同应用或团队创建独立的Kubernetes命名空间，并在命名空间级别通过 `Role` 和 `RoleBinding` 授予开发者所需权限，避免其影响其他应用。

3.  **实施Just-in-Time (JIT) 临时权限（可选，高级控制）**
    *   对于“紧急破窗”等极少数需要最高权限的场景，可以通过自动化流程临时将用户加入特权Google群组，并在预设时间（例如1小时）后自动将其移出，以实现权限的即时申请和自动回收。

4.  **强化审计与监控 (Auditing & Monitoring)**
    *   **启用审计日志**：确保GKE集群启用了[Cloud Audit Logs](https://cloud.google.com/logging/docs/audit)，并收集**Admin Activity**和**Data Access**（特别是对Secrets等敏感资源的访问）日志。
    *   **设置告警**：在Cloud Monitoring中针对特权操作（如绑定`cluster-admin`角色、创建特权Pod等）或异常身份活动创建告警策略。

---

#### **3. 验证方法：如何证明已经合规？**

您可以通过以下命令和流程来收集证据，证明合规性。

1.  **验证IAM层面权限**
    *   **检查谁拥有集群管理员权限**：
        ```sh
        # 将 YOUR_PROJECT_ID 替换为您的项目ID
        gcloud projects get-iam-policy YOUR_PROJECT_ID --format='json' | \
        jq '.bindings[] | select(.role=="roles/container.admin" or .role=="roles/editor" or .role=="roles/owner")'
        ```
        *   **合规标准**：输出结果中的 `members` 应该是预期的管理员Google群组，而不应有个人用户账户。

2.  **验证RBAC层面权限**
    *   **获取集群凭据**：
        ```sh
        # 替换 CLUSTER_NAME 和 REGION/ZONE
        gcloud container clusters get-credentials YOUR_CLUSTER_NAME --zone YOUR_ZONE
        ```
    *   **检查谁拥有`cluster-admin`权限**：
        ```sh
        kubectl get clusterrolebinding -o json | \
        jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .subjects[] | select(.kind=="Group") | .name'
        ```
        *   **合规标准**：输出结果应该是您指定的管理员Google群组的邮件地址。如果出现个人用户或其他非预期条目，则为不合规。

3.  **审计特定命名空间权限**
    *   **检查谁能访问`default`命名空间中的`secrets`**：
        ```sh
        kubectl get rolebinding,clusterrolebinding -n default -o json | \
        jq '.items[] | select(.roleRef.name=="admin" or .roleRef.name=="edit" or .roleRef.name=="cluster-admin")'
        ```
        *   **合规标准**：审计绑定到高权限角色的主体（`subjects`），确保其符合最小权限原则。

4.  **审查审计日志**
    *   **查询入口**：访问GCP控制台 -> Logging -> Logs Explorer。
    *   **查询示例**：使用以下过滤器查询谁在过去7天内修改了RBAC绑定。
        ```
        resource.type="k8s_cluster"
        protoPayload.methodName:"rbac"
        timestamp >= "YYYY-MM-DDTHH:MM:SSZ" 
        ```
        *   **合规标准**：日志中记录的操作应与已批准的变更请求相匹配，证明所有特权操作都经过了授权和记录。