GCP-GKE-CTRL-27
| **GCP-GKE-CTRL-27** | 网络隔离和边界 [NTSC1] | 特定于应用程序的VPC防火墙规则分配必须基于所使用的服务帐户而不是标签。 | CAEP team | 是 | 否 | 当前部分防火墙规则仍基于标签,正在迁移到基于服务账户的规则。 |

### **验证与迁移计划**

为了解决当前部分防火墙规则基于标签的问题，并最终符合 `GCP-GKE-CTRL-27` 控制要求，我们首先需要识别这些规则，然后制定一个清晰的迁移计划。

---
#### **1. 验证过程**

要识别所有基于标签的防火墙规则，请运行以下 `gcloud` 命令。


```sh
# 此命令会列出所有在其源（source）或目标（target）中使用了网络标签（tags）的防火墙规则
gcloud compute firewall-rules list \
  --filter="targetTags:* OR sourceTags:*" \
  --format="yaml(name, direction, priority, targetTags, sourceTags, allowed, denied, targetServiceAccounts, sourceServiceAccounts, description)"
```

**预期输出:**

此命令将返回一个YAML格式的列表，其中包含了所有不合规的规则。您需要审计这个列表中的每一条规则，以规划后续的迁移。例如：

```yaml
# 这是一个示例输出
- direction: INGRESS
  name: allow-app-frontend
  priority: 1000
  sourceTags:
  - lb-proxy
  targetTags:
  - app-frontend
  allowed:
  - IPProtocol: tcp
    ports:
    - '8080'
...
```

---
#### **2. 迁移计划：从基于标签迁移到基于服务帐户**

在您通过上述命令识别出所有相关规则后，可以遵循以下步骤进行迁移。此计划旨在将网络策略与应用程序身份（服务帐户）直接关联，从而提高安全性。

**核心步骤:**

1.  **审计与映射 (Audit & Map):**
    *   **审计:** 逐一分析上一步输出的每一条防火墙规则，明确其目的、所服务的GKE工作负载（Nodes/Pods）以及关联的应用。
    *   **服务帐户映射:** 为每一个受影响的工作负载（或逻辑组）确定或创建一个专用的Kubernetes服务帐户（KSA）。
    *   **Workload Identity关联:** 确保每个KSA都通过**Workload Identity**与一个唯一的Google服务帐户（GSA）相关联。这是将GKE身份映射到GCP防火墙身份的关键。

2.  **创建新规则 (Create New Rules):**
    *   **起草新规:** 为每一条旧的、基于标签的规则，起草一条新的、基于服务帐户的规则。
        *   将 `targetTags` 替换为 `targetServiceAccounts` (值为GSA的电子邮件地址)。
        *   将 `sourceTags` 替换为 `sourceServiceAccounts` (如果适用)。
        *   保持端口、协议和优先级等设置不变，除非您希望重新设计。
    *   **创建命令:** 使用 `gcloud compute firewall-rules create` 命令创建新规则。
        ```sh
        # 示例：创建一个新的基于服务帐户的规则
        gcloud compute firewall-rules create allow-app-frontend-sa \
          --direction=INGRESS \
          --priority=1000 \
          --network=YOUR_VPC_NETWORK \
          --action=ALLOW \
          --rules=tcp:8080 \
          --source-service-accounts=SOURCE_GSA@PROJECT_ID.iam.gserviceaccount.com \
          --target-service-accounts=TARGET_GSA@PROJECT_ID.iam.gserviceaccount.com \
          --description="[Migration] Replaces rule 'allow-app-frontend'. Uses Service Accounts instead of tags."
        ```

3.  **验证与切换 (Validate & Switch):**
    *   **并行运行:** 在迁移初期，建议让新的服务帐户规则与旧的标签规则并存。这可以确保在验证新规则时不会中断服务。
    *   **功能验证:** 部署一个使用新KSA/GSA的应用实例，确认其网络连接符合预期，并且没有出现意外的防火墙阻塞。
    *   **移除节点标签:** 验证成功后，从GKE节点池或节点上移除旧的网络标签。`gcloud container node-pools update ... --update-tags`。

4.  **清理旧规则 (Decommission):**
    *   **监控:** 在新规则稳定运行一段时间（例如，几天或一周）后，可以停用旧规则。
    *   **删除旧规:** 使用 `gcloud compute firewall-rules delete [OLD_RULE_NAME]` 删除基于标签的旧规则。
    *   **最终确认:** 再次确认所有相关应用功能正常。

**重要前提:**

*   **Workload Identity:** 此迁移方案强依赖于GKE的 **Workload Identity** 功能。在开始前，请务必确认您的GKE集群已启用并正确配置了Workload Identity。