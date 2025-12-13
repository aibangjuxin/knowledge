| **GCP-GKE-CTRL-50** | IDAM-3 - 访问规则和角色管理 | RBAC策略不得使用通配符。 | CAEP team | 是 | 是 | 通过CI/CD流水线中的静态检查和Gatekeeper策略强制。 |

### **验证方法：如何检查RBAC策略中的通配符**

为了确保RBAC策略不使用通配符（`*`），这是一种重要的安全实践，可以避免过度授权。您可以使用`kubectl`命令结合`jq`工具来审计`ClusterRole`和`Role`定义中的`rules`字段。

**前提条件：**
*   已安装并配置`kubectl`以连接到您的GKE集群。
*   已安装`jq`工具，用于解析JSON输出。

**步骤1：检查`ClusterRoles`中是否存在通配符**

运行以下命令，查找在`apiGroups`、`resources`或`verbs`字段中使用了通配符的`ClusterRole`。

```bash
kubectl get clusterroles -o json | \
jq '.items[] | select(.rules[] | select( (.apiGroups[]? | select(. == "*")) or (.resources[]? | select(. == "*")) or (.verbs[]? | select(. == "*")) )) | .metadata.name'
```

*   **命令解释**：
    *   `kubectl get clusterroles -o json`：获取所有`ClusterRole`的JSON格式定义。
    *   `jq '.items[] | ...'`：遍历每一个`ClusterRole`。
    *   `select(.rules[] | select( ... ))`：筛选出任何`rules`中包含通配符的`ClusterRole`。
    *   `(.apiGroups[]? | select(. == "*"))`：检查`apiGroups`数组中是否有`*`。`?`表示该字段可选。
    *   `(.resources[]? | select(. == "*"))`：检查`resources`数组中是否有`*`。
    *   `(.verbs[]? | select(. == "*"))`：检查`verbs`数组中是否有`*`。
    *   `.metadata.name`：输出找到的`ClusterRole`的名称。

**合规性预期输出：**

如果您的RBAC策略合规，该命令应该返回**空结果**。任何输出的`ClusterRole`名称都表示存在不合规的通配符使用。

**步骤2：检查`Roles`中是否存在通配符**

运行以下命令，查找在所有命名空间的`Role`定义中，`apiGroups`、`resources`或`verbs`字段中使用了通配符的`Role`。

```bash
kubectl get roles --all-namespaces -o json | \
jq '.items[] | select(.rules[] | select( (.apiGroups[]? | select(. == "*")) or (.resources[]? | select(. == "*")) or (.verbs[]? | select(. == "*")) )) | .metadata.namespace + "/" + .metadata.name'
```

*   **命令解释**：
    *   `kubectl get roles --all-namespaces -o json`：获取所有命名空间中所有`Role`的JSON格式定义。
    *   其余`jq`部分的解释与`ClusterRole`命令类似，但会额外输出`Role`所在的命名空间。

**合规性预期输出：**

如果您的RBAC策略合规，该命令也应该返回**空结果**。任何输出的`Role`名称和命名空间都表示存在不合规的通配符使用。

---

通过执行上述两个命令并确认它们返回空结果，您可以提供证据证明您的GKE集群RBAC策略中没有使用通配符，从而满足`GCP-GKE-CTRL-50`的合规性要求。